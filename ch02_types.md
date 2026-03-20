# Chapter 2 — Types: Value, Reference, Nullable, Records, Structs

> C# is a statically typed language. Every variable, parameter, field,
> and return value has a type known at compile time. The type system is
> not bureaucracy — it is a machine that catches entire categories of
> bugs before your program ever runs. This chapter explains the type
> system from the ground up: what the two fundamental categories are,
> why they behave differently, and the modern C# features built on top
> of them. Everything in later chapters — collections, async, DI, EF
> Core — is built from these types.

---

## 2.1 The Two Fundamental Categories: Value Types and Reference Types

Every type in C# is either a value type or a reference type. This is
the most important distinction in the type system and affects how memory
is allocated, how assignment works, and how equality is defined.

### Value Types — Copy Semantics

A value type stores its data *directly* in the variable. When you assign
a value type to another variable, the data is copied. The two variables
are independent — changing one does not change the other.

Value types are either stored on the stack (when they are local
variables or method parameters) or *inline* inside the containing object
on the heap (when they are fields of a class). There is no separate heap
allocation for a value type. This is why they are fast to create and
require no garbage collection.

```csharp
int a = 42;
int b = a;    // b receives a COPY of 42
b = 100;
Console.WriteLine(a); // 42 — a was not changed
```

Built-in value types: `bool`, `byte`, `sbyte`, `short`, `ushort`, `int`,
`uint`, `long`, `ulong`, `float`, `double`, `decimal`, `char`. User-
defined value types are `struct` and `enum`.

### Reference Types — Reference Semantics

A reference type stores a *reference* (essentially a pointer) in the
variable. The actual data lives on the heap. When you assign a reference
type to another variable, you copy the reference — both variables now
point to the same object on the heap. Changing the object through one
variable changes it for all variables that reference the same object.

```csharp
var list1 = new List<int> { 1, 2, 3 };
var list2 = list1;    // list2 holds a COPY of the reference
                      // both point to the same List object on the heap
list2.Add(4);
Console.WriteLine(list1.Count); // 4 — the shared object was modified
```

Built-in reference types: `class`, `interface`, `delegate`, `array`,
`string`. User-defined reference types are `class` and `record class`.

### Why This Distinction Matters in Practice

Understanding this prevents three common bug categories:

**Bug 1 — Accidental mutation through shared references:**
```csharp
// Passing a list to a method lets the method modify the ORIGINAL list
void AddItem(List<string> items) => items.Add("extra");
var myList = new List<string> { "one", "two" };
AddItem(myList);
Console.WriteLine(myList.Count); // 3 — the original was modified
```

**Bug 2 — Assuming two objects with the same data are equal:**
```csharp
var p1 = new Point { X = 1, Y = 2 };  // class (reference type)
var p2 = new Point { X = 1, Y = 2 };
Console.WriteLine(p1 == p2); // False — they are different objects
                              // Records fix this: see §2.6
```

**Bug 3 — Expecting value-type fields to initialise independently:**
```csharp
// Structs are copied. Classes are referenced.
DateTime[] schedule = new DateTime[5]; // DateTime is a value type
schedule[0] = DateTime.Now;            // fine — direct access
// All five slots are zero-initialised (DateTime.MinValue) independently
```

```
The Type Hierarchy:

System.Object
├── Value types
│   ├── Primitives: bool, byte, short, int, long, float, double, decimal, char
│   ├── struct: DateTime, Guid, TimeSpan, Vector3, custom structs
│   └── enum: Color, Status, Direction
│
└── Reference types
    ├── class: string, List<T>, Dictionary<K,V>, custom classes
    ├── interface: IDisposable, IEnumerable<T>
    ├── delegate: Action, Func<T>, EventHandler
    ├── array: int[], string[][]
    └── record class: immutable data types (§2.6)
```

---

## 2.2 Built-In Value Types — Choosing the Right One

The choice of numeric type is not arbitrary. Using the wrong type wastes
memory, causes overflow bugs, or introduces floating-point precision
errors. Here is the practical guide.

### Integer Types — Signed and Unsigned

```csharp
// Signed integers — can hold negative values
sbyte  value = -100;          // 8-bit  [-128, 127]          — rare, mainly for protocols
short  small = -30_000;       // 16-bit [-32,768, 32,767]    — rare
int    count = 2_000_000;     // 32-bit [-2.1B, 2.1B]        — the default integer type
long   big   = 9_000_000_000L;// 64-bit [-9.2E18, 9.2E18]   — for large IDs, timestamps

// Unsigned integers — no negatives, doubles the positive range
byte   b  = 200;              // 8-bit  [0, 255]             — common for binary data
ushort us = 60_000;           // 16-bit [0, 65,535]          — port numbers
uint   ui = 4_000_000_000U;   // 32-bit [0, 4.3B]
ulong  ul = 18_000_000_000_000_000_000UL; // 64-bit [0, 1.8E19]

// Architecture-dependent (pointer size: 32-bit on x86, 64-bit on x64)
nint   ni  = 42;              // native int — for interop with native APIs
nuint  nui = 42;
```

The `_` separator in numeric literals is purely cosmetic — the compiler
ignores it. Use it to make large numbers readable: `1_000_000` instead of
`1000000`.

Use `int` for general-purpose counting. Use `long` for IDs in databases
where integer overflow is a real risk. Use `byte` for raw data, network
protocols, and binary file parsing.

### Floating-Point Types — When Precision Matters

```csharp
float   f = 3.14f;            // 32-bit, ~7 significant digits
double  d = 3.141592653589793;// 64-bit, ~15-17 digits — the default for science/math
decimal m = 9.99m;            // 128-bit, 28-29 digits, BASE 10 arithmetic

// The critical rule: use decimal for money
decimal price = 9.99m;
decimal tax   = 0.0875m;
decimal total = price * (1 + tax);  // 10.867125m — mathematically exact

// Never use float or double for money
double wrong = 0.1 + 0.2;
Console.WriteLine(wrong); // 0.30000000000000004 — floating-point rounding error
decimal right = 0.1m + 0.2m;
Console.WriteLine(right); // 0.3 — exact
```

The reason `double` gets 0.3 wrong: `double` stores numbers in binary
fractions. 0.1 has no exact binary representation (just like 1/3 has no
exact decimal representation). `decimal` uses base-10 arithmetic, so
0.1, 0.2, and 0.3 are representable exactly.

### Boolean and Character

```csharp
bool isReady = true;
bool computed = (age >= 18) && !isBlocked;  // &&, ||, ! are short-circuit operators

char letter  = 'A';
char unicode = '\u00E9';    // é — any Unicode code point
char newline = '\n';        // escape sequences
int  code    = (int)letter; // 65 — the Unicode code point
```

`bool` values have only two states. Never use `int` as a boolean — the
compiler cannot help you spot a bug where `1` is passed where `true` was
expected. Strongly-typed is always better.

---

## 2.3 Strings — Reference Type With Value-Like Behaviour

`string` is a reference type (it lives on the heap) but it behaves like
a value type in one important way: it is *immutable*. Once created, a
string cannot change. Every operation that appears to modify a string
actually creates a new one.

```csharp
string s1 = "hello";
string s2 = s1.ToUpper();   // creates a new string "HELLO"
                             // s1 is still "hello"
Console.WriteLine(s1);      // hello
Console.WriteLine(s2);      // HELLO
```

### String Equality — Reference Vs. Content

Because strings are immutable, the runtime *interns* literal strings —
two identical string literals may share the same memory. This means `==`
on strings checks *content equality* by default (the `==` operator is
overloaded), unlike most reference types where `==` checks reference
equality.

```csharp
string a = "hello";
string b = "hello";
Console.WriteLine(a == b);              // True — content equality
Console.WriteLine(object.ReferenceEquals(a, b)); // True — same interned instance

string c = new string("hello".ToCharArray()); // forces a new allocation
Console.WriteLine(a == c);              // True  — still content equality
Console.WriteLine(object.ReferenceEquals(a, c)); // False — different objects
```

### String Concatenation and StringBuilder

Concatenation with `+` creates a new string for each operation. In a
loop, this generates O(n²) allocations:

```csharp
// Bad: O(n²) allocations for large n
string result = "";
for (int i = 0; i < 10_000; i++)
    result += i.ToString();   // creates 10,000 intermediate strings

// Good: StringBuilder uses a resizable buffer
var sb = new System.Text.StringBuilder();
for (int i = 0; i < 10_000; i++)
    sb.Append(i);
string result2 = sb.ToString();   // one final string

// Even better for fixed formats: string interpolation (compiler-optimised)
string name = "Alice";
int age = 30;
string msg = $"Name: {name}, Age: {age}";  // compiled efficiently
```

### Raw String Literals (C# 11+)

Raw string literals start and end with three or more quote characters.
They preserve whitespace and do not require escape sequences:

```csharp
string json = """
    {
        "name": "Alice",
        "path": "C:\\Users\\Alice"
    }
    """;
// No escape needed for backslashes or quotes inside
```

---

## 2.4 Nullable Value Types (`T?`) — Making the Absence of a Value Explicit

Before C# 2, if you had a database integer column that could be NULL,
you had no good way to represent that in C#. Developers used sentinel
values (`-1`, `0`, `int.MinValue`) as stand-ins for "no value", leading
to bugs where a valid negative number was mistaken for "missing".

`Nullable<T>` (written `T?` for any value type `T`) solves this. It is a
struct that wraps a value type and adds a boolean `HasValue` flag. A
`null` nullable means "this value is absent" — there is no ambiguity.

```csharp
int? age = null;         // no age provided yet
age = 25;                // age is now 25

// Check before using
if (age.HasValue)
    Console.WriteLine($"Age: {age.Value}");

// Null-coalescing operator: provide a default if null
int actualAge = age ?? 0;

// Null-conditional: safe access without explicit null check
int? length = name?.Length;  // null if name is null, length otherwise

// Pattern matching (cleaner than HasValue)
if (age is int a)
    Console.WriteLine($"Age: {a}");
```

Nullable value types appear everywhere database values are mapped to C#:
an `int?` maps to an SQL `INT NULL` column. An `DateTime?` maps to
`DATETIME NULL`. Never use sentinel values for absent data.

---

## 2.5 Nullable Reference Types (NRT) — Eliminating the Billion-Dollar Mistake

Tony Hoare, who invented null references, called it his "billion-dollar
mistake". `NullReferenceException` is one of the most common runtime
errors in C# — a crash that happens when you call a method on a
reference that turned out to be `null` at runtime.

Nullable Reference Types (C# 8+, enabled with `<Nullable>enable</Nullable>`)
move null safety to compile time. The compiler analyses your code's null
flows and warns you before the program ever runs.

### The Mental Model: Annotations Carry Meaning

With NRT enabled:
- `string` means "this will never be null — I guarantee it"
- `string?` means "this might be null — you must check before using it"

Without NRT enabled, `string` is ambiguous — the compiler cannot tell
you which variables are safe to dereference. With NRT, the annotation
*is* the documentation, enforced by the compiler.

```csharp
// NRT enabled: <Nullable>enable</Nullable>

string name = "Alice";    // guaranteed non-null
string? title = null;     // explicitly nullable

// The compiler prevents dereferencing possibly-null values:
int len1 = name.Length;   // fine — name cannot be null
int len2 = title.Length;  // ERROR: title might be null — CS8602

// Fix: check first
if (title is not null)
    int len3 = title.Length;  // fine inside the null check

// Or use null-coalescing
int len4 = title?.Length ?? 0;
```

### The Three Operators for Working With Nullable References

```csharp
// ?. (null-conditional) — safe member access
string? result = user?.Address?.City;  // null if user or Address is null

// ?? (null-coalescing) — provide a default
string display = result ?? "Unknown city";

// ??= (null-coalescing assignment) — assign only if null
user ??= new User();  // equivalent to: if (user is null) user = new User();
```

### Suppression and `!`

The `!` (null-forgiving) operator tells the compiler "I know this looks
nullable but trust me, it is not null here". Use it only when you have
external knowledge the compiler cannot see:

```csharp
// Entity Framework navigation properties are set by EF, not the constructor
public class Order
{
    public Customer Customer { get; set; } = null!;  // EF sets this before you use it
}
```

The `= null!` pattern is the standard way to handle non-nullable required
reference type properties in classes that are initialised by an external
framework (EF Core, model binding, deserialisers). Do not use `!` to
suppress genuine null warnings — fix the code instead.

---

## 2.6 Records — Immutable Data With Value Equality

Regular classes have reference equality: two different instances with the
same data are not considered equal unless you override `Equals` and
`GetHashCode`. Writing this boilerplate is tedious, and missing it causes
subtle bugs when records are used as dictionary keys or in `HashSet<T>`.

Records (C# 9+) are types declared with `record` that automatically
provide:
- **Value equality**: two records with the same property values are equal
- **`ToString()`**: a formatted representation showing all property values
- **Non-destructive mutation** via `with` expressions
- **Deconstruction** into tuples

Records are the preferred type for data transfer objects, domain events,
configuration objects, and any type whose identity is determined by its
content rather than its object identity.

```csharp
// record class — reference type with value equality
public record Person(string FirstName, string LastName, int Age);

var alice1 = new Person("Alice", "Smith", 30);
var alice2 = new Person("Alice", "Smith", 30);

Console.WriteLine(alice1 == alice2);     // True — value equality (not reference!)
Console.WriteLine(alice1.ToString());    // Person { FirstName = Alice, LastName = Smith, Age = 30 }

// Non-destructive mutation: create a copy with one field changed
var olderAlice = alice1 with { Age = 31 };
Console.WriteLine(alice1.Age);           // 30 — original unchanged
Console.WriteLine(olderAlice.Age);       // 31 — new record
```

### Positional vs. Nominal Records

```csharp
// Positional syntax (parameters → properties + constructor + deconstruct)
public record Point(double X, double Y);

// Nominal syntax — like a class, but with record benefits
public record Address
{
    public required string Street { get; init; }
    public required string City   { get; init; }
    public string? PostCode        { get; init; }
}
```

### `init` — Set-Once Properties

The `init` accessor allows a property to be set only in an object
initialiser or constructor, never afterwards. This provides compile-time
immutability without requiring a full record:

```csharp
public class Order
{
    public int    Id          { get; init; }  // set once, never changed
    public string CustomerId  { get; init; } = "";
    public Status Status      { get; set; }  // mutable
}

var order = new Order { Id = 1, CustomerId = "C001" };
order.Status = Status.Processing;  // fine — Status has set
order.Id = 2;                       // ERROR — Id has init, not set
```

---

## 2.7 Structs — Value Types You Define Yourself

A `struct` is a value type you define. It is stored inline (on the stack
or in the containing object) — no heap allocation, no GC pressure. Use
structs for small, immutable data blobs where performance matters and
the data is logically a single value.

```csharp
// A good candidate for struct: small, logically atomic, immutable
public readonly struct Money
{
    public decimal Amount   { get; }
    public string  Currency { get; }

    public Money(decimal amount, string currency)
    {
        if (amount < 0) throw new ArgumentOutOfRangeException(nameof(amount));
        Amount   = amount;
        Currency = currency ?? throw new ArgumentNullException(nameof(currency));
    }

    // Structs should override Equals and GetHashCode for correctness
    public override bool Equals(object? obj) =>
        obj is Money m && m.Amount == Amount && m.Currency == Currency;
    public override int GetHashCode() => HashCode.Combine(Amount, Currency);
    public override string ToString() => $"{Amount} {Currency}";

    public static Money operator +(Money a, Money b)
    {
        if (a.Currency != b.Currency)
            throw new InvalidOperationException("Currency mismatch");
        return new Money(a.Amount + b.Amount, a.Currency);
    }
}

var price = new Money(9.99m, "EUR");
var tax   = new Money(0.85m, "EUR");
var total = price + tax;  // 10.84 EUR — no heap allocation
```

### `record struct` — Value Type With Record Benefits

C# 10+ introduces `record struct`: a value type with auto-generated value
equality and `with` expressions.

```csharp
public record struct Point(double X, double Y);

var p1 = new Point(1.0, 2.0);
var p2 = new Point(1.0, 2.0);
Console.WriteLine(p1 == p2);          // True — value equality (struct default)
var p3 = p1 with { X = 5.0 };        // non-destructive mutation
```

### When to Use Struct vs Class

| Use `struct` when | Use `class` when |
|---|---|
| Data is small (16 bytes or less) | Data is large (many fields) |
| Data is logically a single value | Object has identity beyond its data |
| Allocation-sensitive hot path | Shared across many places |
| Immutable | Mutable with complex state |
| `Money`, `Coordinate`, `Color`, `Size` | `Order`, `User`, `Connection`, `Repository` |

---

## 2.8 Enums — Named Constants With a Type

An enum defines a set of named integer constants. The name is the
documentation — it makes the intent of a value unmistakably clear.

```csharp
// Without enum: a boolean parameter that no one understands at the call site
ProcessFile(true, false);    // what do these mean?

// With enum: the call site is self-documenting
public enum CompressionMode { None, Gzip, Brotli, Deflate }
public enum EncryptionMode  { None, Aes128, Aes256 }

ProcessFile(CompressionMode.Gzip, EncryptionMode.Aes256);  // clear!
```

```csharp
// Flags enum: combinable values — use powers of 2
[Flags]
public enum Permissions
{
    None    = 0,
    Read    = 1 << 0,  // 1
    Write   = 1 << 1,  // 2
    Execute = 1 << 2,  // 4
    All     = Read | Write | Execute
}

var perms = Permissions.Read | Permissions.Write;
Console.WriteLine(perms);                            // Read, Write
Console.WriteLine(perms.HasFlag(Permissions.Write)); // True
Console.WriteLine(perms.HasFlag(Permissions.Execute)); // False
```

```csharp
// Switch over enum — pattern matching ensures exhaustiveness (see Ch 3)
string Describe(CompressionMode mode) => mode switch
{
    CompressionMode.None    => "uncompressed",
    CompressionMode.Gzip    => "gzip compressed",
    CompressionMode.Brotli  => "brotli compressed",
    CompressionMode.Deflate => "deflate compressed",
    _ => throw new ArgumentOutOfRangeException(nameof(mode))
};
```

---

## 2.9 Generics — One Algorithm, Any Type

Before generics, collections worked by storing everything as `object`,
requiring casts on retrieval and losing type safety entirely. Generics
allow you to write code parametrised over a type that is filled in at
compile time, giving you both type safety and performance (no boxing for
value types).

```csharp
// Non-generic: loses type information, requires cast, boxes value types
ArrayList list = new ArrayList();
list.Add(42);
int n = (int)list[0];   // cast required, easy to get wrong

// Generic: type-safe, no boxing, no cast
List<int> typed = new List<int>();
typed.Add(42);
int m = typed[0];       // no cast — compiler knows it is int
```

### Defining Generic Types

```csharp
// Generic class: T is a type parameter — filled in by the caller
public class Repository<T> where T : class, new()
{
    private readonly List<T> _items = new();

    public void Add(T item) => _items.Add(item);
    public T? Find(Func<T, bool> predicate) => _items.FirstOrDefault(predicate);
    public IReadOnlyList<T> GetAll() => _items.AsReadOnly();
}

var orders = new Repository<Order>();
orders.Add(new Order());
Order? first = orders.Find(o => o.Status == Status.Pending);
```

### Generic Constraints

Constraints tell the compiler what operations are available on `T`:

```csharp
where T : class        // T must be a reference type
where T : struct       // T must be a value type
where T : new()        // T must have a parameterless constructor
where T : SomeClass    // T must inherit from SomeClass
where T : IComparable<T>  // T must implement the interface
where T : notnull      // T cannot be null (value type or non-nullable reference)
```

---

## 2.10 Type Aliases, Tuple Types, and Primary Constructors

### Type Aliases (C# 12+)

A type alias gives a familiar type a more meaningful name in context:

```csharp
using OrderId     = System.Guid;
using CustomerId  = System.Guid;
using Price       = System.Decimal;

// Now these reads like domain language
OrderId    orderId    = Guid.NewGuid();
CustomerId customerId = Guid.NewGuid();
Price      total      = 99.99m;
```

This is documentation that the compiler sees. A method that takes
`CustomerId` will not accidentally accept an `OrderId` — they are both
`Guid` but the alias makes the intent explicit.

### Tuple Types

Tuples let you return multiple values from a method without defining a
class or struct:

```csharp
// Named tuple return type
public (bool Success, string? ErrorMessage) TryParse(string input)
{
    if (string.IsNullOrWhiteSpace(input))
        return (false, "Input was empty");
    return (true, null);
}

var (ok, err) = TryParse("");
if (!ok) Console.WriteLine(err);  // Input was empty
```

Prefer named tuples (with element names) over positional tuples
(`(bool, string?)`) — the names are documentation and prevent mixing up
the meaning of position 0 vs position 1.

### Primary Constructors (C# 12+)

Primary constructors allow constructor parameters directly in the class
or struct declaration, eliminating boilerplate for types that just store
their constructor arguments:

```csharp
// Traditional: field declarations + constructor assignment
public class PaymentService
{
    private readonly IPaymentGateway _gateway;
    private readonly ILogger<PaymentService> _logger;

    public PaymentService(IPaymentGateway gateway, ILogger<PaymentService> logger)
    {
        _gateway = gateway;
        _logger  = logger;
    }
}

// Primary constructor: parameters are captured automatically
public class PaymentService(IPaymentGateway gateway, ILogger<PaymentService> logger)
{
    public async Task<Result> ChargeAsync(decimal amount, CancellationToken ct)
    {
        _logger.LogInformation("Charging {Amount}", amount);
        return await gateway.ChargeAsync(amount, ct);  // parameters in scope
    }
}
```

Primary constructors are the preferred style in .NET 9 code for
dependency-injected services. They reduce noise and make the dependency
list visible in the class declaration line.

---

## 2.11 `dynamic` — Escape Hatch With a Cost

`dynamic` defers type checking to runtime. The compiler will accept any
operation on a `dynamic` value without checking whether it is valid. The
runtime will throw `RuntimeBinderException` if the operation fails.

Use `dynamic` only for COM interop, scripting hosts, or consuming APIs
that genuinely have no types available. In application code, `dynamic`
eliminates the compiler's ability to catch errors and degrades
performance (every operation involves reflection-like dispatch).

```csharp
// Legitimate use: interacting with COM (Office Automation)
dynamic excel = Activator.CreateInstance(Type.GetTypeFromProgID("Excel.Application")!);
excel.Visible = true;

// Never use dynamic to avoid writing proper types:
dynamic data = GetSomeData();   // bad — you have given up type safety
data.DoSomething();             // the compiler cannot verify this
```

---

## 2.12 Connecting Types to the Rest of the Book

Every chapter that follows uses types. Here is how this chapter connects:

- **Ch 3 (Control Flow)** — pattern matching switches on types and
  deconstructs records and tuples.
- **Ch 4 (Methods)** — generic type parameters, delegates, and
  `Func<T>` / `Action<T>` all build on generics.
- **Ch 5 (OOP)** — interfaces, inheritance, and covariance are all
  type-system features.
- **Ch 6 (Principles)** — "Make Illegal States Unrepresentable" and
  "Domain Primitives" use value types, records, and `init` properties.
- **Ch 7 (Collections)** — `List<T>`, `Dictionary<K,V>` are all generic
  types from the BCL.
- **Ch 8 (Async)** — `Task<T>`, `ValueTask<T>`, `IAsyncEnumerable<T>`
  are all generic types.
- **Ch 15a (SQL)** — nullable value types (`int?`, `DateTime?`) map
  directly to SQL nullable columns.
- **Ch 26 (Memory)** — the value-vs-reference distinction is exactly
  the stack-vs-heap allocation distinction.
