# Chapter 2 — Types: Value, Reference, Nullable, Records, Structs

## 2.1 The Type System at a Glance

```
System.Object
├── Value types (sealed, stored inline on stack or in-line in containing type)
│   ├── Primitives: bool, byte, sbyte, short, ushort, int, uint,
│   │               long, ulong, float, double, decimal, char
│   ├── Structs: DateTime, Guid, TimeSpan, Point, custom structs
│   └── Enums: enum Color { Red, Green, Blue }
│
└── Reference types (heap-allocated, reference stored)
    ├── class, interface, delegate, array
    └── record class (reference semantic records)
```

### Value vs. Reference — Implications

```csharp
// Value type: copy semantics
int a = 42;
int b = a;     // b is a copy
b = 100;
Console.WriteLine(a); // 42 — unchanged

// Reference type: reference semantics
var list1 = new List<int> { 1, 2, 3 };
var list2 = list1;   // both point to same object
list2.Add(4);
Console.WriteLine(list1.Count); // 4 — changed!

// Struct: copy semantics
var p1 = new Point(1, 2);
var p2 = p1;      // copy
p2 = p2 with { X = 99 };   // record struct syntax
Console.WriteLine(p1.X); // 1 — unchanged
```

---

## 2.2 Built-In Value Types

### Integer Types

```csharp
// Signed
sbyte sb = -128;          // 8-bit  [-128, 127]
short s  = -32_768;       // 16-bit
int   i  = 2_147_483_647; // 32-bit (most common)
long  l  = 9_223_372_036_854_775_807L; // 64-bit

// Unsigned
byte   b  = 255;           // 8-bit  [0, 255]
ushort us = 65_535;        // 16-bit
uint   ui = 4_294_967_295U;// 32-bit
ulong  ul = 18_446_744_073_709_551_615UL; // 64-bit

// Architecture-dependent
nint  ni  = nint.MaxValue;  // native int (IntPtr size)
nuint nui = nuint.MaxValue;

// Numeric literals
int hex  = 0xFF_AC;         // hex with _ separator
int bin  = 0b_1010_0011;    // binary literal
long sci = 1_000_000L;
```

### Floating Point

```csharp
float  f = 3.14f;          // 32-bit, ~7 digits precision
double d = 3.141592653589793; // 64-bit, ~15-17 digits (default)
decimal m = 3.14159265358979323846m; // 128-bit, 28-29 digits, no rounding errors

// Use decimal for money!
decimal price = 9.99m;
decimal tax   = 0.19m;
decimal total = price * (1 + tax); // 11.8881m — exact

// Special float/double values
double nan  = double.NaN;
double posInf = double.PositiveInfinity;
double negInf = double.NegativeInfinity;
Console.WriteLine(double.IsNaN(nan));           // True
Console.WriteLine(double.IsInfinity(posInf));   // True
```

### Boolean and Char

```csharp
bool flag = true;
bool computed = (5 > 3) && (2 != 3);

char c = 'A';
char unicode = '\u00E9';  // é
char escaped = '\n';       // newline
int codePoint = (int)c;   // 65
```

### Checked Arithmetic

```csharp
// By default, overflow silently wraps
int max = int.MaxValue;
int overflow = max + 1;  // -2147483648 (wraps!)

// checked throws OverflowException
checked
{
    int safe = max + 1;  // throws!
}

int result = checked(max + 1); // inline checked

// unchecked (explicit — overrides checked block)
unchecked
{
    int wrapped = max + 1; // -2147483648
}
```

---

## 2.3 Strings

Strings are **immutable reference types** with **value equality**.

```csharp
// Creation
string s1 = "Hello";
string s2 = "World";
string s3 = s1 + ", " + s2 + "!";    // concatenation (allocates new string)

// String interpolation (preferred)
string name = "Alice";
int age = 30;
string greeting = $"Hello, {name}! You are {age} years old.";

// Multi-line interpolation (C# 11+)
string json = $"""
    {{
        "name": "{name}",
        "age": {age}
    }}
    """;

// Verbatim string (no escape processing)
string path = @"C:\Users\Alice\Documents\file.txt";

// Raw string literal (C# 11+) — no escaping needed
string html = """
    <div class="container">
        <p>Hello, "World"!</p>
    </div>
    """;

// String equality
bool eq1 = s1 == "Hello";                         // true (value equality)
bool eq2 = string.Equals(s1, "hello", StringComparison.OrdinalIgnoreCase); // true

// String methods (immutable — all return new strings)
string upper   = s1.ToUpperInvariant();
string lower   = s1.ToLowerInvariant();
string trimmed = "  hello  ".Trim();
string[] parts = "a,b,c".Split(',');
string joined  = string.Join(", ", parts);
bool starts    = s1.StartsWith("He");
bool contains  = s1.Contains("ell");
int idx        = s1.IndexOf('l');
string sub     = s1.Substring(1, 3);  // "ell"
string sub2    = s1[1..4];            // "ell" (Range syntax)
string replaced= s1.Replace("Hello", "Hi");

// Span<char> for zero-allocation string work
ReadOnlySpan<char> span = s1.AsSpan();
ReadOnlySpan<char> slice = span[1..4]; // "ell" — no allocation

// StringBuilder for many concatenations
var sb = new System.Text.StringBuilder();
for (int i = 0; i < 1000; i++)
    sb.Append(i).Append(", ");
string result = sb.ToString();
```

### String Interning

```csharp
string a = "hello";
string b = "hello";
Console.WriteLine(ReferenceEquals(a, b)); // true — interned!

string c = new string("hello".ToCharArray());
Console.WriteLine(ReferenceEquals(a, c)); // false — not interned

string d = string.Intern(c);
Console.WriteLine(ReferenceEquals(a, d)); // true
```

---

## 2.4 Nullable Value Types (`T?`)

Every value type `T` can be made nullable as `T?` (which is `Nullable<T>`):

```csharp
int?    n1 = null;
double? n2 = 3.14;
bool?   n3 = null;

// Checking
bool hasValue = n1.HasValue;   // false
int value = n1.Value;          // InvalidOperationException if null!

// Safe access
int safe = n1.GetValueOrDefault();     // 0
int safe2 = n1.GetValueOrDefault(-1);  // -1
int safe3 = n1 ?? -1;                  // -1 (null coalescing)

// Pattern matching (preferred)
if (n1 is int actual)
{
    Console.WriteLine(actual);
}

// Lifted operators
int? a = 5;
int? b = null;
int? sum = a + b;    // null (null propagates)
bool? gt = a > 3;    // true
bool? lt = b < 10;   // null

// Nullable boxing
object boxed = n2;   // boxes as double, not Nullable<double>
object boxedNull = (int?)null; // boxes as null
```

---

## 2.5 Nullable Reference Types (NRT) — C# 8+

NRT is a **static analysis** feature — it doesn't change runtime behavior, but enables the compiler to warn about potential null dereferences.

### Enabling NRT

```xml
<!-- In .csproj -->
<Nullable>enable</Nullable>
```

Or per-file:

```csharp
#nullable enable    // turn on for this file
#nullable disable   // turn off
#nullable restore   // restore to project default
```

### The Four States

```csharp
// 1. Non-nullable reference (should never be null)
string name = "Alice";       // OK
string name2 = null;         // ⚠ Warning: Converting null to non-nullable

// 2. Nullable reference (may be null — must check before use)
string? maybeNull = null;    // OK
int len = maybeNull.Length;  // ⚠ Warning: Dereference of possibly null reference
int len2 = maybeNull?.Length ?? 0; // OK

// 3. Non-nullable out of flow (compiler tracks null state)
string? text = null;
if (SomeCondition()) text = "hello";
// After loop: text might still be null — compiler warns if you dereference
Console.WriteLine(text.Length); // ⚠ Warning

// 4. Null-forgiving operator (!) — you know better than the compiler
string? fromDb = GetFromDatabase();
string definitely = fromDb!;  // suppresses warning — use sparingly
```

### Nullable Annotations and Attributes

```csharp
using System.Diagnostics.CodeAnalysis;

// [MaybeNull] — return may be null even if type is non-nullable
[return: MaybeNull]
public T Find<T>(IEnumerable<T> source, Predicate<T> predicate) => ...;

// [NotNull] — out param guaranteed non-null when method returns true
public bool TryGetUser(int id, [NotNullWhen(true)] out User? user)
{
    user = _db.Find(id);
    return user is not null;
}

// Usage:
if (TryGetUser(42, out var user))
{
    Console.WriteLine(user.Name); // no warning — compiler knows user is not null
}

// [AllowNull] — non-nullable property accepts null setter
private string _name = "";
[AllowNull]
public string Name
{
    get => _name;
    set => _name = value ?? ""; // value may be null
}

// [DisallowNull] — nullable type must not receive null
public void SetLabel([DisallowNull] string? label)
{
    ArgumentNullException.ThrowIfNull(label);
    _label = label;
}

// [MemberNotNull] — method guarantees member is non-null after call
[MemberNotNull(nameof(_connection))]
private void InitConnection()
{
    _connection = new SqlConnection(_connectionString);
}

// [NotNullIfNotNull] — return non-null when param is non-null
[return: NotNullIfNotNull(nameof(value))]
public static string? Trim(string? value) => value?.Trim();
```

### Constructor & Initialization Patterns

```csharp
// Problem: required properties with NRT
public class User
{
    // Option 1: required keyword (C# 11+)
    public required string Name { get; init; }
    public required string Email { get; init; }

    // Option 2: constructor
    public User(string name, string email)
    {
        Name = name;
        Email = email;
    }
}

// Usage with required:
var user = new User { Name = "Alice", Email = "alice@example.com" };
// Compiler error if Name or Email omitted.

// Option 3: nullable with default
public class Config
{
    public string? ConnectionString { get; set; }  // nullable, may not be set
    public int Port { get; set; } = 5432;          // default value
}
```

### Null Guards

```csharp
// ArgumentNullException.ThrowIfNull (NET 6+)
void Process(string input)
{
    ArgumentNullException.ThrowIfNull(input);
    // input is guaranteed non-null here
}

// ArgumentException.ThrowIfNullOrEmpty / ThrowIfNullOrWhiteSpace (NET 7+)
void ProcessName(string name)
{
    ArgumentException.ThrowIfNullOrEmpty(name);
    ArgumentException.ThrowIfNullOrWhiteSpace(name);
}

// Null coalescing assignment (C# 8+)
string? cached = null;
cached ??= ComputeExpensive(); // only compute if null
```

---

## 2.6 Records

Records are **compiler-synthesized** immutable (or mutable) types with value-based equality.

### Record Class (reference type)

```csharp
// Positional record — concise syntax
public record Point(double X, double Y);

// The compiler generates:
// - Primary constructor: Point(double X, double Y)
// - Properties: public double X { get; init; }  public double Y { get; init; }
// - Equals/GetHashCode based on all properties
// - ToString(): "Point { X = 1, Y = 2 }"
// - Deconstruct: void Deconstruct(out double x, out double y)
// - With-expression support (Clone + init)

var p1 = new Point(1, 2);
var p2 = new Point(1, 2);
Console.WriteLine(p1 == p2);  // True (value equality!)
Console.WriteLine(ReferenceEquals(p1, p2)); // False

// With-expression (non-destructive mutation)
var p3 = p1 with { X = 99 };
Console.WriteLine(p1);  // Point { X = 1, Y = 2 }
Console.WriteLine(p3);  // Point { X = 99, Y = 2 }

// Deconstruction
var (x, y) = p1;
Console.WriteLine($"{x}, {y}");  // 1, 2
```

### Records with Additional Members

```csharp
public record Order(
    Guid Id,
    string CustomerId,
    IReadOnlyList<OrderLine> Lines,
    DateTime CreatedAt)
{
    // Computed property (not part of equality)
    public decimal Total => Lines.Sum(l => l.Price * l.Quantity);

    // Custom validation in primary constructor body
    public Order
    {
        ArgumentException.ThrowIfNullOrEmpty(CustomerId);
        if (Lines.Count == 0) throw new ArgumentException("Order must have lines.");
        // Properties are already set at this point
    }

    // Additional constructor
    public Order(string customerId, IReadOnlyList<OrderLine> lines)
        : this(Guid.NewGuid(), customerId, lines, DateTime.UtcNow) { }
}

public record OrderLine(string Sku, int Quantity, decimal Price);
```

### Record Struct

```csharp
// record struct = value type + record features
public record struct Vector3(float X, float Y, float Z);

var v1 = new Vector3(1, 0, 0);
var v2 = v1 with { Y = 1 };

// readonly record struct = immutable record struct (recommended)
public readonly record struct Color(byte R, byte G, byte B)
{
    public static readonly Color Red   = new(255, 0, 0);
    public static readonly Color Green = new(0, 255, 0);
    public static readonly Color Blue  = new(0, 0, 255);

    public Color Mix(Color other) => new(
        (byte)((R + other.R) / 2),
        (byte)((G + other.G) / 2),
        (byte)((B + other.B) / 2));

    public override string ToString() => $"#{R:X2}{G:X2}{B:X2}";
}
```

### Record Inheritance

```csharp
public abstract record Shape(string Color);
public record Circle(string Color, double Radius) : Shape(Color);
public record Rectangle(string Color, double Width, double Height) : Shape(Color);

// Equality is type-aware
Shape c1 = new Circle("red", 5);
Shape c2 = new Circle("red", 5);
Console.WriteLine(c1 == c2); // True

Shape r = new Rectangle("red", 5, 5);
Console.WriteLine(c1 == r); // False — different runtime types
```

---

## 2.7 Structs

Structs are value types. Use them for small, short-lived, frequently copied data.

### When to Use Structs

- Small (≤16 bytes recommended, ≤32 bytes acceptable)
- Logically a single value (Point, Color, Money, Temperature)
- Immutable (readonly struct)
- No inheritance needed
- Not boxed often

```csharp
// Basic struct
public struct Point2D
{
    public float X;
    public float Y;

    public Point2D(float x, float y) { X = x; Y = y; }
    public float Distance(Point2D other)
        => MathF.Sqrt(MathF.Pow(X - other.X, 2) + MathF.Pow(Y - other.Y, 2));
}

// readonly struct — all fields must be readonly, methods don't copy
public readonly struct Temperature
{
    public double Celsius { get; }
    public double Fahrenheit => Celsius * 9 / 5 + 32;
    public double Kelvin => Celsius + 273.15;

    public Temperature(double celsius) => Celsius = celsius;

    public static Temperature FromFahrenheit(double f) => new((f - 32) * 5 / 9);
    public static Temperature FromKelvin(double k) => new(k - 273.15);

    public override string ToString() => $"{Celsius:F1}°C";

    // Operators
    public static Temperature operator +(Temperature a, Temperature b)
        => new(a.Celsius + b.Celsius);
    public static bool operator >(Temperature a, Temperature b)
        => a.Celsius > b.Celsius;
    public static bool operator <(Temperature a, Temperature b)
        => a.Celsius < b.Celsius;
}
```

### `ref struct` — Stack-Only

```csharp
// ref struct cannot be boxed, stored on heap, or used in async methods
// Used for: Span<T>, ReadOnlySpan<T>, custom stack-allocated types
public ref struct BufferWriter
{
    private Span<byte> _buffer;
    private int _position;

    public BufferWriter(Span<byte> buffer)
    {
        _buffer = buffer;
        _position = 0;
    }

    public void Write(byte value) => _buffer[_position++] = value;
    public int Written => _position;
}

// Usage:
Span<byte> stack = stackalloc byte[256];
var writer = new BufferWriter(stack);
writer.Write(0xFF);
```

### Struct Interfaces (C# 13+: allows default members)

```csharp
public interface IAddable<T> where T : IAddable<T>
{
    static abstract T operator +(T a, T b);
}

public readonly struct Meters : IAddable<Meters>
{
    public double Value { get; }
    public Meters(double value) => Value = value;
    public static Meters operator +(Meters a, Meters b) => new(a.Value + b.Value);
    public override string ToString() => $"{Value}m";
}

// Generic method using static abstract member
T Sum<T>(IEnumerable<T> items, T initial) where T : IAddable<T>
    => items.Aggregate(initial, (acc, x) => acc + x);
```

---

## 2.8 Enums

```csharp
// Basic enum (backed by int by default)
public enum Direction { North, South, East, West }

// Explicit backing type
public enum StatusCode : byte { Ok = 200, NotFound = 404, Error = 500 }

// Flags enum (bitfield)
[Flags]
public enum Permission
{
    None    = 0,
    Read    = 1 << 0,  // 1
    Write   = 1 << 1,  // 2
    Execute = 1 << 2,  // 4
    Admin   = Read | Write | Execute  // 7
}

// Usage
var perm = Permission.Read | Permission.Write;
bool canRead  = perm.HasFlag(Permission.Read);   // true
bool canExec  = perm.HasFlag(Permission.Execute); // false
var allPerms  = Permission.Admin;
Console.WriteLine(perm);       // "Read, Write"
Console.WriteLine(allPerms);   // "Admin"

// Parsing
Direction d = Enum.Parse<Direction>("North");
bool ok = Enum.TryParse<Direction>("South", out var dir);
string[] names = Enum.GetNames<Direction>();
Direction[] values = Enum.GetValues<Direction>();
```

### Enum Extensions Pattern

```csharp
public static class DirectionExtensions
{
    public static Direction Opposite(this Direction d) => d switch
    {
        Direction.North => Direction.South,
        Direction.South => Direction.North,
        Direction.East  => Direction.West,
        Direction.West  => Direction.East,
        _ => throw new ArgumentOutOfRangeException(nameof(d))
    };

    public static (int dx, int dy) ToVector(this Direction d) => d switch
    {
        Direction.North => (0, 1),
        Direction.South => (0, -1),
        Direction.East  => (1, 0),
        Direction.West  => (-1, 0),
        _ => throw new ArgumentOutOfRangeException(nameof(d))
    };
}
```

---

## 2.9 Generics

### Generic Classes and Methods

```csharp
// Generic class
public class Repository<T> where T : class, IEntity
{
    private readonly List<T> _store = new();

    public void Add(T item)        => _store.Add(item);
    public T?   Get(int id)        => _store.FirstOrDefault(x => x.Id == id);
    public IReadOnlyList<T> GetAll() => _store.AsReadOnly();
}

// Generic method
public static T? MaxBy<T, TKey>(IEnumerable<T> source, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
{
    T? best = default;
    TKey? bestKey = default;
    bool first = true;
    foreach (var item in source)
    {
        var key = keySelector(item);
        if (first || key.CompareTo(bestKey!) > 0)
        {
            best = item;
            bestKey = key;
            first = false;
        }
    }
    return best;
}
```

### Constraints

```csharp
where T : struct           // value type
where T : class            // reference type
where T : class?           // nullable reference type
where T : notnull          // non-nullable (value type or non-nullable ref)
where T : unmanaged        // unmanaged value type (can use in Span<T>, stackalloc)
where T : new()            // has parameterless constructor
where T : SomeBaseClass    // inherits from base
where T : ISomeInterface   // implements interface
where T : ISomeInterface, new()  // multiple constraints

// C# 11: static abstract members in interfaces
where T : INumber<T>       // numeric type (System.Numerics)
```

### Common Generic Patterns

```csharp
// Result<T> monad pattern
public readonly record struct Result<T>
{
    public T? Value { get; }
    public string? Error { get; }
    public bool IsSuccess => Error is null;

    private Result(T value) { Value = value; Error = null; }
    private Result(string error) { Value = default; Error = error; }

    public static Result<T> Ok(T value)       => new(value);
    public static Result<T> Fail(string error) => new(error);

    public Result<TOut> Map<TOut>(Func<T, TOut> f)
        => IsSuccess ? Result<TOut>.Ok(f(Value!)) : Result<TOut>.Fail(Error!);

    public Result<TOut> Bind<TOut>(Func<T, Result<TOut>> f)
        => IsSuccess ? f(Value!) : Result<TOut>.Fail(Error!);

    public T GetOrThrow() => IsSuccess ? Value! : throw new InvalidOperationException(Error);
    public T GetOrDefault(T defaultValue) => IsSuccess ? Value! : defaultValue;
}

// Usage
Result<int> Parse(string s)
    => int.TryParse(s, out var n) ? Result<int>.Ok(n) : Result<int>.Fail($"'{s}' is not a number");

var result = Parse("42")
    .Map(n => n * 2)
    .Bind(n => n > 50 ? Result<int>.Ok(n) : Result<int>.Fail("Too small"));
```

### Covariance and Contravariance

```csharp
// Covariant (out T) — can return T as more base type
// IEnumerable<Derived> is assignable to IEnumerable<Base>
IEnumerable<string> strings = new List<string> { "a", "b" };
IEnumerable<object> objects = strings;  // OK — covariant

// Custom covariant interface
public interface IProducer<out T>
{
    T Produce();
}

// Contravariant (in T) — can accept T as more derived type
// IComparer<Base> is assignable to IComparer<Derived>
IComparer<object> objectComp = Comparer<object>.Default;
IComparer<string> stringComp = objectComp;  // OK — contravariant

// Custom contravariant interface
public interface IConsumer<in T>
{
    void Consume(T item);
}
```

---

## 2.10 Type Aliases (C# 12+)

```csharp
// File-scoped type alias
using Point = (double X, double Y);
using Matrix = double[][];
using UserId = System.Guid;
using Callback = System.Action<string, System.Threading.CancellationToken>;

// Usage
Point origin = (0, 0);
UserId id = Guid.NewGuid();
```

---

## 2.11 Tuple Types

```csharp
// Named tuple (ValueTuple<T1, T2, ...>)
(string Name, int Age) person = ("Alice", 30);
Console.WriteLine(person.Name);  // Alice
Console.WriteLine(person.Age);   // 30

// Return multiple values
(string, bool) TryParse(string s)
{
    bool ok = int.TryParse(s, out _);
    return (s, ok);
}

// Tuple deconstruction
var (name, age) = person;
var (text, success) = TryParse("42");

// Discard unused element
var (_, isOk) = TryParse("xyz");

// Tuple equality
var t1 = (1, "hello");
var t2 = (1, "hello");
Console.WriteLine(t1 == t2);  // True

// Swap idiom
int a = 1, b = 2;
(a, b) = (b, a);  // a=2, b=1
```

---

## 2.12 `dynamic` and `object`

```csharp
// object — everything derives from it, requires casting
object o = 42;
int i = (int)o;       // explicit cast
int j = o as int? ?? 0; // as + null coalesce

// dynamic — bypasses compile-time type checking, resolved at runtime
dynamic d = 42;
d = "now I'm a string"; // no compile error
Console.WriteLine(d.Length); // 16 — works at runtime (IronPython style)

// Use case: COM interop, ExpandoObject, working with JSON in dynamic context
dynamic expando = new System.Dynamic.ExpandoObject();
expando.Name = "Alice";
expando.Age = 30;
Console.WriteLine(expando.Name);
```

> **Rider tip:** For NRT, enable *Inspect Code* (`Ctrl+Alt+Shift+I` / `⌘⌥⇧I`) and run *Null value analysis* inspection. Rider shows squiggles for potential null dereferences even beyond what the compiler reports.

> **VS tip:** *Analyze → Run Code Analysis on Solution* → *Nullable reference types* rule set catches all NRT issues project-wide.

