# Chapter 4 — Methods, Delegates, Lambdas & Functional Patterns

> Functions are the basic unit of computation. This chapter starts from
> method signatures and works outward to delegates, lambdas, and the
> functional patterns that make modern C# expressive and composable.
> Understanding delegates is essential groundwork for async/await
> (Ch 8), LINQ (Ch 7), events, and dependency injection (Ch 10–11).

*Building on:* Ch 2 (generics, type system), Ch 3 (control flow, pattern matching)

---

## 4.1 Method Signatures — What They Actually Mean

A method signature is a contract: it declares what the method needs and
what it returns. C# gives you fine-grained control over how arguments
are passed, which shapes both performance and correctness.

```csharp
// The anatomy of a method signature
public static async Task<IReadOnlyList<Order>> GetActiveOrdersAsync(
    string customerId,          // required value parameter
    int    pageSize   = 20,     // optional: caller can omit, gets 20
    int    page       = 0,      // optional
    CancellationToken ct = default  // conventional last param for async
)
{
    // ...
}

// Callers can use named arguments — order does not matter with named
var orders = await GetActiveOrdersAsync(
    customerId: "C001",
    page: 2,
    pageSize: 10);
```

### Value vs. Reference Parameters — `ref`, `out`, `in`

By default, parameters are passed by value: a copy is made. For
reference types that copy is cheap (it is just a pointer). For large
value types, passing by value copies the whole struct.

```csharp
// ref: pass by reference — caller's variable is modified
void Increment(ref int value) => value++;
int n = 5;
Increment(ref n);
Console.WriteLine(n); // 6 — the original was modified

// out: like ref but the method MUST assign it before returning
// Useful for Try* patterns
bool TryParse(string input, out int result)
{
    return int.TryParse(input, out result);
}
if (TryParse("42", out int n2))
    Console.WriteLine(n2);

// in: pass by reference but READONLY — prevents copy of large structs
// without allowing modification
void PrintMatrix(in Matrix4x4 m)   // 64-byte struct, passed without copying
{
    Console.WriteLine(m.M11);      // read-only access
    // m.M11 = 0;                  // COMPILE ERROR — in is readonly
}
```

### `params` — Variable Number of Arguments

```csharp
// params lets callers pass any number of arguments as if they were an array
int Sum(params int[] numbers) => numbers.Sum();

Sum(1, 2, 3);           // three arguments
Sum(1, 2, 3, 4, 5);    // five arguments
Sum();                   // zero arguments
Sum(new[] { 1, 2, 3 }); // explicit array
```

### Local Functions — Functions Inside Functions

A local function is defined inside another method and can only be called
from within it. Unlike lambdas, local functions can be recursive, can
have `yield return`, and do not allocate a closure object if they
do not capture any outer variables.

```csharp
public IEnumerable<int> GetPrimes(int limit)
{
    for (int i = 2; i <= limit; i++)
        if (IsPrime(i)) yield return i;

    // Local function: only visible inside GetPrimes
    static bool IsPrime(int n)   // 'static' prevents accidental capture of outer variables
    {
        if (n < 2) return false;
        for (int k = 2; k * k <= n; k++)
            if (n % k == 0) return false;
        return true;
    }
}
```

---

## 4.2 Extension Methods — Adding Behaviour to Types You Don't Own

An extension method appears to be a member of a type but is defined
externally in a static class. The compiler rewrites `value.Method()` to
`StaticClass.Method(value)` — it is purely a call-site convenience.

Extension methods are how LINQ (`Where`, `Select`, `OrderBy`) is added
to every `IEnumerable<T>` without modifying any collection class. They
are also how you add utility methods to BCL types like `string`, `int`,
or `IServiceCollection` (the pattern used throughout ASP.NET Core DI).

```csharp
// Define: first parameter is the type being extended, marked with 'this'
public static class StringExtensions
{
    // Adds .Truncate() to all string values
    public static string Truncate(this string value, int maxLength)
    {
        ArgumentNullException.ThrowIfNull(value);
        return value.Length <= maxLength
            ? value
            : value[..maxLength] + "…";
    }

    // Adds .IsNullOrEmpty() to all string? values
    public static bool IsNullOrEmpty(this string? value) =>
        string.IsNullOrEmpty(value);
}

// Usage: looks like a string method
string title = "The Quick Brown Fox Jumped Over The Lazy Dog";
Console.WriteLine(title.Truncate(15)); // "The Quick Brown…"
```

```csharp
// The canonical pattern: extension method on IServiceCollection for DI registration
// This is how the ASP.NET Core ecosystem works — every library adds itself this way
public static IServiceCollection AddEmailService(
    this IServiceCollection services, Action<EmailOptions> configure)
{
    services.Configure(configure);
    services.AddScoped<IEmailSender, SmtpEmailSender>();
    return services;
}

// In Program.cs:
builder.Services.AddEmailService(opts =>
{
    opts.Host = "smtp.example.com";
    opts.Port = 587;
});
```

---

## 4.3 Delegates — Variables That Hold Functions

A delegate is a type that represents a reference to a method. It is a
first-class citizen — you can store a method in a variable, pass it as
an argument, return it from a method, and call it later. This is the
foundation for callbacks, event handling, LINQ, and async continuations.

Before understanding `Func` and `Action` (the modern way), understand
what delegates fundamentally are:

```csharp
// Declare a delegate type: a type signature for methods
delegate int Transform(int input);

// Any method with signature int(int) is compatible
int Double(int x) => x * 2;
int Square(int x) => x * x;

// Assign a method to a delegate variable
Transform op = Double;
Console.WriteLine(op(5));  // 10

op = Square;               // point to a different method
Console.WriteLine(op(5));  // 25
```

### `Func` and `Action` — The Standard Delegate Types

Writing a custom delegate type for every use case is tedious. The BCL
provides generic delegate types that cover all common cases:

```csharp
// Func<T1, ..., TResult> — a function that returns a value
Func<int, int>     doubler   = x => x * 2;
Func<string, bool> notEmpty  = s => !string.IsNullOrEmpty(s);
Func<int, int, int> add      = (a, b) => a + b;

// Action<T1, ...> — a function that returns void (performs a side effect)
Action<string>        log     = Console.WriteLine;
Action<string, int>   repeat  = (s, n) => { for(int i=0;i<n;i++) Console.Write(s); };

// Predicate<T> — specifically a Func<T, bool> (common in older APIs)
Predicate<int>  isEven = n => n % 2 == 0;
```

Passing `Func` and `Action` as parameters is how you write behaviour-
parameterised methods — methods that can be customised by the caller:

```csharp
// Higher-order function: takes a function as a parameter
public List<TResult> Transform<T, TResult>(List<T> items, Func<T, TResult> selector)
{
    var result = new List<TResult>(items.Count);
    foreach (var item in items)
        result.Add(selector(item));
    return result;
}

var names = new List<string> { "alice", "bob", "charlie" };
var upper = Transform(names, s => s.ToUpper());  // passed a lambda
```

---

## 4.4 Lambdas and Closures — Functions Defined Inline

A lambda expression is an anonymous function defined inline. It uses
the `=>` (arrow) syntax: `parameters => body`. Lambdas are the most
common way to provide a `Func` or `Action` argument.

```csharp
// Various lambda syntaxes
Func<int, int> square = x => x * x;           // expression body, one parameter
Func<int, int, int> add = (a, b) => a + b;    // two parameters
Action greet = () => Console.WriteLine("Hi"); // no parameters
Func<int, bool> check = x =>
{
    if (x < 0) return false;
    return x % 2 == 0;
};  // block body for complex logic
```

### Closures — Capturing Variables From Outer Scope

A closure is a lambda that *captures* a variable from the enclosing
scope. The lambda carries a reference to the captured variable, not a
copy. This means the lambda can read and modify the outer variable, and
changes to the outer variable are visible in the lambda.

```csharp
int multiplier = 3;
Func<int, int> triple = x => x * multiplier;  // captures 'multiplier'

Console.WriteLine(triple(5));  // 15

multiplier = 10;               // change the captured variable
Console.WriteLine(triple(5));  // 50 — the lambda sees the CURRENT value of multiplier
```

This behaviour is often surprising. The most common trap is capturing a
loop variable:

```csharp
// BUG: all lambdas capture the SAME variable 'i'
var actions = new List<Action>();
for (int i = 0; i < 5; i++)
    actions.Add(() => Console.WriteLine(i));

actions.ForEach(a => a());
// Prints: 5 5 5 5 5  (not 0 1 2 3 4)
// Because by the time the lambdas run, 'i' is 5

// FIX: capture a copy
for (int i = 0; i < 5; i++)
{
    int captured = i;   // new variable per iteration
    actions.Add(() => Console.WriteLine(captured));
}
actions.ForEach(a => a());
// Prints: 0 1 2 3 4
```

Note: `foreach` (unlike `for`) creates a new scope per iteration in
modern C#, so `foreach (var item in list)` does not have this problem.

---

## 4.5 Events — The Delegate-Based Notification Pattern

An event is a restricted delegate: callers can subscribe (`+=`) and
unsubscribe (`-=`) but cannot invoke it or replace it. This is the
Observer pattern (see Ch 29 §29.5) baked into the language.

Events are used throughout the BCL: `Button.Click`, `Timer.Elapsed`,
`FileSystemWatcher.Changed`, `HttpClient.SendAsync` progress callbacks.

```csharp
// Define an event in a class
public class OrderProcessor
{
    // EventHandler<T> is the standard delegate type for events
    // T = event args type carrying event data
    public event EventHandler<OrderProcessedEventArgs>? OrderProcessed;

    public async Task ProcessAsync(Order order, CancellationToken ct)
    {
        // ... process the order ...

        // Raise the event — notify all subscribers
        // The ?. is critical: if no one has subscribed, OrderProcessed is null
        OrderProcessed?.Invoke(this, new OrderProcessedEventArgs(order.Id, order.Total));
    }
}

public record OrderProcessedEventArgs(Guid OrderId, decimal Total) : EventArgs;

// Subscribe (register a handler)
var processor = new OrderProcessor();
processor.OrderProcessed += (sender, args) =>
    Console.WriteLine($"Order {args.OrderId} processed: {args.Total:C}");

// Unsubscribe to prevent memory leaks
// If the subscriber lives longer than the publisher, the event holds a reference
// to the subscriber, preventing GC. Always unsubscribe when done.
processor.OrderProcessed -= handler;
```

---

## 4.6 Functional Patterns — Pure Functions, Immutability, and Composition

Functional programming is not a separate paradigm — it is a set of
techniques you can apply in C# to write more predictable, testable code.

### Pure Functions — No Side Effects

A pure function always returns the same output for the same input and
has no observable side effects (no mutation of external state, no I/O).
Pure functions are trivially testable, parallelisable, and cacheable.

```csharp
// Pure: depends only on its input, changes nothing external
public static decimal ApplyDiscount(decimal price, decimal discountPercent) =>
    price * (1 - discountPercent / 100);

// Impure: reads from external state, has side effects
public decimal ApplyDiscount(decimal price)
{
    var discount = _database.GetCurrentDiscount();  // reads external state
    _auditLog.RecordDiscount(price, discount);       // side effect
    return price * (1 - discount / 100);
}
```

### Function Composition

Building complex behaviour by combining simple functions:

```csharp
// A pipeline of transformations
var result = prices
    .Where(p => p > 0)               // filter
    .Select(p => p * 1.19m)          // transform (apply VAT)
    .Select(p => Math.Round(p, 2))   // transform (round)
    .OrderByDescending(p => p)       // sort
    .Take(10)                        // limit
    .ToList();                       // materialise
```

Each function in the chain is a pure transformation. The chain is easy
to read, test each step independently, and modify without touching other
steps. This is the foundation of LINQ (Chapter 7).

### Method Chaining and Fluent APIs

The pattern where every method returns `this` (or a new instance), enabling chains:

```csharp
// Building objects fluently
var config = new EmailConfiguration()
    .WithHost("smtp.example.com")
    .WithPort(587)
    .WithCredentials("user", "pass")
    .WithTls(true);
```

```csharp
// Implementation
public class EmailConfiguration
{
    private string _host = "";
    private int _port = 25;

    public EmailConfiguration WithHost(string host)
    {
        _host = host;
        return this;   // return this for chaining
    }
    public EmailConfiguration WithPort(int port)
    {
        _port = port;
        return this;
    }
    // ...
}
```

---

## 4.7 Expression Trees — Functions as Data

A lambda can be compiled as a delegate (executable code) or as an
*expression tree* (a data structure describing the code). Expression
trees are what allow LINQ-to-SQL to work: the `x => x.Age > 18` lambda
is not executed in .NET — it is inspected, translated to SQL, and the
SQL is executed by the database.

```csharp
// Compiled delegate — executes in .NET
Func<int, bool> filter = x => x > 5;
bool result = filter(10); // executes immediately

// Expression tree — represents the code as data
Expression<Func<int, bool>> expr = x => x > 5;
// expr is not a function — it is a tree of nodes:
// BinaryExpression(Parameter("x"), Constant(5), GreaterThan)

// EF Core uses this to translate to SQL
db.Orders.Where(o => o.Total > 100m)  // IQueryable — expression tree passed to EF
         .ToListAsync();               // EF translates the expression to SQL WHERE
```

You rarely write expression tree manipulation directly, but understanding
that `IQueryable<T>` operates on expression trees (not executed code)
explains why you must not call arbitrary methods inside a LINQ-to-EF
query — the database cannot execute C# methods. Chapter 15 §15.12 covers
this thoroughly.

---

## 4.8 Operator Overloading — Make Your Types Feel Native

Operators can be defined for your custom types, making them integrate
naturally with the language. This is appropriate for types that
represent a mathematical or domain concept:

```csharp
public readonly struct Money(decimal amount, string currency)
{
    public decimal Amount   { get; } = amount;
    public string  Currency { get; } = currency;

    public static Money operator +(Money a, Money b)
    {
        if (a.Currency != b.Currency)
            throw new InvalidOperationException($"Currency mismatch: {a.Currency} vs {b.Currency}");
        return new Money(a.Amount + b.Amount, a.Currency);
    }

    public static Money operator *(Money m, decimal factor) =>
        new Money(m.Amount * factor, m.Currency);

    public static bool operator ==(Money a, Money b) =>
        a.Amount == b.Amount && a.Currency == b.Currency;

    public static bool operator !=(Money a, Money b) => !(a == b);

    public override string ToString() => $"{Amount:F2} {Currency}";
}

// Now Money reads like a number
var price = new Money(9.99m, "EUR");
var tax   = new Money(0.85m, "EUR");
var total = price + tax;         // Money.operator+
var discounted = total * 0.9m;   // Money.operator*
Console.WriteLine(discounted);   // 9.76 EUR
```

---

## 4.9 Connecting Methods and Functions to the Rest of the Book

- **Ch 7 (LINQ)** — every LINQ operator (`Where`, `Select`, `GroupBy`)
  takes `Func<T, TResult>` arguments. Understanding lambdas and closures
  is prerequisite for understanding why LINQ behaves the way it does.
- **Ch 8 (Async)** — `async` methods return `Task<T>`, which is itself
  an object holding a continuation (a delegate). The `await` operator
  registers a callback on that continuation.
- **Ch 5 (OOP)** — interfaces define the *signatures* of methods. The
  relationship between a delegate (`Func<IFoo, IBar>`) and an interface
  method (`IFoo.GetBar()`) is deep.
- **Ch 10–11 (DI)** — factory delegates (`Func<IServiceProvider, T>`)
  are a common DI pattern. Extension methods on `IServiceCollection` are
  the primary DI registration mechanism.
- **Ch 29 (Design Patterns)** — Strategy, Observer, and Decorator all
  fundamentally use delegates or interfaces to represent replaceable
  behaviour.
