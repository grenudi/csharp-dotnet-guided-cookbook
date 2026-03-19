# Chapter 18 — Software Architectures

Architecture is not decoration. Each pattern below was invented to solve a specific,
painful problem that people kept running into. Understanding the problem first makes
the pattern obvious.

---

## 18.1 The Problem That All Architectures Are Solving

Every architecture is answering one question:

> **How do I keep my business logic from being contaminated by infrastructure details?**

Infrastructure details: database, HTTP, file system, message queue, UI framework.
They change. They are hard to test. They are not your business.

Without architecture, business logic bleeds into HTTP handlers, database queries
bleed into domain logic, and UI code starts making business decisions. Once mixed,
it cannot be unmixed without a rewrite.

The common goal across all patterns:

```
Core logic           → no framework, no I/O, no external deps
                            ↓ depends on
Abstractions         → interfaces defined by the core, not by infra
                            ↓ implemented by
Infrastructure       → the dirty work: DB, HTTP, files, etc.
                            ↓ wired by
Composition root     → Program.cs: the only place that knows everything
```

---

## 18.2 Layered Architecture (N-Tier) — The Origin

**Invented because:** early web apps had everything in one place.
Controllers talked to the database directly. Business logic was in SQL stored procedures.
When the DB changed, everything broke. When the UI changed, everything broke.

**The fix:** separate into horizontal layers, each allowed to talk only to the layer below it.

```
┌─────────────────────────────┐
│      Presentation Layer     │  HTTP, CLI, Blazor, gRPC endpoints
├─────────────────────────────┤
│      Business Logic Layer   │  services, rules, calculations
├─────────────────────────────┤
│      Data Access Layer      │  repositories, ORM, raw SQL
├─────────────────────────────┤
│      Database               │  PostgreSQL, SQLite, etc.
└─────────────────────────────┘
```

### File Tree

```
MyApp/
├── MyApp.sln
├── src/
│   ├── MyApp.Web/               ← Presentation
│   │   ├── Controllers/
│   │   │   └── OrdersController.cs
│   │   └── Program.cs
│   │
│   ├── MyApp.Services/          ← Business Logic
│   │   ├── OrderService.cs
│   │   └── PricingService.cs
│   │
│   └── MyApp.Data/              ← Data Access
│       ├── AppDbContext.cs
│       └── OrderRepository.cs
└── tests/
    └── MyApp.Services.Tests/
```

### Code

```csharp
// MyApp.Data/OrderRepository.cs
public class OrderRepository
{
    private readonly AppDbContext _db;
    public OrderRepository(AppDbContext db) => _db = db;

    public async Task<Order?> GetByIdAsync(int id) =>
        await _db.Orders.FindAsync(id);

    public async Task SaveAsync(Order order)
    {
        _db.Orders.Add(order);
        await _db.SaveChangesAsync();
    }
}

// MyApp.Services/OrderService.cs
public class OrderService
{
    private readonly OrderRepository _repo;          // depends on concrete class ← problem
    private readonly PricingService  _pricing;

    public OrderService(OrderRepository repo, PricingService pricing)
    { _repo = repo; _pricing = pricing; }

    public async Task<decimal> PlaceOrderAsync(int productId, int qty)
    {
        var price = _pricing.Calculate(productId, qty);
        var order = new Order(productId, qty, price);
        await _repo.SaveAsync(order);
        return price;
    }
}
```

### Why It Falls Short

```
MyApp.Services depends on MyApp.Data  ← business logic knows about the database
MyApp.Services depends on AppDbContext ← cannot test without a real database
MyApp.Web depends on MyApp.Services   ← OK
MyApp.Web depends on MyApp.Data       ← often leaks through
```

The layers call downward, but **they reference concrete implementations**.
Swap the database and you must rewrite `OrderService`. This led to the next pattern.

---

## 18.3 Onion Architecture — Dependency Inversion Applied

**Invented by:** Jeffrey Palermo, 2008.
**Problem it solved:** in layered architecture, the business layer still depends on
the data layer. Onion inverts this — the core defines what it *needs* (interfaces),
and outer layers implement those needs.

```
       ┌──────────────────────────────┐
       │         Infrastructure       │  DB, HTTP, file system
       │   ┌──────────────────────┐   │
       │   │     Application      │   │  use cases, services
       │   │   ┌──────────────┐   │   │
       │   │   │    Domain    │   │   │  entities, value objects, domain services
       │   │   │  (no deps)   │   │   │
       │   │   └──────────────┘   │   │
       │   └──────────────────────┘   │
       └──────────────────────────────┘

Dependencies point INWARD only.
Domain knows nothing. Infrastructure knows everything.
```

### File Tree

```
MyApp/
├── MyApp.sln
├── src/
│   ├── MyApp.Domain/            ← innermost ring, zero external deps
│   │   ├── Entities/
│   │   │   ├── Order.cs
│   │   │   └── Product.cs
│   │   ├── ValueObjects/
│   │   │   ├── Money.cs
│   │   │   └── OrderId.cs
│   │   └── Interfaces/          ← interfaces defined HERE, implemented OUTSIDE
│   │       ├── IOrderRepository.cs
│   │       └── IPricingService.cs
│   │
│   ├── MyApp.Application/       ← use cases, orchestration
│   │   ├── Orders/
│   │   │   ├── PlaceOrderCommand.cs
│   │   │   └── PlaceOrderHandler.cs
│   │   └── ApplicationExtensions.cs
│   │
│   ├── MyApp.Infrastructure/    ← implements domain interfaces
│   │   ├── Persistence/
│   │   │   ├── AppDbContext.cs
│   │   │   └── SqlOrderRepository.cs  ← implements IOrderRepository
│   │   └── InfrastructureExtensions.cs
│   │
│   └── MyApp.Api/               ← outermost, composition root
│       ├── Endpoints/
│       │   └── OrderEndpoints.cs
│       └── Program.cs
└── tests/
    ├── MyApp.Domain.Tests/      ← pure unit tests, zero mocks needed
    ├── MyApp.Application.Tests/ ← mock infrastructure interfaces
    └── MyApp.Integration.Tests/ ← real DB via Testcontainers
```

### Code

```csharp
// Domain/ValueObjects/OrderId.cs — domain primitive, no deps
public record OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
    public override string ToString() => Value.ToString();
}

// Domain/ValueObjects/Money.cs
public record Money(decimal Amount, string Currency)
{
    public static Money Zero(string currency) => new(0, currency);
    public Money Add(Money other)
    {
        if (Currency != other.Currency) throw new InvalidOperationException("Currency mismatch");
        return this with { Amount = Amount + other.Amount };
    }
    public override string ToString() => $"{Amount:F2} {Currency}";
}

// Domain/Entities/Order.cs — pure domain, no framework, no DB, no HTTP
public class Order
{
    public OrderId Id { get; }
    public string  CustomerId { get; }
    public Money   Total { get; private set; }
    public OrderStatus Status { get; private set; }

    private Order() { } // EF Core needs this
    public Order(OrderId id, string customerId, Money total)
    {
        ArgumentException.ThrowIfNullOrEmpty(customerId);
        Id         = id;
        CustomerId = customerId;
        Total      = total;
        Status     = OrderStatus.Pending;
    }

    public void Ship()
    {
        if (Status != OrderStatus.Pending)
            throw new InvalidOperationException($"Cannot ship a {Status} order.");
        Status = OrderStatus.Shipped;
    }
}

public enum OrderStatus { Pending, Shipped, Delivered, Cancelled }

// Domain/Interfaces/IOrderRepository.cs — interface owned by Domain
public interface IOrderRepository
{
    Task<Order?>              GetByIdAsync(OrderId id, CancellationToken ct = default);
    Task<IReadOnlyList<Order>> GetByCustomerAsync(string customerId, CancellationToken ct = default);
    Task                       SaveAsync(Order order, CancellationToken ct = default);
}

// Application/Orders/PlaceOrderCommand.cs
public record PlaceOrderCommand(string CustomerId, decimal Amount, string Currency);
public record PlaceOrderResult(OrderId OrderId, Money Total);

// Application/Orders/PlaceOrderHandler.cs — business logic, depends on interface
public class PlaceOrderHandler
{
    private readonly IOrderRepository _orders;
    private readonly ILogger<PlaceOrderHandler> _log;

    public PlaceOrderHandler(IOrderRepository orders, ILogger<PlaceOrderHandler> log)
    { _orders = orders; _log = log; }

    public async Task<PlaceOrderResult> HandleAsync(PlaceOrderCommand cmd, CancellationToken ct)
    {
        var id    = OrderId.New();
        var total = new Money(cmd.Amount, cmd.Currency);
        var order = new Order(id, cmd.CustomerId, total);

        await _orders.SaveAsync(order, ct);
        _log.LogInformation("Order {OrderId} placed for {Customer}", id, cmd.CustomerId);

        return new PlaceOrderResult(id, total);
    }
}

// Infrastructure/Persistence/SqlOrderRepository.cs — implements the interface
public class SqlOrderRepository : IOrderRepository
{
    private readonly AppDbContext _db;
    public SqlOrderRepository(AppDbContext db) => _db = db;

    public async Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct) =>
        await _db.Orders.FindAsync([id.Value], ct);

    public async Task<IReadOnlyList<Order>> GetByCustomerAsync(string customerId, CancellationToken ct) =>
        await _db.Orders.Where(o => o.CustomerId == customerId).ToListAsync(ct);

    public async Task SaveAsync(Order order, CancellationToken ct)
    {
        _db.Orders.Add(order);
        await _db.SaveChangesAsync(ct);
    }
}

// Api/Program.cs — composition root, only place that knows everything
var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddApplication()     // registers PlaceOrderHandler etc.
    .AddInfrastructure(builder.Configuration);  // registers SqlOrderRepository etc.

var app = builder.Build();
app.MapOrderEndpoints();
app.Run();
```

### Why Onion Is Better Than Layered

```
Domain        → zero deps. Test with no mocks, no DB, no anything.
Application   → depends on Domain interfaces. Swap real DB for fake in 1 line.
Infrastructure → depends on Domain + Application. Knows about EF Core, SQL.
Api           → depends on everything. Just wires it together.

If you change the database: only Infrastructure changes.
If you change the UI framework: only Api changes.
Domain and Application never change for infrastructure reasons.
```

---

## 18.4 Clean Architecture — Onion With Explicit Use Cases

**Invented by:** Robert C. Martin (Uncle Bob), 2012.
**Same fundamental idea as Onion.** The difference is naming and the emphasis on
explicit **Use Cases** as the central unit of the application.

```
         ┌───────────────────────────────────────┐
         │  Frameworks & Drivers (outermost)     │  Express, EF Core, ASP.NET
         │  ┌─────────────────────────────────┐  │
         │  │       Interface Adapters        │  │  Controllers, Presenters, Gateways
         │  │  ┌───────────────────────────┐  │  │
         │  │  │  Application / Use Cases  │  │  │  PlaceOrder, GetUser, etc.
         │  │  │  ┌─────────────────────┐  │  │  │
         │  │  │  │    Entities         │  │  │  │  Business rules, domain objects
         │  │  │  └─────────────────────┘  │  │  │
         │  │  └───────────────────────────┘  │  │
         │  └─────────────────────────────────┘  │
         └───────────────────────────────────────┘

The Dependency Rule: source code dependencies point inward only.
Nothing in an inner circle can know about an outer circle.
```

### File Tree

```
MyApp/
├── src/
│   ├── MyApp.Domain/
│   │   ├── Entities/
│   │   ├── ValueObjects/
│   │   └── Interfaces/
│   │
│   ├── MyApp.Application/
│   │   ├── Common/
│   │   │   ├── Interfaces/          ← ports: IUnitOfWork, IEmailSender, etc.
│   │   │   └── Behaviours/          ← pipeline: logging, validation, auth
│   │   └── Features/
│   │       ├── Orders/
│   │       │   ├── Commands/
│   │       │   │   └── PlaceOrder/
│   │       │   │       ├── PlaceOrderCommand.cs
│   │       │   │       ├── PlaceOrderHandler.cs
│   │       │   │       └── PlaceOrderValidator.cs
│   │       │   └── Queries/
│   │       │       └── GetOrder/
│   │       │           ├── GetOrderQuery.cs
│   │       │           └── GetOrderHandler.cs
│   │       └── Users/
│   │           └── ...
│   │
│   ├── MyApp.Infrastructure/
│   │   ├── Persistence/
│   │   ├── Email/
│   │   └── ...
│   │
│   └── MyApp.Api/
│       ├── Controllers/ or Endpoints/
│       └── Program.cs
```

Clean Architecture is Onion + the **CQRS** split of commands vs. queries.
In practice they are used together.

---

## 18.5 Hexagonal Architecture (Ports & Adapters)

**Invented by:** Alistair Cockburn, 2005. The oldest of the three.
**Same fundamental idea.** Different vocabulary.

```
                    ┌──────────────────────────┐
    HTTP Request ──►│                          │◄── Test Driver
    CLI Args     ──►│   Port (interface)        │
                    │                          │
                    │      APPLICATION         │
                    │      (pure logic)        │
                    │                          │
                    │   Port (interface)        │──► Database Adapter
                    │                          │──► Email Adapter
                    └──────────────────────────┘──► File System Adapter

Ports = interfaces defined by the application
Adapters = concrete implementations of those ports (the outside world)
```

### Vocabulary Mapping

```
Hexagonal           Clean / Onion          What it means
──────────────────  ─────────────────────  ──────────────────────────────
Port                Interface              contract defined by the core
Driving Adapter     Controller / CLI       something that calls the core
Driven Adapter      Repository / Sender    something the core calls
Primary Port        Use Case interface     entry point into the core
Secondary Port      IRepository, IEmail    exit point from the core
```

They are the same pattern. Choose the vocabulary your team knows.

---

## 18.6 Vertical Slice Architecture — Features, Not Layers

**Invented by:** Jimmy Bogard, ~2018.
**Problem it solved:** in layered/onion architecture, adding one feature touches
every layer. A single "add user" feature requires changes in the Controller,
the Service, the Repository, and the Model. Four files across four folders.
The feature is invisible as a unit.

**The fix:** slice the application vertically by feature. Each feature owns its
full stack — from HTTP to database — in one place.

```
Horizontal layers:           Vertical slices:
┌────────────────┐           ┌──────┬──────┬──────┬──────┐
│  Controllers   │           │Order │ User │Invoice│Product
├────────────────┤           │  ↕   │  ↕   │  ↕   │  ↕  │
│   Services     │    vs     │ full │ full │ full │ full │
├────────────────┤           │stack │stack │stack │stack│
│  Repositories  │           └──────┴──────┴──────┴──────┘
└────────────────┘           Each feature is self-contained
```

### File Tree

```
MyApp/
├── src/
│   ├── MyApp.Api/
│   │   ├── Program.cs
│   │   ├── Shared/
│   │   │   ├── AppDbContext.cs      ← shared EF context
│   │   │   └── BaseEndpoint.cs
│   │   │
│   │   └── Features/
│   │       ├── Orders/
│   │       │   ├── PlaceOrder.cs    ← command + handler + endpoint in ONE file
│   │       │   ├── GetOrder.cs
│   │       │   ├── ListOrders.cs
│   │       │   └── CancelOrder.cs
│   │       │
│   │       ├── Users/
│   │       │   ├── RegisterUser.cs
│   │       │   ├── LoginUser.cs
│   │       │   └── GetUserProfile.cs
│   │       │
│   │       └── Products/
│   │           ├── CreateProduct.cs
│   │           └── ListProducts.cs
```

### Code — One File Per Feature

```csharp
// Features/Orders/PlaceOrder.cs — everything for this use case in one file
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MyApp.Features.Orders;

// ── Request / Response ────────────────────────────────────────────────
public record PlaceOrderRequest(string CustomerId, decimal Amount, string Currency);
public record PlaceOrderResponse(Guid OrderId, decimal Total);

// ── Handler (the logic) ───────────────────────────────────────────────
public class PlaceOrderHandler
{
    private readonly AppDbContext _db;
    private readonly ILogger<PlaceOrderHandler> _log;

    public PlaceOrderHandler(AppDbContext db, ILogger<PlaceOrderHandler> log)
    { _db = db; _log = log; }

    public async Task<PlaceOrderResponse> HandleAsync(
        PlaceOrderRequest req, CancellationToken ct)
    {
        var order = new Order
        {
            Id         = Guid.NewGuid(),
            CustomerId = req.CustomerId,
            Total      = req.Amount,
            Currency   = req.Currency,
            PlacedAt   = DateTime.UtcNow
        };

        _db.Orders.Add(order);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Order {Id} placed", order.Id);
        return new PlaceOrderResponse(order.Id, order.Total);
    }
}

// ── Endpoint (the HTTP wire-up) ───────────────────────────────────────
public static class PlaceOrderEndpoint
{
    public static void Map(IEndpointRouteBuilder app) =>
        app.MapPost("/orders", async (
            PlaceOrderRequest req,
            PlaceOrderHandler handler,
            CancellationToken ct) =>
        {
            var result = await handler.HandleAsync(req, ct);
            return Results.Created($"/orders/{result.OrderId}", result);
        });
}

// ── Registration ──────────────────────────────────────────────────────
public static class PlaceOrderModule
{
    public static IServiceCollection AddPlaceOrder(this IServiceCollection s) =>
        s.AddScoped<PlaceOrderHandler>();
}
```

```csharp
// Program.cs — just registers features and maps endpoints
var builder = WebApplication.CreateBuilder(args);
builder.Services
    .AddDbContext<AppDbContext>(...)
    .AddPlaceOrder()
    .AddRegisterUser()
    .AddCreateProduct();

var app = builder.Build();
PlaceOrderEndpoint.Map(app);
RegisterUserEndpoint.Map(app);
app.Run();
```

### When Vertical Slice Wins

- Teams where each developer owns whole features end-to-end
- CRUD-heavy applications where features are independent
- When you keep adding features but rarely modify existing ones

### When It Struggles

- Heavy shared domain logic (conflict resolution, pricing rules) — code duplicates
  across slices or you end up re-extracting a Domain layer anyway
- Large teams needing strict cross-cutting enforcement

---

## 18.7 CQRS — Commands and Queries Never Mix

**Invented by:** Greg Young, 2010. Based on CQS (Bertrand Meyer, 1988).
**Problem it solved:** read and write models are fundamentally different.
Reads are frequent, can be denormalized, need no validation.
Writes are rarer, need validation, need domain logic.
Using one model for both forces compromises on both.

```
Without CQRS:                    With CQRS:
GetUser(id) → User               GetUser(id) → UserDto (read model, optimized)
UpdateUser(user)                  UpdateUser(cmd) → Unit (write model, validated)
Both use the same User class      Different models, different pipelines
```

### File Tree

```
MyApp.Application/
└── Features/
    └── Orders/
        ├── Commands/
        │   ├── PlaceOrder/
        │   │   ├── PlaceOrderCommand.cs    ← changes state
        │   │   ├── PlaceOrderHandler.cs
        │   │   └── PlaceOrderValidator.cs
        │   └── CancelOrder/
        │       ├── CancelOrderCommand.cs
        │       └── CancelOrderHandler.cs
        └── Queries/
            ├── GetOrder/
            │   ├── GetOrderQuery.cs        ← reads state
            │   ├── GetOrderHandler.cs
            │   └── OrderDto.cs             ← read model, not the domain entity
            └── ListOrders/
                ├── ListOrdersQuery.cs
                ├── ListOrdersHandler.cs
                └── OrderSummaryDto.cs
```

### Code

```csharp
// Commands/PlaceOrder/PlaceOrderCommand.cs
// A command changes state. Returns only what the caller needs (the new ID).
public record PlaceOrderCommand(string CustomerId, decimal Amount, string Currency);
public record PlaceOrderResult(Guid OrderId);

// Queries/GetOrder/GetOrderQuery.cs
// A query reads state. Never changes anything. Returns a read-optimized DTO.
public record GetOrderQuery(Guid OrderId);
public record OrderDto(
    Guid     OrderId,
    string   CustomerId,
    decimal  Total,
    string   Currency,
    string   Status,
    DateTime PlacedAt);

// Queries/GetOrder/GetOrderHandler.cs
// Query handler uses Dapper or direct EF projection — no domain entity needed
public class GetOrderHandler
{
    private readonly AppDbContext _db;
    public GetOrderHandler(AppDbContext db) => _db = db;

    public async Task<OrderDto?> HandleAsync(GetOrderQuery q, CancellationToken ct) =>
        await _db.Orders
            .Where(o => o.Id == q.OrderId)
            .Select(o => new OrderDto(
                o.Id, o.CustomerId, o.Total, o.Currency,
                o.Status.ToString(), o.PlacedAt))
            .FirstOrDefaultAsync(ct);
}
```

### CQRS Without Event Sourcing

Most teams use **Simple CQRS**: commands and queries in the same database,
same app, just separated by type. This is the 80% case and adds no infrastructure complexity.

**Event-sourced CQRS** (separate read/write databases, event store, projections)
is a separate architecture used for audit logs, temporal queries, or very high
write throughput. Do not use it unless you have a specific need for it.

---

## 18.8 Modular Monolith — The Middle Path

**Problem it solved:** microservices add enormous operational complexity
(service discovery, distributed tracing, network latency, eventual consistency).
Most teams don't need that complexity but still need to enforce module boundaries.
A Modular Monolith gives you microservice-level boundaries inside one process.

```
One deployable unit (one process, one database)
But internally: strong boundaries enforced by code, not by network
Each module has its own:
  - Public API (interface or minimal set of public types)
  - Private internals (sealed from other modules)
  - Own DB tables (no cross-module table joins — use events or APIs)
```

### File Tree

```
MyApp/
├── MyApp.sln
├── src/
│   ├── MyApp.Host/                  ← entry point only
│   │   └── Program.cs
│   │
│   ├── Modules/
│   │   ├── Orders/
│   │   │   ├── Orders.Module.csproj
│   │   │   ├── OrdersModule.cs      ← public: registration only
│   │   │   ├── Api/                 ← public endpoints
│   │   │   │   └── OrderEndpoints.cs
│   │   │   └── Internal/            ← private: nobody outside can reference this
│   │   │       ├── Domain/
│   │   │       ├── Application/
│   │   │       └── Infrastructure/
│   │   │
│   │   ├── Users/
│   │   │   ├── Users.Module.csproj
│   │   │   ├── UsersModule.cs
│   │   │   ├── Api/
│   │   │   └── Internal/
│   │   │
│   │   └── Notifications/
│   │       ├── Notifications.Module.csproj
│   │       └── ...
│   │
│   └── Shared/
│       └── MyApp.Shared.Contracts/  ← events/DTOs shared between modules
│           ├── OrderPlacedEvent.cs
│           └── UserRegisteredEvent.cs
```

### Enforcing Module Boundaries

```csharp
// Orders.Module.csproj — internal types are hidden by InternalsVisibleTo
<ItemGroup>
  <!-- Only the test project can see internals -->
  <InternalsVisibleTo Include="Orders.Tests" />
</ItemGroup>

// OrdersModule.cs — the ONLY public surface of the Orders module
public static class OrdersModule
{
    public static IServiceCollection AddOrders(this IServiceCollection s, IConfiguration cfg)
    {
        // Registers everything. Callers don't know what's inside.
        s.AddDbContext<OrdersDbContext>(...);
        s.AddScoped<Internal.Application.PlaceOrderHandler>();
        // ...
        return s;
    }

    public static IEndpointRouteBuilder MapOrders(this IEndpointRouteBuilder app)
    {
        Api.OrderEndpoints.Map(app);
        return app;
    }
}

// Internal/Domain/Order.cs — internal: invisible to other modules
internal class Order { ... }

// Internal/Application/PlaceOrderHandler.cs
internal class PlaceOrderHandler { ... }
```

```csharp
// Shared/Contracts/OrderPlacedEvent.cs — shared between modules via events
// Modules communicate through events, never by calling each other's internals
public record OrderPlacedEvent(
    Guid OrderId,
    string CustomerId,
    decimal Total,
    DateTime PlacedAt);

// Orders module publishes:
await _eventBus.PublishAsync(new OrderPlacedEvent(order.Id, ...));

// Notifications module subscribes:
public class OrderPlacedHandler : IEventHandler<OrderPlacedEvent>
{
    public async Task HandleAsync(OrderPlacedEvent e, CancellationToken ct)
        => await _email.SendAsync(e.CustomerId, "Your order was placed!");
}
```

```csharp
// Host/Program.cs — clean, three lines per module
var builder = WebApplication.CreateBuilder(args);
builder.Services
    .AddOrders(builder.Configuration)
    .AddUsers(builder.Configuration)
    .AddNotifications(builder.Configuration);

var app = builder.Build();
app.MapOrders()
   .MapUsers();
app.Run();
```

---

## 18.9 Decision Guide

### By Project Type

| Project type | Recommended architecture |
|---|---|
| Console tool / script | None (flat `Program.cs`) or simple layered |
| Small API (< 10 endpoints) | Vertical Slice or minimal Onion |
| Medium API (10–50 endpoints) | Clean / Onion with CQRS |
| Large API / product | Modular Monolith with Clean Architecture per module |
| Multiple teams, separate deploy | Microservices (out of scope here) |
| Blazor / MAUI app | MVVM within the UI, Clean Architecture for the backend it talks to |
| Worker / daemon | Flat or minimal Onion: one BackgroundService, interfaces for I/O |

### By Team Size

```
1–3 developers   → Vertical Slice or simple Onion. Low overhead.
4–8 developers   → Clean Architecture with CQRS. One pattern everyone knows.
8+ developers    → Modular Monolith. Each team owns a module.
Multiple teams   → Evaluate microservices only if deployment independence is required.
```

### The Path Most Teams Take

```
1. Start with Vertical Slice (fast, feature-focused)
           ↓ grows, domain logic starts duplicating across slices
2. Extract a Domain layer (Onion without the full stack)
           ↓ grows, multiple teams, boundaries need enforcement
3. Move to Modular Monolith
           ↓ only if specific modules need independent scaling/deployment
4. Extract modules as microservices (if ever)
```

Skipping steps is possible but expensive. Most applications never need step 4.

---

## 18.10 The Anti-Patterns to Avoid

### Anemic Domain Model

```csharp
// ❌ Anemic — entity is just a bag of properties, no behaviour
public class Order
{
    public Guid   Id { get; set; }
    public string Status { get; set; }
    public decimal Total { get; set; }
}

// Business logic lives in a service, operates on the anemic entity
public class OrderService
{
    public void Ship(Order order)
    {
        if (order.Status != "Pending") throw new Exception("...");
        order.Status = "Shipped"; // mutating external state
    }
}

// ✅ Rich domain model — entity owns its own behaviour
public class Order
{
    public OrderStatus Status { get; private set; }
    public void Ship()
    {
        if (Status != OrderStatus.Pending) throw new DomainException("...");
        Status = OrderStatus.Shipped;
    }
}
```

### Smart Controller / Fat Handler

```csharp
// ❌ Business logic in the HTTP handler
app.MapPost("/orders", async (PlaceOrderRequest req, AppDbContext db) =>
{
    // pricing logic here
    var discount = req.CustomerId.StartsWith("VIP") ? 0.2m : 0m;
    var total    = req.Amount * (1 - discount);

    // validation here
    if (total <= 0) return Results.BadRequest("...");

    // persistence here
    db.Orders.Add(new Order { ... });
    await db.SaveChangesAsync();

    return Results.Ok();
});

// ✅ Handler is thin — delegates to the application layer
app.MapPost("/orders", async (PlaceOrderRequest req, PlaceOrderHandler handler, CancellationToken ct) =>
{
    var result = await handler.HandleAsync(req, ct);
    return Results.Created($"/orders/{result.OrderId}", result);
});
```

### God Context / Shared Database Across Modules

```csharp
// ❌ All modules join across each other's tables
var query = db.Orders
    .Join(db.Users,  o => o.UserId,  u => u.Id, ...)
    .Join(db.Products, o => o.ProductId, p => p.Id, ...)
    // Orders module now depends on Users and Products tables directly
    // Cannot change Users table without potentially breaking Orders queries

// ✅ Each module has its own DbContext, communicates via events or APIs
// Orders module only sees orders tables
// If it needs user data, it either:
//   a) stores a denormalized copy of what it needs
//   b) calls the Users module's public API
//   c) subscribes to UserUpdated events
```

---

## 18.11 Seeing Architecture in Rider

**Navigate dependencies:**
- *Analyze → Architecture → Show Project Dependency Diagram* — visual map of which projects reference which
- Red arrows = unexpected dependency (e.g., Domain referencing Infrastructure)

**Enforce dependencies:**
- *Solution → Properties → Module Dependencies* — define allowed dependencies, Rider warns on violations

**Check for layer leakage:**
- `Alt+F7` on an Infrastructure type — if it appears in Domain, you have a leak
- Rider's inspections highlight when `internal` types are referenced from outside their assembly

> **Tip:** create an Architecture test using `NetArchTest.Rules` NuGet package — fails the build if any dependency rule is violated:

```csharp
// tests/Architecture.Tests/DependencyTests.cs
[Fact]
public void Domain_Should_Not_Reference_Infrastructure()
{
    var result = Types.InAssembly(typeof(Order).Assembly)
        .Should().NotHaveDependencyOn("MyApp.Infrastructure")
        .GetResult();

    result.IsSuccessful.Should().BeTrue();
}

[Fact]
public void Application_Should_Not_Reference_Api()
{
    var result = Types.InAssembly(typeof(PlaceOrderHandler).Assembly)
        .Should().NotHaveDependencyOn("MyApp.Api")
        .GetResult();

    result.IsSuccessful.Should().BeTrue();
}
```

