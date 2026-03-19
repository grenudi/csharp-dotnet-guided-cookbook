# Chapter 16 — Worker Services & Background Jobs

## 16.1 Worker Service Project

```bash
dotnet new worker -n MyDaemon
```

### Project Structure

```
MyDaemon/
├── MyDaemon.csproj
├── Program.cs
├── appsettings.json
├── appsettings.Development.json
├── Workers/
│   ├── SyncWorker.cs
│   ├── CleanupWorker.cs
│   └── HealthCheckWorker.cs
└── Services/
    ├── ISyncService.cs
    └── SyncService.cs
```

### `.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>MyDaemon</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="9.0.0" />
    <PackageReference Include="Serilog.Extensions.Hosting" Version="9.0.0" />
  </ItemGroup>
</Project>
```

### `Program.cs`

```csharp
using Serilog;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var host = Host.CreateDefaultBuilder(args)
        .UseSerilog((ctx, services, config) => config
            .ReadFrom.Configuration(ctx.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext())
        .ConfigureServices((ctx, services) =>
        {
            services.AddSingleton<ISyncService, SyncService>();
            services.AddHostedService<SyncWorker>();
            services.AddHostedService<CleanupWorker>();
            services.Configure<SyncOptions>(ctx.Configuration.GetSection("Sync"));
        })
        .UseSystemd()      // enables systemd integration (Linux)
        .UseWindowsService() // enables Windows Service integration
        .Build();

    await host.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Host terminated unexpectedly");
}
finally
{
    await Log.CloseAndFlushAsync();
}
```

---

## 16.2 BackgroundService

`BackgroundService` is the base class for long-running services. It implements `IHostedService`.

```csharp
public class SyncWorker : BackgroundService
{
    private readonly ISyncService _sync;
    private readonly IOptionsMonitor<SyncOptions> _opts;
    private readonly ILogger<SyncWorker> _logger;

    public SyncWorker(
        ISyncService sync,
        IOptionsMonitor<SyncOptions> opts,
        ILogger<SyncWorker> logger)
    {
        _sync = sync;
        _opts = opts;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("SyncWorker started");

        // Wait a bit for dependencies to warm up
        await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using (_logger.BeginScope(new { RunId = Guid.NewGuid() }))
                {
                    await _sync.SyncAllAsync(stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break; // graceful shutdown
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during sync cycle");
            }

            var delay = _opts.CurrentValue.Interval;
            _logger.LogDebug("Next sync in {Delay}", delay);
            await Task.Delay(delay, stoppingToken).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing);
        }

        _logger.LogInformation("SyncWorker stopping");
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("SyncWorker stop requested");
        await base.StopAsync(cancellationToken);
    }
}
```

---

## 16.3 Timer-Based Worker (Periodic Timer)

```csharp
// PeriodicTimer — clean, cancellation-friendly (NET 6+)
public class CleanupWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<CleanupWorker> _logger;

    public CleanupWorker(IServiceScopeFactory scopeFactory, ILogger<CleanupWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            _logger.LogInformation("Starting cleanup cycle");
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

                // Delete old sessions
                var cutoff = DateTime.UtcNow.AddDays(-30);
                int deleted = await db.Sessions
                    .Where(s => s.ExpiresAt < cutoff)
                    .ExecuteDeleteAsync(stoppingToken);

                _logger.LogInformation("Deleted {Count} expired sessions", deleted);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Cleanup failed");
            }
        }
    }
}
```

---

## 16.4 Scoped Services in BackgroundService

`BackgroundService` is a singleton. To use scoped services (like `DbContext`), create a scope:

```csharp
public class DataProcessorWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<DataProcessorWorker> _logger;
    private readonly Channel<ProcessJob> _channel;

    public DataProcessorWorker(
        IServiceScopeFactory scopeFactory,
        ILogger<DataProcessorWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
        _channel = Channel.CreateBounded<ProcessJob>(100);
    }

    // Expose writer for other services to enqueue work
    public ChannelWriter<ProcessJob> Queue => _channel.Writer;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var job in _channel.Reader.ReadAllAsync(stoppingToken))
        {
            using var scope = _scopeFactory.CreateScope();
            var processor = scope.ServiceProvider.GetRequiredService<IJobProcessor>();

            try
            {
                await processor.ProcessAsync(job, stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Job {JobId} failed", job.Id);
            }
        }
    }
}
```

---

## 16.5 IHostedService — Custom Lifecycle

Implement `IHostedService` directly for more control:

```csharp
public class GrpcServerHostedService : IHostedService
{
    private WebApplication? _grpcApp;
    private readonly IConfiguration _config;
    private readonly ILogger<GrpcServerHostedService> _logger;

    public GrpcServerHostedService(IConfiguration config, ILogger<GrpcServerHostedService> logger)
    {
        _config = config;
        _logger = logger;
    }

    public async Task StartAsync(CancellationToken ct)
    {
        var builder = WebApplication.CreateBuilder();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton<SyncServiceImpl>();
        builder.WebHost.ConfigureKestrel(opts =>
            opts.ListenUnixSocket("/run/syncdot/syncdot.sock", l =>
                l.Protocols = HttpProtocols.Http2));

        _grpcApp = builder.Build();
        _grpcApp.MapGrpcService<SyncServiceImpl>();

        _logger.LogInformation("Starting gRPC server on Unix socket");
        await _grpcApp.StartAsync(ct);
    }

    public async Task StopAsync(CancellationToken ct)
    {
        _logger.LogInformation("Stopping gRPC server");
        if (_grpcApp is not null)
            await _grpcApp.StopAsync(ct);
    }
}
```

---

## 16.6 systemd Unit File

Deploy a .NET worker as a `systemd` service on Linux:

```ini
# /etc/systemd/system/syncdot.service
[Unit]
Description=SyncDot P2P File Sync Daemon
After=network.target

[Service]
Type=notify
User=syncdot
Group=syncdot
WorkingDirectory=/opt/syncdot
ExecStart=/opt/syncdot/SyncDot.Daemon
Restart=on-failure
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=30

# Environment
Environment=DOTNET_ENVIRONMENT=Production
Environment=ASPNETCORE_ENVIRONMENT=Production
EnvironmentFile=/etc/syncdot/env

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=syncdot

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/syncdot /run/syncdot

[Install]
WantedBy=multi-user.target
```

```bash
# Install and start
sudo systemctl daemon-reload
sudo systemctl enable syncdot
sudo systemctl start syncdot
sudo systemctl status syncdot
journalctl -u syncdot -f   # follow logs
```

### Enable systemd Notifications

```csharp
// Install: Microsoft.Extensions.Hosting.Systemd
builder.Host.UseSystemd();
// This enables:
// - NOTIFY_SOCKET (sends sd_notify READY=1 when started)
// - WATCHDOG_USEC (sends watchdog keepalive)
// - Graceful shutdown on SIGTERM
```

---

## 16.7 Health Checks

```csharp
// Registration
services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy("Running"))
    .AddDbContextCheck<AppDbContext>("database")
    .AddUrlGroup(new Uri("https://api.external.com/ping"), "external-api")
    .AddCheck<SyncWorkerHealthCheck>("sync-worker");

// Custom health check
public class SyncWorkerHealthCheck : IHealthCheck
{
    private readonly SyncWorker _worker;
    public SyncWorkerHealthCheck(SyncWorker worker) => _worker = worker;

    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context, CancellationToken ct)
    {
        if (_worker.LastSyncAt < DateTime.UtcNow.AddMinutes(-15))
            return Task.FromResult(HealthCheckResult.Degraded("Sync is overdue"));

        return Task.FromResult(HealthCheckResult.Healthy($"Last sync: {_worker.LastSyncAt:O}"));
    }
}

// Expose HTTP endpoint (if hosting HTTP as well)
app.MapHealthChecks("/healthz");
app.MapHealthChecks("/healthz/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});
```

---

## 16.8 Hangfire — Scheduled & Recurring Jobs

```xml
<PackageReference Include="Hangfire.AspNetCore" Version="1.8.14" />
<PackageReference Include="Hangfire.InMemory" Version="0.10.1" /> <!-- for dev -->
<PackageReference Include="Hangfire.PostgreSql" Version="1.20.9" /> <!-- for prod -->
```

```csharp
// Registration
builder.Services.AddHangfire(config => config
    .UseSimpleAssemblyNameTypeSerializer()
    .UseRecommendedSerializerSettings()
    .UsePostgreSqlStorage(connectionString));

builder.Services.AddHangfireServer(opts =>
{
    opts.WorkerCount = 5;
    opts.Queues = new[] { "critical", "default", "low" };
});

// Schedule jobs
app.MapHangfireDashboard("/hangfire"); // admin dashboard

// Fire-and-forget
BackgroundJob.Enqueue<IEmailService>(email => email.SendAsync("alice@example.com", "Welcome!"));

// Delayed
BackgroundJob.Schedule<ICleanupService>(
    svc => svc.CleanOldFilesAsync(),
    delay: TimeSpan.FromMinutes(30));

// Recurring
RecurringJob.AddOrUpdate<IReportService>(
    "daily-report",
    svc => svc.GenerateDailyReportAsync(),
    Cron.Daily(hour: 2));   // every day at 2 AM

// Continuations
var jobId = BackgroundJob.Enqueue<IOrderService>(svc => svc.ProcessAsync(orderId));
BackgroundJob.ContinueJobWith<INotificationService>(
    jobId,
    svc => svc.NotifyAsync(orderId));
```

> **Rider tip:** Use *Run → Run Configurations* to create a configuration for the worker service with specific environment variables (`DOTNET_ENVIRONMENT=Development`). Rider shows background service logs in the *Run* tab with color coding by log level.

> **VS tip:** *Debug → Attach to Process* lets you attach the debugger to a running service. Set breakpoints inside `ExecuteAsync` and they'll be hit on the next iteration.

