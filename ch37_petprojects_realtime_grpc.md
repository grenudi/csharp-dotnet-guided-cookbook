# Chapter 37 — Pet Projects V: Real-Time Server & gRPC Service

> Two advanced pet projects: a real-time chat server with SignalR, and
> a gRPC service that exposes a currency exchange rate feed.

---

## 37.1 Project 1 — Real-Time Chat with SignalR

**What it does:** Multi-room chat server. Browser clients connect via
WebSocket. Users join rooms, send messages, see who is online. Message
history stored in SQLite.

**Concepts:** SignalR Hubs (Ch 31), IHubContext, groups, connection
lifecycle, client-side JavaScript, EF Core (Ch 15)

```bash
dotnet new webapi -n ChatServer
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
```

### Persistence

```csharp
// ChatDbContext.cs
public class ChatMessage
{
    public int      Id        { get; set; }
    public string   Room      { get; set; } = "";
    public string   User      { get; set; } = "";
    public string   Text      { get; set; } = "";
    public DateTime SentAt    { get; set; }
}

public class ChatDbContext : DbContext
{
    public ChatDbContext(DbContextOptions<ChatDbContext> o) : base(o) { }
    public DbSet<ChatMessage> Messages => Set<ChatMessage>();
}
```

### Hub

```csharp
// ChatHub.cs
using Microsoft.AspNetCore.SignalR;

public sealed class ChatHub : Hub
{
    private static readonly Dictionary<string, string> _online = new();
    private readonly ChatDbContext _db;

    public ChatHub(ChatDbContext db) => _db = db;

    // Called by client: hub.invoke("JoinRoom", "general", "Alice")
    public async Task JoinRoom(string room, string username)
    {
        _online[Context.ConnectionId] = username;
        await Groups.AddToGroupAsync(Context.ConnectionId, room);

        // Load last 50 messages for this room
        var history = await _db.Messages
            .Where(m => m.Room == room)
            .OrderByDescending(m => m.SentAt)
            .Take(50)
            .OrderBy(m => m.SentAt)
            .Select(m => new { m.User, m.Text, m.SentAt })
            .ToListAsync();

        // Send history only to the joining connection
        await Clients.Caller.SendAsync("History", history);

        // Notify room
        await Clients.Group(room).SendAsync("UserJoined", username);
        await BroadcastOnlineCount(room);
    }

    // Called by client: hub.invoke("SendMessage", "general", "Hello!")
    public async Task SendMessage(string room, string text)
    {
        if (!_online.TryGetValue(Context.ConnectionId, out var username)) return;
        if (string.IsNullOrWhiteSpace(text)) return;

        var message = new ChatMessage
        {
            Room  = room,
            User  = username,
            Text  = text.Trim()[..Math.Min(text.Length, 1000)],
            SentAt = DateTime.UtcNow,
        };
        _db.Messages.Add(message);
        await _db.SaveChangesAsync();

        await Clients.Group(room).SendAsync("ReceiveMessage", new
        {
            username,
            text  = message.Text,
            sentAt = message.SentAt,
        });
    }

    public override async Task OnDisconnectedAsync(Exception? ex)
    {
        if (_online.TryGetValue(Context.ConnectionId, out var username))
        {
            _online.Remove(Context.ConnectionId);
            // Notify all groups this connection was in (simplified)
        }
        await base.OnDisconnectedAsync(ex);
    }

    private Task BroadcastOnlineCount(string room)
        => Clients.Group(room).SendAsync("OnlineCount", _online.Count);
}
```

### Program.cs

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddDbContext<ChatDbContext>(o => o.UseSqlite("Data Source=chat.db"));
builder.Services.AddSignalR(o => { o.EnableDetailedErrors = builder.Environment.IsDevelopment(); });
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();
using (var scope = app.Services.CreateScope())
    await scope.ServiceProvider.GetRequiredService<ChatDbContext>().Database.MigrateAsync();

app.UseCors();
app.MapHub<ChatHub>("/hubs/chat");
app.MapGet("/", () => Results.Redirect("/index.html"));
app.UseStaticFiles();

await app.RunAsync();
```

### Client (`wwwroot/index.html`)

```html
<!DOCTYPE html>
<html>
<head><title>Chat</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/microsoft-signalr/8.0.0/signalr.min.js"></script>
</head>
<body>
<div id="messages" style="height:400px;overflow-y:auto;border:1px solid #ccc;padding:8px"></div>
<input id="msg" placeholder="Message..." style="width:80%">
<button onclick="send()">Send</button>

<script>
const room = "general";
const user = prompt("Your name:") || "Anonymous";

const conn = new signalR.HubConnectionBuilder()
    .withUrl("/hubs/chat")
    .withAutomaticReconnect()
    .build();

conn.on("ReceiveMessage", ({ username, text, sentAt }) => {
    const d = document.getElementById("messages");
    d.innerHTML += `<div><b>${username}</b>: ${text} <small>${new Date(sentAt).toLocaleTimeString()}</small></div>`;
    d.scrollTop = d.scrollHeight;
});

conn.on("History", messages => {
    messages.forEach(m => conn.emit?.("ReceiveMessage", m));
});

conn.on("UserJoined", u => appendSystem(`${u} joined`));
conn.on("OnlineCount", n => document.title = `Chat (${n} online)`);

async function send() {
    const input = document.getElementById("msg");
    if (!input.value.trim()) return;
    await conn.invoke("SendMessage", room, input.value);
    input.value = "";
}

document.getElementById("msg").addEventListener("keypress", e => {
    if (e.key === "Enter") send();
});

(async () => {
    await conn.start();
    await conn.invoke("JoinRoom", room, user);
})();

function appendSystem(msg) {
    const d = document.getElementById("messages");
    d.innerHTML += `<div style="color:grey"><i>${msg}</i></div>`;
}
</script>
</body>
</html>
```

---

## 37.2 Project 2 — gRPC Exchange Rate Service

**What it does:** A gRPC server that streams live currency exchange rate
updates. Clients connect and receive rates as they change. A mock data
generator simulates rate fluctuations.

**Concepts:** gRPC (Ch 13 §13.2), server streaming, `IServerStreamWriter`,
`IAsyncEnumerable`, `Channel<T>` for broadcasting (Ch 8 §8.6)

```bash
dotnet new webapi -n ExchangeRateService
dotnet add package Grpc.AspNetCore
```

### Proto

```protobuf
// Protos/rates.proto
syntax = "proto3";
option csharp_namespace = "ExchangeRateService";

service RateService {
  // Stream live rates to subscriber
  rpc SubscribeRates (SubscribeRequest) returns (stream RateUpdate);
  // Get the latest rate (unary)
  rpc GetRate        (GetRateRequest)   returns (RateResponse);
}

message SubscribeRequest {
  repeated string pairs = 1;  // e.g. ["EUR/USD", "BTC/USD"]
}
message RateUpdate {
  string pair      = 1;   // "EUR/USD"
  double bid       = 2;
  double ask       = 3;
  int64  timestamp = 4;   // Unix ms
}
message GetRateRequest  { string pair = 1; }
message RateResponse    { string pair = 1; double bid = 2; double ask = 3; }
```

### Rate Store (in-memory broadcast hub)

```csharp
// RateStore.cs
public sealed class RateStore
{
    private readonly Dictionary<string, (double Bid, double Ask)> _rates = new()
    {
        ["EUR/USD"] = (1.0850, 1.0852),
        ["GBP/USD"] = (1.2700, 1.2703),
        ["BTC/USD"] = (68000.0, 68010.0),
        ["ETH/USD"] = (3800.0, 3800.5),
    };

    // One channel per subscriber. Broadcast sends to all.
    private readonly List<Channel<(string Pair, double Bid, double Ask)>> _subscribers = new();
    private readonly Lock _lock = new();

    public (double Bid, double Ask)? GetRate(string pair)
        => _rates.TryGetValue(pair, out var r) ? r : null;

    public Channel<(string, double, double)> Subscribe()
    {
        var ch = Channel.CreateBounded<(string, double, double)>(
            new BoundedChannelOptions(100) { FullMode = BoundedChannelFullMode.DropOldest });
        lock (_lock) _subscribers.Add(ch);
        return ch;
    }

    public void Unsubscribe(Channel<(string, double, double)> ch)
    {
        lock (_lock) _subscribers.Remove(ch);
        ch.Writer.TryComplete();
    }

    // Called by RateSimulator to push new rates
    public void UpdateRate(string pair, double bid, double ask)
    {
        _rates[pair] = (bid, ask);
        lock (_lock)
        {
            foreach (var ch in _subscribers)
                ch.Writer.TryWrite((pair, bid, ask));
        }
    }

    public IEnumerable<string> Pairs => _rates.Keys;
}
```

### Rate Simulator (BackgroundService)

```csharp
// RateSimulator.cs
public sealed class RateSimulator : BackgroundService
{
    private readonly RateStore _store;
    private readonly Random    _rng = new();

    public RateSimulator(RateStore store) => _store = store;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(500));
        while (await timer.WaitForNextTickAsync(ct))
        {
            // Randomly tick one pair
            var pairs = _store.Pairs.ToArray();
            var pair  = pairs[_rng.Next(pairs.Length)];
            var rate  = _store.GetRate(pair)!.Value;

            // Random walk: ±0.01%
            var change = (1 + (_rng.NextDouble() - 0.5) * 0.0002);
            _store.UpdateRate(pair, rate.Bid * change, rate.Ask * change);
        }
    }
}
```

### gRPC Service

```csharp
// RateServiceImpl.cs
using Grpc.Core;

public sealed class RateServiceImpl : RateService.RateServiceBase
{
    private readonly RateStore _store;

    public RateServiceImpl(RateStore store) => _store = store;

    public override Task<RateResponse> GetRate(GetRateRequest req, ServerCallContext ctx)
    {
        var rate = _store.GetRate(req.Pair);
        if (rate is null) throw new RpcException(new Status(StatusCode.NotFound, $"Unknown pair: {req.Pair}"));
        return Task.FromResult(new RateResponse { Pair = req.Pair, Bid = rate.Value.Bid, Ask = rate.Value.Ask });
    }

    public override async Task SubscribeRates(
        SubscribeRequest req,
        IServerStreamWriter<RateUpdate> stream,
        ServerCallContext ctx)
    {
        var pairs = req.Pairs.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var ch = _store.Subscribe();

        try
        {
            // Send current snapshot first
            foreach (var pair in pairs)
            {
                var rate = _store.GetRate(pair);
                if (rate is null) continue;
                await stream.WriteAsync(new RateUpdate
                {
                    Pair      = pair,
                    Bid       = rate.Value.Bid,
                    Ask       = rate.Value.Ask,
                    Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                }, ctx.CancellationToken);
            }

            // Stream updates
            await foreach (var (pair, bid, ask) in ch.Reader.ReadAllAsync(ctx.CancellationToken))
            {
                if (!pairs.Contains(pair)) continue;

                await stream.WriteAsync(new RateUpdate
                {
                    Pair      = pair,
                    Bid       = bid,
                    Ask       = ask,
                    Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                }, ctx.CancellationToken);
            }
        }
        finally
        {
            _store.Unsubscribe(ch);
        }
    }
}
```

### Program.cs

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddGrpc();
builder.Services.AddSingleton<RateStore>();
builder.Services.AddHostedService<RateSimulator>();

var app = builder.Build();
app.MapGrpcService<RateServiceImpl>();
await app.RunAsync();
```

### Test the gRPC service

```bash
# grpcurl (install: brew/apt/nix)
grpcurl -plaintext localhost:5000 list

# Unary call
grpcurl -plaintext -d '{"pair":"EUR/USD"}' \
    localhost:5000 RateService/GetRate

# Streaming (Ctrl+C to stop)
grpcurl -plaintext -d '{"pairs":["EUR/USD","BTC/USD"]}' \
    localhost:5000 RateService/SubscribeRates
```

---

## 37.3 What to Build After These Five Chapters

| Level | Chapter | Project ideas to try independently |
|---|---|---|
| Console | Ch 33 | CSV to JSON converter, `grep` clone, log parser |
| CLI | Ch 34 | `git log` pretty-printer, deployment script runner |
| Daemon | Ch 35 | S3 backup daemon, port scanner, DNS checker |
| API | Ch 36 | Bookmark manager, invoice tracker, note-taking API |
| Real-time | Ch 37 | Live code editor, collaborative todo, stock ticker |

The progression from Ch 33 → Ch 37 covers every major program shape you
will encounter in professional .NET development. Each chapter references
the core Bible chapters so you can go deeper on any concept.
