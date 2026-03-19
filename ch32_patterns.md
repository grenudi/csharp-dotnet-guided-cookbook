# Chapter 32 — Common Design Patterns: MediatR, ErrorOr, Repository & More

## 32.1 Why These Patterns

These are not abstract academic patterns. They are solutions to specific problems
that production .NET codebases repeatedly run into. Each one eliminates a recurring
class of coupling or duplication.

---

## 32.2 Mediator Pattern — MediatR

**Problem:** services calling each other directly creates a web of dependencies.
`OrderService` knows about `EmailService`, `InventoryService`, `AuditService`.
Every new action requires touching every related service.

**Solution:** a mediator sits in the middle. Senders send requests without knowing
who handles them. Handlers handle requests without knowing who sent them.

```
Without mediator:          With mediator:
OrderService               OrderService
  → EmailService             → IMediator.Send(PlaceOrderCommand)
  → InventoryService                 ↓
  → AuditService           PlaceOrderHandler (handles it)
  → NotificationService    EmailHandler      (handles OrderPlacedEvent)
                           InventoryHandler  (handles OrderPlacedEvent)
                           AuditHandler      (handles OrderPlacedEvent)
```

```bash
dotnet add package MediatR
```

### Commands (change state, return a result)

```csharp
// Command — request to do something
public record PlaceOrderCommand(
    string CustomerId,
    string Sku,
    int    Quantity,
    decimal UnitPrice) : IRequest<Result<OrderId, DomainError>>;

// Handler — handles the command
public class PlaceOrderHandler
    : IRequestHandler<PlaceOrderCommand, Result<OrderId, DomainError>>
{
    private readonly IOrderRepository _orders;
    private readonly IMediator        _mediator;

    public PlaceOrderHandler(IOrderRepository orders, IMediator mediator)
    { _orders = orders; _mediator = mediator; }

    public async Task<Result<OrderId, DomainError>> Handle(
        PlaceOrderCommand cmd, CancellationToken ct)
    {
        var order = Order.Create(cmd.CustomerId, cmd.Sku, cmd.Quantity, cmd.UnitPrice);
        await _orders.SaveAsync(order, ct);

        // Publish domain event — decoupled from what happens next
        await _mediator.Publish(new OrderPlacedEvent(order.Id, cmd.CustomerId), ct);

        return Result<OrderId, DomainError>.Ok(order.Id);
    }
}
```

### Queries (read state, no side effects)

```csharp
// Query — request to read something
public record GetOrderQuery(OrderId OrderId) : IRequest<OrderDto?>;

// Handler
public class GetOrderHandler : IRequestHandler<GetOrderQuery, OrderDto?>
{
    private readonly IOrderRepository _orders;

    public GetOrderHandler(IOrderRepository orders) => _orders = orders;

    public async Task<OrderDto?> Handle(GetOrderQuery q, CancellationToken ct)
    {
        var order = await _orders.GetByIdAsync(q.OrderId, ct);
        return order is null ? null : OrderDto.From(order);
    }
}
```

### Notifications (domain events — multiple handlers)

```csharp
// Notification — something that happened (multiple handlers can react)
public record OrderPlacedEvent(OrderId OrderId, string CustomerId) : INotification;

// Multiple handlers — each is independent
public class SendConfirmationEmailHandler : INotificationHandler<OrderPlacedEvent>
{
    private readonly IEmailSender _email;
    public SendConfirmationEmailHandler(IEmailSender email) => _email = email;

    public async Task Handle(OrderPlacedEvent notification, CancellationToken ct)
        => await _email.SendAsync(notification.CustomerId, "Order confirmed", ct);
}

public class UpdateInventoryHandler : INotificationHandler<OrderPlacedEvent>
{
    public async Task Handle(OrderPlacedEvent notification, CancellationToken ct)
    { /* deduct from inventory */ }
}
```

### Registration and Usage

```csharp
// Program.cs — one line registers all handlers in the assembly
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssembly(typeof(PlaceOrderCommand).Assembly));

// In the controller — no knowledge of the handler
[HttpPost]
public async Task<IActionResult> PlaceOrder(PlaceOrderRequest req, CancellationToken ct)
{
    var result = await _mediator.Send(new PlaceOrderCommand(
        req.CustomerId, req.Sku, req.Quantity, req.UnitPrice), ct);

    return result.Match<IActionResult>(
        ok:   id    => CreatedAtAction(nameof(GetOrder), new { id }, new { id }),
        fail: error => BadRequest(error.Message));
}
```

### Pipeline Behaviours (Cross-Cutting Concerns)

```csharp
// Logging behaviour — wraps every request
public class LoggingBehaviour<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<LoggingBehaviour<TRequest, TResponse>> _log;

    public LoggingBehaviour(ILogger<LoggingBehaviour<TRequest, TResponse>> log)
        => _log = log;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var name = typeof(TRequest).Name;
        _log.LogInformation("→ Handling {Request}", name);
        var sw = Stopwatch.StartNew();
        try
        {
            var response = await next();
            _log.LogInformation("← {Request} completed in {Ms}ms", name, sw.ElapsedMilliseconds);
            return response;
        }
        catch (Exception ex)
        {
            _log.LogError(ex, "← {Request} failed after {Ms}ms", name, sw.ElapsedMilliseconds);
            throw;
        }
    }
}

// Validation behaviour
public class ValidationBehaviour<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehaviour(IEnumerable<IValidator<TRequest>> validators)
        => _validators = validators;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (!_validators.Any()) return await next();

        var context = new ValidationContext<TRequest>(request);
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

// Register behaviours
builder.Services.AddTransient(typeof(IPipelineBehavior<,>), typeof(LoggingBehaviour<,>));
builder.Services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehaviour<,>));
```

---

## 32.3 Result Pattern — ErrorOr

The Result pattern was covered in Ch 6 §6.3. The `ErrorOr` library provides
a production-ready, idiomatic implementation.

```bash
dotnet add package ErrorOr
```

```csharp
using ErrorOr;

// Domain errors as static values
public static class Errors
{
    public static class Order
    {
        public static Error NotFound(Guid id) =>
            Error.NotFound("Order.NotFound", $"Order {id} was not found.");

        public static Error AlreadyShipped =>
            Error.Conflict("Order.AlreadyShipped", "Order has already been shipped.");

        public static Error InvalidAmount(decimal amount) =>
            Error.Validation("Order.InvalidAmount",
                $"Amount {amount} is not valid. Must be greater than zero.");
    }
}

// Service returns ErrorOr<T>
public async Task<ErrorOr<OrderDto>> GetOrderAsync(Guid id, CancellationToken ct)
{
    var order = await _repo.GetByIdAsync(new OrderId(id), ct);
    if (order is null) return Errors.Order.NotFound(id);
    return OrderDto.From(order);
}

public async Task<ErrorOr<Updated>> ShipOrderAsync(Guid id, CancellationToken ct)
{
    var order = await _repo.GetByIdAsync(new OrderId(id), ct);
    if (order is null)     return Errors.Order.NotFound(id);
    if (order.IsShipped()) return Errors.Order.AlreadyShipped;

    order.Ship();
    await _repo.SaveAsync(order, ct);
    return Result.Updated;
}

// Controller maps ErrorOr to HTTP — one consistent place
[HttpGet("{id:guid}")]
public async Task<IActionResult> Get(Guid id, CancellationToken ct)
{
    var result = await _service.GetOrderAsync(id, ct);

    return result.Match(
        value => Ok(value),
        errors => errors.First().Type switch
        {
            ErrorType.NotFound   => NotFound(errors.First().Description),
            ErrorType.Validation => BadRequest(errors.First().Description),
            ErrorType.Conflict   => Conflict(errors.First().Description),
            _                    => Problem(errors.First().Description)
        });
}
```

---

## 32.4 Repository Pattern

Already introduced in Ch 18. The key points in practice:

```csharp
// ✅ Generic base interface — common CRUD
public interface IRepository<T, TId>
    where T  : class, IEntity
    where TId : notnull
{
    Task<T?>                    GetByIdAsync(TId id, CancellationToken ct = default);
    Task<IReadOnlyList<T>>      GetAllAsync(CancellationToken ct = default);
    Task<TId>                   AddAsync(T entity, CancellationToken ct = default);
    Task                        UpdateAsync(T entity, CancellationToken ct = default);
    Task                        DeleteAsync(TId id, CancellationToken ct = default);
}

// ✅ Specific interface — extends with domain queries
public interface IOrderRepository : IRepository<Order, OrderId>
{
    Task<IReadOnlyList<Order>> GetByCustomerAsync(CustomerId id, CancellationToken ct);
    Task<IReadOnlyList<Order>> GetPendingAsync(CancellationToken ct);
    Task<PagedResult<Order>>   GetPagedAsync(OrderQuery query, CancellationToken ct);
}

// ✅ Unit of Work — group multiple operations in one transaction
public interface IUnitOfWork : IDisposable
{
    IOrderRepository   Orders   { get; }
    IUserRepository    Users    { get; }
    Task<int> CommitAsync(CancellationToken ct = default);
}

// Usage
public class PlaceOrderHandler : IRequestHandler<PlaceOrderCommand, ErrorOr<OrderId>>
{
    private readonly IUnitOfWork _uow;

    public async Task<ErrorOr<OrderId>> Handle(PlaceOrderCommand cmd, CancellationToken ct)
    {
        var order = Order.Create(cmd.CustomerId, cmd.Amount);
        await _uow.Orders.AddAsync(order, ct);
        await _uow.CommitAsync(ct);          // single transaction
        return order.Id;
    }
}
```

---

## 32.5 Specification Pattern

**Problem:** query logic leaks everywhere. `GetActiveAdminUsers` in the repository,
`GetPremiumExpiredUsers` somewhere else. Complex, combinable queries are hard to test.

**Solution:** encapsulate a query condition as a reusable object.

```csharp
// Base specification
public abstract class Specification<T>
{
    public abstract Expression<Func<T, bool>> Criteria { get; }

    public Specification<T> And(Specification<T> other)
        => new AndSpecification<T>(this, other);

    public Specification<T> Or(Specification<T> other)
        => new OrSpecification<T>(this, other);
}

// Concrete specifications
public class ActiveUsersSpec : Specification<User>
{
    public override Expression<Func<User, bool>> Criteria =>
        user => user.IsActive && !user.IsDeleted;
}

public class AdminUsersSpec : Specification<User>
{
    public override Expression<Func<User, bool>> Criteria =>
        user => user.Role == UserRole.Admin;
}

public class ByCountrySpec : Specification<User>
{
    private readonly string _country;
    public ByCountrySpec(string country) => _country = country;

    public override Expression<Func<User, bool>> Criteria =>
        user => user.Country == _country;
}

// Repository accepts specifications
public interface IUserRepository
{
    Task<IReadOnlyList<User>> GetAsync(
        Specification<User> spec, CancellationToken ct);
}

// Usage — compose freely
var activeGermanAdmins = new ActiveUsersSpec()
    .And(new AdminUsersSpec())
    .And(new ByCountrySpec("DE"));

var users = await _users.GetAsync(activeGermanAdmins, ct);

// In EF Core repository
public async Task<IReadOnlyList<User>> GetAsync(Specification<User> spec, CancellationToken ct)
    => await _db.Users.Where(spec.Criteria).ToListAsync(ct);
```

> **Rider tip:** `Alt+F7` on `IRequestHandler` shows every handler in the solution.
> Navigate from a MediatR command to its handler: place cursor on the command type
> in `_mediator.Send(new MyCommand())` → `Ctrl+Alt+B` → jumps to the handler.

> **VS tip:** The *MediatR Helper* extension adds gutter icons showing handler counts.
> Click to navigate directly from send site to handler.
