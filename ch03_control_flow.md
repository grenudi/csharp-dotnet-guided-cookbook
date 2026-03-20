# Chapter 3 — Control Flow & Pattern Matching

> Control flow is the logic that decides which code runs and when. C#
> has inherited decades of `if`/`else`/`switch` evolution, but C# 7–11
> added pattern matching — a genuinely different way of reasoning about
> data that eliminates whole categories of bugs that are invisible in
> the old style. This chapter teaches both, and explains why patterns
> are not just syntax sugar but a different mental model.

*Building on:* Ch 2 (types, records, tuples) — pattern matching operates
on types and destructures records.

---

## 3.1 Basic Control Flow — What You Already Know

The fundamental constructs are universal. C# syntax follows the C family.

```csharp
// if / else
if (temperature > 100)
    Console.WriteLine("Boiling");
else if (temperature > 37)
    Console.WriteLine("Hot");
else
    Console.WriteLine("Normal");

// Always use braces — see the .editorconfig rule and the bug it prevents:
// Without braces, adding a second statement under an if looks guarded but isn't
if (isAdmin)
{
    Log("Admin action");
    ExecuteAdminTask();   // clearly inside the if
}

// Ternary: short if-else as an expression
string label = score >= 60 ? "Pass" : "Fail";

// while
int i = 0;
while (i < 10) { Console.WriteLine(i); i++; }

// do-while: executes at least once before checking condition
do { input = Console.ReadLine()!; } while (string.IsNullOrWhiteSpace(input));

// for: when you know the count
for (int j = 0; j < items.Length; j++)
    Process(items[j]);

// foreach: the preferred form when you do not need the index
foreach (var item in items)
    Process(item);
```

---

## 3.2 The Old `switch` Statement and Its Limitations

The original `switch` statement works on compile-time constants and
requires explicit `break` on every case. It cannot match on types,
conditions, or structure. This forced developers into long `if-else`
chains for anything beyond simple equality checks:

```csharp
// Old style: if-else chain for type-based dispatch
void DrawShape(object shape)
{
    if (shape is Circle c)
        DrawCircle(c.Radius);
    else if (shape is Rectangle r)
        DrawRectangle(r.Width, r.Height);
    else if (shape is Triangle t)
        DrawTriangle(t.Base, t.Height);
    else
        throw new ArgumentException($"Unknown shape: {shape.GetType()}");
}
```

Problems with this pattern:
- Adding a new shape type requires finding every such chain in the codebase
- The compiler cannot tell you if you missed a case
- The type cast (`as Circle`) and the null check (`if (c != null)`) are
  visually separate, allowing bugs where you use a null reference

Pattern matching solves all three.

---

## 3.3 Pattern Matching — The Modern Approach

Pattern matching is a way to simultaneously test a value's shape (type,
structure, or conditions) and extract parts of it in one expression.
Introduced in C# 7 and significantly extended through C# 11, it
fundamentally changes how you write conditional logic.

The key insight: patterns are *irrefutable* in the case where they match.
Inside a pattern match, the compiler knows exactly what type you have and
has already done the null check. No casting, no null guards, no brittle
chains.

### Type Patterns

```csharp
// is-pattern: test type and bind in one step
object value = GetValue();

if (value is string s)
    Console.WriteLine($"String of length {s.Length}");  // s is guaranteed string here

if (value is int n && n > 0)
    Console.WriteLine($"Positive int: {n}");

// switch expression with type patterns
string Describe(object obj) => obj switch
{
    int n          => $"integer {n}",
    string s       => $"string '{s}'",
    null           => "null",
    _              => $"other: {obj.GetType().Name}"  // _ is the discard (default)
};
```

### Property Patterns — Match on Structure

Property patterns let you match on the *values of properties*, not just
the type. This is where pattern matching becomes genuinely expressive:

```csharp
// Instead of: if (order != null && order.Status == Status.Pending && order.Total > 100)
bool IsHighValuePending(Order? order) => order is
{
    Status: Status.Pending,
    Total: > 100m
};

// Nested property patterns
string ClassifyCustomer(Customer customer) => customer switch
{
    { TierLevel: "Gold",   YearsActive: >= 5 } => "Loyal Gold",
    { TierLevel: "Gold"                       } => "New Gold",
    { TierLevel: "Silver", YearsActive: >= 3  } => "Established Silver",
    { IsActive: false }                          => "Inactive",
    _                                            => "Standard"
};
```

### Positional Patterns — Destructure Records and Tuples

When a type supports deconstruction (records do automatically), you can
match on the positions of deconstructed values:

```csharp
public record Point(int X, int Y);

string QuadrantOf(Point p) => p switch
{
    (0, 0)     => "Origin",
    (> 0, > 0) => "Quadrant I",
    (< 0, > 0) => "Quadrant II",
    (< 0, < 0) => "Quadrant III",
    (> 0, < 0) => "Quadrant IV",
    _          => "On an axis"
};
```

### Relational and Logical Patterns

```csharp
// Relational patterns: <, >, <=, >=
string RateTemp(double celsius) => celsius switch
{
    < 0    => "Freezing",
    < 10   => "Cold",
    < 20   => "Cool",
    < 30   => "Warm",
    < 40   => "Hot",
    _      => "Extreme"
};

// Logical patterns: and, or, not
bool IsWeekday(DayOfWeek day) => day is not (DayOfWeek.Saturday or DayOfWeek.Sunday);

// Combined
string Category(int score) => score switch
{
    >= 90            => "A",
    >= 80 and < 90   => "B",
    >= 70 and < 80   => "C",
    >= 60 and < 70   => "D",
    _                => "F"
};
```

### List Patterns (C# 11) — Match on Sequence Structure

```csharp
// Match arrays and lists by structure
string Describe(int[] numbers) => numbers switch
{
    []           => "empty",
    [var x]      => $"single element: {x}",
    [var x, var y] => $"two elements: {x} and {y}",
    [0, ..]      => "starts with zero",
    [.., 0]      => "ends with zero",
    [var first, .., var last] => $"starts with {first}, ends with {last}"
};
```

### Why Exhaustiveness Matters

The switch expression (unlike the switch statement) is an *expression* —
it must return a value for every possible input. The compiler warns you
if your patterns do not cover all cases:

```csharp
// Compiler warning CS8509 if any enum value is not covered
string StatusLabel(OrderStatus status) => status switch
{
    OrderStatus.Pending    => "Awaiting payment",
    OrderStatus.Processing => "Being prepared",
    OrderStatus.Shipped    => "On its way",
    OrderStatus.Delivered  => "Delivered",
    // Compiler: CS8509 — switch expression does not handle all possible values
    // of 'OrderStatus'. Add 'OrderStatus.Cancelled' or a discard pattern.
};
```

This is enormously valuable when you add a new enum member. Every switch
expression that covers the enum will produce a compiler warning, pointing
you to every place that needs updating.

---

## 3.4 Exception Handling — Communicate Failure Appropriately

Exceptions exist to communicate *unexpected* failures — situations that
violate the contract of a method. They should not be used for expected
outcomes like "user not found" or "validation failed". See Ch 6 §6.3
for the deeper principle (Errors Are Values).

```csharp
try
{
    var result = await ProcessOrderAsync(orderId, ct);
    return result;
}
catch (OrderNotFoundException ex)
{
    // Specific exception first — ordered from most specific to least specific
    _logger.LogWarning("Order {Id} not found: {Message}", orderId, ex.Message);
    return NotFound();
}
catch (ValidationException ex)
{
    return BadRequest(ex.Errors);
}
catch (TimeoutException ex)
{
    _logger.LogError(ex, "Timeout processing order {Id}", orderId);
    return StatusCode(503, "Service temporarily unavailable");
}
catch (Exception ex)
{
    // Only catch the base Exception to log and rethrow
    // Never swallow it silently
    _logger.LogError(ex, "Unexpected error processing order {Id}", orderId);
    throw;  // 'throw' (not 'throw ex') preserves the original stack trace
}
finally
{
    // Runs regardless of success or failure — use for cleanup
    // But prefer 'using' statements (§3.5) for IDisposable cleanup
    _metrics.RecordAttempt();
}
```

### Exception Filters — `when`

`when` lets you narrow a catch to only handle exceptions that meet a
condition, without catching and rethrowing:

```csharp
catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.ServiceUnavailable)
{
    // Only handles 503, not 404 or 401
    await Task.Delay(TimeSpan.FromSeconds(5), ct);
    throw;  // rethrow to let the retry policy handle it
}
```

### Custom Exceptions — When and How

Create a custom exception when callers need to distinguish your failure
mode from all other failures:

```csharp
public class InsufficientFundsException(decimal required, decimal available)
    : Exception($"Need {required:C} but only {available:C} available")
{
    public decimal Required  { get; } = required;
    public decimal Available { get; } = available;
}

// Caller can catch specifically
catch (InsufficientFundsException ex)
{
    ShowFundsError(ex.Required, ex.Available);
}
```

---

## 3.5 `using` and `IDisposable` — Deterministic Resource Cleanup

The garbage collector handles memory. It does not handle *other resources*:
file handles, database connections, network sockets, native memory. These
resources must be released explicitly and promptly, or you leak them.

`IDisposable` is the contract: a type that implements it has a `Dispose()`
method that releases its unmanaged resources. The `using` statement
guarantees `Dispose` is called when the variable goes out of scope, even
if an exception is thrown.

```csharp
// Classic using block
using (var conn = new SqliteConnection(connectionString))
{
    conn.Open();
    // ... use conn ...
}  // conn.Dispose() called here, even if an exception was thrown inside

// Modern using declaration (C# 8+) — 'using' without braces
// Dispose is called at the end of the enclosing scope (method, block)
using var conn2 = new SqliteConnection(connectionString);
conn2.Open();
// ... use conn2 ...
// conn2.Dispose() called when method returns or throws
```

The `using` declaration (without braces) is preferred for its brevity
when the resource should live for the duration of the current method.
Use the block form when you need to release the resource before the
method ends. See Chapter 26 for the full `IDisposable` implementation
pattern and how the finaliser interacts with it.

---

## 3.6 Iteration — `foreach`, `yield`, and Lazy Sequences

`foreach` works on any type that implements `IEnumerable<T>` or has a
compatible `GetEnumerator()` method. This includes arrays, lists,
dictionaries, LINQ queries, and custom types.

### `yield return` — Generating Sequences Lazily

`yield return` creates an *iterator method* — a method that produces a
sequence one element at a time without materialising the whole sequence
into memory at once. The method body is suspended after each `yield`
and resumed when the next element is requested.

```csharp
// Without yield: materialises all results into memory before returning
public IEnumerable<string> ReadAllLines(string path) =>
    File.ReadAllLines(path);  // reads entire file, then returns

// With yield: reads and produces one line at a time — works on arbitrarily large files
public IEnumerable<string> ReadLines(string path)
{
    using var reader = new StreamReader(path);
    while (!reader.EndOfStream)
        yield return reader.ReadLine()!;
}
// File is read lazily: only the lines actually consumed are ever in memory

// Yield works with any condition
public IEnumerable<int> Fibonacci()
{
    int a = 0, b = 1;
    while (true)
    {
        yield return a;
        (a, b) = (b, a + b);  // indefinitely — caller controls how many they take
    }
}

var first10 = Fibonacci().Take(10).ToList();
```

`yield` pairs naturally with LINQ (Chapter 7) because LINQ is itself
lazy — it processes one element at a time through a chain of operators.

---

## 3.7 Connecting Control Flow to the Rest of the Book

Pattern matching built on Ch 2's type system:
- **Ch 6 §6.5 (Totality)** — exhaustive pattern matching ensures you
  handle every case, not just the common one.
- **Ch 7 (LINQ)** — `Where`, `Select`, `GroupBy` are all control flow
  over sequences, expressed functionally.
- **Ch 8 (Async)** — `await` in a `while` loop, `foreach` over
  `IAsyncEnumerable<T>`, and cancellation all follow control flow rules.
- **Ch 14 (ASP.NET Core)** — route matching uses pattern-like concepts;
  middleware is a chain of conditional delegates.
- **Ch 26 (Memory)** — `using` and `IDisposable` are the most important
  control flow construct for resource management.
