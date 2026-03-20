# Chapter 18 — Software Architectures

> Architecture is the set of decisions that are hard to change later.
> Getting it wrong does not prevent you from shipping — it just makes
> every subsequent change harder. This chapter explains the most
> important architectural patterns used in .NET systems, each through
> the lens of the problem it solves. By the end, you should be able to
> choose an architecture based on your actual constraints rather than
> fashion or habit.

*Building on:* All of Ch 1–17. Architecture is the organisation of
everything you have learned so far. Ch 5 (interfaces, composition),
Ch 10–11 (DI — the mechanism that enforces architectural rules at
runtime), Ch 17 (testing — architecture determines what is easy or
hard to test)

---

## 18.1 The Problem All Architectures Are Solving

Every architecture answers one question: **which parts of the system are
allowed to depend on which other parts?** This is the dependency rule.

Why does it matter? Because dependencies are transitive — if A depends
on B and B depends on C, then A implicitly depends on C. In a system
where all components can depend on all others, every change ripples
everywhere. You cannot test one piece without all the others. You cannot
swap the database without rewriting business logic.

The patterns in this chapter differ primarily in *how they draw the
boundaries* and *which direction dependencies are allowed to flow*. Each
pattern makes certain changes cheap and certain changes expensive. The
right pattern depends on which changes your system needs to make most
often.

---

## 18.2 Layered Architecture (N-Tier) — The Historical Baseline

The oldest and most familiar pattern. Code is divided into horizontal
layers where each layer can only use the layer directly below it:

```
┌─────────────────────────────────────────┐
│  Presentation (UI, API Controllers)     │
├─────────────────────────────────────────┤
│  Business Logic / Application Layer     │
├─────────────────────────────────────────┤
│  Data Access (Repositories, ORM)        │
├─────────────────────────────────────────┤
│  Database                               │
└─────────────────────────────────────────┘

Dependency direction: top → bottom
```

**What it solves**: separation of concerns. Controllers do not write SQL.
Business logic does not handle HTTP.

**What goes wrong at scale**: the business logic layer (the most
important) depends on the data access layer (an implementation detail).
If you want to swap from SQL Server to PostgreSQL, or add a second data
source, the business logic must change. If you want to unit-test business
logic, you must either use a real database or mock every repository method.

The core symptom of layered architecture done badly: the data access
layer bleeds through into the business logic as `IOrderRepository`
interfaces that look suspiciously like EF Core `DbSet` methods.

---

## 18.3 Onion Architecture — Inversion of Dependencies

Onion Architecture (Jeffrey Palermo, 2008) fixes layered architecture's
dependency problem by inverting it. The domain — the business rules —
is at the centre and depends on nothing. Everything else depends on the
domain, not the other way around.

```
          ┌───────────────────────────────────────┐
          │  Infrastructure                       │
          │  ┌────────────────────────────────┐   │
          │  │  Application / Use Cases       │   │
          │  │  ┌─────────────────────────┐   │   │
          │  │  │  Domain                 │   │   │
          │  │  │  (entities, rules,      │   │   │
          │  │  │   interfaces)           │   │   │
          │  │  └─────────────────────────┘   │   │
          │  └────────────────────────────────┘   │
          └───────────────────────────────────────┘

Dependency rule: all arrows point INWARD
Domain depends on nothing.
Infrastructure depends on Domain.
```

The trick: the Domain defines *interfaces* for the things it needs (a
repository, an email sender). The Infrastructure implements those
interfaces. Dependency injection wires them up at runtime. The Domain
never imports Infrastructure.

```
MyApp.Domain          → no external dependencies
  IOrderRepository    (interface — what the domain needs)
  Order, Customer     (entities)
  OrderService        (business logic)

MyApp.Infrastructure  → depends on Domain
  EfOrderRepository : IOrderRepository  (EF Core implementation)
  SmtpEmailSender   : IEmailSender

MyApp.Api             → depends on Domain and Infrastructure
  OrderController     (wires HTTP to the OrderService)
  Program.cs          (DI registrations)
```

**What this enables**: you can unit-test `OrderService` with fake
repositories — no database needed, no EF Core, pure logic. You can swap
EF Core for Dapper or a different database without touching any domain
code.

---

## 18.4 Clean Architecture — Onion with Explicit Use Cases

Clean Architecture (Robert Martin, 2012) is Onion Architecture with
stronger prescriptions about naming and one addition: explicit *Use
Cases* (also called Interactors or Application Services) as a distinct
layer between the domain and the outer layers.

```
                  ┌─────────────────────────────────────────────┐
Frameworks        │  Web API, EF Core, SMTP, File System        │
& Drivers         └──────────────────────┬──────────────────────┘
                                         │ depends on
                  ┌──────────────────────▼──────────────────────┐
Interface         │  Controllers, Gateways, Presenters           │
Adapters          └──────────────────────┬──────────────────────┘
                                         │ depends on
                  ┌──────────────────────▼──────────────────────┐
Application       │  Use Cases / Application Services            │
Business Rules    │  PlaceOrderUseCase, CancelOrderUseCase       │
                  └──────────────────────┬──────────────────────┘
                                         │ depends on
                  ┌──────────────────────▼──────────────────────┐
Enterprise        │  Entities, Domain Services, Value Objects    │
Business Rules    │  Order, Customer, Money, OrderPolicy         │
                  └─────────────────────────────────────────────┘
```

**What the Use Case layer adds**: the application layer knows about
workflows — the sequence of steps for a business operation. The domain
is pure logic with no knowledge of "place order" as a concept — it just
has `Order`, `Customer`, and rules about them. The Use Case orchestrates
the domain objects to complete the operation.

---

## 18.5 Hexagonal Architecture (Ports & Adapters) — Outside In

Hexagonal Architecture (Alistair Cockburn, 2005) names its abstractions
differently but achieves the same goal: the application is at the centre
and everything external is an adapter that plugs into a port.

```
              ┌──────────────────────────┐
HTTP Client   │  HTTP Adapter            │     ┌─────────────────┐
  →  POST /   │ (Controller)             │     │  Application    │
              └──────────┬───────────────┘     │  Core           │
                         │ drives               │  (domain logic) │
              ┌──────────▼──────────────────────────────────────┐
              │         Port (IOrderService interface)           │
              └──────────────────────────────────────────────────┘
              ┌──────────────────────────────────────────────────┐
              │         Port (IOrderRepository interface)        │
              └──────────┬───────────────────────────────────────┘
                         │ driven by
              ┌──────────▼───────────────┐
              │  Database Adapter         │     ┌─────────────────┐
              │ (EfOrderRepository)       │  →  │  PostgreSQL DB  │
              └──────────────────────────┘     └─────────────────┘
```

**Ports** are interfaces defined by the application. **Adapters** are
implementations of those interfaces that connect to the external world.
The application drives primary adapters (HTTP, CLI) and is driven by
secondary adapters (database, email, message queue).

The naming distinction from Onion is mostly conceptual. In practice,
Hexagonal and Onion produce very similar project structures in .NET.

---

## 18.6 Vertical Slice Architecture — Features, Not Layers

All the previous architectures organise code by technical role (Domain,
Application, Infrastructure). Vertical Slice organises code by *feature*:
everything for "Place Order" lives together — the request, the handler,
the validation, the database query, the response.

```
src/
├── Features/
│   ├── Orders/
│   │   ├── PlaceOrder/
│   │   │   ├── PlaceOrderCommand.cs     ← request
│   │   │   ├── PlaceOrderHandler.cs     ← business logic + data access
│   │   │   ├── PlaceOrderValidator.cs   ← validation
│   │   │   └── PlaceOrderResponse.cs   ← response
│   │   ├── CancelOrder/
│   │   └── GetOrder/
│   └── Customers/
│       ├── RegisterCustomer/
│       └── GetCustomer/
```

**What it solves**: in layered/onion architecture, adding a new feature
requires touching multiple layers — a new service method, a new repository
method, a new controller action. Vertical slices let you add a feature
by adding one folder. Each slice is self-contained.

**The trade-off**: code shared across features (a common query, a shared
validator) does not have an obvious home. Teams can handle this with a
`Shared/` or `Common/` folder for genuinely shared logic.

Vertical Slice pairs naturally with MediatR (Chapter 32) — each slice
is a request/handler pair:

```csharp
// Features/Orders/PlaceOrder/PlaceOrderHandler.cs
public record PlaceOrderCommand(string CustomerId, List<OrderLineDto> Lines)
    : IRequest<PlaceOrderResponse>;

public class PlaceOrderHandler(AppDbContext db, IEmailSender email)
    : IRequestHandler<PlaceOrderCommand, PlaceOrderResponse>
{
    public async Task<PlaceOrderResponse> Handle(
        PlaceOrderCommand cmd, CancellationToken ct)
    {
        var order = new Order { CustomerId = cmd.CustomerId };
        // ... build and save the order ...
        await email.SendConfirmationAsync(cmd.CustomerId, order.Id, ct);
        return new PlaceOrderResponse(order.Id);
    }
}
```

---

## 18.7 CQRS — Separating Reads from Writes

CQRS (Command Query Responsibility Segregation) splits every operation
into a Command (changes state, returns nothing or a minimal result) or
a Query (reads state, changes nothing). These follow separate paths
through the codebase and can use different data models.

The motivation: the data model that is optimal for writes (normalised,
relational, with all constraints) is often suboptimal for reads (you
want a flat, pre-joined, possibly cached view). Trying to serve both
with the same model leads to complex queries and over-fetched data.

```
Command path:               Query path:
PlaceOrderCommand           GetOrdersQuery
    ↓                           ↓
PlaceOrderHandler          GetOrdersQueryHandler
    ↓ uses                      ↓ uses
AppDbContext               AppDbContext (read-only)
(normalised schema)        + Dapper (complex joins)
                           or a read model (denormalised)
```

```csharp
// Command: write operation — returns minimal result
public record PlaceOrderCommand(string CustomerId, List<OrderLine> Lines)
    : IRequest<Guid>;  // returns the new order ID

// Query: read operation — returns a rich view model
public record GetOrdersByCustomerQuery(string CustomerId, int Page)
    : IRequest<PagedResult<OrderSummary>>;

// Query handler can use a different data source or projection
public class GetOrdersByCustomerHandler(AppDbContext db)
    : IRequestHandler<GetOrdersByCustomerQuery, PagedResult<OrderSummary>>
{
    public async Task<PagedResult<OrderSummary>> Handle(
        GetOrdersByCustomerQuery query, CancellationToken ct)
    {
        return await db.Orders
            .AsNoTracking()   // read-only — no change tracking needed
            .Where(o => o.CustomerId == query.CustomerId)
            .Select(o => new OrderSummary(o.Id, o.Total, o.Status, o.CreatedAt))
            .ToPagedResultAsync(query.Page, pageSize: 20, ct);
    }
}
```

CQRS does not require event sourcing or separate databases — those are
additional patterns. Even in a single-database system, splitting Commands
and Queries improves clarity and prevents query logic from leaking into
write paths.

---

## 18.8 Modular Monolith — The Middle Path

A modular monolith is a single deployable unit (one process) partitioned
into bounded modules with well-defined interfaces between them. Modules
cannot access each other's internal data directly — they communicate
through interfaces or events.

```
MyApp (single process)
├── Orders/
│   ├── Internal/          ← private to the module
│   │   ├── OrderService.cs
│   │   └── EfOrderRepository.cs
│   └── Public/            ← the module's public API
│       └── IOrderModule.cs
├── Customers/
│   ├── Internal/
│   └── Public/
└── Inventory/
    ├── Internal/
    └── Public/
```

**What it solves**: microservices add network calls, distributed
transactions, and operational complexity. A well-structured monolith is
easier to develop, test, and debug than premature microservices. When
modules are properly isolated, splitting into microservices later is
a mechanical refactoring, not a rewrite.

---

## 18.9 Choosing an Architecture

| Situation | Consider |
|---|---|
| Simple CRUD app, small team | Vertical Slice or simple layered |
| Long-lived domain with complex rules | Onion / Clean Architecture |
| Feature-centric team, varied feature complexity | Vertical Slice + CQRS |
| Needs to swap infrastructure (DB, email, etc.) | Onion / Hexagonal |
| Many teams working on overlapping areas | Modular Monolith |
| High read/write asymmetry | CQRS |
| Getting started on a new project | Vertical Slice (easiest to grow) |

The most common mistake: choosing Microservices at the start. Microservices
are an operational and organisational pattern — they solve deployment
independence and team autonomy at scale. They add latency, distributed
transactions, and operational burden. Most projects benefit from a well-
structured monolith until those specific problems arise.

---

## 18.10 Project Structure — What Goes Where

A clean architecture in .NET:

```
MyApp.sln
├── src/
│   ├── MyApp.Domain/
│   │   # Entities, Value Objects, Domain Services, Domain Events
│   │   # Zero external dependencies — not even EF Core
│   │   # References: nothing except perhaps a result type library
│   │
│   ├── MyApp.Application/
│   │   # Use Cases, Application Services, Interfaces for Infrastructure
│   │   # IOrderRepository, IEmailSender — defined here, implemented elsewhere
│   │   # References: MyApp.Domain only
│   │
│   ├── MyApp.Infrastructure/
│   │   # EF Core, SMTP, file system, HTTP clients
│   │   # EfOrderRepository : IOrderRepository (from Application)
│   │   # References: MyApp.Application (and transitively Domain)
│   │
│   └── MyApp.Api/
│       # Controllers / Minimal API, DI wiring in Program.cs
│       # The assembly that starts the process
│       # References: all of the above
│
└── tests/
    ├── MyApp.Domain.Tests/      # pure unit tests — no mocks needed
    ├── MyApp.Application.Tests/ # unit tests with fake implementations
    └── MyApp.Integration.Tests/ # real DB via Testcontainers
```

Enforcing these rules:

```xml
<!-- MyApp.Domain.csproj — nothing else -->
<ProjectReference Include="..\MyApp.Domain\MyApp.Domain.csproj" />

<!-- MyApp.Application.csproj — domain only -->
<ProjectReference Include="..\MyApp.Domain\MyApp.Domain.csproj" />

<!-- Add <PrivateAssets>all</PrivateAssets> to prevent transitive leaking -->
```

Chapter 32 covers the Repository and Specification patterns that
implement domain boundaries in code.
