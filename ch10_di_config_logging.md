# Chapter 10 — Dependency Injection, Configuration & Logging

> This chapter covers DI, Options, and Logging in the context of ASP.NET Core and Worker services.
> For a standalone deep-dive with fully runnable examples covering every DI concept from scratch,
> see **[Chapter 19 — Dependency Injection: The Complete Picture](ch19_di_deep_dive.md)**.

## 10.1 Dependency Injection (DI)

`Microsoft.Extensions.DependencyInjection` is the built-in DI container.

### Service Lifetimes

| Lifetime | Scope | Created |
|----------|-------|---------|
| **Transient** | New instance every resolve | `AddTransient<TService, TImpl>()` |
| **Scoped** | Once per request/scope | `AddScoped<TService, TImpl>()` |
| **Singleton** | Once per application lifetime | `AddSingleton<TService, TImpl>()` |

```
Request 1:
  Resolve IService (Scoped) → instance A
  Resolve IService (Scoped) → instance A (same scope)
  Resolve ITransient       → instance X
  Resolve ITransient       → instance Y (new each time)
  Resolve ISingleton       → instance S
  [end of request] → A disposed

Request 2:
  Resolve IService (Scoped) → instance B (new scope)
  Resolve ISingleton       → instance S (same singleton)
```

### Setting Up the Container

#### Console App / Worker

```csharp
// Program.cs
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((context, services) =>
    {
        // Register services
        services.AddTransient<IEmailSender, SmtpEmailSender>();
        services.AddScoped<IOrderService, OrderService>();
        services.AddSingleton<ICache, MemoryCache>();

        // Register with factory
        services.AddSingleton<IDbConnection>(_ =>
            new SqlConnection(context.Configuration.GetConnectionString("Default")));

        // Register all implementations of an interface
        services.AddTransient<IPlugin, PluginA>();
        services.AddTransient<IPlugin, PluginB>(); // IEnumerable<IPlugin> injection works!

        // Register options
        services.Configure<SmtpOptions>(context.Configuration.GetSection("Smtp"));

        // Background service
        services.AddHostedService<MyWorker>();
    })
    .Build();

await host.RunAsync();
```

#### ASP.NET Core

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Application services
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddSingleton<IEventBus, InMemoryEventBus>();

// EF Core
builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseSqlite(builder.Configuration.GetConnectionString("Default")));

// HttpClient with named/typed
builder.Services.AddHttpClient<IGithubClient, GithubClient>(client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.DefaultRequestHeaders.Add("User-Agent", "MyApp/1.0");
});

var app = builder.Build();
// ...
```

### Injecting Dependencies

```csharp
// Constructor injection (preferred)
public class OrderService : IOrderService
{
    private readonly IRepository<Order> _orders;
    private readonly IEmailSender _email;
    private readonly ILogger<OrderService> _logger;

    public OrderService(
        IRepository<Order> orders,
        IEmailSender email,
        ILogger<OrderService> logger)
    {
        _orders = orders;
        _email = email;
        _logger = logger;
    }

    public async Task PlaceOrderAsync(Order order, CancellationToken ct)
    {
        await _orders.AddAsync(order, ct);
        await _email.SendAsync(order.CustomerEmail, "Order placed", ..., ct);
        _logger.LogInformation("Order {OrderId} placed", order.Id);
    }
}

// Inject IEnumerable<T> — gets all registrations
public class PluginRunner
{
    private readonly IEnumerable<IPlugin> _plugins;
    public PluginRunner(IEnumerable<IPlugin> plugins) => _plugins = plugins;

    public async Task RunAllAsync()
    {
        foreach (var plugin in _plugins)
            await plugin.RunAsync();
    }
}

// Inject factory — avoid resolving transient from singleton (captive dependency)
public class MySingleton
{
    private readonly IServiceScopeFactory _scopeFactory;

    public MySingleton(IServiceScopeFactory scopeFactory)
        => _scopeFactory = scopeFactory;

    public async Task DoWorkAsync()
    {
        using var scope = _scopeFactory.CreateScope();
        var scoped = scope.ServiceProvider.GetRequiredService<IScopedService>();
        await scoped.DoAsync();
    }
}
```

### Keyed Services (NET 8+)

```csharp
// Register with key
services.AddKeyedSingleton<ICache, MemoryCache>("memory");
services.AddKeyedSingleton<ICache, RedisCache>("redis");

// Inject by key
public class MyService
{
    private readonly ICache _memCache;
    private readonly ICache _redisCache;

    public MyService(
        [FromKeyedServices("memory")] ICache memCache,
        [FromKeyedServices("redis")]  ICache redisCache)
    {
        _memCache  = memCache;
        _redisCache = redisCache;
    }
}

// Resolve manually
var redis = sp.GetRequiredKeyedService<ICache>("redis");
```

### Extension Method Pattern for Service Registration

```csharp
// Organize DI into extension methods per feature
public static class OrderingServiceExtensions
{
    public static IServiceCollection AddOrdering(
        this IServiceCollection services,
        IConfiguration config)
    {
        services.AddScoped<IOrderService, OrderService>();
        services.AddScoped<IOrderRepository, SqlOrderRepository>();
        services.AddScoped<IPaymentGateway, StripePaymentGateway>();
        services.Configure<OrderOptions>(config.GetSection("Ordering"));
        return services;
    }
}

// Usage
builder.Services.AddOrdering(builder.Configuration);
```

---

## 10.2 Options Pattern

### Defining Options

```csharp
public class SmtpOptions
{
    public const string SectionName = "Smtp";

    [Required]
    public string Host { get; set; } = "";

    [Range(1, 65535)]
    public int Port { get; set; } = 587;

    public bool UseSsl { get; set; } = true;

    [Required]
    public string Username { get; set; } = "";

    [Required]
    public string Password { get; set; } = "";

    public int TimeoutSeconds { get; set; } = 30;
}
```

### `appsettings.json`

```json
{
  "Smtp": {
    "Host": "smtp.gmail.com",
    "Port": 587,
    "UseSsl": true,
    "Username": "user@gmail.com",
    "Password": "app-password",
    "TimeoutSeconds": 30
  }
}
```

### Registering

```csharp
services.AddOptions<SmtpOptions>()
    .BindConfiguration(SmtpOptions.SectionName)
    .ValidateDataAnnotations()
    .ValidateOnStart();   // fail at startup if invalid, not on first use
```

### Injecting Options

```csharp
// IOptions<T> — singleton, does not reload
public class EmailSender
{
    private readonly SmtpOptions _opts;
    public EmailSender(IOptions<SmtpOptions> opts) => _opts = opts.Value;
}

// IOptionsSnapshot<T> — scoped, reloads per scope
public class FeatureService
{
    private readonly FeatureOptions _opts;
    public FeatureService(IOptionsSnapshot<FeatureOptions> opts) => _opts = opts.Value;
}

// IOptionsMonitor<T> — singleton, hot reload support
public class ConfigWatcher
{
    private readonly IOptionsMonitor<AppOptions> _monitor;
    private IDisposable? _sub;

    public ConfigWatcher(IOptionsMonitor<AppOptions> monitor)
    {
        _monitor = monitor;
        _sub = monitor.OnChange(opts =>
        {
            Console.WriteLine($"Config changed: {opts.Setting}");
        });
    }
}
```

### Named Options

```csharp
// Register multiple named options
services.Configure<ConnectionOptions>("primary", config.GetSection("Connections:Primary"));
services.Configure<ConnectionOptions>("replica", config.GetSection("Connections:Replica"));

// Inject
public class DbRouter
{
    private readonly ConnectionOptions _primary;
    private readonly ConnectionOptions _replica;

    public DbRouter(IOptionsMonitor<ConnectionOptions> opts)
    {
        _primary = opts.Get("primary");
        _replica = opts.Get("replica");
    }
}
```

---

## 10.3 Configuration

### Configuration Providers (in priority order, last wins)

```
appsettings.json
  → appsettings.{Environment}.json
    → Environment variables
      → Command-line arguments
        → User secrets (Development only)
```

### `appsettings.json` Full Example

```json
{
  "ConnectionStrings": {
    "Default": "Data Source=app.db"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "App": {
    "Name": "MyApp",
    "Version": "1.0.0",
    "Features": {
      "EnableBeta": false,
      "MaxRetries": 3
    }
  },
  "Smtp": {
    "Host": "smtp.example.com",
    "Port": 587
  }
}
```

### Accessing Configuration

```csharp
// Direct access (avoid in app code — use Options pattern instead)
string conn = config["ConnectionStrings:Default"]!;
string host = config.GetConnectionString("Default")!;
string app  = config.GetSection("App")["Name"]!;

// Bind section to typed object
var smtpOpts = config.GetSection("Smtp").Get<SmtpOptions>()!;

// Bind with validation
var opts = new SmtpOptions();
config.GetSection("Smtp").Bind(opts);

// In service registration
services.Configure<SmtpOptions>(config.GetSection("Smtp"));
```

### Environment Variables

```bash
# Override nested config: use double underscore __ as separator
export App__Features__EnableBeta=true
export ConnectionStrings__Default="Server=prod-db;..."

# In Docker Compose:
environment:
  - App__Features__EnableBeta=true
  - ConnectionStrings__Default=Server=db;Database=prod;
```

### User Secrets (Development)

```bash
# Initialize
dotnet user-secrets init

# Set
dotnet user-secrets set "Smtp:Password" "super-secret"
dotnet user-secrets set "ConnectionStrings:Default" "Server=localhost;..."

# List
dotnet user-secrets list

# Remove
dotnet user-secrets remove "Smtp:Password"
```

User secrets are stored at:
- Linux/macOS: `~/.microsoft/usersecrets/{userSecretsId}/secrets.json`
- Windows: `%APPDATA%\Microsoft\UserSecrets\{userSecretsId}\secrets.json`

### Custom Configuration Provider

```csharp
// Add configuration from database or any custom source
public class DatabaseConfigurationSource : IConfigurationSource
{
    private readonly string _connectionString;
    public DatabaseConfigurationSource(string cs) => _connectionString = cs;

    public IConfigurationProvider Build(IConfigurationBuilder builder)
        => new DatabaseConfigurationProvider(_connectionString);
}

public class DatabaseConfigurationProvider : ConfigurationProvider
{
    private readonly string _cs;
    public DatabaseConfigurationProvider(string cs) => _cs = cs;

    public override void Load()
    {
        using var conn = new SqlConnection(_cs);
        var pairs = conn.Query<(string Key, string Value)>(
            "SELECT [Key], [Value] FROM AppConfig WHERE IsActive = 1");
        Data = pairs.ToDictionary(x => x.Key, x => x.Value, StringComparer.OrdinalIgnoreCase);
    }
}

// Register
builder.Configuration.Add(new DatabaseConfigurationSource(connectionString));
```

---

## 10.4 Logging

### Basic Usage

```csharp
public class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger) => _logger = logger;

    public async Task PlaceOrderAsync(string orderId, decimal total)
    {
        _logger.LogInformation("Placing order {OrderId} for {Total:C}", orderId, total);

        try
        {
            await SaveOrderAsync(orderId);
            _logger.LogInformation("Order {OrderId} saved successfully", orderId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save order {OrderId}", orderId);
            throw;
        }
    }
}
```

### Log Levels

```csharp
_logger.LogTrace("Detailed trace for debugging");      // Trace (0)
_logger.LogDebug("Debug info: {Value}", someValue);    // Debug (1)
_logger.LogInformation("User {UserId} logged in", id); // Information (2)
_logger.LogWarning("Retry {Count} for {Url}", n, url); // Warning (3)
_logger.LogError(ex, "Error processing {Item}", item); // Error (4)
_logger.LogCritical("Database unavailable!");          // Critical (5)

// Check before logging expensive operations
if (_logger.IsEnabled(LogLevel.Debug))
    _logger.LogDebug("Expensive debug info: {Data}", ComputeExpensiveData());
```

### Structured Logging with Serilog

```csharp
// Install: Serilog.AspNetCore, Serilog.Sinks.Console, Serilog.Sinks.File

// Program.cs
using Serilog;

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Debug()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .MinimumLevel.Override("System", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithMachineName()
    .Enrich.WithEnvironmentName()
    .WriteTo.Console(outputTemplate:
        "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext}: {Message:lj}{NewLine}{Exception}")
    .WriteTo.File("logs/app-.log",
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 7,
        outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff} [{Level:u3}] {SourceContext}: {Message:lj}{NewLine}{Exception}")
    .WriteTo.Seq("http://localhost:5341")  // structured log viewer
    .CreateLogger();

builder.Host.UseSerilog();

// Or inline builder:
builder.Host.UseSerilog((ctx, services, config) =>
{
    config
        .ReadFrom.Configuration(ctx.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .WriteTo.Console();
});
```

### High-Performance Logging with LoggerMessage

```csharp
// Source-generated logging (NET 6+) — zero allocation, no boxing
public static partial class Log
{
    [LoggerMessage(Level = LogLevel.Information, Message = "Order {OrderId} placed for {Total:C}")]
    public static partial void OrderPlaced(ILogger logger, string orderId, decimal total);

    [LoggerMessage(Level = LogLevel.Error, Message = "Failed to process item {ItemId} after {Attempts} attempts")]
    public static partial void ProcessingFailed(ILogger logger, Exception ex, string itemId, int attempts);

    [LoggerMessage(Level = LogLevel.Debug, Message = "Cache miss for key {Key}")]
    public static partial void CacheMiss(ILogger logger, string key);
}

// Usage — zero allocation, no boxing
Log.OrderPlaced(_logger, orderId, total);
Log.ProcessingFailed(_logger, ex, itemId, attempts);
Log.CacheMiss(_logger, cacheKey);
```

### Log Scopes — Adding Context

```csharp
// Add contextual properties to all log entries within the scope
using (_logger.BeginScope(new Dictionary<string, object>
{
    ["OrderId"]   = orderId,
    ["CustomerId"] = customerId,
    ["RequestId"] = HttpContext.TraceIdentifier
}))
{
    _logger.LogInformation("Starting order processing");
    await ValidateOrderAsync();
    await SaveOrderAsync();
    _logger.LogInformation("Order processing complete");
    // All log entries above include OrderId, CustomerId, RequestId
}
```

### Serilog `appsettings.json` Configuration

```json
{
  "Serilog": {
    "Using": ["Serilog.Sinks.Console", "Serilog.Sinks.File"],
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "System": "Warning",
        "Microsoft.EntityFrameworkCore": "Warning"
      }
    },
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "outputTemplate": "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}"
        }
      },
      {
        "Name": "File",
        "Args": {
          "path": "logs/app-.log",
          "rollingInterval": "Day",
          "retainedFileCountLimit": 7
        }
      }
    ],
    "Enrich": ["FromLogContext", "WithMachineName", "WithThreadId"]
  }
}
```

> **Rider tip:** *Rider → Settings → Tools → Log Viewer* integrates with local log files. Use *Find Usages* on a logger message string to find all uses of a log message across the codebase.

> **VS tip:** *View → Output → Debug* shows log output in real time during debugging. *Application Insights* and *Seq* integration available via Azure extensions.

