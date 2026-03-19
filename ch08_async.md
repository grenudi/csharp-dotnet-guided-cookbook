# Chapter 8 — Async/Await & Concurrency

## 8.1 The Async/Await Mental Model

Async/await is **not threading** — it is cooperative multitasking. `await` yields the current thread to do other work while an I/O operation completes, then resumes on a (possibly different) thread.

```
Thread 1 calls GetDataAsync()
    │
    ├── await httpClient.GetAsync(...)
    │       │
    │       └── Thread 1 is RELEASED back to thread pool
    │              (can serve other requests here)
    │
    └── I/O completes (kernel notifies IOCP)
           │
           └── Thread 2 (or Thread 1 again) picks up the continuation
                  │
                  └── Code after await runs
```

---

## 8.2 Task, Task\<T\>, and ValueTask\<T\>

```csharp
// Task — represents a void async operation
public async Task DoWorkAsync(CancellationToken ct = default)
{
    await Task.Delay(1000, ct);
    Console.WriteLine("Done");
}

// Task<T> — represents an async operation that returns a value
public async Task<int> ComputeAsync()
{
    await Task.Delay(100);
    return 42;
}

// ValueTask<T> — for hot paths that often complete synchronously
// Use when: frequently called, often returns cached result
public async ValueTask<string> GetCachedAsync(string key)
{
    if (_cache.TryGetValue(key, out var val))
        return val;  // no allocation! returns immediately

    var result = await FetchFromDatabaseAsync(key);
    _cache[key] = result;
    return result;
}

// ValueTask — avoid awaiting more than once, avoid storing
// BAD:
var vt = GetCachedAsync("key");
var r1 = await vt;
var r2 = await vt; // undefined behavior!

// GOOD — await immediately or convert
var result = await GetCachedAsync("key");
// Or:
var vt2 = GetCachedAsync("key");
if (!vt2.IsCompleted) await vt2.AsTask(); // convert when needed
```

---

## 8.3 Writing Correct Async Code

### The Three Golden Rules

```csharp
// 1. Async all the way — don't mix sync and async
// BAD — deadlock risk in non-ASP.NET contexts with SynchronizationContext:
public string GetData() => GetDataAsync().Result; // .Wait() / .Result = deadlock!

// GOOD — make the caller async too
public async Task<string> GetDataAsync()
{
    return await FetchAsync();
}

// 2. ConfigureAwait(false) in library code
// Libraries don't need to resume on the original context
public async Task<byte[]> DownloadAsync(string url)
{
    using var client = new HttpClient();
    // ConfigureAwait(false): don't capture SynchronizationContext
    var response = await client.GetAsync(url).ConfigureAwait(false);
    return await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
}
// In ASP.NET Core there's no SynchronizationContext, so ConfigureAwait is less critical
// but still a good habit in library code.

// 3. Always pass CancellationToken
public async Task<User?> GetUserAsync(int id, CancellationToken ct = default)
{
    return await _db.Users.FindAsync([id], ct).ConfigureAwait(false);
}
```

### Async State Machine Optimization

```csharp
// If no actual await (or only in rare paths), avoid state machine overhead:
public Task<int> GetCountAsync()
{
    if (_count > 0) return Task.FromResult(_count); // no state machine!
    return GetCountFromDbAsync();
}

// ValueTask eliminates allocation for sync-fast path:
public ValueTask<int> GetCountValueAsync()
{
    if (_count > 0) return ValueTask.FromResult(_count);
    return new ValueTask<int>(GetCountFromDbAsync());
}

// Async method with no await — returns completed task
public async Task<int> GetZeroAsync()
{
    return 0; // compiler warns: no await, consider removing async
}
// Better:
public Task<int> GetZeroAsync2() => Task.FromResult(0);
```

---

## 8.4 CancellationToken

```csharp
// Create a token
var cts = new CancellationTokenSource();
var ct = cts.Token;

// Cancel after timeout
var cts2 = new CancellationTokenSource(TimeSpan.FromSeconds(30));
// Or:
cts.CancelAfter(TimeSpan.FromSeconds(30));

// Cancel manually
cts.Cancel(); // signals cancellation
cts.Cancel(throwOnFirstException: false); // all registered callbacks run

// Check for cancellation
ct.ThrowIfCancellationRequested(); // throws OperationCanceledException
bool isCancelled = ct.IsCancellationRequested;

// Register cleanup callback
ct.Register(() => Console.WriteLine("Cancelled!"));
using var reg = ct.Register(() => CloseSocket()); // dispose to unregister

// Linked token — cancel if any source cancels
using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct1, ct2);

// Pass through to all awaitable methods
public async Task ProcessAllAsync(IEnumerable<string> items, CancellationToken ct)
{
    foreach (var item in items)
    {
        ct.ThrowIfCancellationRequested();  // check at loop boundaries
        await ProcessItemAsync(item, ct);   // pass to awaitable
    }
}

// Catching cancellation
try
{
    await LongOperationAsync(ct);
}
catch (OperationCanceledException) when (ct.IsCancellationRequested)
{
    // graceful cancel — log, cleanup, but don't rethrow as error
    _logger.LogInformation("Operation cancelled");
}
```

---

## 8.5 Task Combinators

```csharp
// Task.WhenAll — wait for all, fail on first failure
var tasks = urls.Select(url => httpClient.GetStringAsync(url)).ToList();
string[] results = await Task.WhenAll(tasks);

// Collect all errors (not just first)
var results2 = await Task.WhenAll(tasks);
// If any task faults, WhenAll's exception is AggregateException

// Catch aggregate errors:
try
{
    await Task.WhenAll(tasks);
}
catch (Exception)
{
    var exceptions = tasks.Where(t => t.IsFaulted).Select(t => t.Exception!);
    // handle each
}

// Task.WhenAny — return when any completes (race)
var winner = await Task.WhenAny(tasks);
string winnerResult = await winner; // re-await to unwrap exception

// Task.WhenEach (NET 9+) — yield results as they complete
await foreach (var task in Task.WhenEach(tasks))
{
    var result = await task; // available in order of completion
    Console.WriteLine(result);
}

// Task.WaitAll / WaitAny — blocking versions (avoid in async code)
Task.WaitAll(task1, task2); // blocks thread!

// Parallel.ForEachAsync (NET 6+)
await Parallel.ForEachAsync(items, new ParallelOptions
{
    MaxDegreeOfParallelism = 4,
    CancellationToken = ct
}, async (item, ct) =>
{
    await ProcessAsync(item, ct);
});
```

---

## 8.6 Channels — Producer/Consumer

`System.Threading.Channels` is the modern, high-performance alternative to `BlockingCollection<T>`.

```csharp
using System.Threading.Channels;

// Unbounded channel
var channel = Channel.CreateUnbounded<string>();

// Bounded channel (backpressure)
var bounded = Channel.CreateBounded<string>(new BoundedChannelOptions(100)
{
    FullMode = BoundedChannelFullMode.Wait, // producer waits when full
    SingleReader = false,
    SingleWriter = true
});

// Producer
async Task ProduceAsync(ChannelWriter<string> writer, CancellationToken ct)
{
    try
    {
        for (int i = 0; i < 1000; i++)
        {
            await writer.WriteAsync($"item-{i}", ct);
        }
    }
    finally
    {
        writer.Complete(); // signal no more items
    }
}

// Consumer
async Task ConsumeAsync(ChannelReader<string> reader, CancellationToken ct)
{
    await foreach (var item in reader.ReadAllAsync(ct))
    {
        await ProcessAsync(item);
    }
}

// Wire up
var ch = Channel.CreateUnbounded<string>();
var producer = ProduceAsync(ch.Writer, cts.Token);
var consumer = ConsumeAsync(ch.Reader, cts.Token);
await Task.WhenAll(producer, consumer);

// Pipeline pattern
Channel<T> CreatePipeline<T>(ChannelReader<T> input, Func<T, Task<T>> transform, int workers = 4)
{
    var output = Channel.CreateUnbounded<T>();
    Task.Run(async () =>
    {
        await Parallel.ForEachAsync(input.ReadAllAsync(), new ParallelOptions
        {
            MaxDegreeOfParallelism = workers
        }, async (item, ct) =>
        {
            var result = await transform(item);
            await output.Writer.WriteAsync(result, ct);
        });
        output.Writer.Complete();
    });
    return output;
}
```

---

## 8.7 SemaphoreSlim — Async Rate Limiting

```csharp
// Limit concurrency to 5 parallel operations
var semaphore = new SemaphoreSlim(5, 5);

async Task<string> FetchWithLimitAsync(string url)
{
    await semaphore.WaitAsync();
    try
    {
        return await httpClient.GetStringAsync(url);
    }
    finally
    {
        semaphore.Release();
    }
}

// Throttle many requests
var tasks = urls.Select(url => FetchWithLimitAsync(url));
var results = await Task.WhenAll(tasks); // max 5 concurrent

// As a mutex (binary semaphore)
var mutex = new SemaphoreSlim(1, 1);
await mutex.WaitAsync();
try
{
    // critical section
}
finally
{
    mutex.Release();
}
```

---

## 8.8 async/await Patterns

### Retry with Exponential Backoff

```csharp
public static async Task<T> RetryAsync<T>(
    Func<CancellationToken, Task<T>> action,
    int maxAttempts = 3,
    TimeSpan? initialDelay = null,
    CancellationToken ct = default)
{
    initialDelay ??= TimeSpan.FromSeconds(1);
    Exception? lastEx = null;

    for (int attempt = 0; attempt < maxAttempts; attempt++)
    {
        try
        {
            return await action(ct);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            lastEx = ex;
            if (attempt < maxAttempts - 1)
            {
                var delay = initialDelay.Value * Math.Pow(2, attempt);
                await Task.Delay(delay, ct);
            }
        }
    }

    throw new RetryExhaustedException($"Failed after {maxAttempts} attempts", lastEx!);
}

// Usage
var data = await RetryAsync(
    ct => httpClient.GetStringAsync("https://example.com", ct),
    maxAttempts: 3,
    initialDelay: TimeSpan.FromSeconds(2),
    ct: cancellationToken);
```

### Timeout Wrapper

```csharp
public static async Task<T> WithTimeoutAsync<T>(
    Func<CancellationToken, Task<T>> action,
    TimeSpan timeout,
    CancellationToken ct = default)
{
    using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
    cts.CancelAfter(timeout);
    try
    {
        return await action(cts.Token);
    }
    catch (OperationCanceledException) when (!ct.IsCancellationRequested)
    {
        throw new TimeoutException($"Operation timed out after {timeout}");
    }
}
```

### Fire-and-Forget with Error Handling

```csharp
// Never use: _ = Task.Run(async () => await Something()); — errors are swallowed

// Better: proper fire-and-forget with logging
public static void FireAndForget(
    this Task task,
    ILogger? logger = null,
    [CallerMemberName] string caller = "")
{
    task.ContinueWith(t =>
    {
        if (t.IsFaulted)
            logger?.LogError(t.Exception, "Unhandled exception in fire-and-forget from {Caller}", caller);
    }, TaskContinuationOptions.OnlyOnFaulted);
}

// Usage
DoSomethingAsync().FireAndForget(_logger);
```

---

## 8.9 Parallel Programming

```csharp
// Parallel.For / Parallel.ForEach — CPU-bound work on multiple threads
var results = new ConcurrentBag<int>();

Parallel.For(0, 1000, i =>
{
    results.Add(ExpensiveComputation(i));
});

Parallel.ForEach(items, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount }, item =>
{
    ProcessItem(item);
});

// PLINQ — parallel LINQ
var primes = Enumerable.Range(2, 1_000_000)
    .AsParallel()                           // parallelize
    .WithDegreeOfParallelism(4)
    .WithCancellation(ct)
    .Where(IsPrime)
    .OrderBy(n => n)                        // re-sequential for ordering
    .ToList();

// AsOrdered — preserve input order (with perf cost)
var orderedResults = items.AsParallel().AsOrdered().Select(Transform).ToList();

// ForAll — side-effecting parallel action
items.AsParallel().ForAll(item => ProcessItem(item));
```

---

## 8.10 Async Streams (IAsyncEnumerable\<T\>)

```csharp
// Producer — async generator
public static async IAsyncEnumerable<WeatherReading> GetReadingsAsync(
    string station,
    [EnumeratorCancellation] CancellationToken ct = default)
{
    while (!ct.IsCancellationRequested)
    {
        var reading = await FetchCurrentReadingAsync(station, ct);
        yield return reading;
        await Task.Delay(TimeSpan.FromMinutes(5), ct);
    }
}

// Consumer
await foreach (var reading in GetReadingsAsync("station-A", cts.Token))
{
    Console.WriteLine($"{reading.Timestamp}: {reading.Temperature}°C");
    if (reading.Temperature > 40) cts.Cancel();
}

// Operators via LINQ (System.Linq.Async NuGet package)
using System.Linq;

var high = GetReadingsAsync("A")
    .Where(r => r.Temperature > 30)
    .Take(10);

await foreach (var r in high)
    Console.WriteLine(r);
```

---

## 8.11 Thread Safety Primitives

```csharp
// Interlocked — lock-free atomic operations
private int _count = 0;
int newCount = Interlocked.Increment(ref _count);
int dec      = Interlocked.Decrement(ref _count);
int old      = Interlocked.Exchange(ref _count, 0);
int compared = Interlocked.CompareExchange(ref _count, 100, 0); // set to 100 if was 0
Interlocked.Add(ref _count, 5);

// volatile — prevents CPU and compiler reordering
private volatile bool _running = true;
// Ensure reads/writes aren't cached in registers

// Monitor / lock
private readonly object _lock = new();

public void AddItem(string item)
{
    lock (_lock)
    {
        _items.Add(item);
    }
}

// ReaderWriterLockSlim — many readers, exclusive writer
private readonly ReaderWriterLockSlim _rwLock = new();

public string Read(string key)
{
    _rwLock.EnterReadLock();
    try { return _dict[key]; }
    finally { _rwLock.ExitReadLock(); }
}

public void Write(string key, string val)
{
    _rwLock.EnterWriteLock();
    try { _dict[key] = val; }
    finally { _rwLock.ExitWriteLock(); }
}
```

> **Rider tip:** Rider's *Async* call stack is visible in the debugger under *Debug → Async Stacks* — it shows the logical async call chain across thread switches, not just the current physical stack.

> **VS tip:** *Debug → Windows → Tasks* shows all active Task objects. *Debug → Windows → Parallel Stacks* visualizes all thread stacks and task continuations simultaneously. Very useful for diagnosing deadlocks.


> **See also:** [Chapter 20 §20.6 — Explicit Over Implicit](ch20_principles.md) — always pass `CancellationToken` and `ISystemClock` as parameters rather than using `DateTime.UtcNow` directly. [Chapter 19 §19.10](ch19_di_deep_dive.md) — the `BackgroundService` + `IServiceScopeFactory` pattern for long-running workers.
