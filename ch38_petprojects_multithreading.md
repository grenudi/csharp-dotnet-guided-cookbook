# Chapter 38 — Pet Projects VI: Multithreading, Race Conditions & Concurrency

> Every program you write beyond "hello world" eventually shares state
> across threads — a cache, a counter, a queue. This chapter shows you
> exactly what goes wrong and how to fix it, grounded in three
> real-world projects: a parallel file processor, a producer/consumer
> pipeline, and a thread-safe in-memory cache built from scratch.

**Concepts exercised:** Ch 7 (ConcurrentDictionary, ImmutableList), Ch 8
(async/await, Task.WhenAll, Channels, Parallel.ForEachAsync, SemaphoreSlim,
CancellationToken), Ch 26 (Interlocked, volatile, memory model), Ch 28 (no
race conditions in auth state)

---

## 38.1 The Three Kinds of Concurrency in .NET

Before touching code, name what you're dealing with:

| Kind | Mechanism | When to use |
|---|---|---|
| **I/O concurrency** | `async`/`await` | Waiting for network, disk, DB |
| **CPU parallelism** | `Parallel`, `Task.Run`, PLINQ | Heavy computation, multiple cores |
| **Shared state** | locks, `Interlocked`, concurrent collections | Multiple threads touch same data |

Most bugs come from mixing these up — using `Task.Run` to escape an async
context when you needed I/O concurrency, or forgetting that two async
continuations can interleave and corrupt shared state.

---

## 38.2 The Race Condition Zoo

Run each of these. Note the wrong output. Then apply the fix.

### Race 1 — Lost Update

```csharp
// BROKEN: two threads both read 0, both write 1, final result = 1 not 2
int counter = 0;

var t1 = Task.Run(() => { for (int i = 0; i < 1_000_000; i++) counter++; });
var t2 = Task.Run(() => { for (int i = 0; i < 1_000_000; i++) counter++; });

await Task.WhenAll(t1, t2);
Console.WriteLine(counter); // prints something less than 2,000,000
```

`counter++` compiles to three instructions: read, increment, write.
Thread 1 reads 5, Thread 2 reads 5, both write 6. One increment is lost.

```csharp
// FIX 1: Interlocked — atomic operations, no lock overhead
int counter = 0;
var t1 = Task.Run(() => { for (int i = 0; i < 1_000_000; i++) Interlocked.Increment(ref counter); });
var t2 = Task.Run(() => { for (int i = 0; i < 1_000_000; i++) Interlocked.Increment(ref counter); });
await Task.WhenAll(t1, t2);
Console.WriteLine(counter); // always 2,000,000
```

```csharp
// FIX 2: lock — for multi-step operations that must be atomic
object _lock = new();
int counter = 0;
// ...
lock (_lock) { counter++; }   // single-statement here so Interlocked is better,
                               // but lock is correct when multiple lines must be atomic
```

### Race 2 — Check-Then-Act

```csharp
// BROKEN: cache miss + expensive compute, called concurrently
var cache = new Dictionary<string, string>();

string GetOrCompute(string key)
{
    if (cache.ContainsKey(key))        // check
        return cache[key];             // read  (race: key may have been inserted by another thread)
    var value = ExpensiveCompute(key); // might run twice for same key
    cache[key] = value;                // write (Dictionary is not thread-safe)
    return value;
}
```

```csharp
// FIX: ConcurrentDictionary.GetOrAdd — atomic check + insert
var cache = new ConcurrentDictionary<string, string>();

string GetOrCompute(string key) =>
    cache.GetOrAdd(key, ExpensiveCompute);
// If two threads call GetOrAdd concurrently for the same key,
// ExpensiveCompute may be called twice but only one result is stored.
// Use GetOrAdd(key, _ => lazy.Value) with Lazy<T> if compute must run once.
```

```csharp
// FIX for "compute exactly once":
var cache = new ConcurrentDictionary<string, Lazy<string>>();

string GetOrCompute(string key) =>
    cache.GetOrAdd(key, k => new Lazy<string>(() => ExpensiveCompute(k))).Value;
```

### Race 3 — Async + Shared State (the tricky one)

```csharp
// BROKEN: looks safe because it's async, but continuations interleave
var counts = new Dictionary<string, int>();

async Task IncrementAsync(string key)
{
    var current = counts.TryGetValue(key, out var v) ? v : 0; // read
    await Task.Delay(1);   // <── another task runs HERE and also reads 0
    counts[key] = current + 1;  // write — both write 1, one is lost
}

await Task.WhenAll(
    IncrementAsync("hits"),
    IncrementAsync("hits"));

Console.WriteLine(counts["hits"]); // 1, not 2
```

`await` is a suspension point. When you resume, another task may have
mutated your shared state. `async` does NOT make code thread-safe.

```csharp
// FIX: ConcurrentDictionary + Interlocked
var counts = new ConcurrentDictionary<string, int>();

async Task IncrementAsync(string key)
{
    await Task.Delay(1);
    counts.AddOrUpdate(key, 1, (_, v) => v + 1); // atomic update delegate
}
```

---

## 38.3 Project: `imgresizer` — Parallel Image Resizer

**What it does:** resize all images in a directory to multiple target
sizes. Uses `Parallel.ForEachAsync` with a configurable degree of
parallelism. Demonstrates: bounded parallelism, progress reporting,
cancellation, and correct error aggregation.

```bash
dotnet new console -n imgresizer
cd imgresizer
dotnet add package SixLabors.ImageSharp
dotnet add package Spectre.Console
```

```csharp
// Program.cs
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;
using Spectre.Console;

var inputDir  = args.ElementAtOrDefault(0) ?? ".";
var outputDir = args.ElementAtOrDefault(1) ?? "./resized";
var sizes     = new[] { 128, 512, 1024 };

Directory.CreateDirectory(outputDir);

var files = Directory.EnumerateFiles(inputDir, "*.*")
    .Where(f => f.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
             || f.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
    .ToList();

if (files.Count == 0)
{
    AnsiConsole.MarkupLine("[yellow]No images found.[/]");
    return;
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

// ── Counters — use Interlocked, not ++ ────────────────────────────
int processed = 0;
int failed    = 0;
var errors    = new System.Collections.Concurrent.ConcurrentBag<string>();

await AnsiConsole.Progress()
    .Columns(
        new TaskDescriptionColumn(),
        new ProgressBarColumn(),
        new PercentageColumn(),
        new SpinnerColumn())
    .StartAsync(async ctx =>
    {
        var progressTask = ctx.AddTask("[green]Resizing images[/]", maxValue: files.Count);

        // ParallelOptions.MaxDegreeOfParallelism limits CPU threads
        // Without this, all 500 files start at once → memory explosion
        var options = new ParallelOptions
        {
            MaxDegreeOfParallelism = Environment.ProcessorCount,
            CancellationToken      = cts.Token,
        };

        await Parallel.ForEachAsync(files, options, async (file, ct) =>
        {
            try
            {
                await ResizeImageAsync(file, outputDir, sizes, ct);
                Interlocked.Increment(ref processed);
            }
            catch (OperationCanceledException)
            {
                // swallow — cancellation is expected
            }
            catch (Exception ex)
            {
                Interlocked.Increment(ref failed);
                errors.Add($"{Path.GetFileName(file)}: {ex.Message}");
            }
            finally
            {
                progressTask.Increment(1);
            }
        });
    });

AnsiConsole.MarkupLine($"[green]Done.[/] {processed} processed, {failed} failed.");
if (!errors.IsEmpty)
{
    AnsiConsole.MarkupLine("[red]Errors:[/]");
    foreach (var e in errors)
        AnsiConsole.MarkupLine($"  [red]•[/] {Markup.Escape(e)}");
}

// ── Per-file work ─────────────────────────────────────────────────
static async Task ResizeImageAsync(
    string inputPath, string outputDir, int[] sizes, CancellationToken ct)
{
    using var image = await Image.LoadAsync(inputPath, ct);
    var name = Path.GetFileNameWithoutExtension(inputPath);
    var ext  = Path.GetExtension(inputPath);

    foreach (var size in sizes)
    {
        ct.ThrowIfCancellationRequested();

        using var resized = image.Clone(x => x.Resize(new ResizeOptions
        {
            Size = new(size, size),
            Mode = ResizeMode.Max,
        }));

        var outPath = Path.Combine(outputDir, $"{name}_{size}px{ext}");
        await resized.SaveAsync(outPath, ct);
    }
}
```

**What to observe:**

1. Remove `MaxDegreeOfParallelism = Environment.ProcessorCount` and run
   with 200+ images — memory spikes as all images load simultaneously.
2. Add it back — memory stays flat, CPU is fully used.
3. Press Ctrl+C mid-run — cancellation propagates cleanly through every
   in-flight task via `CancellationToken`.

---

## 38.4 Project: `pipeline` — Producer/Consumer with Channels

**What it does:** reads lines from a file (producer), processes each
line through two stages (normalise, then enrich via HTTP), writes results
to another file (consumer). Three goroutine-style stages connected by
`Channel<T>`, bounded so memory stays constant even for 10-million-line files.

```bash
dotnet new console -n pipeline
cd pipeline
```

```csharp
// Program.cs
using System.Threading.Channels;

var source  = args.ElementAtOrDefault(0) ?? "input.txt";
var dest    = args.ElementAtOrDefault(1) ?? "output.txt";

if (!File.Exists(source))
{
    Console.Error.WriteLine($"File not found: {source}");
    return 1;
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

// ── Create bounded channels ────────────────────────────────────────
// BoundedChannelFullMode.Wait: producer blocks when channel is full
// This creates natural backpressure — Stage 2 controls Stage 1's speed
var rawChannel = Channel.CreateBounded<string>(new BoundedChannelOptions(256)
{
    FullMode       = BoundedChannelFullMode.Wait,
    SingleWriter   = true,
    SingleReader   = false,
});

var enrichedChannel = Channel.CreateBounded<string>(new BoundedChannelOptions(256)
{
    FullMode       = BoundedChannelFullMode.Wait,
    SingleWriter   = false,
    SingleReader   = true,
});

// ── Stage 1: Reader ───────────────────────────────────────────────
async Task ReadStage(ChannelWriter<string> writer)
{
    try
    {
        await foreach (var line in File.ReadLinesAsync(source, cts.Token))
            await writer.WriteAsync(line, cts.Token);
    }
    finally
    {
        writer.Complete(); // signals "no more items" to downstream
    }
}

// ── Stage 2: Normalise (fan-out to 4 concurrent workers) ─────────
async Task NormaliseStage(
    ChannelReader<string> reader,
    ChannelWriter<string> writer,
    int workerCount = 4)
{
    async Task Worker()
    {
        await foreach (var line in reader.ReadAllAsync(cts.Token))
        {
            // Normalise: trim, lowercase, remove consecutive spaces
            var normalised = string.Join(' ',
                line.Trim().ToLowerInvariant().Split(' ',
                    StringSplitOptions.RemoveEmptyEntries));

            if (!string.IsNullOrEmpty(normalised))
                await writer.WriteAsync(normalised, cts.Token);
        }
    }

    // Run N workers, all reading from the same channel
    await Task.WhenAll(Enumerable.Range(0, workerCount).Select(_ => Worker()));
    writer.Complete();
}

// ── Stage 3: Writer ───────────────────────────────────────────────
async Task WriteStage(ChannelReader<string> reader)
{
    await using var file   = File.CreateText(dest);
    await using var writer = new StreamWriter(dest);

    await foreach (var line in reader.ReadAllAsync(cts.Token))
        await writer.WriteLineAsync(line);
}

// ── Run all three stages concurrently ────────────────────────────
try
{
    await Task.WhenAll(
        ReadStage(rawChannel.Writer),
        NormaliseStage(rawChannel.Reader, enrichedChannel.Writer, workerCount: 4),
        WriteStage(enrichedChannel.Reader));

    Console.WriteLine("Done.");
}
catch (OperationCanceledException)
{
    Console.WriteLine("Cancelled.");
}

return 0;
```

**Key design points:**

- **Bounded channels** — the channel holds at most 256 items. Stage 1
  (reader) blocks on `WriteAsync` when Stage 2 is slow. This is
  backpressure: fast producers cannot overwhelm slow consumers.

- **`writer.Complete()`** in `finally` — this is the termination signal.
  Without it, `ReadAllAsync` in the next stage blocks forever.

- **Fan-out** — four workers all call `reader.ReadAllAsync` on the same
  channel. The runtime routes each item to exactly one worker. You get
  4× throughput with no extra synchronisation.

- **`SingleWriter = true`** hints to the runtime that there will only be
  one producer, enabling a faster lock-free implementation.

---

## 38.5 Project: `threadcache` — A Thread-Safe In-Memory Cache

**What it does:** implements a read-through, write-through cache with
TTL and a background eviction worker. Builds the same thing from three
different synchronisation primitives so you can compare them.

```csharp
// Approach A: ReaderWriterLockSlim — fast reads, exclusive writes
public sealed class RwlCache<TKey, TValue> : IDisposable
    where TKey : notnull
{
    private readonly ReaderWriterLockSlim _lock = new();
    private readonly Dictionary<TKey, (TValue Value, DateTime ExpiresAt)> _store = new();
    private readonly TimeSpan _ttl;

    public RwlCache(TimeSpan ttl) => _ttl = ttl;

    public bool TryGet(TKey key, out TValue? value)
    {
        _lock.EnterReadLock();   // multiple readers allowed simultaneously
        try
        {
            if (_store.TryGetValue(key, out var entry) && entry.ExpiresAt > DateTime.UtcNow)
            {
                value = entry.Value;
                return true;
            }
            value = default;
            return false;
        }
        finally
        {
            _lock.ExitReadLock();
        }
    }

    public void Set(TKey key, TValue value)
    {
        _lock.EnterWriteLock();  // exclusive — no readers or writers during this
        try
        {
            _store[key] = (value, DateTime.UtcNow + _ttl);
        }
        finally
        {
            _lock.ExitWriteLock();
        }
    }

    public void Evict()
    {
        _lock.EnterWriteLock();
        try
        {
            var now     = DateTime.UtcNow;
            var expired = _store.Keys.Where(k => _store[k].ExpiresAt <= now).ToList();
            foreach (var k in expired)
                _store.Remove(k);
        }
        finally
        {
            _lock.ExitWriteLock();
        }
    }

    public void Dispose() => _lock.Dispose();
}
```

```csharp
// Approach B: ConcurrentDictionary — no explicit lock, atomic operations
public sealed class CdCache<TKey, TValue>
    where TKey : notnull
{
    private readonly ConcurrentDictionary<TKey, (TValue Value, DateTime ExpiresAt)> _store = new();
    private readonly TimeSpan _ttl;

    public CdCache(TimeSpan ttl) => _ttl = ttl;

    public bool TryGet(TKey key, out TValue? value)
    {
        if (_store.TryGetValue(key, out var entry) && entry.ExpiresAt > DateTime.UtcNow)
        {
            value = entry.Value;
            return true;
        }
        value = default;
        return false;
    }

    public void Set(TKey key, TValue value) =>
        _store[key] = (value, DateTime.UtcNow + _ttl);

    public void Evict()
    {
        var now = DateTime.UtcNow;
        foreach (var (key, entry) in _store)
            if (entry.ExpiresAt <= now)
                _store.TryRemove(key, out _);
    }
}
```

```csharp
// Approach C: ImmutableDictionary + Interlocked.CompareExchange
// Useful when you need snapshot isolation: readers always see a
// consistent point-in-time view even during concurrent writes.
public sealed class ImmutableCache<TKey, TValue>
    where TKey : notnull
{
    private volatile ImmutableDictionary<TKey, TValue> _snapshot =
        ImmutableDictionary<TKey, TValue>.Empty;

    public bool TryGet(TKey key, out TValue? value) =>
        _snapshot.TryGetValue(key, out value);

    public void Set(TKey key, TValue value)
    {
        // Spin until our compare-exchange wins
        ImmutableDictionary<TKey, TValue> original, updated;
        do
        {
            original = _snapshot;
            updated  = original.SetItem(key, value);
        }
        while (Interlocked.CompareExchange(ref _snapshot!, updated, original) != original);
    }
}
```

### Background Eviction Worker

```csharp
public class EvictionWorker(RwlCache<string, string> cache) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));
        while (await timer.WaitForNextTickAsync(ct))
            cache.Evict();
    }
}
```

---

## 38.6 Synchronisation Primitive Cheat Sheet

| Primitive | Use when | Notes |
|---|---|---|
| `lock` | Simple multi-step critical section | Fastest for short-lived locks |
| `Interlocked` | Single numeric operation | Truly atomic, no overhead |
| `ReaderWriterLockSlim` | Many reads, rare writes | Allows concurrent readers |
| `SemaphoreSlim` | Limit concurrent async operations | The async-friendly rate limiter |
| `Mutex` | Cross-process locking | Heavy; usually `lock` is sufficient |
| `ConcurrentDictionary` | Shared dictionary | Built-in fine-grained locking |
| `ConcurrentBag` / `Queue` | Unordered/ordered shared bag | Lock-free on hot path |
| `Channel<T>` | Producer/consumer | The modern replacement for `BlockingCollection<T>` |
| `Volatile.Read/Write` | Single field visibility | Prevents reordering, not atomicity |
| `ImmutableDictionary` | Snapshot consistency | Allocates; use when reads dominate |

### When to Reach for Each

```
Need to count something from multiple threads?
  → Interlocked.Increment / Decrement / Add

Need to protect a Dict or List from concurrent access?
  → ConcurrentDictionary / ConcurrentBag  or  lock {}

Need async rate limiting ("max 8 concurrent HTTP calls")?
  → SemaphoreSlim(8, 8)

Need a queue between async stages?
  → Channel<T> (bounded for backpressure, unbounded for fire-and-forget)

Need parallel CPU work with progress and cancellation?
  → Parallel.ForEachAsync with ParallelOptions

Need to run multiple async tasks and collect all results?
  → Task.WhenAll(tasks)
     BUT: await each result to surface exceptions properly:
     var results = await Task.WhenAll(tasks);
     // Not: var r = Task.WhenAll(tasks).Result — deadlocks under SynchronizationContext
```

---

## 38.7 The Five Rules You Must Not Break

1. **Never `await` inside a `lock`.**
   `lock` acquires on a thread. `await` may resume on a different thread.
   The lock is released on the wrong thread → deadlock or `SynchronizationLockException`.
   Use `SemaphoreSlim` for async-safe mutual exclusion.

2. **Never call `.Result` or `.Wait()` on a Task in async code.**
   Deadlocks under `SynchronizationContext` (ASP.NET, Blazor, WinForms).
   Always `await`.

3. **Pass `CancellationToken` everywhere.**
   Every method that does I/O or long computation must accept and respect a `CancellationToken`.
   Not doing so means Ctrl+C leaves threads running until the process is killed.

4. **Check `MaxDegreeOfParallelism` on `Parallel.ForEachAsync`.**
   The default is `Environment.ProcessorCount`. On a DB-heavy workload
   you want fewer than that. On pure CPU work you want exactly that.

5. **`ConcurrentDictionary` is not a replacement for a database.**
   It lives in RAM. It has no persistence, no transactions, no durability.
   Use it for caches and ephemeral coordination, never for source-of-truth state.
