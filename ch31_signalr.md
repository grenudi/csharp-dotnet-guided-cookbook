# Chapter 31 — SignalR: Real-Time Communication

## 31.1 Why SignalR Exists

HTTP is request-response. The client asks, the server answers. The server cannot
initiate communication. For real-time features — live dashboards, chat, notifications,
collaborative editing — you need the server to push data to clients without being asked.

SignalR solves this by maintaining a persistent connection and providing an abstraction
over transport protocols:

```
Preferred:    WebSockets    — full-duplex, lowest latency
Fallback:     Server-Sent Events — server → client only
Last resort:  Long Polling  — HTTP polling, highest overhead

SignalR picks the best available transport automatically.
```

---

## 31.2 Setup

```bash
dotnet add package Microsoft.AspNetCore.SignalR
```

```csharp
// Program.cs
builder.Services.AddSignalR(opts =>
{
    opts.EnableDetailedErrors         = builder.Environment.IsDevelopment();
    opts.MaximumReceiveMessageSize    = 32 * 1024;  // 32KB max message
    opts.ClientTimeoutInterval        = TimeSpan.FromSeconds(60);
    opts.HandshakeTimeout             = TimeSpan.FromSeconds(15);
});

app.MapHub<OrderHub>("/hubs/orders");
app.MapHub<NotificationHub>("/hubs/notifications");
```

---

## 31.3 Defining a Hub

A Hub is a class whose public methods are callable from connected clients.

```csharp
// Hubs/OrderHub.cs
[Authorize]
public class OrderHub : Hub
{
    private readonly IOrderService _orders;
    private readonly ILogger<OrderHub> _log;

    public OrderHub(IOrderService orders, ILogger<OrderHub> log)
    { _orders = orders; _log = log; }

    // ── Lifecycle ─────────────────────────────────────────────────────
    public override async Task OnConnectedAsync()
    {
        var userId = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        _log.LogInformation("Client connected: {ConnectionId} User: {UserId}",
            Context.ConnectionId, userId);

        // Add to user-specific group
        if (userId is not null)
            await Groups.AddToGroupAsync(Context.ConnectionId, $"user:{userId}");

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        _log.LogInformation("Client disconnected: {ConnectionId}", Context.ConnectionId);
        await base.OnDisconnectedAsync(exception);
    }

    // ── Client-callable methods (RPC from client → server) ─────────────
    public async Task SubscribeToOrder(Guid orderId)
    {
        // Add this connection to an order-specific group
        await Groups.AddToGroupAsync(Context.ConnectionId, $"order:{orderId}");
        _log.LogDebug("{ConnectionId} subscribed to order {OrderId}",
            Context.ConnectionId, orderId);
    }

    public async Task UnsubscribeFromOrder(Guid orderId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"order:{orderId}");
    }

    // Return a value to the caller
    public async Task<OrderStatus> GetOrderStatus(Guid orderId)
    {
        var order = await _orders.GetByIdAsync(new OrderId(orderId), Context.ConnectionAborted);
        return order?.Status ?? OrderStatus.Unknown;
    }
}
```

### Strongly-Typed Hubs (Recommended)

```csharp
// Define the client-side interface — what the server can call on clients
public interface IOrderHubClient
{
    Task OrderStatusChanged(Guid orderId, string newStatus, string message);
    Task OrderShipped(Guid orderId, string trackingNumber);
    Task PaymentReceived(Guid orderId, decimal amount);
    Task Error(string message);
}

// Strongly typed hub — compiler checks method names and signatures
public class OrderHub : Hub<IOrderHubClient>
{
    // Client calls are now type-safe
    public async Task SubscribeToOrder(Guid orderId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"order:{orderId}");
        // Tell the caller the current status
        await Clients.Caller.OrderStatusChanged(orderId, "Pending", "Subscribed to order updates");
    }
}
```

---

## 31.4 Pushing from Services — IHubContext

Inject `IHubContext<THub, TClient>` into any service to push to connected clients
from outside the hub:

```csharp
public class OrderEventHandler : IEventHandler<OrderStatusChangedEvent>
{
    private readonly IHubContext<OrderHub, IOrderHubClient> _hub;

    public OrderEventHandler(IHubContext<OrderHub, IOrderHubClient> hub)
        => _hub = hub;

    public async Task HandleAsync(OrderStatusChangedEvent e, CancellationToken ct)
    {
        // Push to all subscribers of this order
        await _hub.Clients.Group($"order:{e.OrderId}")
            .OrderStatusChanged(e.OrderId, e.NewStatus.ToString(), e.Message);

        // Push to the specific user who placed the order
        await _hub.Clients.Group($"user:{e.UserId}")
            .OrderStatusChanged(e.OrderId, e.NewStatus.ToString(), e.Message);
    }
}

// Register the handler
builder.Services.AddScoped<IEventHandler<OrderStatusChangedEvent>, OrderEventHandler>();
```

### Pushing to Specific Targets

```csharp
IHubContext<OrderHub, IOrderHubClient> hub;

// All connected clients
await hub.Clients.All.OrderStatusChanged(orderId, status, msg);

// Specific connection (you must know the ConnectionId)
await hub.Clients.Client(connectionId).OrderStatusChanged(orderId, status, msg);

// All clients in a group
await hub.Clients.Group($"order:{orderId}").OrderStatusChanged(orderId, status, msg);

// Multiple groups
await hub.Clients.Groups(new[] { "admins", $"user:{userId}" })
    .OrderStatusChanged(orderId, status, msg);

// All except specific connection
await hub.Clients.AllExcept(connectionId).OrderStatusChanged(orderId, status, msg);

// Specific user (all connections of that user — they might have multiple tabs)
await hub.Clients.User(userId).OrderStatusChanged(orderId, status, msg);
```

---

## 31.5 JavaScript Client

```javascript
// npm install @microsoft/signalr
import * as signalR from "@microsoft/signalr";

const connection = new signalR.HubConnectionBuilder()
    .withUrl("/hubs/orders", {
        accessTokenFactory: () => getAuthToken(),
    })
    .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])  // retry delays in ms
    .configureLogging(signalR.LogLevel.Information)
    .build();

// Handle incoming messages from server
connection.on("OrderStatusChanged", (orderId, newStatus, message) => {
    console.log(`Order ${orderId} is now ${newStatus}: ${message}`);
    updateUI(orderId, newStatus);
});

connection.on("OrderShipped", (orderId, trackingNumber) => {
    showNotification(`Your order shipped! Tracking: ${trackingNumber}`);
});

// Handle reconnection
connection.onreconnecting(error => console.warn("Reconnecting:", error));
connection.onreconnected(connectionId => console.log("Reconnected:", connectionId));
connection.onclose(error => console.error("Connection closed:", error));

// Start
await connection.start();

// Call server methods
await connection.invoke("SubscribeToOrder", orderId);

// Call with return value
const status = await connection.invoke("GetOrderStatus", orderId);
```

---

## 31.6 Blazor Client

```razor
@* Components/OrderTracker.razor *@
@inject NavigationManager Nav
@inject IAccessTokenProvider TokenProvider
@implements IAsyncDisposable

<div>
    <h3>Order @OrderId</h3>
    <p>Status: @_status</p>
    @foreach (var update in _updates)
    {
        <p>@update.Time.ToString("HH:mm:ss"): @update.Message</p>
    }
</div>

@code {
    [Parameter] public Guid OrderId { get; set; }

    private HubConnection? _hub;
    private string _status = "Loading...";
    private readonly List<(DateTime Time, string Message)> _updates = new();

    protected override async Task OnInitializedAsync()
    {
        _hub = new HubConnectionBuilder()
            .WithUrl(Nav.ToAbsoluteUri("/hubs/orders"), opts =>
            {
                opts.AccessTokenProvider = async () =>
                {
                    var result = await TokenProvider.RequestAccessToken();
                    return result.TryGetToken(out var token) ? token.Value : null;
                };
            })
            .WithAutomaticReconnect()
            .Build();

        _hub.On<Guid, string, string>("OrderStatusChanged",
            async (id, status, message) =>
            {
                if (id != OrderId) return;
                _status = status;
                _updates.Add((DateTime.Now, message));
                await InvokeAsync(StateHasChanged);  // update UI on UI thread
            });

        await _hub.StartAsync();
        await _hub.InvokeAsync("SubscribeToOrder", OrderId);
    }

    public async ValueTask DisposeAsync()
    {
        if (_hub is not null)
            await _hub.DisposeAsync();
    }
}
```

---

## 31.7 Scaling SignalR — Redis Backplane

By default, SignalR state lives in-process. With multiple server instances,
a client connected to Server A cannot receive messages sent from Server B.

```csharp
// Install: Microsoft.AspNetCore.SignalR.StackExchangeRedis
builder.Services.AddSignalR()
    .AddStackExchangeRedis(connectionString, opts =>
    {
        opts.Configuration.ChannelPrefix = RedisChannel.Literal("MyApp");
    });

// Now all instances share group membership and can fan out messages
// Server A sends to group → Redis backplane → Server B, C, D all receive
```

> **Rider tip:** Set a breakpoint inside a Hub method — it hits on every client
> call. `Context.ConnectionId` and `Context.User` are visible in the debugger.
> Use the built-in HTTP client to test via `ws://` WebSocket connections.

> **VS tip:** *View → Other Windows → SignalR Inspector* (via Azure SignalR extension)
> shows all connected clients, groups, and message history during local development.
