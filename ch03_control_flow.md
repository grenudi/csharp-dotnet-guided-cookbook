# Chapter 3 — Control Flow & Pattern Matching

## 3.1 Basic Control Flow

### if / else

```csharp
// Classic
if (x > 0)
{
    Console.WriteLine("positive");
}
else if (x < 0)
{
    Console.WriteLine("negative");
}
else
{
    Console.WriteLine("zero");
}

// Single-line (omit braces only for trivial cases)
if (flag) return;

// Ternary
string label = x > 0 ? "positive" : x < 0 ? "negative" : "zero";

// Null coalescing
string result = maybeNull ?? "default";

// Null conditional
int? length = maybeString?.Length;
string? upper = maybeString?.ToUpperInvariant();

// Null conditional + coalescing
string safe = maybeString?.Trim() ?? "";

// Null coalescing assignment (C# 8+)
cache ??= ComputeExpensive();
```

### for / foreach / while / do-while

```csharp
// for — classic index-based loop
for (int i = 0; i < 10; i++)
    Console.Write(i);

// Reverse
for (int i = 9; i >= 0; i--)
    Console.Write(i);

// foreach — most idiomatic for collections
foreach (var item in collection)
    Process(item);

// foreach with index (use LINQ or deconstruction)
foreach (var (item, index) in collection.Select((x, i) => (x, i)))
    Console.WriteLine($"[{index}] {item}");

// while
while (reader.Read())
    Process(reader.Current);

// do-while — guaranteed at least one execution
do
{
    Console.Write("Enter command: ");
    command = Console.ReadLine();
} while (command != "quit");
```

### Range & Index (C# 8+)

```csharp
int[] arr = [1, 2, 3, 4, 5];  // collection expression (C# 12)

// Index from end with ^
int last  = arr[^1];   // 5
int second = arr[^2];  // 4

// Range [start..end) — end exclusive
int[] mid  = arr[1..4];   // [2, 3, 4]
int[] tail = arr[2..];    // [3, 4, 5]
int[] head = arr[..3];    // [1, 2, 3]
int[] all  = arr[..];     // [1, 2, 3, 4, 5] (copy)

// Spans — zero allocation slice
Span<int> spanMid = arr.AsSpan(1, 3); // [2, 3, 4] — no allocation

// for loop with Range
for (int i = 1; i < arr.Length - 1; i++) { /* ... */ }
```

---

## 3.2 Switch Statement vs. Switch Expression

### Classic switch Statement

```csharp
switch (status)
{
    case HttpStatusCode.OK:
        HandleSuccess();
        break;
    case HttpStatusCode.NotFound:
    case HttpStatusCode.Gone:      // fall-through to share handler
        HandleMissing();
        break;
    case HttpStatusCode.Unauthorized:
    case HttpStatusCode.Forbidden:
        HandleAuth();
        break;
    default:
        HandleUnknown();
        break;
}
```

### Switch Expression (C# 8+)

Returns a value. No `break`. Exhaustiveness checked by compiler.

```csharp
string description = status switch
{
    HttpStatusCode.OK          => "Success",
    HttpStatusCode.NotFound    => "Not Found",
    HttpStatusCode.Unauthorized => "Unauthorized",
    _ => "Other"
};

// With complex expressions
decimal discount = customerType switch
{
    CustomerType.Gold   when totalPurchases > 10_000 => 0.20m,
    CustomerType.Gold                                 => 0.15m,
    CustomerType.Silver when totalPurchases > 5_000  => 0.10m,
    CustomerType.Silver                               => 0.05m,
    CustomerType.Bronze                               => 0.0m,
    _                                                 => throw new ArgumentOutOfRangeException()
};
```

---

## 3.3 Pattern Matching — Complete Reference

C# pattern matching lets you test a value's shape, type, and content in one expression.

### Type Pattern

```csharp
object obj = GetObject();

// is-type
if (obj is string s)
{
    Console.WriteLine(s.ToUpper()); // s is string here
}

// switch expression with type pattern
string Describe(object o) => o switch
{
    int n           => $"integer: {n}",
    string s        => $"string: {s}",
    double d        => $"double: {d:F2}",
    bool b          => $"bool: {b}",
    null            => "null",
    _               => $"unknown: {o.GetType().Name}"
};
```

### Constant Pattern

```csharp
int result = value switch
{
    0 => 0,
    1 => 1,
    2 => 4,
    _ => value * value
};

// null check
if (obj is null) return;
if (obj is not null) Use(obj);
```

### Relational Pattern (C# 9+)

```csharp
string Grade(int score) => score switch
{
    >= 90 => "A",
    >= 80 => "B",
    >= 70 => "C",
    >= 60 => "D",
    _     => "F"
};

// With ranges
bool IsWorkingAge(int age) => age is >= 16 and <= 65;
bool IsTeenager(int age)   => age is >= 13 and <= 19;
```

### Logical Pattern (`and`, `or`, `not`)

```csharp
// not
if (x is not null) { }
if (x is not (> 0 and < 10)) { }

// and — both must match
bool InRange(int x) => x is >= 1 and <= 100;

// or — either must match
bool IsWeekend(DayOfWeek day) => day is DayOfWeek.Saturday or DayOfWeek.Sunday;

// Combine freely
string Classify(int n) => n switch
{
    < 0                    => "negative",
    0                      => "zero",
    > 0 and < 10          => "small positive",
    >= 10 and < 100       => "medium positive",
    >= 100                 => "large positive"
};
```

### Property Pattern

```csharp
record Address(string City, string Country, string PostalCode);
record Person(string Name, int Age, Address Address);

string Classify(Person p) => p switch
{
    { Age: < 18 }                               => "minor",
    { Age: >= 18, Address.Country: "DE" }       => "German adult",
    { Age: >= 18, Address.City: "Berlin" }      => "Berliner adult",
    { Name: "Alice", Age: >= 30 }              => "Alice in her 30s+",
    _                                           => "other"
};

// Nested property pattern
bool IsLocalGerman(Person p) => p is
{
    Address: { Country: "DE", City: "Berlin" or "Hamburg" or "Munich" },
    Age: >= 18
};
```

### Positional Pattern (Deconstruct)

Works with records, tuples, and types that have `Deconstruct`:

```csharp
public record Point(double X, double Y);

string Quadrant(Point p) => p switch
{
    ( > 0,  > 0) => "Q1",
    ( < 0,  > 0) => "Q2",
    ( < 0,  < 0) => "Q3",
    ( > 0,  < 0) => "Q4",
    (0, 0)       => "origin",
    (0, _)       => "y-axis",
    (_, 0)       => "x-axis",
};

// With named elements
string Describe((int x, int y) point) => point switch
{
    (0, 0)          => "origin",
    (var x, 0)      => $"on x-axis at {x}",
    (0, var y)      => $"on y-axis at {y}",
    (var x, var y)  => $"at ({x}, {y})"
};
```

### List Pattern (C# 11+)

```csharp
int[] arr = [1, 2, 3, 4, 5];

bool matched = arr switch
{
    []                  => true,   // empty
    [1, 2, ..]         => true,   // starts with 1, 2
    [.., 4, 5]         => true,   // ends with 4, 5
    [1, .. var mid, 5] => true,   // capture middle
    [var first, ..]    => true,   // capture first element
    _                   => false
};

// Practical: routing
string Route(string[] segments) => segments switch
{
    ["api", "v1", "users"]            => "list users",
    ["api", "v1", "users", var id]    => $"get user {id}",
    ["api", "v1", "products", ..]     => "product endpoints",
    ["api", var version, ..]          => $"api version {version}",
    _                                 => "not found"
};

// Pattern match on spans (C# 11+)
bool StartsWithHttp(ReadOnlySpan<char> url) => url switch
{
    ['h', 't', 't', 'p', 's', ':',..] => true,
    ['h', 't', 't', 'p', ':',..] => true,
    _ => false
};
```

### var Pattern

```csharp
// var always matches, captures the value
string Inspect(object o) => o switch
{
    int n when n % 2 == 0 => $"even int: {n}",
    string { Length: var len } when len > 10 => "long string",
    var x => $"other: {x}"
};

// Useful for side-effects in switch
void Log(object o)
{
    if (o is var x and not null)
    {
        Console.WriteLine(x);
    }
}
```

### Combining All Patterns — Real-World Example

```csharp
// Shape hierarchy
abstract record Shape;
record Circle(double Radius) : Shape;
record Rectangle(double Width, double Height) : Shape;
record Triangle(double Base, double Height) : Shape;

double Area(Shape shape) => shape switch
{
    Circle { Radius: var r }                         => Math.PI * r * r,
    Rectangle { Width: var w, Height: var h }        => w * h,
    Triangle { Base: var b, Height: var h }          => 0.5 * b * h,
    null                                              => throw new ArgumentNullException(nameof(shape)),
    _                                                 => throw new NotSupportedException($"Unknown shape: {shape}")
};

string Classify(Shape shape) => shape switch
{
    Circle { Radius: 0 }           => "degenerate circle",
    Circle { Radius: < 1 }        => "small circle",
    Circle { Radius: >= 1 and < 10 } => "medium circle",
    Circle                         => "large circle",
    Rectangle { Width: var w, Height: var h } when w == h => "square",
    Rectangle                      => "rectangle",
    Triangle { Base: var b, Height: var h } when b == h   => "isoceles-ish triangle",
    Triangle                       => "triangle",
    _                              => "unknown"
};
```

---

## 3.4 Exception Handling

```csharp
// Basic try/catch/finally
try
{
    var result = RiskyOperation();
    return result;
}
catch (FileNotFoundException ex)
{
    _logger.LogError(ex, "File not found: {Path}", ex.FileName);
    throw;  // re-throw preserving stack trace
}
catch (IOException ex) when (ex.HResult == -2147024784) // specific HResult
{
    return null;
}
catch (OperationCanceledException)
{
    // Don't log cancelled operations as errors
    return null;
}
catch (Exception ex)
{
    _logger.LogError(ex, "Unexpected error");
    throw new ServiceException("Operation failed", ex);  // wrapping
}
finally
{
    Cleanup(); // always runs, even on exception or return
}
```

### Exception Filters (`when`)

```csharp
catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.TooManyRequests)
{
    await Task.Delay(TimeSpan.FromSeconds(1));
    return await RetryAsync();
}

catch (SqlException ex) when (ex.Number == 1205)  // deadlock
{
    // retry
}

// Filter with side effect (logging without catching)
catch (Exception ex) when (Log(ex) && false) { }
// Log(ex) runs, but false means the filter never matches — exception propagates
```

### Custom Exceptions

```csharp
// Base pattern for custom exceptions
public class OrderException : Exception
{
    public string OrderId { get; }

    public OrderException(string orderId, string message)
        : base(message)
    {
        OrderId = orderId;
    }

    public OrderException(string orderId, string message, Exception inner)
        : base(message, inner)
    {
        OrderId = orderId;
    }
}

public class OrderNotFoundException : OrderException
{
    public OrderNotFoundException(string orderId)
        : base(orderId, $"Order '{orderId}' was not found.") { }
}

public class InsufficientStockException : OrderException
{
    public string Sku { get; }
    public int Requested { get; }
    public int Available { get; }

    public InsufficientStockException(string orderId, string sku, int requested, int available)
        : base(orderId, $"Insufficient stock for SKU '{sku}': requested {requested}, available {available}.")
    {
        Sku = sku;
        Requested = requested;
        Available = available;
    }
}
```

### Using `ExceptionDispatchInfo`

```csharp
// Capture and re-throw without losing original stack trace
var edi = ExceptionDispatchInfo.Capture(ex);
await DoCleanupAsync();
edi.Throw(); // re-throws with original stack trace
```

---

## 3.5 `using` Statement and `IDisposable`

```csharp
// Classic using statement
using (var conn = new SqlConnection(connectionString))
{
    conn.Open();
    // conn.Dispose() called automatically even on exception
}

// using declaration (C# 8+) — disposed at end of enclosing scope
using var conn = new SqlConnection(connectionString);
conn.Open();
// conn.Dispose() called when method returns

// Multiple resources
using var conn = new SqlConnection(connectionString);
using var cmd  = conn.CreateCommand();
using var reader = cmd.ExecuteReader();

// await using for IAsyncDisposable
await using var context = new AppDbContext(options);
await using var transaction = await context.Database.BeginTransactionAsync();
```

### Implementing `IDisposable`

```csharp
public class FileProcessor : IDisposable, IAsyncDisposable
{
    private FileStream? _stream;
    private bool _disposed;

    public FileProcessor(string path)
    {
        _stream = new FileStream(path, FileMode.Open, FileAccess.Read);
    }

    public void Process() { /* use _stream */ }

    // IDisposable
    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;
        if (disposing)
        {
            _stream?.Dispose();
            _stream = null;
        }
        _disposed = true;
    }

    // IAsyncDisposable
    public async ValueTask DisposeAsync()
    {
        if (_stream is not null)
        {
            await _stream.DisposeAsync();
            _stream = null;
        }
        GC.SuppressFinalize(this);
    }
}
```

---

## 3.6 Iteration and `yield return`

```csharp
// Generator method — lazy evaluation
public static IEnumerable<int> Fibonacci()
{
    int a = 0, b = 1;
    while (true)
    {
        yield return a;
        (a, b) = (b, a + b);
    }
}

// Take first 10
var fibs = Fibonacci().Take(10).ToList();
// [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

// yield break
public static IEnumerable<string> ReadLines(string path)
{
    if (!File.Exists(path)) yield break;  // stop iteration early
    using var reader = new StreamReader(path);
    string? line;
    while ((line = reader.ReadLine()) is not null)
        yield return line;
}

// Async generators (C# 8+)
public static async IAsyncEnumerable<int> GetNumbersAsync(
    [EnumeratorCancellation] CancellationToken ct = default)
{
    for (int i = 0; i < 100; i++)
    {
        await Task.Delay(10, ct);
        yield return i;
    }
}

// Consuming async enumerable
await foreach (var n in GetNumbersAsync(cts.Token))
{
    Console.WriteLine(n);
}
```

---

## 3.7 goto (and When to Avoid It)

```csharp
// goto is valid C# but almost never needed. Exception: break from nested loops
for (int i = 0; i < 10; i++)
{
    for (int j = 0; j < 10; j++)
    {
        if (i + j > 10) goto done;  // only legitimate use
    }
}
done:
Console.WriteLine("done");

// Better: extract to method and use return
void Search()
{
    for (int i = 0; i < 10; i++)
        for (int j = 0; j < 10; j++)
            if (i + j > 10) return;
}
```

> **Rider tip:** Use *Navigate → Next/Prev highlighted error* (`F2` / `Shift+F2`) to jump between pattern match exhaustiveness warnings. Rider highlights unhandled cases in switch expressions in red.

> **VS tip:** *Ctrl+.* on an incomplete switch expression offers *"Add missing cases"* — it generates stubs for all unhandled enum values or type hierarchy members.

