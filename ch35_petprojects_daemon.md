# Chapter 35 — Pet Projects III: Background Daemons & Worker Services

> A daemon runs continuously, silently, doing work triggered by timers,
> file changes, or queues. This chapter shows three complete daemons
> using the .NET Generic Host (Ch 16) as the runtime.

---

## 35.1 The Generic Host as Daemon Chassis

```bash
dotnet new worker -n MyDaemon
```

A Worker Service project gives you this skeleton, which is the correct
foundation for every daemon in this chapter:

```csharp
// Program.cs
using Serilog;

Log.Logger = new LoggerConfiguration().WriteTo.Console().CreateBootstrapLogger();
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddSerilog((_, lc) => lc.ReadFrom.Configuration(builder.Configuration).WriteTo.Console());
builder.Services.AddHostedService<MyWorker>();
builder.Services.AddHostedService<AnotherWorker>();

builder.Services.UseSystemd();   // Linux systemd integration
// builder.Services.UseWindowsService(); // Windows SCM

await builder.Build().RunAsync();
```

```bash
# Packages
dotnet add package Serilog.Extensions.Hosting
dotnet add package Serilog.Sinks.Console
dotnet add package Serilog.Sinks.File
dotnet add package Microsoft.Extensions.Hosting.Systemd
```

---

## 35.2 Project 1 — File Watcher Daemon

**What it does:** Watch one or more directories for changes, debounce
events, write a structured event log to a rolling JSON file. Loads
watched paths from config.

**Concepts:** `FileSystemWatcher`, `IOptionsMonitor<T>`, `BackgroundService`,
`Channels`, `PeriodicTimer`, rolling file output (Ch 12, Ch 16, Ch 10)

```csharp
// appsettings.json
{
  "Watcher": {
    "Directories": ["/home/user/Documents", "/home/user/Downloads"],
    "LogDirectory": "/tmp/filewatcher-logs"
  }
}
```

```csharp
// WatcherOptions.cs
public class WatcherOptions
{
    public const string Section = "Watcher";
    public string[] Directories { get; set; } = [];
    public string   LogDirectory { get; set; } = "/tmp/fw-logs";
}

// FileEvent.cs
public record FileEvent(
    string   Path,
    string   Kind,         // "Created" | "Modified" | "Deleted" | "Renamed"
    long?    Size,
    DateTime OccurredAt);

// FileWatcherWorker.cs
public sealed class FileWatcherWorker : BackgroundService
{
    private readonly WatcherOptions                   _opts;
    private readonly ILogger<FileWatcherWorker>       _logger;
    private readonly Channel<FileEvent>               _channel;
    private readonly List<FileSystemWatcher>          _watchers = new();

    // Debounce: suppress duplicate events within 300ms for the same path
    private readonly Dictionary<string, DateTime>    _lastSeen = new();
    private const int DebounceMs = 300;

    public FileWatcherWorker(IOptions<WatcherOptions> opts, ILogger<FileWatcherWorker> logger)
    {
        _opts    = opts.Value;
        _logger  = logger;
        _channel = Channel.CreateBounded<FileEvent>(
            new BoundedChannelOptions(1024) { FullMode = BoundedChannelFullMode.DropOldest });
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        Directory.CreateDirectory(_opts.LogDirectory);

        foreach (var dir in _opts.Directories)
        {
            if (!Directory.Exists(dir)) { _logger.LogWarning("Directory not found: {Dir}", dir); continue; }
            var watcher = new FileSystemWatcher(dir)
            {
                IncludeSubdirectories = true,
                NotifyFilter          = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.DirectoryName,
                EnableRaisingEvents   = true,
            };
            watcher.Changed += (_, e) => Enqueue(e.FullPath, "Modified");
            watcher.Created += (_, e) => Enqueue(e.FullPath, "Created");
            watcher.Deleted += (_, e) => Enqueue(e.FullPath, "Deleted");
            watcher.Renamed += (_, e) => Enqueue(e.FullPath, "Renamed");
            _watchers.Add(watcher);
            _logger.LogInformation("Watching {Dir}", dir);
        }

        // Consumer: write events to rolling JSON log
        _ = Task.Run(() => FlushLoopAsync(ct), ct);

        await Task.Delay(Timeout.Infinite, ct);
    }

    private void Enqueue(string path, string kind)
    {
        // Debounce
        var now = DateTime.UtcNow;
        lock (_lastSeen)
        {
            if (_lastSeen.TryGetValue(path, out var last) &&
                (now - last).TotalMilliseconds < DebounceMs) return;
            _lastSeen[path] = now;
        }

        long? size = null;
        if (File.Exists(path)) try { size = new FileInfo(path).Length; } catch { }

        _channel.Writer.TryWrite(new FileEvent(path, kind, size, now));
    }

    private async Task FlushLoopAsync(CancellationToken ct)
    {
        var logPath = Path.Combine(_opts.LogDirectory, $"events-{DateTime.UtcNow:yyyy-MM-dd}.jsonl");
        await using var writer = new StreamWriter(logPath, append: true);

        await foreach (var evt in _channel.Reader.ReadAllAsync(ct))
        {
            var json = System.Text.Json.JsonSerializer.Serialize(evt);
            await writer.WriteLineAsync(json);
            await writer.FlushAsync(ct);
            _logger.LogDebug("{Kind} {Path}", evt.Kind, evt.Path);
        }
    }

    public override void Dispose()
    {
        foreach (var w in _watchers) w.Dispose();
        _channel.Writer.Complete();
        base.Dispose();
    }
}
```

---

## 35.3 Project 2 — Log Tail and Alerter

**What it does:** Watch a log file (like nginx or app logs). Scan new
lines for patterns (regex). Send an alert to a webhook (e.g. Slack,
Discord, ntfy.sh) when a pattern matches.

**Concepts:** `FileStream` with retry/seek, `PeriodicTimer`, `Regex`,
`HttpClient`, `IOptionsMonitor` (Ch 12, Ch 13, Ch 8)

```csharp
// appsettings.json
{
  "LogTail": {
    "FilePath":   "/var/log/nginx/error.log",
    "Patterns":   ["ERROR", "CRITICAL", "Out of memory"],
    "WebhookUrl": "https://ntfy.sh/my-alerts",
    "Topic":      "server-alerts"
  }
}
```

```csharp
public class LogTailOptions
{
    public const string Section = "LogTail";
    public string   FilePath   { get; set; } = "";
    public string[] Patterns   { get; set; } = [];
    public string   WebhookUrl { get; set; } = "";
}

public sealed class LogTailerWorker : BackgroundService
{
    private readonly LogTailOptions             _opts;
    private readonly HttpClient                 _http;
    private readonly ILogger<LogTailerWorker>   _logger;
    private readonly System.Text.RegularExpressions.Regex[] _regexes;

    public LogTailerWorker(IOptions<LogTailOptions> opts,
        HttpClient http, ILogger<LogTailerWorker> logger)
    {
        _opts    = opts.Value;
        _http    = http;
        _logger  = logger;
        _regexes = opts.Value.Patterns
            .Select(p => new System.Text.RegularExpressions.Regex(
                p, System.Text.RegularExpressions.RegexOptions.Compiled |
                   System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            .ToArray();
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _logger.LogInformation("Tailing {File}", _opts.FilePath);

        // Wait for file to exist
        while (!File.Exists(_opts.FilePath) && !ct.IsCancellationRequested)
        {
            _logger.LogWarning("Waiting for {File}…", _opts.FilePath);
            await Task.Delay(5000, ct);
        }

        // Seek to end — we only care about NEW lines
        long position = new FileInfo(_opts.FilePath).Length;

        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(2));
        while (await timer.WaitForNextTickAsync(ct))
        {
            try { position = await ReadNewLinesAsync(position, ct); }
            catch (Exception ex) { _logger.LogError(ex, "Error reading log file"); }
        }
    }

    private async Task<long> ReadNewLinesAsync(long fromPosition, CancellationToken ct)
    {
        await using var stream = new FileStream(_opts.FilePath,
            FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

        if (stream.Length < fromPosition)  // file was rotated
            fromPosition = 0;

        stream.Seek(fromPosition, SeekOrigin.Begin);
        using var reader = new StreamReader(stream, leaveOpen: true);

        string? line;
        while ((line = await reader.ReadLineAsync(ct)) is not null)
        {
            foreach (var regex in _regexes)
            {
                if (!regex.IsMatch(line)) continue;
                _logger.LogWarning("ALERT matched '{Pattern}': {Line}", regex.ToString(), line);
                await SendAlertAsync(line, ct);
                break;
            }
        }

        return stream.Position;
    }

    private async Task SendAlertAsync(string message, CancellationToken ct)
    {
        try
        {
            // ntfy.sh: just POST plaintext to the topic URL
            using var content = new StringContent(message[..Math.Min(message.Length, 500)]);
            await _http.PostAsync(_opts.WebhookUrl, content, ct);
        }
        catch (Exception ex) { _logger.LogError(ex, "Failed to send alert"); }
    }
}
```

---

## 35.4 Project 3 — Scheduled Job Runner

**What it does:** Define jobs as classes with a cron-style schedule.
Each job runs on its timer. A dashboard task prints status every 10s.

**Concepts:** `BackgroundService`, `PeriodicTimer`, `CancellationToken`,
`Task.WhenAll`, scoped services in background (Ch 16)

```csharp
// Program.cs additions
builder.Services.AddSingleton<JobRegistry>();
builder.Services.AddTransient<CleanTempFilesJob>();
builder.Services.AddTransient<DailyReportJob>();
builder.Services.AddHostedService<JobRunnerWorker>();
```

```csharp
// JobRegistry.cs
public interface IScheduledJob
{
    string       Name     { get; }
    TimeSpan     Interval { get; }
    Task         RunAsync(CancellationToken ct);
}

public class JobRegistry
{
    private readonly List<IScheduledJob> _jobs = new();
    public void Register(IScheduledJob job) => _jobs.Add(job);
    public IReadOnlyList<IScheduledJob> Jobs => _jobs;
}

// CleanTempFilesJob.cs — runs every hour
public sealed class CleanTempFilesJob : IScheduledJob
{
    private readonly ILogger<CleanTempFilesJob> _logger;

    public CleanTempFilesJob(ILogger<CleanTempFilesJob> logger) => _logger = logger;

    public string   Name     => "CleanTempFiles";
    public TimeSpan Interval => TimeSpan.FromHours(1);

    public Task RunAsync(CancellationToken ct)
    {
        var tmp    = Path.GetTempPath();
        int deleted = 0;
        var cutoff  = DateTime.UtcNow - TimeSpan.FromDays(1);

        foreach (var file in Directory.EnumerateFiles(tmp, "*.tmp"))
        {
            if (ct.IsCancellationRequested) break;
            try
            {
                if (File.GetLastWriteTimeUtc(file) < cutoff)
                { File.Delete(file); deleted++; }
            }
            catch { /* skip locked */ }
        }
        _logger.LogInformation("CleanTempFiles: deleted {Count} files", deleted);
        return Task.CompletedTask;
    }
}

// JobRunnerWorker.cs
public sealed class JobRunnerWorker : BackgroundService
{
    private readonly JobRegistry                 _registry;
    private readonly ILogger<JobRunnerWorker>    _logger;

    public JobRunnerWorker(JobRegistry registry, ILogger<JobRunnerWorker> logger)
    {
        _registry = registry;
        _logger   = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var tasks = _registry.Jobs.Select(job => RunJobAsync(job, ct));
        await Task.WhenAll(tasks);
    }

    private async Task RunJobAsync(IScheduledJob job, CancellationToken ct)
    {
        // Run immediately on start, then on interval
        await TryRunAsync(job, ct);

        using var timer = new PeriodicTimer(job.Interval);
        while (await timer.WaitForNextTickAsync(ct))
            await TryRunAsync(job, ct);
    }

    private async Task TryRunAsync(IScheduledJob job, CancellationToken ct)
    {
        _logger.LogDebug("Starting job: {Job}", job.Name);
        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            await job.RunAsync(ct);
            _logger.LogInformation("Job {Job} completed in {Ms}ms", job.Name, sw.ElapsedMilliseconds);
        }
        catch (Exception ex) when (!ct.IsCancellationRequested)
        {
            _logger.LogError(ex, "Job {Job} failed", job.Name);
        }
    }
}
```

---

## 35.5 Installing as a systemd Service

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My .NET 9 Daemon
After=network.target

[Service]
Type=notify
User=myapp
ExecStart=/opt/myapp/MyDaemon
WorkingDirectory=/opt/myapp
Restart=on-failure
RestartSec=5
Environment=DOTNET_ENVIRONMENT=Production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=myapp

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable myapp
sudo systemctl start myapp
sudo systemctl status myapp
journalctl -u myapp -f          # follow live logs
```

The `UseSystemd()` call in `Program.cs` makes `systemctl status` show
the "active (running)" notification and `systemctl stop` triggers a
graceful shutdown via `CancellationToken`.
