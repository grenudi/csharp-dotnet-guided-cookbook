# Chapter 39 — Pet Projects VII: Configuration, Secrets & Settings in Real Apps

> Every program type — console, CLI, daemon, API, desktop — needs to
> read configuration. The pattern is always the same but the source
> differs. This chapter shows you the complete picture once so you never
> have to rediscover it. Every project type gets its own wiring example.

**Concepts exercised:** Ch 9 (env vars, 12-factor), Ch 10 (IOptions,
IConfiguration), Ch 11 (DI), Ch 28 (secrets, no plaintext passwords)

---

## 39.1 The Configuration Stack

.NET's configuration system stacks providers. Later providers override earlier ones.

```
Default values in code
  ↑ override
appsettings.json
  ↑ override
appsettings.{Environment}.json
  ↑ override
User Secrets (development only)
  ↑ override
Environment variables
  ↑ override
Command-line arguments
```

The stack is intentional: environment variables override JSON so your
production deploy can set secrets without touching code or files.

---

## 39.2 The `IOptions<T>` Pattern — One Config Class to Rule Them All

The rule: **one strongly-typed class per config section. Never inject
`IConfiguration` directly into your services.**

```json
// appsettings.json
{
  "Database": {
    "ConnectionString": "Data Source=app.db",
    "MaxRetries": 3,
    "CommandTimeoutSeconds": 30
  },
  "Smtp": {
    "Host": "smtp.example.com",
    "Port": 587,
    "From": "noreply@example.com"
  }
}
```

```csharp
// Config classes — plain records, validated at startup
public record DatabaseOptions
{
    public required string ConnectionString      { get; init; }
    public          int    MaxRetries            { get; init; } = 3;
    public          int    CommandTimeoutSeconds { get; init; } = 30;
}

public record SmtpOptions
{
    public required string Host { get; init; }
    public required int    Port { get; init; }
    public required string From { get; init; }
}
```

```csharp
// Registration with startup validation
services
    .AddOptions<DatabaseOptions>()
    .BindConfiguration("Database")
    .ValidateDataAnnotations()   // honours [Required], [Range] etc.
    .ValidateOnStart();          // fails at startup, not first use

services
    .AddOptions<SmtpOptions>()
    .BindConfiguration("Smtp")
    .ValidateOnStart();

// Inject into your services:
public class OrderRepository(IOptions<DatabaseOptions> opts)
{
    private readonly DatabaseOptions _db = opts.Value;
    // ...
}
```

---

## 39.3 Console App — Minimal Config Setup

```csharp
// Program.cs
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

var config = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: true)
    .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? "Production"}.json",
                 optional: true)
    .AddUserSecrets<Program>(optional: true)   // development only
    .AddEnvironmentVariables()
    .AddCommandLine(args)
    .Build();

var services = new ServiceCollection();
services.AddSingleton<IConfiguration>(config);

services
    .AddOptions<DatabaseOptions>()
    .BindConfiguration("Database")
    .ValidateOnStart();

var provider = services.BuildServiceProvider();
var dbOpts   = provider.GetRequiredService<IOptions<DatabaseOptions>>().Value;
Console.WriteLine($"DB: {dbOpts.ConnectionString}");
```

---

## 39.4 Generic Host — Config in a Daemon or API

The Generic Host (`Host.CreateDefaultBuilder`) wires the full stack automatically.

```csharp
// Program.cs
var builder = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((ctx, cfg) =>
    {
        // Host.CreateDefaultBuilder already adds:
        // appsettings.json, appsettings.{Env}.json, env vars, cmd args
        // You only need to add extras:
        cfg.AddJsonFile("config/extra.json", optional: true);
    })
    .ConfigureServices((ctx, services) =>
    {
        services
            .AddOptions<SmtpOptions>()
            .BindConfiguration("Smtp")
            .ValidateOnStart();

        services.AddHostedService<EmailWorker>();
    });

await builder.Build().RunAsync();
```

---

## 39.5 Secrets — Never in Source Control

**The three secrets patterns, from simplest to most robust:**

### Pattern 1: User Secrets (development machines only)

```bash
dotnet user-secrets init                              # adds <UserSecretsId> to .csproj
dotnet user-secrets set "Smtp:Password" "s3cr3t"     # stored in OS keyring equivalent
dotnet user-secrets list
dotnet user-secrets clear
```

Stored at `~/.microsoft/usersecrets/{id}/secrets.json` on Linux/macOS.
**Never committed to git.** Only available when `DOTNET_ENVIRONMENT=Development`.

```csharp
// Automatically loaded by Host.CreateDefaultBuilder in Development:
builder.Configuration.AddUserSecrets<Program>();
```

### Pattern 2: Environment Variables (the 12-factor approach)

```bash
# Linux/macOS
export Smtp__Password="s3cr3t"         # __ = : in env vars
export Database__ConnectionString="Data Source=/prod/app.db"

# Or in a .env file loaded by direnv (never commit .env)
```

```csharp
// Loaded automatically — __ maps to config hierarchy separator :
// Smtp__Password → config["Smtp:Password"] → SmtpOptions.Password
```

### Pattern 3: ASP.NET Core Data Protection (for encrypted values on disk)

```csharp
// For values that must persist between restarts, encrypted at rest:
services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo("/etc/myapp/keys"))
    .SetApplicationName("myapp");

// In your service:
public class SecretService(IDataProtectionProvider dp)
{
    private readonly IDataProtector _p = dp.CreateProtector("secrets.v1");

    public string Encrypt(string plain)  => _p.Protect(plain);
    public string Decrypt(string cipher) => _p.Unprotect(cipher);
}
```

---

## 39.6 Environment-Specific Configuration Files

```
appsettings.json            ← defaults, committed
appsettings.Development.json ← dev overrides, committed (no real secrets)
appsettings.Staging.json    ← staging, committed (no secrets)
appsettings.Production.json ← prod, committed (no secrets — use env vars)
appsettings.Local.json      ← .gitignored, developer's personal overrides
```

```json
// appsettings.json
{
  "Logging": { "LogLevel": { "Default": "Warning" } },
  "Database": { "MaxRetries": 3 }
}

// appsettings.Development.json
{
  "Logging": { "LogLevel": { "Default": "Debug" } },
  "Database": { "ConnectionString": "Data Source=dev.db" }
}
```

```bash
DOTNET_ENVIRONMENT=Staging dotnet run    # loads appsettings.Staging.json
```

---

## 39.7 Config Validation at Startup

Failing fast on bad config is better than failing at 3am when the first
request hits the code path that reads the missing value.

```csharp
// Data annotations
public record SmtpOptions
{
    [Required]
    public required string Host { get; init; }

    [Range(1, 65535)]
    public required int Port { get; init; }

    [EmailAddress]
    public required string From { get; init; }
}

services
    .AddOptions<SmtpOptions>()
    .BindConfiguration("Smtp")
    .ValidateDataAnnotations()
    .ValidateOnStart();   // throws OptionsValidationException at startup
```

For custom logic:

```csharp
services
    .AddOptions<SmtpOptions>()
    .BindConfiguration("Smtp")
    .Validate(opts =>
    {
        if (opts.UseTls && opts.Port == 25)
            return false;   // 25 is not TLS
        return true;
    }, "SMTP: Port 25 cannot be used with TLS. Use 465 or 587.")
    .ValidateOnStart();
```

---

## 39.8 `IOptionsMonitor<T>` — Live Reloading

```csharp
// Some settings should update without restarting the app
// Example: log level, feature flags, rate limits

// Source: appsettings.json with reloadOnChange: true (the default)
config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);

public class RateLimitMiddleware(IOptionsMonitor<RateLimitOptions> opts)
{
    // opts.CurrentValue always reflects the latest config
    // This reads the updated value without restart
    public async Task InvokeAsync(HttpContext ctx, RequestDelegate next)
    {
        var limit = opts.CurrentValue.RequestsPerMinute;
        // ...
    }
}

// Subscribe to change events:
public class FeatureFlagService(IOptionsMonitor<FeatureFlags> monitor)
{
    public FeatureFlagService(IOptionsMonitor<FeatureFlags> monitor)
    {
        monitor.OnChange(flags =>
            Console.WriteLine($"Feature flags updated: {flags}"));
    }
}
```

---

## 39.9 CLI App — Config from Arguments + File + Env

```csharp
// CLI tools often need: --config path.json to point at a custom config file
// This is how to wire it up cleanly with System.CommandLine

var configFileOption = new Option<FileInfo?>("--config", "Path to config file");
var root = new RootCommand { configFileOption };

root.SetHandler(async (FileInfo? cfgFile) =>
{
    var cfgBuilder = new ConfigurationBuilder()
        .AddEnvironmentVariables("MYTOOL_");  // MYTOOL_Database__Host etc.

    if (cfgFile is { Exists: true })
        cfgBuilder.AddJsonFile(cfgFile.FullName);
    else
        cfgBuilder.AddJsonFile("appsettings.json", optional: true);

    var config = cfgBuilder.Build();
    // ... build services, run
}, configFileOption);

await root.InvokeAsync(args);
```

---

## 39.10 The Settings Summary Table

| Where it's needed | How to store | How to read |
|---|---|---|
| Dev machine overrides | User Secrets | `AddUserSecrets<Program>()` |
| Plaintext per-env config | `appsettings.{Env}.json` | Loaded by Host automatically |
| Production secrets | Environment variables | `AddEnvironmentVariables()` |
| Encrypted on-disk values | Data Protection | `IDataProtector.Protect/Unprotect` |
| Container/Kubernetes | Env vars or mounted files | `AddEnvironmentVariables()` / `AddJsonFile()` |
| CLI overrides | Command-line args | `AddCommandLine(args)` |
| Live-reloading settings | `appsettings.json` + `reloadOnChange: true` | `IOptionsMonitor<T>` |

### The Rule of Thumb

```
If it's different per environment → appsettings.{Env}.json
If it's secret → environment variable
If it needs encrypting at rest → Data Protection
If it changes at runtime → IOptionsMonitor
If it must be validated → ValidateDataAnnotations + ValidateOnStart
Never → string literals in source code
Never → secrets in appsettings.json in git
```
