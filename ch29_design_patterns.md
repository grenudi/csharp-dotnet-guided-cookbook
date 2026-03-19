# Chapter 29 — Design Patterns

Design patterns are named, documented solutions to recurring structural problems.
They give teams a shared vocabulary: "use a Strategy here" communicates a complete idea.

The 23 Gang of Four (GoF) patterns from the 1994 book *Design Patterns* are the
canonical reference. Not all 23 are equally useful in daily C# work. This chapter
covers the ones you will encounter and use constantly, in order of practical importance.

---

## 29.1 Why Patterns Matter

The problem patterns solve is not technical — it is communication and recognition.

When you see code shaped a certain way, recognising it as "the Strategy pattern"
tells you immediately: what it does, why it's structured that way, and how to extend it.
Without the vocabulary, you rebuild the wheel and explain it from scratch every time.

The patterns below are split into three categories:

```
Creational   — how objects are created
Structural   — how objects are composed
Behavioral   — how objects communicate
```

---

## 29.2 Strategy — Swap Algorithms at Runtime

**Category:** Behavioral
**The problem:** you have multiple ways to do the same thing and need to choose
at runtime without a cascade of `if/switch` statements.

### The Bug Without It

```csharp
// ❌ Growing if-chain — add a new method, touch this function
public decimal CalculateShipping(Order order, string method)
{
    if (method == "standard")     return order.Weight * 0.5m;
    if (method == "express")      return order.Weight * 1.5m + 5m;
    if (method == "overnight")    return order.Weight * 2.0m + 15m;
    if (method == "international") return order.Weight * 3.0m + 25m;
    throw new ArgumentException($"Unknown method: {method}");
}
// Adding "drone delivery" means editing this function — violates Open/Closed
```

### The Fix

```csharp
// Interface = the strategy contract
public interface IShippingStrategy
{
    decimal Calculate(Order order);
    string Name { get; }
}

// Each algorithm in its own class — never touch existing ones to add new
public class StandardShipping  : IShippingStrategy
{
    public string Name => "standard";
    public decimal Calculate(Order o) => o.Weight * 0.5m;
}

public class ExpressShipping : IShippingStrategy
{
    public string Name => "express";
    public decimal Calculate(Order o) => o.Weight * 1.5m + 5m;
}

public class OvernightShipping : IShippingStrategy
{
    public string Name => "overnight";
    public decimal Calculate(Order o) => o.Weight * 2.0m + 15m;
}

// Context: uses whichever strategy is injected
public class ShippingCalculator
{
    private readonly IEnumerable<IShippingStrategy> _strategies;

    public ShippingCalculator(IEnumerable<IShippingStrategy> strategies)
        => _strategies = strategies;

    public decimal Calculate(Order order, string method)
    {
        var strategy = _strategies.FirstOrDefault(s => s.Name == method)
            ?? throw new ArgumentException($"Unknown method: {method}");
        return strategy.Calculate(order);
    }
}

// DI registration — adding a new strategy = add one line here, nothing else changes
services.AddSingleton<IShippingStrategy, StandardShipping>();
services.AddSingleton<IShippingStrategy, ExpressShipping>();
services.AddSingleton<IShippingStrategy, OvernightShipping>();
services.AddSingleton<ShippingCalculator>();
```

---

## 29.3 Decorator — Add Behaviour Without Modifying

**Category:** Structural
**The problem:** you want to add behaviour to an object (caching, logging, validation,
retry) without changing the class or creating an inheritance explosion.
Already shown in Ch 6 §6.8 — this section shows the full real-world pattern.

```csharp
// Base interface
public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct);
    Task SaveAsync(Order order, CancellationToken ct);
}

// Real implementation
public class SqlOrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;
    public SqlOrderRepository(AppDbContext db) => _db = db;

    public async Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct)
        => await _db.Orders.FindAsync([id.Value], ct);

    public async Task SaveAsync(Order order, CancellationToken ct)
    {
        _db.Orders.Add(order);
        await _db.SaveChangesAsync(ct);
    }
}

// Decorator 1: caching — wraps the real repo
public class CachedOrderRepository : IOrderRepository
{
    private readonly IOrderRepository _inner;
    private readonly IMemoryCache     _cache;

    public CachedOrderRepository(IOrderRepository inner, IMemoryCache cache)
    { _inner = inner; _cache = cache; }

    public async Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct)
        => await _cache.GetOrCreateAsync($"order:{id}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            return await _inner.GetByIdAsync(id, ct);
        });

    public async Task SaveAsync(Order order, CancellationToken ct)
    {
        _cache.Remove($"order:{order.Id}");
        await _inner.SaveAsync(order, ct);
    }
}

// Decorator 2: logging — wraps the cached repo
public class LoggedOrderRepository : IOrderRepository
{
    private readonly IOrderRepository _inner;
    private readonly ILogger<LoggedOrderRepository> _log;

    public LoggedOrderRepository(IOrderRepository inner, ILogger<LoggedOrderRepository> log)
    { _inner = inner; _log = log; }

    public async Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct)
    {
        _log.LogDebug("Fetching order {Id}", id);
        var result = await _inner.GetByIdAsync(id, ct);
        _log.LogDebug("Order {Id}: {Found}", id, result is null ? "not found" : "found");
        return result;
    }

    public async Task SaveAsync(Order order, CancellationToken ct)
    {
        _log.LogInformation("Saving order {Id}", order.Id);
        await _inner.SaveAsync(order, ct);
    }
}

// Wire in DI: Logged(Cached(Sql))
services.AddScoped<IOrderRepository>(sp =>
    new LoggedOrderRepository(
        new CachedOrderRepository(
            new SqlOrderRepository(sp.GetRequiredService<AppDbContext>()),
            sp.GetRequiredService<IMemoryCache>()),
        sp.GetRequiredService<ILogger<LoggedOrderRepository>>()));
```

---

## 29.4 Factory Method and Abstract Factory

**Category:** Creational
**The problem:** you need to create objects but the calling code should not know
which concrete type is being created.

### Factory Method

```csharp
// The "factory" is a method that returns an abstraction
public interface INotificationSender
{
    Task SendAsync(string to, string message, CancellationToken ct);
}

public class EmailSender   : INotificationSender { /* ... */ }
public class SmsSender     : INotificationSender { /* ... */ }
public class PushSender    : INotificationSender { /* ... */ }

// Factory: creates the right sender based on context
public static class NotificationSenderFactory
{
    public static INotificationSender Create(NotificationChannel channel) => channel switch
    {
        NotificationChannel.Email => new EmailSender(),
        NotificationChannel.Sms   => new SmsSender(),
        NotificationChannel.Push  => new PushSender(),
        _ => throw new ArgumentOutOfRangeException(nameof(channel))
    };
}
```

### Factory with DI (The .NET Way)

```csharp
// Register all implementations, inject the factory
services.AddSingleton<EmailSender>();
services.AddSingleton<SmsSender>();
services.AddSingleton<PushSender>();

public class NotificationSenderFactory
{
    private readonly IServiceProvider _sp;
    public NotificationSenderFactory(IServiceProvider sp) => _sp = sp;

    public INotificationSender Create(NotificationChannel channel) => channel switch
    {
        NotificationChannel.Email => _sp.GetRequiredService<EmailSender>(),
        NotificationChannel.Sms   => _sp.GetRequiredService<SmsSender>(),
        NotificationChannel.Push  => _sp.GetRequiredService<PushSender>(),
        _ => throw new ArgumentOutOfRangeException()
    };
}
// Or use keyed services (NET 8+) — see Ch 11 §11.8
```

---

## 29.5 Observer — React to Events

**Category:** Behavioral
**The problem:** when something happens, multiple unrelated parts of the system
need to react — but they shouldn't be coupled to each other.

C# events ARE the Observer pattern. But for decoupled cross-domain notifications,
use a domain event bus:

```csharp
// Event
public record OrderPlacedEvent(OrderId OrderId, string CustomerId, decimal Total);

// Observer interface
public interface IEventHandler<T> where T : class
{
    Task HandleAsync(T @event, CancellationToken ct);
}

// Observers — completely independent, don't know about each other
public class SendConfirmationEmailHandler : IEventHandler<OrderPlacedEvent>
{
    private readonly IEmailSender _email;
    public SendConfirmationEmailHandler(IEmailSender email) => _email = email;

    public async Task HandleAsync(OrderPlacedEvent e, CancellationToken ct)
        => await _email.SendAsync(e.CustomerId, $"Order {e.OrderId} confirmed!");
}

public class UpdateInventoryHandler : IEventHandler<OrderPlacedEvent>
{
    private readonly IInventoryService _inventory;
    public UpdateInventoryHandler(IInventoryService inv) => _inventory = inv;

    public async Task HandleAsync(OrderPlacedEvent e, CancellationToken ct)
        => await _inventory.ReserveForOrderAsync(e.OrderId, ct);
}

// Event bus: publish to all registered handlers
public class InMemoryEventBus
{
    private readonly IServiceProvider _sp;
    public InMemoryEventBus(IServiceProvider sp) => _sp = sp;

    public async Task PublishAsync<T>(T @event, CancellationToken ct) where T : class
    {
        var handlers = _sp.GetServices<IEventHandler<T>>();
        foreach (var h in handlers)
            await h.HandleAsync(@event, ct);
    }
}

// Register
services.AddScoped<IEventHandler<OrderPlacedEvent>, SendConfirmationEmailHandler>();
services.AddScoped<IEventHandler<OrderPlacedEvent>, UpdateInventoryHandler>();
services.AddSingleton<InMemoryEventBus>();

// Usage in OrderService
await _bus.PublishAsync(new OrderPlacedEvent(order.Id, order.CustomerId, order.Total), ct);
// Both handlers run. OrderService doesn't know they exist.
```

---

## 29.6 Builder — Construct Complex Objects Step by Step

**Category:** Creational
**The problem:** constructing an object requires many steps or has many optional parameters.
Constructors with 8 parameters are a builder waiting to happen.

```csharp
// ❌ Constructor with too many params — which bool is which?
var report = new Report("Q4", true, false, true, "PDF", "en", 100, false);

// ✅ Builder — reads like a sentence
var report = new ReportBuilder("Q4")
    .IncludeCharts()
    .ExcludeRawData()
    .InFormat(ReportFormat.Pdf)
    .InLanguage("en")
    .WithPageLimit(100)
    .Build();

// Implementation
public class ReportBuilder
{
    private readonly string _title;
    private bool   _includeCharts  = false;
    private bool   _includeRawData = true;
    private string _format         = "PDF";
    private string _language       = "en";
    private int    _pageLimit       = int.MaxValue;

    public ReportBuilder(string title) => _title = title;

    public ReportBuilder IncludeCharts()          { _includeCharts  = true;  return this; }
    public ReportBuilder ExcludeRawData()         { _includeRawData = false; return this; }
    public ReportBuilder InFormat(string format)  { _format = format;        return this; }
    public ReportBuilder InLanguage(string lang)  { _language = lang;        return this; }
    public ReportBuilder WithPageLimit(int limit) { _pageLimit = limit;      return this; }

    public Report Build() => new Report(
        _title, _includeCharts, _includeRawData, _format, _language, _pageLimit);
}
```

---

## 29.7 Singleton — One Instance for the Application

**Category:** Creational
**The problem:** some objects should have exactly one instance (config, connection pool,
cache, logging sink).

In .NET, **use DI `AddSingleton` — not the manual Singleton pattern.**
The manual Singleton causes testability problems and hides dependencies.

```csharp
// ❌ Classic Singleton — hidden dependency, untestable
public class ConfigManager
{
    public static ConfigManager Instance { get; } = new();
    private ConfigManager() { }
    public string Get(string key) => /* ... */;
}
// Usage: ConfigManager.Instance.Get("key")
// Cannot be replaced in tests. Cannot be injected.

// ✅ .NET way: registered as singleton in DI
builder.Services.AddSingleton<IConfigManager, ConfigManager>();
// Injected normally — testable, replaceable, explicit
```

When the manual Singleton is appropriate: truly global, stateless, immutable shared state
like `Random.Shared`, `JsonSerializerOptions`, or static compile-time constants.

---

## 29.8 Repository — Abstract Data Access

**Category:** Structural (Domain-Driven Design pattern, not strictly GoF)
**The problem:** domain logic should not know about the database. Tests should not
need a real database.

```csharp
// Interface defined in Domain/Application layer
public interface IOrderRepository
{
    Task<Order?>              GetByIdAsync(OrderId id, CancellationToken ct);
    Task<IReadOnlyList<Order>> GetByCustomerAsync(CustomerId id, CancellationToken ct);
    Task<PagedResult<Order>>  ListAsync(OrderQuery q, CancellationToken ct);
    Task                      SaveAsync(Order order, CancellationToken ct);
    Task                      DeleteAsync(OrderId id, CancellationToken ct);
}

// Implementation in Infrastructure layer (knows about EF Core)
public class EfOrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;
    public EfOrderRepository(AppDbContext db) => _db = db;

    public async Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct)
        => await _db.Orders
            .AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id.Value, ct);

    public async Task<IReadOnlyList<Order>> GetByCustomerAsync(
        CustomerId id, CancellationToken ct)
        => await _db.Orders
            .Where(o => o.CustomerId == id.Value)
            .AsNoTracking()
            .ToListAsync(ct);

    public async Task SaveAsync(Order order, CancellationToken ct)
    {
        _db.Orders.Add(order);
        await _db.SaveChangesAsync(ct);
    }

    public async Task DeleteAsync(OrderId id, CancellationToken ct)
    {
        await _db.Orders.Where(o => o.Id == id.Value).ExecuteDeleteAsync(ct);
    }
}
```

---

## 29.9 Mediator — Decouple Senders from Receivers

**Category:** Behavioral
**The problem:** in large apps with CQRS, every handler needs to find its caller.
Direct coupling creates a web. The Mediator sits in the middle — senders don't
know who handles their request.

```csharp
// Install: MediatR NuGet

// Command (request that changes state)
public record CreateOrderCommand(string CustomerId, decimal Amount)
    : IRequest<OrderId>;

// Handler
public class CreateOrderHandler : IRequestHandler<CreateOrderCommand, OrderId>
{
    private readonly IOrderRepository _repo;
    public CreateOrderHandler(IOrderRepository repo) => _repo = repo;

    public async Task<OrderId> Handle(
        CreateOrderCommand cmd, CancellationToken ct)
    {
        var order = Order.Create(cmd.CustomerId, cmd.Amount);
        await _repo.SaveAsync(order, ct);
        return order.Id;
    }
}

// Query
public record GetOrderQuery(OrderId Id) : IRequest<OrderDto?>;

public class GetOrderHandler : IRequestHandler<GetOrderQuery, OrderDto?>
{
    private readonly IOrderRepository _repo;
    public GetOrderHandler(IOrderRepository repo) => _repo = repo;

    public async Task<OrderDto?> Handle(GetOrderQuery q, CancellationToken ct)
    {
        var order = await _repo.GetByIdAsync(q.Id, ct);
        return order is null ? null : OrderDto.From(order);
    }
}

// Registration
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssembly(typeof(CreateOrderHandler).Assembly));

// Controller/Endpoint — sends to mediator, never knows the handler
app.MapPost("/orders", async (CreateOrderCommand cmd, IMediator mediator, CancellationToken ct) =>
{
    var orderId = await mediator.Send(cmd, ct);
    return Results.Created($"/orders/{orderId}", new { orderId });
});

// Pipeline behaviours (cross-cutting via mediator)
public class ValidationBehaviour<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehaviour(IEnumerable<IValidator<TRequest>> validators)
        => _validators = validators;

    public async Task<TResponse> Handle(TRequest req,
        RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        var context = new ValidationContext<TRequest>(req);
        var failures = _validators
            .Select(v => v.Validate(context))
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count > 0)
            throw new ValidationException(failures);

        return await next();
    }
}
```

---

## 29.10 Facade — Simplify a Complex Subsystem

**Category:** Structural
**The problem:** a subsystem is complex. Callers shouldn't need to know the internals.

```csharp
// ❌ Callers know too much about the internals
var order  = await _orderRepo.GetByIdAsync(id, ct);
var invoice = _invoiceService.GenerateInvoice(order);
var pdf    = _pdfGenerator.Generate(invoice);
await _emailService.AttachAndSendAsync(order.CustomerEmail, pdf, ct);
await _auditLog.LogAsync($"Invoice sent for order {id}", ct);

// ✅ Facade hides the complexity
public class InvoicingFacade
{
    private readonly IOrderRepository _orders;
    private readonly IInvoiceService  _invoices;
    private readonly IPdfGenerator    _pdf;
    private readonly IEmailService    _email;
    private readonly IAuditLog        _audit;

    // ... constructor ...

    public async Task SendInvoiceAsync(OrderId id, CancellationToken ct)
    {
        var order   = await _orders.GetByIdAsync(id, ct);
        var invoice = _invoices.GenerateInvoice(order!);
        var pdf     = _pdf.Generate(invoice);
        await _email.AttachAndSendAsync(order!.CustomerEmail, pdf, ct);
        await _audit.LogAsync($"Invoice sent for {id}", ct);
    }
}

// Caller now:
await _invoicing.SendInvoiceAsync(orderId, ct);
```

---

## 29.11 Template Method — Fixed Algorithm, Variable Steps

**Category:** Behavioral
**The problem:** you have an algorithm whose overall structure is fixed but specific
steps vary by subclass.

```csharp
// Abstract base: defines the algorithm skeleton
public abstract class DataImporter
{
    // Template method — the fixed algorithm
    public async Task ImportAsync(string source, CancellationToken ct)
    {
        var raw  = await ReadAsync(source, ct);      // step 1: variable
        var data = Parse(raw);                        // step 2: variable
        Validate(data);                               // step 3: fixed
        await SaveAsync(data, ct);                    // step 4: variable
        await NotifyAsync(data.Count, ct);            // step 5: fixed
    }

    // Variable steps — subclasses implement these
    protected abstract Task<string> ReadAsync(string source, CancellationToken ct);
    protected abstract IReadOnlyList<Record> Parse(string raw);
    protected abstract Task SaveAsync(IReadOnlyList<Record> data, CancellationToken ct);

    // Fixed steps — shared behaviour
    private void Validate(IReadOnlyList<Record> data)
    {
        if (data.Count == 0) throw new ImportException("No records found.");
    }

    private async Task NotifyAsync(int count, CancellationToken ct)
    {
        // send notification — same for all importers
    }
}

// Concrete importer: CSV
public class CsvDataImporter : DataImporter
{
    protected override Task<string> ReadAsync(string path, CancellationToken ct)
        => File.ReadAllTextAsync(path, ct);

    protected override IReadOnlyList<Record> Parse(string raw)
        => raw.Split('\n').Skip(1).Select(Record.FromCsvLine).ToList();

    protected override Task SaveAsync(IReadOnlyList<Record> data, CancellationToken ct)
        => _db.BulkInsertAsync(data, ct);
}

// JSON importer — different steps, same algorithm structure
public class JsonDataImporter : DataImporter
{
    protected override async Task<string> ReadAsync(string url, CancellationToken ct)
        => await _http.GetStringAsync(url, ct);

    protected override IReadOnlyList<Record> Parse(string raw)
        => JsonSerializer.Deserialize<List<Record>>(raw)!;

    // ...
}
```

---

## 29.12 Quick Reference — Which Pattern When

| Problem | Pattern |
|---|---|
| Multiple algorithms, choose at runtime | Strategy |
| Add behaviour without modifying the class | Decorator |
| Create objects without knowing their concrete type | Factory Method |
| One instance for the whole app | Singleton (via DI) |
| Construct complex objects step by step | Builder |
| Decouple event publishers from subscribers | Observer |
| Simplify a complex subsystem | Facade |
| Decouple request senders from handlers | Mediator |
| Abstract data storage from domain logic | Repository |
| Fix algorithm structure, vary specific steps | Template Method |
| Allow multiple implementations, plug in DI | Strategy + DI |

> **Rider tip:** `Ctrl+Alt+H` (Type Hierarchy) on an interface shows all Strategy/
> Decorator implementations at a glance. `Alt+F7` (Find Usages) on a factory method
> shows every place an object is created through it.

