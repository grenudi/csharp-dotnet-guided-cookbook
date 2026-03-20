# Chapter 10 — Dependency Injection, Configuration & Logging

> Three concerns — how your application gets its dependencies, how it
> reads its settings, and how it records what it does — are entangled by
> design in .NET. They share the same container, the same startup wiring,
> and the same host model. This chapter introduces all three together,
> which is how they appear in real projects. Chapter 11 then dives deep
> into DI alone with standalone examples.

*Building on:* Ch 5 (interfaces, why you abstract), Ch 9 (environment
variables, the configuration sources), Ch 4 (extension methods — the
DI registration pattern)

---

## 10.1 Dependency Injection — The Problem It Solves

Before DI, you constructed dependencies directly:

```csharp
// Without DI: every class builds its own dependencies
public class OrderService
{
    private readonly OrderRepository _repo;
    private readonly EmailService    _email;
    private readonly PaymentGateway  _payment;

    public OrderService()
    {
        var connStr  = Environment.GetEnvironmentVariable("DB_CONNECTION")!;
        _repo    = new OrderRepository(new SqlConnection(connStr));
        _email   = new EmailService(new SmtpClient("smtp.example.com"));
        _payment = new PaymentGateway(new HttpClient());
    }
}
```

Problems with this approach:
1. `OrderService` must know how to construct each dependency — it has
   knowledge it should not have
2. You cannot swap implementations — tests must use the real database
3. Lifetime management is manual — who disposes `SqlConnection`?
4. Configuration changes require editing source code

DI inverts this: you describe *what* you need, and a container *provides*
it. The container knows how to construct everything. The service declares
its needs through its constructor:

```csharp
// With DI: declare what you need, the container provides it
public class OrderService(
    IOrderRepository repo,       // interface, not concrete class
    IEmailSender     email,      // swappable
    IPaymentGateway  payment)    // swappable
{
    // Uses what was injected; knows nothing about how to construct them
}
```

### Service Lifetimes — How Long Each Instance Lives

The most important decision when registering a service is its lifetime.
Getting this wrong causes bugs that are subtle and environment-specific:

```
┌─────────────┬─────────────────────────────────────────────┐
│ Lifetime    │ When created                                 │
├─────────────┼─────────────────────────────────────────────┤
│ Transient   │ New instance every time it is resolved       │
│             │ → Best for lightweight, stateless services   │
├─────────────┼─────────────────────────────────────────────┤
│ Scoped      │ Once per scope (per HTTP request in ASP.NET) │
│             │ → Best for services tied to a request:       │
│             │   DbContext, CurrentUser, RequestState       │
├─────────────┼─────────────────────────────────────────────┤
│ Singleton   │ Once per application lifetime                │
│             │ → Best for stateless shared services:        │
│             │   HttpClient, MemoryCache, ILogger           │
└─────────────┴─────────────────────────────────────────────┘
```

The **Captive Dependency** bug: injecting a Scoped service into a
Singleton. The Singleton is created once. The Scoped service it captures
is the first instance ever created — every request shares the same
instance, defeating the purpose of Scoped:

```csharp
// BUG: Singleton captures Scoped — DbContext shared across all requests
services.AddSingleton<OrderRepository>();   // singleton
services.AddScoped<AppDbContext>();         // scoped

// OrderRepository is constructed once with one AppDbContext
// All requests share that DbContext — data leaks between requests!

// FIX: use Scoped for the service too, or inject IServiceScopeFactory
services.AddScoped<OrderRepository>();     // scoped: new instance per request
```

### Registering Services

```csharp
// Worker Service / Console App
var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, services) =>
    {
        // Interface → Implementation binding
        services.AddTransient<IEmailSender, SmtpEmailSender>();
        services.AddScoped<IOrderRepository, EfOrderRepository>();
        services.AddSingleton<ICache, MemoryCache>();

        // Self-binding: useful for classes without interfaces (rare)
        services.AddScoped<OrderService>();

        // Factory: build the instance yourself
        services.AddSingleton<IDbConnection>(_ =>
            new SqliteConnection(ctx.Configuration["Database:ConnectionString"]));

        // Multiple implementations of the same interface
        // Inject IEnumerable<IPlugin> to get all of them
        services.AddTransient<IPlugin, PluginA>();
        services.AddTransient<IPlugin, PluginB>();

        // Options (see §10.2)
        services.Configure<SmtpOptions>(ctx.Configuration.GetSection("Smtp"));
    })
    .Build();
```

```csharp
// ASP.NET Core — same API, accessed through WebApplicationBuilder
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddScoped<IOrderRepository, EfOrderRepository>();
// ...
var app = builder.Build();
```

---

## 10.2 The Options Pattern — Strongly-Typed Configuration

Hard-coded configuration strings in services are fragile, undiscoverable,
and impossible to validate centrally. The Options pattern binds a
configuration section to a strongly-typed class, validates it at startup,
and injects it where needed.

```csharp
// Define the shape of your configuration section
public record SmtpOptions
{
    public required string Host     { get; init; }
    public required int    Port     { get; init; }
    public required string From     { get; init; }
    public bool   UseTls            { get; init; } = true;
    public string? Username         { get; init; }
    public string? Password         { get; init; }
}
```

```json
// appsettings.json
{
  "Smtp": {
    "Host": "smtp.example.com",
    "Port": 587,
    "From": "noreply@example.com",
    "UseTls": true
  }
}
```

```csharp
// Registration — bind, validate, and fail at startup if invalid
services.AddOptions<SmtpOptions>()
    .BindConfiguration("Smtp")           // reads from config["Smtp:*"]
    .ValidateDataAnnotations()           // honours [Required], [Range]
    .ValidateOnStart();                  // fail at startup, not first use

// Injection: IOptions<T> for static values
public class EmailService(IOptions<SmtpOptions> opts)
{
    private readonly SmtpOptions _smtp = opts.Value;   // access the bound object

    public async Task SendAsync(string to, string subject, CancellationToken ct)
    {
        using var client = new SmtpClient(_smtp.Host, _smtp.Port);
        // ...
    }
}

// IOptionsMonitor<T> for values that can change without restart
// (see Ch 39 for the full explanation)
public class RateLimitMiddleware(IOptionsMonitor<RateLimitOptions> opts)
{
    public async Task InvokeAsync(HttpContext ctx, RequestDelegate next)
    {
        var limit = opts.CurrentValue.RequestsPerMinute;  // reads latest value
        // ...
    }
}
```

---

## 10.3 Configuration — The Full Source Stack

The configuration system stacks providers. Later providers override
earlier ones. The resulting merged `IConfiguration` is the single source
of truth for all settings.

```
Default values in code
    ↑ override
appsettings.json
    ↑ override
appsettings.{Environment}.json   (e.g., appsettings.Development.json)
    ↑ override
User Secrets (only in Development environment)
    ↑ override
Environment variables
    ↑ override
Command-line arguments           (highest priority — useful for CI)
```

`Host.CreateDefaultBuilder()` sets up this entire stack automatically.
The environment (Development, Staging, Production) is controlled by the
`ASPNETCORE_ENVIRONMENT` or `DOTNET_ENVIRONMENT` variable.

```csharp
// Manual setup (for console apps without Generic Host)
var config = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: true)
    .AddJsonFile($"appsettings.{environment}.json", optional: true)
    .AddUserSecrets<Program>(optional: true)   // only in Development
    .AddEnvironmentVariables()
    .AddCommandLine(args)
    .Build();

// Reading values
string? connStr = config["Database:ConnectionString"];  // : = nested section
string? host    = config.GetSection("Smtp")["Host"];    // section then key
int port        = config.GetValue<int>("Smtp:Port", 587); // typed with default
```

### Environment Variables Naming

Environment variables use `__` (double underscore) to represent the `:`
separator, because `:` is not valid in environment variable names on
Linux:

```bash
# This environment variable...
export Smtp__Host=smtp.example.com
export Smtp__Port=587
# ...maps to config["Smtp:Host"] and config["Smtp:Port"]
```

Chapter 9 covers the full environment variable and secrets story.

---

## 10.4 Logging — Structured and Queryable

Log output is most valuable when it is *structured* — not a plain text
string, but a record with discrete fields that can be queried, filtered,
and aggregated. .NET's logging system produces structured logs when
connected to a structured sink like Serilog or OpenTelemetry.

### The Built-In Logging API

```csharp
// Inject ILogger<T> — T is the category (usually the containing class)
public class OrderService(ILogger<OrderService> logger)
{
    public async Task<Order> CreateAsync(CreateOrderRequest req, CancellationToken ct)
    {
        // Structured log: {OrderId} is a structured field, not a string format
        logger.LogInformation("Creating order for customer {CustomerId}", req.CustomerId);

        // Use log levels appropriately
        logger.LogDebug("Validating order details: {@Request}", req);   // Debug: dev-only detail
        logger.LogInformation("Order {OrderId} created", order.Id);     // Info: important events
        logger.LogWarning("Order {OrderId} flagged for review", id);    // Warning: unusual
        logger.LogError(ex, "Failed to process order {OrderId}", id);   // Error: failure with exception
        logger.LogCritical("Database connection lost — all orders failing"); // Critical: system-wide
    }
}
```

The `{OrderId}` syntax is not string formatting — it is a *message
template*. The logging framework captures `OrderId` as a structured field
alongside the message. Tools like Seq, Kibana, or Datadog can then filter
by `OrderId = "abc123"` across millions of log entries.

### Source-Generated Logging (Performance)

For hot paths, string interpolation in log messages allocates even when
the log level is not enabled. Source-generated logging avoids this:

```csharp
// Define once with a source generator attribute
public static partial class Log
{
    [LoggerMessage(Level = LogLevel.Information, Message = "Order {OrderId} created for {CustomerId}")]
    public static partial void OrderCreated(ILogger logger, Guid orderId, string customerId);

    [LoggerMessage(Level = LogLevel.Error, Message = "Failed to process payment for order {OrderId}")]
    public static partial void PaymentFailed(ILogger logger, Exception ex, Guid orderId);
}

// Usage: no allocation if the log level is not enabled
Log.OrderCreated(logger, order.Id, order.CustomerId);
```

### Configuration: Log Levels and Sinks

```json
// appsettings.json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning",                // only Warning and above for everything
      "Microsoft.AspNetCore": "Warning",   // suppress framework noise
      "MyApp": "Information",              // more verbose for your own code
      "MyApp.OrderService": "Debug"        // maximum detail for one service
    }
  }
}
```

For production, use Serilog with a structured sink:

```bash
dotnet add package Serilog.AspNetCore
dotnet add package Serilog.Sinks.Console
dotnet add package Serilog.Sinks.File
```

```csharp
// Program.cs
builder.Host.UseSerilog((ctx, cfg) =>
    cfg.ReadFrom.Configuration(ctx.Configuration)  // read Serilog: section
       .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext}: {Message:lj}{NewLine}{Exception}")
       .WriteTo.File("logs/app-.log", rollingInterval: RollingInterval.Day));
```

---

## 10.5 Connecting DI, Configuration, and Logging to the Rest of the Book

These three form the infrastructure backbone that everything else plugs
into:

- **Ch 11 (DI Deep Dive)** — every DI concept from §10.1 with complete
  standalone runnable examples.
- **Ch 14 (ASP.NET Core)** — the request pipeline is itself DI-driven.
  Middleware, filters, and controllers are all resolved through the
  container.
- **Ch 15 (EF Core)** — `DbContext` is typically registered as Scoped,
  one per request. `IOptions<T>` carries the connection string.
- **Ch 17 (Testing)** — tests replace real implementations with fakes
  using the same DI container that production code uses.
- **Ch 30 (Observability)** — structured logging integrates with
  OpenTelemetry for distributed tracing across services.
- **Ch 39 (Configuration project)** — complete end-to-end examples
  of configuration in every program type.
