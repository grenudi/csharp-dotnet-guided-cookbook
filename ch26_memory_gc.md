# Chapter 26 — Memory Management & the Garbage Collector

## 26.1 Why This Matters

Most .NET developers never think about memory — and most of the time that is fine.
The GC handles it. But senior developers need to understand the GC because:

- Memory leaks are real in .NET and they come from specific patterns
- GC pauses affect latency in high-throughput applications
- Knowing how the GC works explains why certain patterns (Span<T>, pooling,
  value types) exist and when to use them

---

## 26.2 How the GC Works — The Heap

The managed heap has three generations plus a Large Object Heap:

```
┌─────────────────────────────────────────────────────────────┐
│                    Managed Heap                             │
├────────────┬──────────────┬───────────────┬─────────────────┤
│  Gen 0     │    Gen 1     │    Gen 2       │  LOH (Large)   │
│ ~256 KB    │  ~2 MB       │  Unlimited     │  ≥85,000 bytes │
├────────────┴──────────────┴───────────────┴─────────────────┤
│  New objects live here    Objects that survive GCs move up  │
│  Collected very frequently Collected rarely                  │
└─────────────────────────────────────────────────────────────┘
```

**Generation 0** — new allocations. Collected very frequently (milliseconds).
**Generation 1** — objects that survived one Gen 0 GC. Buffer between 0 and 2.
**Generation 2** — long-lived objects. Collected rarely. Full GC = expensive.
**LOH** — objects ≥ 85,000 bytes. Treated as Gen 2. Not compacted by default.

When you allocate an object:
1. It goes into Gen 0
2. If it survives a GC, it is promoted to Gen 1
3. If it survives again, promoted to Gen 2
4. Gen 2 objects are only collected during a full GC

**The rule:** short-lived objects are cheap. Long-lived objects are expensive.
Design for fast allocation and fast death.

---

## 26.3 The IDisposable Pattern — Correctly

`IDisposable` is for releasing **unmanaged resources** (file handles, network sockets,
database connections, native memory). The GC does NOT call `Dispose` — you must.

```csharp
// ❌ Resource leak — GC will eventually finalize but you cannot control when
var conn = new SqlConnection(connectionString);
conn.Open();
var result = conn.ExecuteScalar("SELECT COUNT(*) FROM orders");
// conn is never disposed — connection held until GC finalizes it
// Under load: connection pool exhausted, new connections fail

// ✅ Always use using — guaranteed disposal even on exception
using var conn = new SqlConnection(connectionString);
conn.Open();
var result = conn.ExecuteScalar("SELECT COUNT(*) FROM orders");
// conn.Dispose() called here — connection returned to pool immediately
```

### Implementing IDisposable Correctly

```csharp
// The standard Dispose pattern for classes that own unmanaged resources
public class FileManager : IDisposable
{
    private FileStream? _stream;
    private bool        _disposed;

    public FileManager(string path)
    {
        _stream = new FileStream(path, FileMode.Open);
    }

    // Called by consumer code via using statement
    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);  // tell GC not to call finalizer
    }

    // Called by GC finalizer (safety net if consumer forgot to Dispose)
    ~FileManager()
    {
        Dispose(disposing: false);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;

        if (disposing)
        {
            // Free managed resources (other IDisposable objects)
            _stream?.Dispose();
            _stream = null;
        }
        // Free unmanaged resources here (always, regardless of disposing flag)

        _disposed = true;
    }

    public void Write(string text)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        // ...
    }
}
```

### Simplified Pattern (Most Cases)

```csharp
// For classes that only own managed IDisposable objects (no native resources):
// Skip the finalizer — it's only needed for raw unmanaged resources
public class OrderProcessor : IDisposable
{
    private readonly HttpClient      _http;
    private readonly AppDbContext    _db;
    private bool                     _disposed;

    public OrderProcessor(HttpClient http, AppDbContext db)
    { _http = http; _db = db; }

    public void Dispose()
    {
        if (_disposed) return;
        _http.Dispose();
        _db.Dispose();
        _disposed = true;
    }
}
```

### IAsyncDisposable

```csharp
// For classes with async cleanup (DB transactions, network connections)
public class AsyncResource : IAsyncDisposable
{
    private readonly SemaphoreSlim _lock = new(1, 1);

    public async ValueTask DisposeAsync()
    {
        await FlushAsync();          // drain pending work before closing
        _lock.Dispose();
        GC.SuppressFinalize(this);
    }

    private async Task FlushAsync() { /* flush buffers */ }
}

// Usage
await using var resource = new AsyncResource();
// resource.DisposeAsync() called automatically
```

---

## 26.4 Common Memory Leak Patterns

### Event Handler Leak

```csharp
// ❌ Classic leak — subscriber holds a reference to publisher via event
public class OrderService
{
    public event EventHandler<OrderEventArgs>? OrderPlaced;
}

public class EmailNotifier
{
    private readonly OrderService _service;

    public EmailNotifier(OrderService service)
    {
        _service = service;
        _service.OrderPlaced += OnOrderPlaced;  // publisher holds reference to this!
    }

    private void OnOrderPlaced(object? sender, OrderEventArgs e) { /* ... */ }

    // If EmailNotifier is "discarded" but OrderService lives on,
    // EmailNotifier is never GC'd — it's still referenced by the event
}

// ✅ Fix: unsubscribe in Dispose
public class EmailNotifier : IDisposable
{
    public EmailNotifier(OrderService service)
    {
        _service = service;
        _service.OrderPlaced += OnOrderPlaced;
    }

    public void Dispose()
    {
        _service.OrderPlaced -= OnOrderPlaced;  // unsubscribe
    }
}
```

### Static Field Leak

```csharp
// ❌ Leak: static dictionary grows forever — objects can never be GC'd
private static readonly Dictionary<string, UserSession> _sessions = new();

public void AddSession(string token, UserSession session)
    => _sessions[token] = session;  // grows forever — no eviction

// ✅ Use IMemoryCache with expiry (see Chapter 27)
// ✅ Or use WeakReference for optional caching
private static readonly Dictionary<string, WeakReference<UserSession>> _cache = new();
```

### WeakReference — Optional Caching Without Leaks

```csharp
// WeakReference lets GC collect the object when memory is needed
// Use when: caching is optional — you can regenerate if the object is collected
private readonly Dictionary<int, WeakReference<ComputedReport>> _reportCache = new();

public ComputedReport GetReport(int id)
{
    if (_reportCache.TryGetValue(id, out var weak) &&
        weak.TryGetTarget(out var cached))
    {
        return cached;  // still alive
    }

    // Regenerate — either not cached or GC collected it
    var report = ComputeExpensiveReport(id);
    _reportCache[id] = new WeakReference<ComputedReport>(report);
    return report;
}
```

### Closures Capturing Large Objects

```csharp
// ❌ Closure captures the entire Order — keeps it alive
byte[] buffer = new byte[10_000_000];  // 10MB

Func<int> getLength = () => buffer.Length;  // buffer stays alive as long as getLength lives

// ✅ Capture only what you need
int length = buffer.Length;
Func<int> getLength2 = () => length;  // only the int, not the array
buffer = null!;  // array can now be GC'd
```

---

## 26.5 Reducing GC Pressure

### Object Pooling

```csharp
using Microsoft.Extensions.ObjectPool;

// Pool expensive-to-create objects rather than allocating/deallocating
var pool = ObjectPool.Create<StringBuilder>();

// Get from pool
var sb = pool.Get();
try
{
    sb.Append("Hello ");
    sb.Append("World");
    var result = sb.ToString();
    return result;
}
finally
{
    pool.Return(sb);  // return to pool — not GC'd
}

// ArrayPool<T> — high-performance array renting
byte[] buffer = ArrayPool<byte>.Shared.Rent(4096);  // may give >4096
try
{
    int read = await stream.ReadAsync(buffer.AsMemory(0, 4096));
    Process(buffer.AsSpan(0, read));
}
finally
{
    ArrayPool<byte>.Shared.Return(buffer);  // return to pool
}
```

### Value Types for Short-Lived Data

```csharp
// Structs live on the stack (when local) or inline in their container (when field)
// No GC pressure for short-lived data

// ❌ Class — heap allocation + GC pressure for every coordinate
public class Point { public double X; public double Y; }

// ✅ Struct — stack-allocated when local, no GC involved
public readonly record struct Point(double X, double Y);

// Processing a million points:
Point[] points = new Point[1_000_000];  // ONE heap allocation, elements inline
// vs Point[] with class: 1M heap allocations + GC overhead
```

---

## 26.6 GC Modes and Configuration

```csharp
// Server GC vs Workstation GC
// Server GC: one GC heap per CPU core, parallel GC — for server apps
// Workstation GC: single heap, lower latency — for desktop apps
// ASP.NET Core uses Server GC by default
```

```json
// Configure in runtimeconfig.json or .csproj
{
  "configProperties": {
    "System.GC.Server": true,            // server GC
    "System.GC.Concurrent": true,        // background GC (default true)
    "System.GC.HeapHardLimit": 1073741824, // 1GB hard limit
    "System.GC.HighMemoryPercent": 90    // trigger GC at 90% memory usage
  }
}
```

```xml
<!-- In .csproj -->
<PropertyGroup>
  <ServerGarbageCollection>true</ServerGarbageCollection>
  <GarbageCollectionAdaptationMode>0</GarbageCollectionAdaptationMode>
</PropertyGroup>
```

---

## 26.7 Diagnosing Memory Problems

```bash
# dotnet-counters — live memory metrics
dotnet counters monitor --process-id <pid> \
    --counters System.Runtime[gc-heap-size,gen-0-gc-count,gen-1-gc-count,gen-2-gc-count]

# dotnet-dump — capture heap snapshot
dotnet dump collect --process-id <pid>

# Analyze the dump
dotnet dump analyze ./core_20250115.dmp

# Inside dump analysis:
# > dumpheap -stat        — object counts and sizes by type
# > gcroot <address>      — what is keeping this object alive?
# > eeheap -gc            — GC heap layout

# dotnet-gcdump — GC-specific heap snapshot (smaller, faster)
dotnet gcdump collect --process-id <pid>
# Open in Visual Studio or PerfView
```

### Memory Leak Investigation in Code

```csharp
// Add memory tracking to find leaks in tests
[Fact]
public void Operation_DoesNotLeak()
{
    // Force GC to establish baseline
    GC.Collect(2, GCCollectionMode.Forced, blocking: true);
    GC.WaitForPendingFinalizers();
    GC.Collect(2, GCCollectionMode.Forced, blocking: true);

    long before = GC.GetTotalMemory(forceFullCollection: false);

    // Run the operation 1000 times
    for (int i = 0; i < 1000; i++)
        RunOperation();

    GC.Collect(2, GCCollectionMode.Forced, blocking: true);
    GC.WaitForPendingFinalizers();
    GC.Collect(2, GCCollectionMode.Forced, blocking: true);

    long after = GC.GetTotalMemory(forceFullCollection: false);
    long perOp = (after - before) / 1000;

    // If perOp >> 0, something is leaking
    Assert.True(perOp < 1000, $"Possible memory leak: {perOp} bytes/op retained");
}
```

> **Rider tip:** *Run → dotMemory Session* attaches the JetBrains memory profiler.
> Take a snapshot, run your operation, take another snapshot, and use *Compare* to
> see exactly which objects were created and not collected. Filter by "Survived" to
> find leaks immediately.

> **VS tip:** *Debug → Performance Profiler → .NET Object Allocation Tracking* shows
> every allocation with its call stack. *Memory Usage* shows heap snapshots. Both are
> in `Alt+F2 → Performance Profiler`.
