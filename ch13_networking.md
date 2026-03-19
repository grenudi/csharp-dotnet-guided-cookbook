# Chapter 13 — Networking: HttpClient, gRPC, WebSockets & QUIC

## 13.1 HttpClient — Best Practices

### The Socket Exhaustion Problem

```csharp
// WRONG — creates new connections each call, exhausts sockets
public async Task<string> FetchAsync(string url)
{
    using var client = new HttpClient(); // DO NOT do this in production!
    return await client.GetStringAsync(url);
}

// BETTER — single HttpClient (but doesn't rotate DNS)
private static readonly HttpClient _client = new();

// BEST — IHttpClientFactory (handles lifecycle, rotation, resilience)
// Register in DI:
services.AddHttpClient();

// Inject:
public class MyService
{
    private readonly HttpClient _http;
    public MyService(IHttpClientFactory factory)
        => _http = factory.CreateClient();
}
```

### Named Clients

```csharp
// Registration
builder.Services.AddHttpClient("github", client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.DefaultRequestHeaders.UserAgent.ParseAdd("MyApp/1.0");
    client.DefaultRequestHeaders.Authorization =
        new AuthenticationHeaderValue("Bearer", "token");
    client.Timeout = TimeSpan.FromSeconds(30);
});

// Inject
public class GithubService
{
    private readonly HttpClient _http;

    public GithubService(IHttpClientFactory factory)
        => _http = factory.CreateClient("github");

    public async Task<JsonDocument?> GetRepoAsync(string owner, string repo, CancellationToken ct)
    {
        var response = await _http.GetAsync($"repos/{owner}/{repo}", ct);
        response.EnsureSuccessStatusCode();
        return await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
    }
}
```

### Typed Clients

```csharp
// Define typed client
public class WeatherClient
{
    private readonly HttpClient _http;

    public WeatherClient(HttpClient http)
    {
        _http = http;
    }

    public async Task<WeatherForecast[]> GetForecastAsync(string city, CancellationToken ct = default)
    {
        var response = await _http.GetAsync($"forecast?city={Uri.EscapeDataString(city)}", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<WeatherForecast[]>(ct)
               ?? [];
    }
}

// Register
builder.Services.AddHttpClient<WeatherClient>(client =>
{
    client.BaseAddress = new Uri("https://api.openweathermap.org/");
});

// Inject directly
public class WeatherPage
{
    public WeatherPage(WeatherClient weather) { ... }
}
```

### HttpMessageHandler and Resilience

```csharp
// Add Polly (Microsoft.Extensions.Http.Polly) for retry, circuit breaker
builder.Services.AddHttpClient<ApiClient>()
    .AddTransientHttpErrorPolicy(p =>
        p.WaitAndRetryAsync(3, retry => TimeSpan.FromSeconds(Math.Pow(2, retry))))
    .AddTransientHttpErrorPolicy(p =>
        p.CircuitBreakerAsync(5, TimeSpan.FromSeconds(30)));

// Or with the new Resilience package (NET 8+, Microsoft.Extensions.Http.Resilience)
builder.Services.AddHttpClient<ApiClient>()
    .AddStandardResilienceHandler(); // retry + circuit breaker + timeout + hedging
```

### Making Requests

```csharp
// GET
var response = await _http.GetAsync(url, ct);
response.EnsureSuccessStatusCode();
string text = await response.Content.ReadAsStringAsync(ct);
var obj = await response.Content.ReadFromJsonAsync<MyType>(ct);

// GET with query params
var builder = new UriBuilder("https://api.example.com/users");
var query = System.Web.HttpUtility.ParseQueryString("");
query["page"] = "1";
query["limit"] = "20";
query["search"] = "alice";
builder.Query = query.ToString();
var result = await _http.GetFromJsonAsync<UserList>(builder.Uri, ct);

// POST JSON
var body = new { Name = "Alice", Age = 30 };
var response2 = await _http.PostAsJsonAsync("/users", body, ct);
response2.EnsureSuccessStatusCode();
var created = await response2.Content.ReadFromJsonAsync<User>(ct);

// PUT / PATCH / DELETE
await _http.PutAsJsonAsync($"/users/{id}", updatedUser, ct);
await _http.DeleteAsync($"/users/{id}", ct);

// Multipart form data (file upload)
using var form = new MultipartFormDataContent();
form.Add(new StringContent("Alice"), "name");
form.Add(new ByteArrayContent(fileBytes), "file", "photo.jpg");
await _http.PostAsync("/upload", form, ct);

// Custom request
using var req = new HttpRequestMessage(HttpMethod.Patch, $"/users/{id}")
{
    Content = JsonContent.Create(patch, options: JsonOptions.Web),
    Headers = { { "X-Custom-Header", "value" } }
};
var resp = await _http.SendAsync(req, ct);

// Streaming response (large download)
using var response3 = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
await using var stream = await response3.Content.ReadAsStreamAsync(ct);
await using var fs = new FileStream("download.bin", FileMode.Create);
await stream.CopyToAsync(fs, ct);
```

---

## 13.2 gRPC

### Project Setup

```xml
<!-- MyGrpc.csproj -->
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <PackageReference Include="Grpc.AspNetCore" Version="2.65.0" />
    <PackageReference Include="Grpc.Tools" Version="2.65.0" PrivateAssets="all" />
  </ItemGroup>
  <ItemGroup>
    <Protobuf Include="Protos/**/*.proto" GrpcServices="Server" />
  </ItemGroup>
</Project>

<!-- Client project -->
<ItemGroup>
  <PackageReference Include="Grpc.Net.Client" Version="2.65.0" />
  <PackageReference Include="Google.Protobuf" Version="3.28.0" />
  <PackageReference Include="Grpc.Tools" Version="2.65.0" PrivateAssets="all" />
</ItemGroup>
<ItemGroup>
  <Protobuf Include="Protos/**/*.proto" GrpcServices="Client" />
</ItemGroup>
```

### Proto Definition

```protobuf
// Protos/sync.proto
syntax = "proto3";
option csharp_namespace = "SyncDot.Grpc";

package sync;

service SyncService {
  rpc GetStatus (StatusRequest)              returns (StatusResponse);
  rpc ListFiles (ListFilesRequest)           returns (stream FileEntry);
  rpc SyncFiles (stream FileChunk)           returns (SyncResult);
  rpc WatchChanges (WatchRequest)            returns (stream ChangeEvent);
}

message StatusRequest {}
message StatusResponse {
  string node_id = 1;
  int64 file_count = 2;
  int64 total_bytes = 3;
  bool is_syncing = 4;
}

message ListFilesRequest {
  string directory = 1;
}

message FileEntry {
  string path = 1;
  int64 size = 2;
  int64 modified_at = 3;  // Unix timestamp
  string hash = 4;
}

message FileChunk {
  string path = 1;
  bytes data = 2;
  int32 chunk_index = 3;
  bool is_last = 4;
}

message SyncResult {
  int32 files_synced = 1;
  int32 files_failed = 2;
  repeated string errors = 3;
}

message WatchRequest {
  repeated string directories = 1;
}

message ChangeEvent {
  enum ChangeType { CREATED = 0; MODIFIED = 1; DELETED = 2; RENAMED = 3; }
  ChangeType type = 1;
  string path = 2;
  string old_path = 3;  // for renames
  int64 timestamp = 4;
}
```

### gRPC Server Implementation

```csharp
using Grpc.Core;
using SyncDot.Grpc;

public class SyncServiceImpl : SyncService.SyncServiceBase
{
    private readonly IFileSystem _fs;
    private readonly ILogger<SyncServiceImpl> _logger;

    public SyncServiceImpl(IFileSystem fs, ILogger<SyncServiceImpl> logger)
    {
        _fs = fs;
        _logger = logger;
    }

    // Unary
    public override Task<StatusResponse> GetStatus(StatusRequest request, ServerCallContext context)
    {
        return Task.FromResult(new StatusResponse
        {
            NodeId     = _fs.NodeId,
            FileCount  = _fs.FileCount,
            TotalBytes = _fs.TotalBytes,
            IsSyncing  = _fs.IsSyncing
        });
    }

    // Server streaming
    public override async Task ListFiles(ListFilesRequest request,
        IServerStreamWriter<FileEntry> responseStream,
        ServerCallContext context)
    {
        await foreach (var entry in _fs.EnumerateAsync(request.Directory, context.CancellationToken))
        {
            await responseStream.WriteAsync(new FileEntry
            {
                Path       = entry.Path,
                Size       = entry.Size,
                ModifiedAt = entry.ModifiedAt.ToUnixTimeSeconds(),
                Hash       = entry.Hash ?? ""
            });
        }
    }

    // Client streaming
    public override async Task<SyncResult> SyncFiles(
        IAsyncStreamReader<FileChunk> requestStream,
        ServerCallContext context)
    {
        int synced = 0, failed = 0;
        var errors = new List<string>();
        var buffers = new Dictionary<string, List<FileChunk>>();

        await foreach (var chunk in requestStream.ReadAllAsync(context.CancellationToken))
        {
            if (!buffers.ContainsKey(chunk.Path))
                buffers[chunk.Path] = new();
            buffers[chunk.Path].Add(chunk);

            if (chunk.IsLast)
            {
                try
                {
                    var allChunks = buffers[chunk.Path].OrderBy(c => c.ChunkIndex);
                    await _fs.WriteFileAsync(chunk.Path, allChunks.SelectMany(c => c.Data.ToByteArray()));
                    buffers.Remove(chunk.Path);
                    synced++;
                }
                catch (Exception ex)
                {
                    errors.Add($"{chunk.Path}: {ex.Message}");
                    failed++;
                }
            }
        }

        return new SyncResult { FilesSynced = synced, FilesFailed = failed, Errors = { errors } };
    }

    // Bidirectional streaming
    public override async Task WatchChanges(
        WatchRequest request,
        IServerStreamWriter<ChangeEvent> responseStream,
        ServerCallContext context)
    {
        var ct = context.CancellationToken;
        await foreach (var change in _fs.WatchAsync(request.Directories, ct))
        {
            await responseStream.WriteAsync(new ChangeEvent
            {
                Type      = (ChangeEvent.Types.ChangeType)change.Type,
                Path      = change.Path,
                OldPath   = change.OldPath ?? "",
                Timestamp = change.Timestamp.ToUnixTimeSeconds()
            });
        }
    }
}
```

### gRPC Server Setup

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddGrpc(opts =>
{
    opts.MaxReceiveMessageSize = 16 * 1024 * 1024; // 16MB
    opts.MaxSendMessageSize    = 16 * 1024 * 1024;
    opts.EnableDetailedErrors  = builder.Environment.IsDevelopment();
});

// Unix socket (for local IPC — used by SyncDot)
builder.WebHost.ConfigureKestrel(opts =>
{
    opts.ListenUnixSocket("/run/syncdot/syncdot.sock", listen =>
    {
        listen.Protocols = Microsoft.AspNetCore.Server.Kestrel.Core.HttpProtocols.Http2;
    });
    // Or TCP:
    opts.ListenAnyIP(50051, listen => listen.Protocols = HttpProtocols.Http2);
});

var app = builder.Build();
app.MapGrpcService<SyncServiceImpl>();
app.Run();
```

### gRPC Client

```csharp
// Connect to Unix socket
var channel = GrpcChannel.ForAddress("http://localhost", new GrpcChannelOptions
{
    HttpHandler = new SocketsHttpHandler
    {
        ConnectCallback = async (ctx, ct) =>
        {
            var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            await socket.ConnectAsync(new UnixDomainSocketEndPoint("/run/syncdot/syncdot.sock"), ct);
            return new NetworkStream(socket, ownsSocket: true);
        }
    }
});

var client = new SyncService.SyncServiceClient(channel);

// Unary call
var status = await client.GetStatusAsync(new StatusRequest());
Console.WriteLine($"Node: {status.NodeId}, Files: {status.FileCount}");

// Server streaming
using var stream = client.ListFiles(new ListFilesRequest { Directory = "/" });
await foreach (var entry in stream.ResponseStream.ReadAllAsync())
    Console.WriteLine($"{entry.Path} ({entry.Size} bytes)");

// Client streaming
using var sync = client.SyncFiles();
foreach (var chunk in GetChunks(files))
    await sync.RequestStream.WriteAsync(chunk);
await sync.RequestStream.CompleteAsync();
var result = await sync.ResponseAsync;

// Bidirectional streaming
using var watch = client.WatchChanges(new WatchRequest { Directories = { "/home/user/sync" } });
await foreach (var change in watch.ResponseStream.ReadAllAsync(ct))
    Console.WriteLine($"[{change.Type}] {change.Path}");
```

---

## 13.3 WebSockets

```csharp
// Server (ASP.NET Core)
app.UseWebSockets();
app.Map("/ws", async context =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = 400;
        return;
    }

    using var ws = await context.WebSockets.AcceptWebSocketAsync();
    var buffer = new byte[4096];

    while (ws.State == WebSocketState.Open)
    {
        var result = await ws.ReceiveAsync(buffer, ct);
        if (result.MessageType == WebSocketMessageType.Close)
        {
            await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", ct);
            break;
        }

        var message = Encoding.UTF8.GetString(buffer, 0, result.Count);
        var reply = $"Echo: {message}";
        await ws.SendAsync(
            Encoding.UTF8.GetBytes(reply),
            WebSocketMessageType.Text,
            endOfMessage: true,
            ct);
    }
});

// Client
using var client = new ClientWebSocket();
await client.ConnectAsync(new Uri("ws://localhost:5000/ws"), ct);

await client.SendAsync(
    Encoding.UTF8.GetBytes("Hello"),
    WebSocketMessageType.Text,
    true, ct);

var buf = new byte[4096];
var r = await client.ReceiveAsync(buf, ct);
Console.WriteLine(Encoding.UTF8.GetString(buf, 0, r.Count));
```

---

## 13.4 HTTP/3 and QUIC (NET 9+)

```csharp
// Enable HTTP/3 in Kestrel
builder.WebHost.ConfigureKestrel(opts =>
{
    opts.ListenAnyIP(443, listen =>
    {
        listen.UseHttps();
        listen.Protocols = HttpProtocols.Http1AndHttp2AndHttp3;
    });
});

// QUIC connection (low-level, System.Net.Quic)
using System.Net.Quic;
using System.Net.Security;

var options = new QuicClientConnectionOptions
{
    RemoteEndPoint = new DnsEndPoint("example.com", 443),
    DefaultStreamErrorCode = 0,
    DefaultCloseErrorCode = 0,
    IdleTimeout = TimeSpan.FromSeconds(60),
    ClientAuthenticationOptions = new SslClientAuthenticationOptions
    {
        ApplicationProtocols = new[] { new SslApplicationProtocol("myproto") },
        TargetHost = "example.com",
    }
};

await using var connection = await QuicConnection.ConnectAsync(options, ct);
await using var stream = await connection.OpenOutboundStreamAsync(QuicStreamType.Bidirectional, ct);

await stream.WriteAsync(Encoding.UTF8.GetBytes("HELLO"), ct);
await stream.FlushAsync(ct);

var buffer = new byte[1024];
int read = await stream.ReadAsync(buffer, ct);
Console.WriteLine(Encoding.UTF8.GetString(buffer, 0, read));
```

---

## 13.5 mDNS / Zeroconf (Service Discovery)

For local P2P discovery (like SyncDot):

```csharp
// Install: Zeroconf NuGet package

using Zeroconf;

// Discover services
var results = await ZeroconfResolver.ResolveAsync("_syncdot._tcp.local.");
foreach (var host in results)
{
    Console.WriteLine($"Found: {host.DisplayName} @ {host.IPAddresses.First()}:{host.Services.Values.First().Port}");
}

// Advertise a service (using dns-sd / Avahi on Linux)
// In systemd unit or shell:
// avahi-publish-service "SyncDot-{hostname}" _syncdot._tcp 50051
```

> **Rider tip:** *View → Tool Windows → HTTP Client* lets you write and send HTTP requests directly from Rider with full IntelliSense for headers and JSON bodies. The `.http` file format is also supported in VS Code.

> **VS tip:** *View → Other Windows → Web API Tester* (or install the *REST Client* extension). Rider's HTTP client is more full-featured for this use case.

