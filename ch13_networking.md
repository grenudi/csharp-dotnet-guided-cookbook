# Chapter 13 — Networking: HttpClient, gRPC, WebSockets & QUIC

> Almost every modern application is a networked application. Whether
> it is calling a third-party API, talking to its own microservices, or
> pushing real-time updates to clients, the code that crosses process
> boundaries is critical to get right. This chapter covers the four main
> networking primitives in .NET and explains when to reach for each one.

*Building on:* Ch 8 (async/await — all networking is async), Ch 12
(streams — HTTP response bodies are streams), Ch 10 (DI — HttpClient
should be registered via IHttpClientFactory, not newed directly)

---

## 13.1 HttpClient — The Right Way

`HttpClient` is the BCL type for making HTTP requests. It is deceptively
simple but has serious misuse patterns that cause production problems.

### The Two Common Mistakes

**Mistake 1 — Creating a new `HttpClient` per request:**

```csharp
// WRONG: new HttpClient every time
public async Task<string> GetDataAsync(string url)
{
    using var client = new HttpClient();   // creates new TCP connection every call
    return await client.GetStringAsync(url);
}
```

`HttpClient` implements `IDisposable` which makes it look like it should
be in a `using` statement. But disposing it does not immediately close
sockets — the underlying `HttpClientHandler` exhausts your available
TCP ports under high load (socket exhaustion).

**Mistake 2 — A single static instance shared forever:**

```csharp
// WRONG: static singleton ignores DNS changes
private static readonly HttpClient _client = new();
```

A long-lived single instance respects DNS TTLs but ignores DNS updates.
If the target server changes IP, your static client never discovers it.

### The Solution: `IHttpClientFactory`

`IHttpClientFactory` manages a pool of `HttpClientHandler` instances with
a configurable lifetime. It reuses handlers (avoiding socket exhaustion)
and cycles them (respecting DNS changes):

```csharp
// Registration
builder.Services.AddHttpClient<IGitHubClient, GitHubClient>(client =>
{
    client.BaseAddress = new Uri("https://api.github.com");
    client.DefaultRequestHeaders.Add("User-Agent", "MyApp/1.0");
    client.Timeout = TimeSpan.FromSeconds(30);
})
.AddStandardResilienceHandler();   // adds retry, circuit breaker, timeout

// Typed client: HttpClient is injected, pre-configured
public class GitHubClient(HttpClient http)
{
    public async Task<Repository?> GetRepoAsync(
        string owner, string repo, CancellationToken ct)
    {
        var response = await http.GetAsync($"/repos/{owner}/{repo}", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<Repository>(ct);
    }
}
```

### Making Requests

```csharp
// GET — most common
var response = await http.GetAsync("/api/users", ct);
response.EnsureSuccessStatusCode();   // throws HttpRequestException on non-2xx
var users = await response.Content.ReadFromJsonAsync<List<User>>(ct);

// POST with JSON body
var created = await http.PostAsJsonAsync("/api/orders", new CreateOrderRequest
{
    CustomerId = "C001",
    Items = [new() { ProductId = "P01", Quantity = 2 }]
}, ct);

// PUT, PATCH, DELETE
await http.PutAsJsonAsync("/api/orders/123", updateRequest, ct);
await http.DeleteAsync("/api/orders/123", ct);

// Raw request with headers
using var request = new HttpRequestMessage(HttpMethod.Get, "/api/data");
request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
var raw = await http.SendAsync(request, ct);
```

### Resilience — Retry, Circuit Breaker, Timeout

```csharp
// Microsoft.Extensions.Http.Resilience (recommended)
builder.Services.AddHttpClient<IPaymentClient, StripePaymentClient>()
    .AddStandardResilienceHandler(opts =>
    {
        opts.Retry.MaxRetryAttempts = 3;
        opts.Retry.Delay = TimeSpan.FromSeconds(1);
        opts.CircuitBreaker.BreakDuration = TimeSpan.FromSeconds(30);
        opts.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(60);
    });
```

---

## 13.2 gRPC — High-Performance Service Communication

gRPC is a Remote Procedure Call framework built on HTTP/2 (multiplexed,
bi-directional) and Protocol Buffers (compact binary serialisation). It
is faster than REST/JSON for service-to-service communication and
provides strongly-typed generated clients.

### When to Use gRPC vs REST

| Situation | Prefer |
|---|---|
| Service-to-service internal communication | gRPC |
| Browser clients | REST (or gRPC-Web for browser support) |
| Public API | REST (familiar, toolable with Swagger) |
| Streaming data (server push) | gRPC server streaming |
| Bidirectional real-time | gRPC bidirectional streaming |
| Performance-critical high-throughput | gRPC |

### Defining a Service in Proto

The `.proto` file is the single source of truth. The `dotnet-grpc` tool
generates both server stubs and client code from it:

```protobuf
// protos/orders.proto
syntax = "proto3";
option csharp_namespace = "MyApp.Orders.Grpc";

service OrderService {
  // Unary: one request, one response (like REST)
  rpc GetOrder      (GetOrderRequest)      returns (OrderResponse);
  rpc CreateOrder   (CreateOrderRequest)   returns (OrderResponse);

  // Server streaming: one request, many responses (feed of results)
  rpc ListOrders    (ListOrdersRequest)    returns (stream OrderResponse);

  // Client streaming: many requests, one response (batch upload)
  rpc BulkCreate    (stream CreateOrderRequest) returns (BulkCreateResult);

  // Bidirectional streaming: many requests AND many responses
  rpc OrderUpdates  (stream SubscribeRequest) returns (stream OrderUpdate);
}

message GetOrderRequest    { string id = 1; }
message OrderResponse      { string id = 1; string customer = 2; double total = 3; }
message ListOrdersRequest  { string customer_id = 1; int32 page = 2; }
message BulkCreateResult   { int32 created = 1; repeated string errors = 2; }
```

```csharp
// Server implementation
public class OrderGrpcService(IOrderRepository repo) : OrderService.OrderServiceBase
{
    public override async Task<OrderResponse> GetOrder(
        GetOrderRequest request, ServerCallContext context)
    {
        var order = await repo.GetByIdAsync(request.Id, context.CancellationToken);
        if (order is null)
            throw new RpcException(new Status(StatusCode.NotFound, $"Order {request.Id} not found"));

        return new OrderResponse { Id = order.Id, Customer = order.Customer, Total = (double)order.Total };
    }

    public override async Task ListOrders(
        ListOrdersRequest request,
        IServerStreamWriter<OrderResponse> stream,
        ServerCallContext context)
    {
        await foreach (var order in repo.GetByCustomerAsync(request.CustomerId, context.CancellationToken))
        {
            await stream.WriteAsync(new OrderResponse
            {
                Id = order.Id, Customer = order.Customer, Total = (double)order.Total
            });
        }
    }
}
```

```csharp
// Client
var channel = GrpcChannel.ForAddress("https://orders.internal:5001");
var client  = new OrderService.OrderServiceClient(channel);

// Unary call
var order = await client.GetOrderAsync(new GetOrderRequest { Id = "ORD001" });

// Server streaming: process results as they arrive
using var stream = client.ListOrders(new ListOrdersRequest { CustomerId = "C001" });
await foreach (var o in stream.ResponseStream.ReadAllAsync(ct))
    Console.WriteLine($"Order: {o.Id} — {o.Total:C}");
```

---

## 13.3 WebSockets — Full-Duplex Text and Binary

WebSockets are a persistent, full-duplex connection between client and
server. Unlike HTTP (request/response), either side can send data at any
time. They are ideal for: chat, live notifications, collaborative
editing, game state updates.

For most real-time use cases, SignalR (Chapter 31) is a better choice —
it provides automatic reconnection, group management, and falls back to
long-polling for clients that do not support WebSockets. Use raw
WebSockets only when you need the maximum control or are implementing
a protocol that specifies them.

```csharp
// ASP.NET Core WebSocket server
app.UseWebSockets();
app.Map("/ws", async context =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = 400;
        return;
    }

    using var ws = await context.WebSockets.AcceptWebSocketAsync();
    var buffer   = new byte[1024 * 4];

    while (ws.State == WebSocketState.Open)
    {
        var result = await ws.ReceiveAsync(buffer, ct);
        if (result.MessageType == WebSocketMessageType.Close)
            break;

        var message = Encoding.UTF8.GetString(buffer, 0, result.Count);
        var response = Encoding.UTF8.GetBytes($"Echo: {message}");
        await ws.SendAsync(response, WebSocketMessageType.Text, endOfMessage: true, ct);
    }

    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Done", ct);
});

// Client
using var wsClient = new ClientWebSocket();
await wsClient.ConnectAsync(new Uri("ws://localhost:5000/ws"), ct);
await wsClient.SendAsync(Encoding.UTF8.GetBytes("Hello"), WebSocketMessageType.Text, true, ct);
```

---

## 13.4 mDNS / Zeroconf — Local Network Service Discovery

mDNS (Multicast DNS) allows services to discover each other on a local
network without a central DNS server. Services broadcast their presence,
and clients scan for them. This is how printers and network drives
appear automatically on your laptop, and how Sync.Mesh discovers peers.

```bash
dotnet add package Zeroconf
```

```csharp
// Advertise a service on the local network
// (Uses _syncmesh._tcp as the service type)
using var server = new MdnsServiceRegistration("syncmesh", "_syncmesh._tcp", 50051,
    properties: new[] { ("nodeId", nodeId), ("version", "1.0") });
await server.StartAsync(ct);

// Scan for services on the local network
var discovered = await ZeroconfResolver.ResolveAsync("_syncmesh._tcp.",
    scanTime: TimeSpan.FromSeconds(5),
    cancellationToken: ct);

foreach (var host in discovered)
{
    Console.WriteLine($"Found: {host.DisplayName} at {host.IPAddress}:{host.Port}");
    // host.Properties contains the TXT record key-value pairs
}
```

---

## 13.5 HTTP/3 and QUIC (.NET 9+)

HTTP/3 runs over QUIC (a UDP-based transport) rather than TCP. This
eliminates TCP's head-of-line blocking: in HTTP/2, a lost packet stalls
all streams; in QUIC, each stream is independent. On lossy connections
(mobile networks, satellite), HTTP/3 is significantly faster.

ASP.NET Core Kestrel supports HTTP/3 out of the box:

```csharp
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenLocalhost(5001, listenOptions =>
    {
        listenOptions.UseHttps();
        listenOptions.Protocols = HttpProtocols.Http1AndHttp2AndHttp3;
    });
});
```

`HttpClient` in .NET 9+ automatically upgrades to HTTP/3 if the server
advertises support via the `Alt-Svc` header — no client code changes
needed.

---

## 13.6 Connecting Networking to the Rest of the Book

- **Ch 8 (Async)** — every network operation returns a `Task`. The
  async model is what allows a server to handle thousands of concurrent
  connections with a small thread pool.
- **Ch 14 (ASP.NET Core)** — HTTP server hosting, middleware, and
  request routing sit on top of Kestrel's networking layer.
- **Ch 31 (SignalR)** — the high-level real-time framework built on
  WebSockets (with HTTP long-polling fallback).
- **Ch 28 (Security)** — TLS termination, certificate pinning, and JWT
  validation all happen at the network boundary.
- **Ch 30 (Observability)** — distributed tracing propagates context
  (trace ID, span ID) through HTTP and gRPC headers. Understanding the
  underlying transport helps understand how tracing works.
- **Ch 37 (Pet Projects V)** — a complete gRPC streaming service with
  server-side stream broadcasting via Channel<T>.
