# Chapter 26 — Memory Management & the Garbage Collector

> .NET manages memory automatically. Most of the time you write code
> and never think about memory allocation. But automatic does not mean
> free — and when your application starts leaking memory, consuming
> gigabytes, or pausing for GC collection cycles, you need to understand
> what the runtime is doing on your behalf. This chapter explains the
> GC model, how to avoid the most common memory problems, and how to
> diagnose them when they appear.

*Building on:* Ch 2 (value types vs reference types — the fundamental
split between stack and heap allocation), Ch 3 (IDisposable, `using` —
the mechanism for releasing unmanaged resources), Ch 7 (Span<T> — the
primary tool for reducing allocations in hot paths)

---

## 26.1 The Stack and the Heap — Where Memory Lives

Every piece of data in a .NET program lives in one of two places:

**The stack** is a LIFO (last-in-first-out) block of memory per thread,
managed automatically by the CPU. Local variables and method parameters
are pushed when a method is entered and popped when it returns. Allocation
and deallocation are a single instruction — changing the stack pointer.
Value types (int, bool, struct, DateTime) typically live on the stack
when they are local variables.

**The heap** is a large region of memory managed by the GC. Reference
types (class instances) are always heap-allocated. The GC tracks which
objects are reachable (referenced) and periodically reclaims the memory
of objects that are no longer referenced.

```
Thread stack:              Heap:
│ ...          │          ┌──────────────────────┐
│ int count=5  │          │ List<Order> ←────────┼── local var 'orders'
│ Order* ref ──┼──────────┤ Order(Id=1)          │
│ ...          │          │ Order(Id=2)           │
└──────────────┘          │ ...                  │
                          └──────────────────────┘
```

When a method returns, its stack frame is popped instantly. When an
object on the heap has no more references to it, the GC will eventually
reclaim its memory — but not immediately.

---

## 26.2 How the Garbage Collector Works

The GC divides heap objects into three generations based on how long
they have survived. This reflects the empirical observation that most
objects die young:

```
Generation 0  — recently allocated objects
              — collected most frequently (milliseconds)
              — 90%+ of objects die here

Generation 1  — objects that survived one Gen 0 collection
              — collected less frequently
              — a buffer between Gen 0 and Gen 2

Generation 2  — long-lived objects: caches, singletons, static data
              — collected rarely
              — collections are expensive (pause the whole process)

Large Object Heap (LOH) — objects ≥ 85KB
              — collected with Gen 2
              — fragmentation risk
              — arrays, large strings, buffers
```

When the GC runs, it:
1. Pauses the application (Stop-The-World)
2. Walks the reference graph from known roots (statics, stack variables)
3. Marks all reachable objects
4. Reclaims unreachable objects
5. Compacts the heap (moves surviving objects together, updates references)
6. Resumes the application

The pause duration is why GC matters for latency. A Gen 0 collection is
under a millisecond. A Gen 2 collection on a large heap can pause for
tens or hundreds of milliseconds — a visible hitch in real-time systems.

### Server GC vs Workstation GC

```csharp
// In runtimeconfig.json or host configuration
{
  "configProperties": {
    "System.GC.Server": true    // Server GC — one heap per CPU core, better throughput
                                // Default for ASP.NET Core
                                // Workstation GC — single heap, lower memory, better latency
  }
}
```

---

## 26.3 `IDisposable` — Releasing Unmanaged Resources

The GC handles managed memory. It does not handle unmanaged resources:
file handles, database connections, network sockets, unmanaged memory
buffers, OS handles. These must be released explicitly.

`IDisposable` is the contract: implement `Dispose()` to release resources.
The `using` statement guarantees `Dispose()` is called, even if an
exception is thrown.

```csharp
// The complete IDisposable pattern
public class DatabaseConnection : IDisposable
{
    private SqliteConnection? _conn;
    private bool _disposed;

    public DatabaseConnection(string connectionString)
    {
        _conn = new SqliteConnection(connectionString);
        _conn.Open();
    }

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);  // prevent finaliser from running — we already cleaned up
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;
        if (disposing)
        {
            // Release managed resources that are themselves IDisposable
            _conn?.Dispose();
            _conn = null;
        }
        // If there were unmanaged resources (IntPtr, SafeHandle), release them here
        _disposed = true;
    }

    // Finaliser: safety net if the caller forgot to call Dispose()
    // Only needed if you hold unmanaged resources directly (rare)
    ~DatabaseConnection()
    {
        Dispose(disposing: false);
    }
}

// Caller always uses 'using'
using var conn = new DatabaseConnection(connectionString);
// ... use conn ...
// conn.Dispose() called here even if an exception occurs
```

### `IAsyncDisposable` — For Async Cleanup

When resource release requires async work (flushing a buffer, closing
a gRPC channel gracefully), implement `IAsyncDisposable`:

```csharp
public class AsyncResourceHolder : IAsyncDisposable
{
    private Stream? _stream;

    public async ValueTask DisposeAsync()
    {
        if (_stream is not null)
        {
            await _stream.FlushAsync();
            await _stream.DisposeAsync();
            _stream = null;
        }
        GC.SuppressFinalize(this);
    }
}

// Always prefer await using for IAsyncDisposable
await using var holder = new AsyncResourceHolder();
```

---

## 26.4 Memory Leaks — What Causes Them in .NET

A memory leak in .NET means: objects are being kept alive by references
that you forgot to clear. The GC cannot collect what it cannot see is
unused. Three patterns cause most leaks:

### Leak 1 — Event Handler Not Unsubscribed

```csharp
// The publisher holds a reference to every subscriber through the event delegate
// If the subscriber is unsubscribed, it stays alive as long as the publisher does
public class DataService
{
    public event EventHandler<DataChangedEventArgs>? DataChanged;
}

public class MyView
{
    private readonly DataService _service;

    public MyView(DataService service)
    {
        _service = service;
        _service.DataChanged += OnDataChanged;  // creates reference: service → view
    }

    private void OnDataChanged(object? s, DataChangedEventArgs e) { /* ... */ }

    public void Close()
    {
        // MUST unsubscribe — otherwise DataService holds this view alive forever
        _service.DataChanged -= OnDataChanged;
    }
}
```

### Leak 2 — Static References Holding Dynamic Data

```csharp
// Static fields live for the application lifetime
// Anything a static holds lives for the application lifetime
public static class GlobalCache
{
    // This cache grows forever if items are never removed
    private static readonly Dictionary<string, UserSession> _sessions = new();

    public static void AddSession(string id, UserSession s) => _sessions[id] = s;
    // Missing: expiry, eviction, cleanup
}
```

### Leak 3 — Captured Variables in Long-Lived Lambdas

```csharp
// The lambda captures 'data' — keeps it alive as long as the lambda lives
byte[] data = LoadLargeData();   // 100MB array

// If this lambda is stored in a long-lived collection, 'data' is never collected
_timers.Add(new Timer(_ =>
{
    Process(data);   // captures data — holds 100MB forever
}, null, TimeSpan.Zero, TimeSpan.FromHours(1)));
```

---

## 26.5 Reducing GC Pressure — Common Patterns

GC pressure means allocating many short-lived objects, which causes
frequent Gen 0 collections. In throughput-sensitive code (tight loops,
high-frequency request handlers), reducing allocations measurably
improves performance.

### Object Pooling

```csharp
// ArrayPool: reuse byte arrays instead of allocating new ones
// Avoids putting large arrays on the LOH
byte[] buffer = ArrayPool<byte>.Shared.Rent(4096);
try
{
    int read = await stream.ReadAsync(buffer, ct);
    Process(buffer[..read]);
}
finally
{
    ArrayPool<byte>.Shared.Return(buffer);  // return to pool, not GC
}

// ObjectPool<T> from Microsoft.Extensions.ObjectPool for custom types
var pool = ObjectPool.Create<StringBuilder>();
var sb   = pool.Get();
try
{
    sb.Append("build something");
    return sb.ToString();
}
finally
{
    pool.Return(sb);
}
```

### `Span<T>` and `Memory<T>` — Slice Without Allocation

```csharp
// Without Span: Substring allocates a new string
string input  = "2024-01-15";
string year   = input.Substring(0, 4);   // allocates "2024"
int    parsed = int.Parse(year);          // fine, but string allocated

// With Span: zero allocation
ReadOnlySpan<char> span = input.AsSpan();
int parsed2 = int.Parse(span[..4]);       // no allocation — span is a view
```

### Struct and `readonly struct` — Stack Allocation

```csharp
// A readonly struct lives on the stack or inline in the containing object
// No heap allocation, no GC involvement
public readonly record struct Point(double X, double Y);

// Array of value types is one heap allocation (the array itself)
// not N+1 (one for the array plus one per element)
Point[] points = new Point[1000];   // 1 allocation of 16KB (1000 × 16 bytes)
                                    // vs 1001 allocations for Point[] with a class type
```

---

## 26.6 GC Modes and Configuration

For latency-sensitive applications (real-time trading, game servers,
interactive applications), you can configure the GC to prefer shorter
pauses at the cost of higher memory usage:

```json
// In runtimeconfig.json
{
  "configProperties": {
    "System.GC.Server":         true,   // server GC: one heap per core
    "System.GC.Concurrent":     true,   // concurrent GC: less stop-the-world
    "System.GC.HeapHardLimit":  536870912   // 512MB heap limit (useful in containers)
  }
}
```

For containerised applications, set a memory limit and configure the GC
to respect it:

```dockerfile
ENV DOTNET_GCHeapHardLimitPercent=75   # use at most 75% of container memory for GC
ENV DOTNET_GCConserveMemory=5          # more aggressive collection (0-9 scale)
```

---

## 26.7 Diagnosing Memory Problems

```bash
# dotnet-counters: live GC metrics
dotnet tool install --global dotnet-counters
dotnet counters monitor --process-id <pid> --counters System.Runtime

# Watch for:
# gc-heap-size: total managed heap size
# gen-0-gc-count / gen-1-gc-count / gen-2-gc-count: collection frequency
# threadpool-queue-length: sign of thread pool starvation

# dotnet-dump: heap snapshot
dotnet tool install --global dotnet-dump
dotnet-dump collect --process-id <pid>
dotnet-dump analyze <dump.dmp>
> dumpheap -stat         # show top types by size
> gcroot <address>       # show what's keeping an object alive
```

In Rider, the Memory Profiler shows allocation hotspots. In Visual
Studio 2022, the Diagnostic Tools window shows real-time GC events.

---

## 26.8 Connecting Memory to the Rest of the Book

- **Ch 2 (Types)** — value types vs reference types is the stack vs
  heap allocation distinction. Records, structs, and the choice between
  them directly impacts GC load.
- **Ch 3 (IDisposable)** — `using` statements are the mechanism for
  deterministic cleanup of unmanaged resources. Never skip them for
  streams, connections, or OS handles.
- **Ch 7 (Span<T>)** — Span is the primary tool for zero-allocation
  data slicing and parsing. Covered in context of collections.
- **Ch 21 (Native AOT)** — AOT binaries have different GC characteristics:
  no JIT allocations during warmup, potentially different GC tuning.
- **Ch 38 (Multithreading)** — `ImmutableDictionary` and persistent
  data structures trade CPU for allocation-free thread-safe reads.
