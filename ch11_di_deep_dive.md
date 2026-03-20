# Chapter 11 — Dependency Injection: The Complete Picture

> Chapter 10 introduced DI in context. This chapter goes deeper with
> every concept fully demonstrated in standalone, runnable examples.
> By the end you should understand not just how to register and inject,
> but *why* the system works the way it does and how to handle every
> edge case you will encounter in production.

*Building on:* Ch 5 (interfaces), Ch 10 §10.1 (DI introduction),
Ch 4 (extension methods — the registration pattern)

---

## 11.1 What the Container Actually Is

The DI container (formally `IServiceProvider`) is a factory. It knows
how to construct objects and how long to keep each one alive. When you
ask it for an `IOrderService`, it:

1. Looks up what implementation is registered for `IOrderService`
2. Looks up all constructor parameters of that implementation
3. Recursively constructs each parameter (which may have their own dependencies)
4. Manages the lifetime of the resulting instances

This construction of the entire dependency graph is called *resolution*.
The container builds the tree bottom-up: leaf nodes (services with no
dependencies) first, then the services that depend on them, up to the
root (the service you actually asked for).

```
Resolve: IOrderService
  └── OrderService(IOrderRepo, IEmailSender, IPaymentGateway)
        ├── EfOrderRepo(AppDbContext)
        │      └── AppDbContext(DbContextOptions)
        │              └── (options configured from IConfiguration)
        ├── SmtpEmailSender(IOptions<SmtpOptions>)
        │      └── (options resolved from configuration)
        └── StripePaymentGateway(HttpClient, IOptions<StripeOptions>)
               └── (HttpClient from IHttpClientFactory)
```

You declare the graph. The container traverses and builds it. You never
call `new` on services that have dependencies.

---

## 11.2 The Three Lifetimes — What Actually Happens

```csharp
// Start fresh
dotnet new console -n DependencyLifetimes
dotnet add package Microsoft.Extensions.Hosting
```

```csharp
// Demonstrates all three lifetimes with the same interface
public interface IOperation
{
    string Id { get; }   // unique per instance — shows when a new one is created
}

// All three use the same interface, different registration
public class TransientOperation  : IOperation { public string Id { get; } = Guid.NewGuid().ToString("N")[..8]; }
public class ScopedOperation     : IOperation { public string Id { get; } = Guid.NewGuid().ToString("N")[..8]; }
public class SingletonOperation  : IOperation { public string Id { get; } = Guid.NewGuid().ToString("N")[..8]; }

public class OperationLogger(
    TransientOperation  transient,
    ScopedOperation     scoped,
    SingletonOperation  singleton)
{
    public void Log() =>
        Console.WriteLine($"Transient: {transient.Id}, Scoped: {scoped.Id}, Singleton: {singleton.Id}");
}
```

```csharp
// Program.cs
var services = new ServiceCollection();
services.AddTransient<TransientOperation>();
services.AddScoped<ScopedOperation>();
services.AddSingleton<SingletonOperation>();
services.AddTransient<OperationLogger>();

await using var provider = services.BuildServiceProvider();

Console.WriteLine("=== Scope 1 ===");
await using (var scope1 = provider.CreateAsyncScope())
{
    // Within the same scope, Scoped is the same instance
    var logger1 = scope1.ServiceProvider.GetRequiredService<OperationLogger>();
    var logger2 = scope1.ServiceProvider.GetRequiredService<OperationLogger>();
    logger1.Log();
    logger2.Log();
    // Output shows: Transient IDs differ, Scoped ID same, Singleton ID same
}

Console.WriteLine("=== Scope 2 ===");
await using (var scope2 = provider.CreateAsyncScope())
{
    // New scope: Scoped gets a new instance
    // Transient always new, Singleton always same
    var logger3 = scope2.ServiceProvider.GetRequiredService<OperationLogger>();
    logger3.Log();
    // Output shows: Transient ID new, Scoped ID new (new scope!), Singleton same
}
```

Running this makes the lifetime behaviour concrete: Scoped creates a new
instance per scope (per request in ASP.NET Core), while Singleton truly
lives for the entire process lifetime.

---

## 11.3 Constructor Injection — The Only Right Way

Constructor injection is the preferred mechanism. It makes dependencies
explicit and visible, enables immutability, and allows the compiler to
catch missing dependencies.

```csharp
// Good: dependencies declared in constructor, stored as readonly
public class CustomerService(
    ICustomerRepository repo,
    IEmailSender         email,
    ILogger<CustomerService> logger)
{
    // Primary constructor captures these as private fields automatically (C# 12)
    // They are in scope throughout the class

    public async Task<Customer> CreateAsync(
        string name, string email2, CancellationToken ct)
    {
        logger.LogInformation("Creating customer {Name}", name);
        var customer = Customer.Create(name, email2);
        await repo.AddAsync(customer, ct);
        await email.SendWelcomeAsync(customer.Email, ct);
        return customer;
    }
}
```

Avoid property injection (setting properties after construction) and
service locator (calling `IServiceProvider.GetService<T>()` inside
a service). Both obscure dependencies and make testing harder.

---

## 11.4 Swapping Implementations — The Core Value Proposition

The power of DI is that you can change which implementation is provided
without changing any consumer code. This is most valuable for:

- **Testing**: replace expensive or network-dependent services with fakes
- **Feature flags**: swap implementations based on configuration
- **Environment**: different implementations per Development/Production

```csharp
// Three implementations of the same interface
public interface INotificationSender
{
    Task SendAsync(string message, CancellationToken ct);
}

public class SmtpNotificationSender  : INotificationSender { /* real SMTP */ }
public class SmsNotificationSender   : INotificationSender { /* real SMS */ }
public class ConsoleNotificationSender : INotificationSender
{
    public Task SendAsync(string message, CancellationToken ct)
    {
        Console.WriteLine($"[NOTIFICATION] {message}");
        return Task.CompletedTask;
    }
}
```

```csharp
// Swap via environment configuration
services.AddScoped<INotificationSender>(provider =>
{
    var config   = provider.GetRequiredService<IConfiguration>();
    var channel  = config["Notifications:Channel"] ?? "console";

    return channel switch
    {
        "smtp" => new SmtpNotificationSender(provider.GetRequiredService<IOptions<SmtpOptions>>()),
        "sms"  => new SmsNotificationSender(provider.GetRequiredService<IOptions<SmsOptions>>()),
        _      => new ConsoleNotificationSender()
    };
});
```

---

## 11.5 Extension Methods — The Self-Registration Pattern

When a library registers several related services, it should expose a
single `AddX(this IServiceCollection services)` extension method. This
is the pattern used by every framework and library in the .NET ecosystem:
`AddAuthentication()`, `AddEntityFrameworkCore()`, `AddSignalR()`.

```csharp
// Sync.Mesh Core — all core services in one call
public static IServiceCollection AddSyncMeshCore(this IServiceCollection services)
{
    services.AddSingleton<SyncEngine>();
    services.AddScoped<ConflictResolver>();
    services.AddScoped<SnapshotDiff>();
    services.AddScoped<PairingService>();
    services.AddScoped<FeatureGate>();
    return services;
}

// Consumer: self-documenting, no knowledge of internals needed
builder.Services.AddSyncMeshCore();
```

---

## 11.6 `IServiceProvider` vs `IServiceCollection`

Understanding the difference prevents a common confusion:

- `IServiceCollection` is the *builder* — you add registrations to it at
  startup. It is mutable. You only interact with it in `Program.cs` or
  extension methods.

- `IServiceProvider` is the built container — you resolve services from
  it at runtime. It is immutable. You only access it when constructing
  services (through constructor injection) or in factory delegates.

Directly injecting `IServiceProvider` into a service (service locator
pattern) is an anti-pattern — it hides dependencies and makes the service
impossible to test without a full container. Use it only in factories or
middleware where you need to resolve services dynamically:

```csharp
// Legitimate: factory method that creates a service per-operation
public class ReportFactory(IServiceProvider provider)
{
    public IReport Create(ReportType type) => type switch
    {
        ReportType.Pdf  => provider.GetRequiredService<PdfReport>(),
        ReportType.Excel => provider.GetRequiredService<ExcelReport>(),
        _ => throw new ArgumentException($"Unknown type {type}")
    };
}
```

---

## 11.7 Multiple Implementations — Resolving All of Them

When multiple implementations of the same interface are registered, you
can inject `IEnumerable<T>` to get all of them. This is the basis of
plugin systems, pipeline steps, and the Chain of Responsibility pattern:

```csharp
// Multiple validators
services.AddTransient<IOrderValidator, PriceValidator>();
services.AddTransient<IOrderValidator, StockValidator>();
services.AddTransient<IOrderValidator, FraudValidator>();

// Inject all validators
public class OrderService(IEnumerable<IOrderValidator> validators)
{
    public async Task<ValidationResult> ValidateAsync(Order order, CancellationToken ct)
    {
        var errors = new List<string>();
        foreach (var validator in validators)
        {
            var result = await validator.ValidateAsync(order, ct);
            if (!result.IsValid)
                errors.AddRange(result.Errors);
        }
        return new ValidationResult(errors);
    }
}
```

---

## 11.8 Scoped Services in BackgroundService

This is one of the most common DI mistakes. `BackgroundService` is a
Singleton (it lives for the application lifetime). You cannot inject a
Scoped service directly into it — the Scoped service would be captured by
the Singleton, making it effectively a Singleton too (the captive
dependency bug from §10.1).

The fix is to inject `IServiceScopeFactory` and create a scope per unit
of work:

```csharp
// WRONG: DbContext is Scoped, captured by the Singleton BackgroundService
public class InvoiceProcessor(AppDbContext db) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while (await _timer.WaitForNextTickAsync(ct))
            await ProcessPendingInvoicesAsync(db, ct);  // same db instance forever
    }
}

// CORRECT: create a new scope per execution cycle
public class InvoiceProcessor(IServiceScopeFactory scopeFactory) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(5));
        while (await timer.WaitForNextTickAsync(ct))
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var db      = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var service = scope.ServiceProvider.GetRequiredService<IInvoiceService>();
            await service.ProcessPendingAsync(ct);
        }  // scope disposed here — DbContext freed, connection returned to pool
    }
}
```

---

## 11.9 Testing With DI — Using the Real Container

For integration tests, you can build a test service collection that
replaces specific services with fakes while using real implementations
for everything else:

```csharp
// xUnit test
public class OrderServiceTests
{
    private readonly FakeEmailSender _email = new();

    private IOrderService CreateSut()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddDbContext<AppDbContext>(o => o.UseInMemoryDatabase("test"));
        services.AddScoped<IOrderRepository, EfOrderRepository>();
        services.AddScoped<IOrderService, OrderService>();

        // Replace the real email sender with a fake
        services.AddSingleton<IEmailSender>(_email);

        var provider = services.BuildServiceProvider();
        return provider.GetRequiredService<IOrderService>();
    }

    [Fact]
    public async Task CreateOrder_sends_confirmation_email()
    {
        var sut = CreateSut();
        await sut.CreateOrderAsync(new CreateOrderRequest { CustomerEmail = "alice@example.com" });

        Assert.Single(_email.SentEmails);
        Assert.Contains("alice@example.com", _email.SentEmails[0].To);
    }
}
```

---

## 11.10 The Mental Model — Summary

DI is about two things:
1. **Inversion of Control**: services declare their needs; the framework
   provides them. The service does not look up its own dependencies.
2. **Open/Closed Principle**: you can add new behaviour (new
   implementations) without modifying existing services. The consumer
   service does not change when you swap its dependency.

Together these make systems modular, testable, and deployable to
different environments without code changes — just different registrations
in `Program.cs`.
