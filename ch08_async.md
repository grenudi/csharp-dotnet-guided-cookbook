# Chapter 8 — Async/Await & Concurrency

> I/O is slow. A disk read takes microseconds; a network call takes
> milliseconds; a database query takes tens of milliseconds. A CPU
> instruction takes nanoseconds. If your thread waits for each I/O
> operation to complete before moving on, you waste the CPU for the
> entire duration of every wait. Async/await is .NET's answer to this
> problem — and it is one of the most consequential features in the
> language for real-world application performance.

*Building on:* Ch 2 (generics, nullable), Ch 4 (delegates, lambdas),
Ch 7 (IEnumerable, which async extends into IAsyncEnumerable)

---

## 8.1 The Mental Model — What `await` Actually Does

`async`/`await` is **not threading**. This is the most common misconception.
Adding `async` to a method does not create a new thread. Instead, it
implements *cooperative multitasking*: when the program reaches an
`await`, it says "I have nothing useful to do right now while this I/O
operation completes — let someone else use this thread". When the I/O
finishes, the continuation (the code after `await`) is scheduled to run.

The thread is *released* during the wait and is free to handle other
work — other HTTP requests, other operations, other completions. On a web
server, this is what allows a single server to handle thousands of
concurrent requests with a small thread pool.

```
Thread 1 calls GetUserAsync()
    │
    ├── await httpClient.GetAsync(...)   ← Thread 1 is RELEASED here
    │         │                            It goes back to the pool.
    │         │                            Other requests use it.
    │         │
    │         └── Network I/O completes (OS notifies IOCP)
    │                   │
    │                   └── Thread 2 (or Thread 1 again) picks up the continuation
    │                             │
    │                             └── Code after await runs here
    │
    └── Returns to caller with the result
```

The key insight: during `await`, *no thread is blocked*. The thread is
not sitting idle doing nothing — it is returned to the pool and serves
other work. This is fundamentally different from a synchronous call where
the thread is frozen for the duration.

---

## 8.2 `Task`, `Task<T>`, and `ValueTask<T>` — The Return Types

When a method is declared `async`, it must return one of these types.
Each represents an in-progress operation that will eventually complete.

### `Task` — An Async Void

`Task` represents an operation that produces no value but may succeed or
fail. It is the async equivalent of `void`:

```csharp
// Caller can await this to wait for completion and observe exceptions
public async Task SaveChangesAsync(CancellationToken ct)
{
    await _db.SaveChangesAsync(ct);
    _logger.LogInformation("Changes saved");
    // No return value, but exceptions will propagate to the awaiter
}
```

### `Task<T>` — An Async Value

`Task<T>` represents an operation that will eventually produce a value
of type `T`. This is the most common async return type:

```csharp
public async Task<User> GetUserAsync(int id, CancellationToken ct)
{
    var user = await _db.Users.FindAsync(id, ct);
    return user ?? throw new UserNotFoundException(id);
    // The Task<User> holds this User value when the Task completes
}

// Caller awaits to get the value
User user = await GetUserAsync(42, ct);
```

### `ValueTask<T>` — For Hot Paths That Are Often Synchronous

`Task<T>` always allocates a heap object. For methods that are very
frequently called and often return a cached result synchronously, this
allocation is measurable overhead. `ValueTask<T>` avoids the allocation
when the result is immediately available:

```csharp
private readonly Dictionary<string, User> _cache = new();

public async ValueTask<User?> GetCachedUserAsync(string id, CancellationToken ct)
{
    // If the result is cached, return without any heap allocation
    if (_cache.TryGetValue(id, out var cached))
        return cached;   // ValueTask wraps the value directly — no Task allocated

    // Only when we actually go async do we pay the Task cost
    var user = await _db.Users.FindAsync(id, ct);
    if (user is not null)
        _cache[id] = user;
    return user;
}
```

**Rule:** Use `ValueTask<T>` only in performance-sensitive code where
profiling shows Task allocation is a bottleneck. Misuse causes subtle
bugs: a `ValueTask` must be awaited exactly once, cannot be awaited after
it has completed, and should not be stored in a field.

---

## 8.3 Writing Correct Async Code

### The Four Rules

**Rule 1: async all the way down.**
If a method calls an async method, it should itself be async. Mixing
sync and async is where deadlocks live:

```csharp
// WRONG: .Result blocks the current thread, holding the SynchronizationContext
// Under ASP.NET Core this doesn't deadlock but in WinForms/WPF it will
public User GetUser(int id) =>
    GetUserAsync(id).Result;   // blocks current thread

// CORRECT: await all the way up
public async Task<User> GetUserAsync(int id) =>
    await _service.FetchUserAsync(id);
```

**Rule 2: always pass `CancellationToken`.**
Operations that can be cancelled must accept a `CancellationToken` and
pass it to every async call they make. Without it, a user cancellation
(navigating away, closing the app) leaves the work running until it
finishes naturally:

```csharp
// WRONG: user cancels, but the operation runs to completion
public async Task<Report> GenerateReportAsync()
{
    var data    = await FetchDataAsync();          // ignores cancellation
    var analysed = await AnalyseAsync(data);       // ignores cancellation
    return await FormatAsync(analysed);            // ignores cancellation
}

// CORRECT: cancellation propagates through the entire call chain
public async Task<Report> GenerateReportAsync(CancellationToken ct = default)
{
    var data     = await FetchDataAsync(ct);
    var analysed = await AnalyseAsync(data, ct);
    return await FormatAsync(analysed, ct);
}
```

**Rule 3: never use `async void` except for event handlers.**
`async void` methods cannot be awaited, and any exception thrown inside
them crashes the process immediately (it goes to the unhandled exception
handler with no chance to catch it). The only legitimate use is in event
handlers where the signature is fixed:

```csharp
// WRONG: exceptions vanish or crash the process
async void LoadDataBadly() => await FetchDataAsync();

// CORRECT: return Task so the caller can await and handle exceptions
async Task LoadDataAsync() => await FetchDataAsync();

// Exception for event handlers — the signature is fixed by the framework
button.Click += async (sender, e) =>
{
    // Inside async void event handlers, wrap in try-catch
    try { await LoadDataAsync(); }
    catch (Exception ex) { ShowError(ex.Message); }
};
```

**Rule 4: `ConfigureAwait(false)` in library code.**
When a library method resumes after `await`, by default it tries to
resume on the original `SynchronizationContext`. In ASP.NET Core, there
is no SynchronizationContext, so this does not matter. But in libraries
used from WinForms or WPF (which have a UI SynchronizationContext), the
library code trying to resume on the UI thread can cause deadlocks.
Library code should use `ConfigureAwait(false)`:

```csharp
// In library code
public async Task<string> FetchAsync(string url, CancellationToken ct)
{
    var response = await _http.GetAsync(url, ct).ConfigureAwait(false);
    return await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
}
// Not needed in ASP.NET Core applications — no SynchronizationContext
```

---

## 8.4 `CancellationToken` — Cooperative Cancellation

Cancellation in .NET is cooperative, not preemptive. You cannot force a
running method to stop — you can only signal that cancellation has been
requested and rely on the method to check for it and stop voluntarily.

A `CancellationTokenSource` creates a `CancellationToken` and controls
when it is cancelled. The token is passed to operations; they check it
periodically and throw `OperationCanceledException` when it is cancelled.

```csharp
// Creating a cancellation source
using var cts = new CancellationTokenSource();

// Cancel after a timeout
using var cts2 = new CancellationTokenSource(TimeSpan.FromSeconds(30));

// Link two tokens: cancel if EITHER fires
using var cts3 = CancellationTokenSource.CreateLinkedTokenSource(
    userCancellation, timeoutCancellation);

// In a method: check the token, pass it down
public async Task ProcessItemsAsync(
    IEnumerable<Item> items, CancellationToken ct)
{
    foreach (var item in items)
    {
        ct.ThrowIfCancellationRequested();   // check at each iteration
        await ProcessOneAsync(item, ct);      // pass to every async call
    }
}

// Trigger cancellation
cts.Cancel();                  // immediate
await cts.CancelAsync();       // async (C# 10+)
```

```csharp
// Consuming cancellation results
try
{
    await ProcessItemsAsync(items, cts.Token);
}
catch (OperationCanceledException)
{
    // Normal cancellation — clean up and move on
    _logger.LogInformation("Processing cancelled");
}
```

The `HttpClient` built into .NET checks the token on every read. The EF
Core async methods accept and check it. Any API that performs I/O should
accept and forward a `CancellationToken`.

---

## 8.5 Task Combinators — Running Multiple Operations

Sometimes you need to run multiple async operations. How you combine them
depends on whether you want them in parallel or sequentially.

```csharp
// Sequential: one after the other
var user    = await GetUserAsync(id, ct);
var orders  = await GetOrdersAsync(id, ct);
var profile = await GetProfileAsync(id, ct);
// Total time: sum of all three

// Parallel with WhenAll: start all three, wait for all to complete
// Much faster when the operations are independent
var (user, orders, profile) = await (
    GetUserAsync(id, ct),
    GetOrdersAsync(id, ct),
    GetProfileAsync(id, ct)
).WhenAll();                  // runs all three concurrently
// Total time: the slowest of the three

// Or the explicit form
var userTask    = GetUserAsync(id, ct);
var ordersTask  = GetOrdersAsync(id, ct);
var profileTask = GetProfileAsync(id, ct);
await Task.WhenAll(userTask, ordersTask, profileTask);
var user2    = await userTask;   // await again to get results (or check .Result after WhenAll)
var orders2  = await ordersTask;
```

```csharp
// WhenAny: complete as soon as the FIRST task finishes
// Useful for: timeout races, fan-out where you only need one response
var timeoutTask   = Task.Delay(TimeSpan.FromSeconds(5), ct);
var operationTask = DoSlowOperationAsync(ct);
var winner = await Task.WhenAny(operationTask, timeoutTask);
if (winner == timeoutTask)
    throw new TimeoutException("Operation took too long");
var result = await operationTask;   // it completed — safe to await
```

---

## 8.6 Channels — Producer/Consumer Pipelines

`System.Threading.Channels` provides a high-performance, thread-safe
queue for producer/consumer scenarios. It is the modern replacement for
`BlockingCollection<T>` and `ConcurrentQueue<T>` for async code.

A channel has a writer end and a reader end. One or more producers write
to the writer; one or more consumers read from the reader. The channel
buffers items between them.

```csharp
// Bounded channel: blocks the producer when the buffer is full (backpressure)
// This prevents fast producers from overwhelming slow consumers
var channel = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(100)
{
    FullMode     = BoundedChannelFullMode.Wait,  // producer waits when full
    SingleWriter = true,    // optimisation hint: only one writer
    SingleReader = false,   // multiple readers (workers) are fine
});

// Producer: writes items to the channel
async Task Produce(ChannelWriter<WorkItem> writer, CancellationToken ct)
{
    try
    {
        await foreach (var item in GetItemsAsync(ct))
            await writer.WriteAsync(item, ct);  // blocks if buffer full
    }
    finally
    {
        writer.Complete();  // signals "no more items" — readers see end of stream
    }
}

// Consumer: reads items from the channel
async Task Consume(ChannelReader<WorkItem> reader, CancellationToken ct)
{
    await foreach (var item in reader.ReadAllAsync(ct))
        await ProcessAsync(item, ct);
    // Loop ends automatically when writer calls Complete()
}

// Run producer and multiple consumers concurrently
await Task.WhenAll(
    Produce(channel.Writer, ct),
    Consume(channel.Reader, ct),
    Consume(channel.Reader, ct));   // two consumers share the same reader
```

The bounded channel with `FullMode.Wait` creates natural *backpressure*:
if consumers are slow, producers pause automatically. No items are lost
and memory stays bounded even with arbitrarily large input.

---

## 8.7 `SemaphoreSlim` — Async Rate Limiting

`SemaphoreSlim` is the async-safe way to limit how many operations run
concurrently. It is an async mutual exclusion lock generalised to allow
N simultaneous holders (not just 1):

```csharp
// Allow at most 8 concurrent HTTP requests
// (Prevents overwhelming the downstream API with rate limits)
private readonly SemaphoreSlim _throttle = new SemaphoreSlim(8, 8);

public async Task<string> FetchWithRateLimitAsync(string url, CancellationToken ct)
{
    await _throttle.WaitAsync(ct);   // blocks if 8 requests are already in-flight
    try
    {
        return await _http.GetStringAsync(url, ct);
    }
    finally
    {
        _throttle.Release();   // always release, even if an exception occurs
    }
}

// Throttled parallel processing: process all items but max 8 at once
await Parallel.ForEachAsync(urls, new ParallelOptions
{
    MaxDegreeOfParallelism = 8,
    CancellationToken = ct
}, async (url, innerCt) => await FetchWithRateLimitAsync(url, innerCt));
```

---

## 8.8 Async Streams — `IAsyncEnumerable<T>`

A regular `IEnumerable<T>` produces items synchronously. When the source
is async (a database, a file, a network stream), you need
`IAsyncEnumerable<T>` — a sequence that produces items asynchronously,
one at a time, with `await foreach`.

This is the async equivalent of `yield return` (Chapter 3 §3.6):

```csharp
// Producer: yield return inside an async method
public async IAsyncEnumerable<Order> StreamOrdersAsync(
    [EnumeratorCancellation] CancellationToken ct = default)
{
    await using var conn = await _db.OpenConnectionAsync(ct);

    await foreach (var order in _db.Orders.AsAsyncEnumerable().WithCancellation(ct))
        yield return order;
}

// Consumer: await foreach
await foreach (var order in StreamOrdersAsync(ct))
{
    await ProcessAsync(order, ct);
    // Each order is processed immediately — no need to load all orders first
}
```

The advantage over `ToListAsync()`: with a stream, you process each item
as soon as it arrives. You never hold the full result set in memory. For
a table with a million rows, this is the difference between 1MB and 1GB
of memory.

---

## 8.9 Thread Safety Primitives

Async code runs on thread pool threads. Multiple async operations can
run concurrently, and if they share state, you have race conditions. See
Chapter 38 for the full treatment; here are the essential primitives:

```csharp
// lock: protect a critical section — only one thread at a time
private readonly object _lock = new();
private int _counter = 0;

void Increment()
{
    lock (_lock)
    {
        _counter++;   // read-modify-write is now atomic
    }
}

// NEVER await inside a lock:
lock (_lock)
{
    await DoSomethingAsync();   // COMPILE ERROR — by design
    // lock is held by a thread; await may resume on a different thread
    // SemaphoreSlim(1,1) is the async-safe alternative to lock
}

// Interlocked: atomic operations without lock overhead
Interlocked.Increment(ref _counter);
Interlocked.Add(ref _total, amount);
int snapshot = Interlocked.CompareExchange(ref _state, newValue, expectedOld);
```

---

## 8.10 Parallel Programming — CPU-Bound Work

`async`/`await` is for I/O-bound work (waiting for external operations).
CPU-bound work (heavy computation that keeps the CPU busy) is parallelised
differently — with `Task.Run`, `Parallel`, or `PLINQ`:

```csharp
// Task.Run: offload CPU work to a thread pool thread
// The calling thread is freed to do other work
double result = await Task.Run(() => ComputeHeavyMath(largeDataSet), ct);

// Parallel.ForEachAsync: process items concurrently with async support
await Parallel.ForEachAsync(items,
    new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount, CancellationToken = ct },
    async (item, innerCt) =>
    {
        await ProcessItemAsync(item, innerCt);
    });

// PLINQ: parallel LINQ for CPU-bound data transformation
var results = items.AsParallel()
                   .WithDegreeOfParallelism(4)
                   .Where(x => ExpensiveFilter(x))
                   .Select(x => ExpensiveTransform(x))
                   .ToList();
```

Do not use `Task.Run` for I/O-bound work — it wastes a thread pool
thread on waiting. Use the native async methods: `await httpClient.GetAsync()`,
not `await Task.Run(() => httpClient.GetAsync().Result)`.

---

## 8.11 Connecting Async to the Rest of the Book

- **Ch 7 (Collections, LINQ)** — `IAsyncEnumerable<T>` extends LINQ
  into the async world. `ToListAsync()`, `FirstOrDefaultAsync()` are
  async versions of LINQ terminal operators.
- **Ch 12 (IO)** — All file, network, and stream operations have async
  variants. Async I/O is what prevents I/O-bound threads from blocking.
- **Ch 13 (Networking)** — `HttpClient`, gRPC, and WebSocket APIs are
  entirely async. Every call returns a `Task` or `ValueTask`.
- **Ch 14 (ASP.NET Core)** — Every request handler is async. The
  middleware pipeline is async. The framework handles the
  SynchronizationContext details for you.
- **Ch 15 (EF Core)** — All database operations have async variants:
  `ToListAsync`, `SaveChangesAsync`, `FindAsync`. Use them always.
- **Ch 38 (Multithreading)** — Channels, locks, and race conditions
  in full. This chapter covers the problems; Chapter 38 shows them in
  real projects.
