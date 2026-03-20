# Chapter 16 — Worker Services & Background Jobs

> Not all work in a program responds to a request. Sending emails,
> processing queued jobs, watching files, syncing data, cleaning up old
> records — all of this happens in the background, driven by time or
> events rather than user input. .NET's Generic Host and
> `BackgroundService` provide a principled way to run this work as
> long-running processes with the same configuration, DI, and logging
> infrastructure as your web application.

*Building on:* Ch 8 (async/await, CancellationToken — the entire
lifecycle of a BackgroundService is async and cancellable), Ch 9
(configuration), Ch 10 (DI — the host is a DI container),
Ch 11 §11.8 (scoped services in BackgroundService — the captive
dependency trap)

---

## 16.1 The Generic Host — The Engine Behind Workers and Web Apps

The Generic Host is the chassis that every modern .NET application runs
on, whether it is a web API, a background worker, or a CLI tool. It
provides:

- **Dependency Injection** — registers and resolves services
- **Configuration** — loads `appsettings.json`, env vars, etc.
- **Logging** — wires up ILogger for all services
- **Lifetime management** — handles startup, graceful shutdown, and SIGTERM

For web applications, ASP.NET Core is an `IHostedService` that plugs into
the host. For background workers, your services are `IHostedService`
(or its convenience subclass `BackgroundService`). The host starts all
hosted services, waits for a shutdown signal, then stops them gracefully.

```csharp
// The entire skeleton of a worker service
var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, services) =>
    {
        // Configuration is already wired; add your services here
        services.AddOptions<WorkerOptions>()
            .BindConfiguration("Worker")
            .ValidateOnStart();

        services.AddDbContext<AppDbContext>(o =>
            o.UseSqlite(ctx.Configuration["Database:ConnectionString"]));

        // Register one or more background services
        services.AddHostedService<CleanupWorker>();
        services.AddHostedService<EmailWorker>();
    })
    .Build();

await host.RunAsync();
```

`Host.CreateDefaultBuilder` wires the full configuration stack, Serilog-
compatible logging, and SIGTERM handling for free.

---

## 16.2 `BackgroundService` — The Building Block

`BackgroundService` is an abstract class that wraps `IHostedService`. You
override one method: `ExecuteAsync`. The host calls it at startup and
awaits it. When the host receives a shutdown signal, it cancels the
`CancellationToken` that `ExecuteAsync` receives. Your service detects
the cancellation and exits cleanly.

```csharp
// The pattern: a loop that does work, checks for cancellation, sleeps
public class EmailDispatchWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<EmailDispatchWorker> _logger;

    public EmailDispatchWorker(IServiceScopeFactory scopeFactory,
                               ILogger<EmailDispatchWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger       = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _logger.LogInformation("Email dispatch worker starting");

        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));

        // WaitForNextTickAsync returns false when ct is cancelled
        while (await timer.WaitForNextTickAsync(ct))
        {
            try
            {
                await DispatchPendingEmailsAsync(ct);
            }
            catch (OperationCanceledException)
            {
                // Cancellation — exit the loop cleanly
                break;
            }
            catch (Exception ex)
            {
                // Log the error but keep the worker running
                // A crash here stops the worker permanently — prefer resilience
                _logger.LogError(ex, "Error dispatching emails");
            }
        }

        _logger.LogInformation("Email dispatch worker stopped");
    }

    private async Task DispatchPendingEmailsAsync(CancellationToken ct)
    {
        // Create a new scope per cycle — DbContext is Scoped, not Singleton
        await using var scope  = _scopeFactory.CreateAsyncScope();
        var db    = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var email = scope.ServiceProvider.GetRequiredService<IEmailSender>();

        var pending = await db.EmailQueue
            .Where(e => e.Status == EmailStatus.Pending)
            .Take(50)
            .ToListAsync(ct);

        foreach (var item in pending)
        {
            await email.SendAsync(item.To, item.Subject, item.Body, ct);
            item.Status = EmailStatus.Sent;
            item.SentAt = DateTime.UtcNow;
        }
        await db.SaveChangesAsync(ct);
        _logger.LogInformation("Dispatched {Count} emails", pending.Count);
    }
}
```

### Why `IServiceScopeFactory` and Not Direct Injection of `DbContext`

`BackgroundService` is a Singleton — it lives for the entire application
lifetime. `DbContext` is Scoped — it should live for a single unit of work.
If you inject `DbContext` directly into `BackgroundService`, you capture
one DbContext forever (the captive dependency bug). All work cycles share
the same stale, connection-leaking instance.

The fix: inject `IServiceScopeFactory`, create a new scope per work cycle,
resolve the Scoped services from that scope, then dispose it. This gives
each cycle its own fresh DbContext with its own connection.

---

## 16.3 `PeriodicTimer` — The Modern Timer Pattern

`PeriodicTimer` (introduced in .NET 6) is the preferred timer for
background work. Unlike `System.Timers.Timer`, it does not fire callbacks
on thread pool threads while your previous callback is still running —
the next tick only becomes available after the previous one is awaited.
This prevents concurrent execution of your work method with no extra
synchronisation needed.

```csharp
using var timer = new PeriodicTimer(TimeSpan.FromMinutes(5));
while (await timer.WaitForNextTickAsync(ct))  // blocks until tick or cancellation
{
    await DoWorkAsync(ct);  // this FINISHES before the next tick is awaited
}
// If DoWorkAsync takes 4 minutes and the interval is 5 minutes,
// the next tick comes 5 minutes after the PREVIOUS tick was awaited,
// not 1 minute after work finishes. There is no overlap.
```

---

## 16.4 `IHostedService` — Custom Lifecycle

`BackgroundService` covers most cases. Use `IHostedService` directly when
you need precise control over startup and shutdown sequencing — for example,
a service that must acquire a resource during startup and release it at
shutdown:

```csharp
public class DatabaseHealthChecker : IHostedService, IDisposable
{
    private Timer? _timer;
    private readonly ILogger<DatabaseHealthChecker> _logger;

    public DatabaseHealthChecker(ILogger<DatabaseHealthChecker> logger) =>
        _logger = logger;

    // Called by the host at startup — before the app is ready to serve requests
    public Task StartAsync(CancellationToken ct)
    {
        _logger.LogInformation("DB health checker starting");
        _timer = new Timer(CheckHealth, null,
            dueTime:  TimeSpan.Zero,
            period:   TimeSpan.FromSeconds(30));
        return Task.CompletedTask;
    }

    private void CheckHealth(object? state) { /* ... */ }

    // Called by the host at shutdown — after all requests are drained
    public Task StopAsync(CancellationToken ct)
    {
        _logger.LogInformation("DB health checker stopping");
        _timer?.Change(Timeout.Infinite, 0);
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();
}

services.AddSingleton<IHostedService, DatabaseHealthChecker>();
```

---

## 16.5 Health Checks — Signalling Readiness and Liveness

Health checks tell orchestrators (Kubernetes, load balancers) whether the
service is healthy. There are two distinct signals:

- **Liveness**: is the process running? If not, restart it.
- **Readiness**: is the service ready to receive traffic? If not, remove
  it from the load balancer until it is.

```csharp
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>("database")   // pings the DB
    .AddUrlGroup(new Uri("https://api.external.com/health"), "external-api")
    .AddCheck("disk", () =>
    {
        var drive = new DriveInfo("/");
        return drive.AvailableFreeSpace < 100_000_000   // < 100MB free
            ? HealthCheckResult.Degraded("Disk space low")
            : HealthCheckResult.Healthy();
    });

// Map health check endpoints
app.MapHealthChecks("/health/live",  new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});
```

---

## 16.6 Deploying as a systemd Service

On Linux, the standard way to run a background service is as a systemd
unit. `UseSystemd()` integrates the host's lifetime with systemd signals
(SIGTERM for graceful stop, watchdog pings for health):

```bash
dotnet add package Microsoft.Extensions.Hosting.Systemd
```

```csharp
var host = Host.CreateDefaultBuilder(args)
    .UseSystemd()        // integrate with systemd: SIGTERM → graceful shutdown
    .ConfigureServices(...)
    .Build();
await host.RunAsync();
```

```ini
# /etc/systemd/system/myapp-worker.service
[Unit]
Description=My App Background Worker
After=network.target

[Service]
Type=notify                              # tells systemd we support sd_notify
ExecStart=/opt/myapp/MyApp.Worker        # path to published binary
WorkingDirectory=/opt/myapp
User=myapp
Group=myapp
Restart=always                           # restart if process exits
RestartSec=10
EnvironmentFile=/etc/myapp/secrets.env   # load secrets from file (chmod 600)

# Optional: resource limits
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable myapp-worker
sudo systemctl start myapp-worker
sudo systemctl status myapp-worker
sudo journalctl -u myapp-worker -f    # follow logs
```

---

## 16.7 Hangfire — Scheduled and Recurring Jobs

Hangfire is a library for jobs that need persistence (survive restarts),
scheduling, retry policies, and a management dashboard. It stores job
state in a database:

```bash
dotnet add package Hangfire.AspNetCore
dotnet add package Hangfire.Storage.SQLite  # or Hangfire.PostgreSql
```

```csharp
builder.Services.AddHangfire(cfg => cfg.UseSQLiteStorage("hangfire.db"));
builder.Services.AddHangfireServer(opts => opts.WorkerCount = 4);

// In Program.cs after Build():
app.MapHangfireDashboard("/jobs");  // management UI

// Enqueue a job (runs as soon as a worker is available)
BackgroundJob.Enqueue<IInvoiceService>(svc => svc.GenerateMonthlyInvoices());

// Schedule a job in the future
BackgroundJob.Schedule<IReportService>(
    svc => svc.GenerateDailyReport(),
    TimeSpan.FromHours(1));

// Recurring job (cron expression)
RecurringJob.AddOrUpdate<ICleanupService>(
    "cleanup-old-files",
    svc => svc.CleanOldFilesAsync(),
    Cron.Daily(hour: 2));   // 2am every day
```

---

## 16.8 Connecting Workers to the Rest of the Book

- **Ch 8 (Async)** — `CancellationToken` is the entire mechanism for
  graceful worker shutdown. Every async operation in the worker should
  accept and propagate it.
- **Ch 11 §11.8 (DI)** — the `IServiceScopeFactory` pattern is mandatory
  for using Scoped services from a Singleton BackgroundService.
- **Ch 35 (Pet Projects — Daemons)** — complete file watcher, log tail,
  and job runner daemons built on this chapter's foundations.
- **Ch 30 (Observability)** — background services need metrics and
  distributed tracing just as much as API endpoints. OpenTelemetry
  works in BackgroundService.
