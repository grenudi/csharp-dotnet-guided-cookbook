# Chapter 4 — Methods, Delegates, Lambdas & Functional Patterns

## 4.1 Method Signatures

```csharp
// Basic method
public string Greet(string name) => $"Hello, {name}!";

// Multiple parameters
public static double Hypotenuse(double a, double b)
    => Math.Sqrt(a * a + b * b);

// ref parameters — pass by reference, must be pre-initialized
public static void Swap<T>(ref T a, ref T b)
{
    T tmp = a; a = b; b = tmp;
}

int x = 1, y = 2;
Swap(ref x, ref y); // x=2, y=1

// out parameters — must be assigned before method returns
public static bool TryDivide(int a, int b, out double result)
{
    if (b == 0) { result = 0; return false; }
    result = (double)a / b;
    return true;
}

if (TryDivide(10, 3, out var r)) Console.WriteLine(r); // 3.333...
TryDivide(10, 0, out _); // discard out param

// in parameters — read-only by-reference (avoids copy for large structs)
public static double DotProduct(in Vector3 a, in Vector3 b)
    => a.X * b.X + a.Y * b.Y + a.Z * b.Z;
```

### Optional Parameters and Named Arguments

```csharp
public string Format(
    string text,
    int maxLength = 100,
    bool ellipsis = true,
    string separator = ", ")
{
    if (text.Length <= maxLength) return text;
    return ellipsis ? text[..maxLength] + "…" : text[..maxLength];
}

// Call with named arguments — order doesn't matter
var s1 = Format("hello", maxLength: 5, ellipsis: false);
var s2 = Format(text: "hello", separator: " | ", maxLength: 50);
```

### params — Variable-Length Arguments

```csharp
public static int Sum(params int[] values)
    => values.Sum();

public static string Concat(string separator, params string[] parts)
    => string.Join(separator, parts);

// params IEnumerable<T> / params ReadOnlySpan<T> (C# 13+)
public static T Max<T>(params ReadOnlySpan<T> values) where T : IComparable<T>
{
    if (values.IsEmpty) throw new ArgumentException("No values");
    T max = values[0];
    foreach (var v in values[1..])
        if (v.CompareTo(max) > 0) max = v;
    return max;
}

int total = Sum(1, 2, 3, 4, 5);           // 15
string s   = Concat(", ", "a", "b", "c"); // "a, b, c"
int biggest = Max(3, 1, 4, 1, 5, 9, 2);  // 9
```

---

## 4.2 Local Functions

Defined inside another method — they can capture outer variables (closures) or be declared `static`:

```csharp
public static IEnumerable<int> Fibonacci(int count)
{
    return Generate();

    // Local function — visible within the enclosing method
    IEnumerable<int> Generate()
    {
        int a = 0, b = 1;
        for (int i = 0; i < count; i++)
        {
            yield return a;
            (a, b) = (b, a + b);
        }
    }
}

// Static local function — cannot capture (prevents accidental closure)
public double Calculate(double x)
{
    return Transform(Normalize(x));

    static double Normalize(double v) => (v - 0) / (100 - 0);
    static double Transform(double v) => Math.Sqrt(v);
}

// Local functions for recursive lambdas (lambdas can't be self-referencing)
public static int Factorial(int n)
{
    return Calc(n);

    static int Calc(int n) => n <= 1 ? 1 : n * Calc(n - 1);
}
```

---

## 4.3 Extension Methods

```csharp
// Must be in a static class, first param is `this T`
public static class StringExtensions
{
    public static bool IsNullOrWhiteSpace(this string? s)
        => string.IsNullOrWhiteSpace(s);

    public static string Truncate(this string s, int maxLen, string suffix = "…")
        => s.Length <= maxLen ? s : s[..maxLen] + suffix;

    public static T? ParseEnum<T>(this string s) where T : struct, Enum
        => Enum.TryParse<T>(s, ignoreCase: true, out var v) ? v : null;

    public static IEnumerable<T> WhereNotNull<T>(this IEnumerable<T?> source) where T : class
        => source.Where(x => x is not null)!;
}

// Extension on interfaces — adds methods to all implementors
public static class EnumerableExtensions
{
    public static IEnumerable<T> Shuffle<T>(this IEnumerable<T> source, Random? rng = null)
    {
        rng ??= Random.Shared;
        var arr = source.ToArray();
        for (int i = arr.Length - 1; i > 0; i--)
        {
            int j = rng.Next(i + 1);
            (arr[i], arr[j]) = (arr[j], arr[i]);
        }
        return arr;
    }

    public static async Task<List<T>> ToListAsync<T>(this IAsyncEnumerable<T> source,
        CancellationToken ct = default)
    {
        var list = new List<T>();
        await foreach (var item in source.WithCancellation(ct))
            list.Add(item);
        return list;
    }
}
```

---

## 4.4 Delegates

A delegate is a type-safe function pointer.

```csharp
// Declare delegate type
public delegate int Transformer(int input);

// Assign method
Transformer square = x => x * x;
Transformer negate = x => -x;

// Compose
Transformer squareThenNegate = x => negate(square(x));
Console.WriteLine(squareThenNegate(5)); // -25

// Multicast delegate (+=)
Action<string> log = Console.WriteLine;
log += s => Debug.WriteLine(s);
log += WriteToFile;  // called in order: Console, Debug, file
log("hello");
log -= WriteToFile;  // remove handler
```

### Built-In Delegate Types

```csharp
// Action — void return, 0-16 type params
Action doSomething = () => Console.WriteLine("hi");
Action<int> printInt = n => Console.WriteLine(n);
Action<string, int> printBoth = (s, n) => Console.WriteLine($"{s}={n}");

// Func — non-void return, 0-16 input params + 1 return
Func<int> getZero = () => 0;
Func<int, int> square = x => x * x;
Func<int, int, int> add = (a, b) => a + b;
Func<string, bool> isLong = s => s.Length > 10;

// Predicate<T> — shorthand for Func<T, bool>
Predicate<int> isEven = n => n % 2 == 0;

// Comparison<T> — shorthand for Func<T, T, int>
Comparison<string> byLength = (a, b) => a.Length.CompareTo(b.Length);
var sorted = words.OrderBy(x => x.Length).ToList();

// EventHandler<TEventArgs>
EventHandler<OrderPlacedEventArgs> handler = (sender, e) => Console.WriteLine(e.OrderId);
```

---

## 4.5 Lambdas & Closures

```csharp
// Lambda forms
Func<int, int> f1 = x => x * x;            // expression lambda
Func<int, int> f2 = (int x) => x * x;     // typed param
Func<int, int> f3 = x => { return x * x; }; // statement lambda
Func<int, int, int> f4 = (x, y) => x + y;

// Discard unused params
Action<int, int> onlyFirst = (x, _) => Console.WriteLine(x);

// Closures capture outer variables by reference
int multiplier = 3;
Func<int, int> multiply = x => x * multiplier;
multiplier = 10;
Console.WriteLine(multiply(5)); // 50 — captures the variable, not the value!

// Capture with caution in loops
var fns = new List<Func<int>>();
for (int i = 0; i < 3; i++)
{
    int captured = i;  // capture copy to avoid closure bug
    fns.Add(() => captured);
}
// Without int captured = i: all fns would return 3

// Static lambdas (C# 9+) — cannot capture, guaranteed no allocation
Func<int, int> staticSquare = static x => x * x;
```

### Lambda Attributes (C# 10+)

```csharp
// Apply attributes to lambdas
var validate = [DebuggerStepThrough] (string? s) => !string.IsNullOrEmpty(s);
```

---

## 4.6 Events

```csharp
// Define event args
public class OrderPlacedEventArgs : EventArgs
{
    public string OrderId { get; }
    public decimal Total { get; }
    public OrderPlacedEventArgs(string orderId, decimal total)
    {
        OrderId = orderId;
        Total = total;
    }
}

// Publisher
public class OrderService
{
    // Event using EventHandler<T>
    public event EventHandler<OrderPlacedEventArgs>? OrderPlaced;

    protected virtual void OnOrderPlaced(OrderPlacedEventArgs e)
        => OrderPlaced?.Invoke(this, e);  // thread-safe null check with ?.

    public void PlaceOrder(string id, decimal total)
    {
        // ... business logic ...
        OnOrderPlaced(new OrderPlacedEventArgs(id, total));
    }
}

// Subscriber
var svc = new OrderService();
svc.OrderPlaced += (sender, e) =>
    Console.WriteLine($"Order {e.OrderId} placed: {e.Total:C}");

svc.OrderPlaced += async (sender, e) =>
{
    await SendEmailAsync(e.OrderId);
};

svc.PlaceOrder("ORD-001", 99.99m);

// Custom event accessors
private EventHandler<OrderPlacedEventArgs>? _orderPlaced;
public event EventHandler<OrderPlacedEventArgs>? OrderPlaced
{
    add    => _orderPlaced += value;
    remove => _orderPlaced -= value;
}
```

---

## 4.7 Functional Patterns in C#

### Higher-Order Functions

```csharp
// Function that takes functions
public static IEnumerable<TResult> Map<T, TResult>(
    IEnumerable<T> source,
    Func<T, TResult> f)
    => source.Select(f);

// Function that returns functions
public static Func<T, bool> Not<T>(Func<T, bool> predicate)
    => x => !predicate(x);

public static Func<T, TResult> Memoize<T, TResult>(Func<T, TResult> f)
    where T : notnull
{
    var cache = new Dictionary<T, TResult>();
    return x =>
    {
        if (!cache.TryGetValue(x, out var result))
        {
            result = f(x);
            cache[x] = result;
        }
        return result;
    };
}

// Usage
var isNotEmpty = Not<string>(string.IsNullOrEmpty);
var cachedFib = Memoize<int, long>(n => n <= 1 ? n : Fibonacci(n - 1) + Fibonacci(n - 2));
```

### Currying & Partial Application

```csharp
// Currying — transform (A, B) -> C into A -> B -> C
public static Func<B, C> Curry<A, B, C>(Func<A, B, C> f, A a)
    => b => f(a, b);

Func<int, int, int> add = (a, b) => a + b;
Func<int, int> add5 = Curry(add, 5);
Console.WriteLine(add5(3));  // 8

// Partial application
Func<string, string, string> concat = (prefix, s) => prefix + s;
Func<string, string> addPrefix = s => concat("LOG: ", s);
```

### Pipeline / Method Chaining

```csharp
// Fluent builder pattern
public class QueryBuilder
{
    private string _table = "";
    private readonly List<string> _conditions = new();
    private int? _limit;
    private string? _orderBy;

    public QueryBuilder From(string table) { _table = table; return this; }
    public QueryBuilder Where(string condition) { _conditions.Add(condition); return this; }
    public QueryBuilder Limit(int n) { _limit = n; return this; }
    public QueryBuilder OrderBy(string col) { _orderBy = col; return this; }

    public string Build()
    {
        var sql = $"SELECT * FROM {_table}";
        if (_conditions.Any()) sql += " WHERE " + string.Join(" AND ", _conditions);
        if (_orderBy is not null) sql += $" ORDER BY {_orderBy}";
        if (_limit.HasValue) sql += $" LIMIT {_limit}";
        return sql;
    }
}

// Usage
var query = new QueryBuilder()
    .From("users")
    .Where("age > 18")
    .Where("active = 1")
    .OrderBy("name")
    .Limit(50)
    .Build();
```

### Option / Maybe Pattern

```csharp
// Custom Option<T> for explicit maybe semantics
public readonly struct Option<T>
{
    private readonly T _value;
    public bool HasValue { get; }

    private Option(T value) { _value = value; HasValue = true; }

    public static Option<T> Some(T value) => new(value);
    public static Option<T> None()        => default;

    public T GetOrThrow() => HasValue ? _value : throw new InvalidOperationException("No value.");
    public T GetOrDefault(T def) => HasValue ? _value : def;

    public Option<TOut> Map<TOut>(Func<T, TOut> f)
        => HasValue ? Option<TOut>.Some(f(_value)) : Option<TOut>.None();

    public Option<TOut> Bind<TOut>(Func<T, Option<TOut>> f)
        => HasValue ? f(_value) : Option<TOut>.None();

    public void Match(Action<T> some, Action none)
    {
        if (HasValue) some(_value); else none();
    }

    public TOut Match<TOut>(Func<T, TOut> some, Func<TOut> none)
        => HasValue ? some(_value) : none();
}

static class Option
{
    public static Option<T> Some<T>(T value) => Option<T>.Some(value);
    public static Option<T> None<T>() => Option<T>.None();
}

// Usage
Option<User> FindUser(int id) =>
    _db.TryGetValue(id, out var u) ? Option.Some(u) : Option.None<User>();

var name = FindUser(42)
    .Map(u => u.Name)
    .GetOrDefault("Unknown");
```

---

## 4.8 Expression Trees

Expression trees represent code as data — used by LINQ-to-SQL, ORMs, mocking frameworks.

```csharp
using System.Linq.Expressions;

// Compile-time expression tree
Expression<Func<int, int>> squareExpr = x => x * x;

// Inspect the tree
var body = (BinaryExpression)squareExpr.Body;
Console.WriteLine(body.NodeType);   // Multiply
Console.WriteLine(body.Left);       // x
Console.WriteLine(body.Right);      // x

// Compile and invoke
var square = squareExpr.Compile();
Console.WriteLine(square(5));       // 25

// Build at runtime
var param = Expression.Parameter(typeof(int), "x");
var mul   = Expression.Multiply(param, param);
var lambda = Expression.Lambda<Func<int, int>>(mul, param);
var fn = lambda.Compile();
Console.WriteLine(fn(7));           // 49

// Real use: EF Core strongly-typed filter
IQueryable<User> FilterBy<T>(IQueryable<User> q, Expression<Func<User, T>> selector, T value)
{
    // This translates to SQL — lambda expressions, not delegates!
    var param = selector.Parameters[0];
    var eq = Expression.Equal(selector.Body, Expression.Constant(value));
    var predicate = Expression.Lambda<Func<User, bool>>(eq, param);
    return q.Where(predicate);
}
```

---

## 4.9 Operator Overloading

```csharp
public readonly record struct Money(decimal Amount, string Currency)
{
    public static Money operator +(Money a, Money b)
    {
        if (a.Currency != b.Currency)
            throw new InvalidOperationException($"Cannot add {a.Currency} and {b.Currency}");
        return new(a.Amount + b.Amount, a.Currency);
    }

    public static Money operator -(Money a, Money b)
    {
        if (a.Currency != b.Currency)
            throw new InvalidOperationException("Currency mismatch");
        return new(a.Amount - b.Amount, a.Currency);
    }

    public static Money operator *(Money m, decimal factor) => new(m.Amount * factor, m.Currency);
    public static Money operator *(decimal factor, Money m) => m * factor;

    public static bool operator >(Money a, Money b)  => a.Amount > b.Amount;
    public static bool operator <(Money a, Money b)  => a.Amount < b.Amount;
    public static bool operator >=(Money a, Money b) => a.Amount >= b.Amount;
    public static bool operator <=(Money a, Money b) => a.Amount <= b.Amount;

    // Implicit/explicit conversions
    public static explicit operator decimal(Money m) => m.Amount;
    public static implicit operator string(Money m)  => m.ToString();

    public override string ToString() => $"{Amount:F2} {Currency}";
}

// Usage
var price = new Money(9.99m, "EUR");
var tax   = new Money(1.90m, "EUR");
var total = price + tax;                    // 11.89 EUR
var doubled = total * 2;                    // 23.78 EUR
bool expensive = total > new Money(10m, "EUR"); // true
```

> **Rider tip:** *Alt+Enter* on a lambda expression offers *"Convert to method group"* when applicable (e.g., `x => x.ToString()` → `Convert.ToString`). Also use *Refactor → Extract Method* (`Ctrl+Alt+M` / `⌘⌥M`) to extract a lambda into a named local function or method.

> **VS tip:** *Ctrl+.* on a complex delegate expression offers *"Introduce local variable"* or *"Convert to method"*. Use *Quick Actions* to convert between lambda forms.

