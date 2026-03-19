# Chapter 5 — OOP: Classes, Interfaces, Inheritance & Polymorphism

## 5.1 Classes — Full Anatomy

```csharp
// Complete class with all common members
public class BankAccount
{
    // ── Static members ────────────────────────────────────────────────
    private static int _nextId = 0;
    public static int TotalAccounts => _nextId;

    // Static constructor — runs once before first use
    static BankAccount() { /* initialize static state */ }

    // ── Instance fields ───────────────────────────────────────────────
    private readonly int _id;
    private decimal _balance;
    private readonly string _owner;
    private readonly List<Transaction> _history = new();

    // ── Constructors ──────────────────────────────────────────────────
    public BankAccount(string owner, decimal initialBalance = 0m)
    {
        ArgumentException.ThrowIfNullOrEmpty(owner);
        if (initialBalance < 0) throw new ArgumentOutOfRangeException(nameof(initialBalance));

        _id = Interlocked.Increment(ref _nextId);
        _owner = owner;
        _balance = initialBalance;
    }

    // Constructor chaining (this(...))
    public BankAccount(string owner) : this(owner, 0m) { }

    // ── Properties ────────────────────────────────────────────────────
    public int Id => _id;                              // read-only computed
    public string Owner => _owner;
    public decimal Balance => _balance;
    public IReadOnlyList<Transaction> History => _history.AsReadOnly();

    // Auto-property with init (C# 9+)
    public DateTime CreatedAt { get; } = DateTime.UtcNow;

    // Property with validation in setter
    private string? _label;
    public string? Label
    {
        get => _label;
        set => _label = value?.Trim();
    }

    // ── Methods ───────────────────────────────────────────────────────
    public void Deposit(decimal amount)
    {
        if (amount <= 0) throw new ArgumentOutOfRangeException(nameof(amount));
        _balance += amount;
        _history.Add(new Transaction(TransactionType.Deposit, amount));
    }

    public bool TryWithdraw(decimal amount, out string? error)
    {
        if (amount <= 0) { error = "Amount must be positive"; return false; }
        if (_balance < amount) { error = "Insufficient funds"; return false; }
        _balance -= amount;
        _history.Add(new Transaction(TransactionType.Withdrawal, amount));
        error = null;
        return true;
    }

    // ── Overrides ─────────────────────────────────────────────────────
    public override string ToString() => $"Account#{_id} [{_owner}]: {_balance:C}";
    public override bool Equals(object? obj) => obj is BankAccount other && _id == other._id;
    public override int GetHashCode() => _id.GetHashCode();

    // ── Operators ─────────────────────────────────────────────────────
    public static bool operator ==(BankAccount? a, BankAccount? b)
        => a?.Equals(b) ?? b is null;
    public static bool operator !=(BankAccount? a, BankAccount? b) => !(a == b);
}

// Supporting types
public enum TransactionType { Deposit, Withdrawal, Transfer }
public record Transaction(TransactionType Type, decimal Amount, DateTime At = default)
{
    public DateTime At { get; } = At == default ? DateTime.UtcNow : At;
}
```

---

## 5.2 Inheritance

```csharp
public abstract class Animal
{
    public string Name { get; }
    public int Age { get; }

    protected Animal(string name, int age)
    {
        Name = name;
        Age = age;
    }

    // Abstract — must be overridden
    public abstract string Sound();

    // Virtual — can be overridden
    public virtual string Describe()
        => $"{GetType().Name} named {Name}, age {Age}, says '{Sound()}'";

    // Non-virtual — cannot be overridden
    public string GetId() => $"{GetType().Name}_{Name}";
}

public class Dog : Animal
{
    public string Breed { get; }

    public Dog(string name, int age, string breed) : base(name, age)
    {
        Breed = breed;
    }

    public override string Sound() => "Woof";

    // Override and extend
    public override string Describe()
        => base.Describe() + $" (breed: {Breed})";
}

public class Cat : Animal
{
    public bool IsIndoor { get; }

    public Cat(string name, int age, bool isIndoor) : base(name, age)
    {
        IsIndoor = isIndoor;
    }

    public override string Sound() => "Meow";
}

// Polymorphism
List<Animal> animals = [
    new Dog("Rex", 3, "German Shepherd"),
    new Cat("Whiskers", 2, true),
    new Dog("Buddy", 5, "Labrador"),
];

foreach (var a in animals)
    Console.WriteLine(a.Describe()); // virtual dispatch
```

### `sealed` — Prevent Overriding

```csharp
public class PremiumAccount : BankAccount
{
    // sealed override — cannot be overridden by further subclasses
    public sealed override string ToString() => $"[PREMIUM] {base.ToString()}";
}

// sealed class — cannot be inherited
public sealed class SingletonService
{
    public static SingletonService Instance { get; } = new();
    private SingletonService() { }
}
```

### `new` — Hiding (vs. `override`)

```csharp
public class Base
{
    public virtual string Greet() => "Hello from Base";
    public string Name => "Base";  // non-virtual
}

public class Derived : Base
{
    public override string Greet() => "Hello from Derived"; // polymorphic
    public new string Name => "Derived"; // hiding — NOT polymorphic
}

Base b = new Derived();
Console.WriteLine(b.Greet()); // "Hello from Derived" — virtual dispatch
Console.WriteLine(b.Name);    // "Base" — not virtual, uses static type
```

---

## 5.3 Interfaces

### Defining and Implementing

```csharp
// Interface definition
public interface IRepository<T> where T : class, IEntity
{
    Task<T?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct = default);
    Task<int> AddAsync(T entity, CancellationToken ct = default);
    Task UpdateAsync(T entity, CancellationToken ct = default);
    Task DeleteAsync(int id, CancellationToken ct = default);
}

// Implementing
public class SqlUserRepository : IRepository<User>
{
    private readonly AppDbContext _db;
    public SqlUserRepository(AppDbContext db) => _db = db;

    public async Task<User?> GetByIdAsync(int id, CancellationToken ct = default)
        => await _db.Users.FindAsync([id], ct);

    public async Task<IReadOnlyList<User>> GetAllAsync(CancellationToken ct = default)
        => await _db.Users.ToListAsync(ct);

    public async Task<int> AddAsync(User user, CancellationToken ct = default)
    {
        _db.Users.Add(user);
        await _db.SaveChangesAsync(ct);
        return user.Id;
    }

    public async Task UpdateAsync(User user, CancellationToken ct = default)
    {
        _db.Users.Update(user);
        await _db.SaveChangesAsync(ct);
    }

    public async Task DeleteAsync(int id, CancellationToken ct = default)
    {
        var user = await GetByIdAsync(id, ct);
        if (user is not null)
        {
            _db.Users.Remove(user);
            await _db.SaveChangesAsync(ct);
        }
    }
}
```

### Default Interface Members (C# 8+)

```csharp
public interface ILogger
{
    void Log(string message, LogLevel level);

    // Default implementation — implementing class doesn't have to override
    void LogInfo(string message)    => Log(message, LogLevel.Information);
    void LogWarning(string message) => Log(message, LogLevel.Warning);
    void LogError(string message)   => Log(message, LogLevel.Error);

    // Default static factory
    static ILogger Null => NullLogger.Instance;
}

// Minimal implementation
public class ConsoleLogger : ILogger
{
    public void Log(string message, LogLevel level)
        => Console.WriteLine($"[{level}] {message}");
    // LogInfo/LogWarning/LogError come for free from defaults
}
```

### Static Interface Members (C# 11+)

```csharp
// Interfaces can have static abstract/virtual members
public interface IAddable<T> where T : IAddable<T>
{
    static abstract T Zero { get; }
    static abstract T operator +(T left, T right);
}

public interface IParseable<T> where T : IParseable<T>
{
    static abstract T Parse(string s);
    static virtual T? TryParse(string s) => // virtual with default
        TryParseImpl(s, out var v) ? v : default;
    private static bool TryParseImpl(string s, out T? v) => throw new NotImplementedException();
}

// Generic math (System.Numerics):
// INumber<T>, IComparable<T>, IFloatingPoint<T>, IInteger<T>, etc.
public static T Sum<T>(IEnumerable<T> items) where T : INumber<T>
{
    T total = T.Zero;
    foreach (var item in items) total += item;
    return total;
}

// Works with int, double, decimal, float, etc.
Sum([1, 2, 3, 4, 5]);           // 15
Sum([1.5, 2.5, 3.0]);           // 7.0
Sum([1.99m, 2.01m, 3.00m]);     // 7.00m
```

### Explicit Interface Implementation

```csharp
public interface IJsonSerializable
{
    string ToJson();
}

public interface IXmlSerializable
{
    string ToXml();
}

public class User : IJsonSerializable, IXmlSerializable
{
    public string Name { get; }
    public int Age { get; }

    public User(string name, int age) { Name = name; Age = age; }

    // Explicit implementation — only accessible via interface reference
    string IJsonSerializable.ToJson()
        => $"{{\"name\":\"{Name}\",\"age\":{Age}}}";

    string IXmlSerializable.ToXml()
        => $"<User><Name>{Name}</Name><Age>{Age}</Age></User>";
}

var user = new User("Alice", 30);
// user.ToJson(); // Compile error — not accessible on User
((IJsonSerializable)user).ToJson(); // OK
IXmlSerializable xml = user;
xml.ToXml(); // OK
```

---

## 5.4 Abstract Classes vs. Interfaces

| Feature | Abstract Class | Interface |
|---------|---------------|-----------|
| Instantiation | No | No |
| State (fields) | Yes | No (only static, C# 11+) |
| Constructor | Yes | No |
| Default methods | Yes | Yes (C# 8+) |
| Multiple inheritance | No (single base only) | Yes (multiple interfaces) |
| Access modifiers on members | Yes | All public (default) |
| Use when | Shared implementation + IS-A relationship | Capability / contract / multiple behavior |

```csharp
// Abstract class — for shared implementation
public abstract class Transport
{
    private readonly string _name;
    protected Transport(string name) => _name = name;

    // Shared implementation
    public void Start() { Initialize(); Console.WriteLine($"{_name} started."); }
    public void Stop()  { Shutdown(); Console.WriteLine($"{_name} stopped."); }

    // Subclass-specific
    protected abstract void Initialize();
    protected abstract void Shutdown();
    public abstract int MaxPassengers { get; }
}

// Interface — for capability
public interface IElectric
{
    double BatteryLevel { get; }
    void Charge();
}

public interface ISelfDriving
{
    void EnableAutopilot();
    void DisableAutopilot();
}

// Class can extend one abstract class, implement many interfaces
public class ElectricCar : Transport, IElectric, ISelfDriving
{
    private double _battery = 100;
    private bool _autopilot = false;

    public ElectricCar() : base("ElectricCar") { }

    public override int MaxPassengers => 5;
    protected override void Initialize() => Console.WriteLine("Checking battery...");
    protected override void Shutdown()   => Console.WriteLine("Saving state...");

    public double BatteryLevel => _battery;
    public void Charge()           => _battery = 100;
    public void EnableAutopilot()  => _autopilot = true;
    public void DisableAutopilot() => _autopilot = false;
}
```

---

## 5.5 Properties — Advanced

```csharp
public class Circle
{
    // Required init-only (C# 11+)
    public required double Radius { get; init; }

    // Computed property
    public double Diameter    => Radius * 2;
    public double Area        => Math.PI * Radius * Radius;
    public double Circumference => 2 * Math.PI * Radius;

    // Property with backing field and validation
    private int _sides = 1;
    public int Sides
    {
        get => _sides;
        private set => _sides = value > 0
            ? value
            : throw new ArgumentOutOfRangeException(nameof(value), "Must be positive");
    }
}

// Init-only property
public record class Point
{
    public required double X { get; init; }
    public required double Y { get; init; }
}
var p = new Point { X = 1, Y = 2 };
// p.X = 5; // Compile error — init only

// Property pattern with expression body
public class Temperature
{
    public double Celsius { get; }
    public double Fahrenheit => Celsius * 9.0 / 5.0 + 32;
    public Temperature(double celsius) => Celsius = celsius;
}

// Indexer
public class Matrix<T>
{
    private readonly T[,] _data;

    public Matrix(int rows, int cols) => _data = new T[rows, cols];

    public T this[int row, int col]
    {
        get => _data[row, col];
        set => _data[row, col] = value;
    }

    public int Rows => _data.GetLength(0);
    public int Cols => _data.GetLength(1);
}

var m = new Matrix<double>(3, 3);
m[0, 0] = 1.0;
m[1, 1] = 2.0;
Console.WriteLine(m[0, 0]); // 1.0
```

---

## 5.6 Object Initialization Patterns

```csharp
// Object initializer
var user = new User
{
    Name = "Alice",
    Age = 30,
    Email = "alice@example.com"
};

// Collection initializer
var names = new List<string> { "Alice", "Bob", "Charlie" };
var dict  = new Dictionary<string, int> { ["a"] = 1, ["b"] = 2 };

// Collection expressions (C# 12+)
string[] arr = ["Alice", "Bob", "Charlie"];
List<int> nums = [1, 2, 3, 4, 5];
int[] combined = [..arr1, ..arr2];  // spread operator

// Object initializer with records (with-expression)
var p1 = new Point { X = 1, Y = 2 };
var p2 = p1 with { X = 99 };

// Builder pattern (fluent)
var config = new ConfigBuilder()
    .WithHost("localhost")
    .WithPort(5432)
    .WithDatabase("mydb")
    .WithCredentials("user", "pass")
    .Build();
```

---

## 5.7 Object Comparison and Equality

```csharp
public class Product : IEquatable<Product>, IComparable<Product>
{
    public string Sku { get; }
    public decimal Price { get; }

    public Product(string sku, decimal price)
    {
        Sku = sku;
        Price = price;
    }

    // IEquatable<T> — efficient typed equality
    public bool Equals(Product? other)
        => other is not null && Sku == other.Sku;

    public override bool Equals(object? obj)
        => obj is Product p && Equals(p);

    public override int GetHashCode()
        => Sku.GetHashCode();

    public static bool operator ==(Product? a, Product? b) => a?.Equals(b) ?? b is null;
    public static bool operator !=(Product? a, Product? b) => !(a == b);

    // IComparable<T> — natural ordering
    public int CompareTo(Product? other)
        => other is null ? 1 : Price.CompareTo(other.Price);

    public static bool operator <(Product a, Product b)  => a.CompareTo(b) < 0;
    public static bool operator >(Product a, Product b)  => a.CompareTo(b) > 0;
    public static bool operator <=(Product a, Product b) => a.CompareTo(b) <= 0;
    public static bool operator >=(Product a, Product b) => a.CompareTo(b) >= 0;
}

// Custom comparer
public class ProductByNameComparer : IComparer<Product>
{
    public static readonly IComparer<Product> Instance = new ProductByNameComparer();
    public int Compare(Product? x, Product? y)
        => StringComparer.OrdinalIgnoreCase.Compare(x?.Sku, y?.Sku);
}

// Usage
var products = GetProducts();
products.Sort(); // by price (IComparable)
products.Sort(ProductByNameComparer.Instance); // by sku
var sorted = products.OrderBy(p => p.Price).ThenBy(p => p.Sku).ToList();
```

---

## 5.8 Covariance and Contravariance in OOP

```csharp
// Return type covariance (C# 9+) — override can return more derived type
public abstract class AnimalFactory
{
    public abstract Animal Create();
}

public class DogFactory : AnimalFactory
{
    public override Dog Create() => new Dog("Rex", 2, "Lab"); // Dog is Animal
}

// Covariant IEnumerable<out T>
IEnumerable<Dog> dogs = GetDogs();
IEnumerable<Animal> animals = dogs; // OK — covariant

// Contravariant IComparer<in T>
IComparer<Animal> animalComp = Comparer<Animal>.Default;
IComparer<Dog> dogComp = animalComp; // OK — contravariant
```

> **Rider tip:** *Navigate → Go to Base* (`Ctrl+U` / `⌘U`) and *Navigate → Go to Implementation(s)* (`Ctrl+Alt+B` / `⌘⌥B`) are essential for navigating class hierarchies. The *Type Hierarchy* window (`Ctrl+Alt+H` / `⌘⌥H`) shows the full inheritance tree.

> **VS tip:** *View → Object Browser* shows the full type hierarchy. *Go to Implementation* is `Ctrl+F12`. Use the *Class View* (`Ctrl+Shift+C`) to browse all types in the solution.


> **See also:** [Chapter 20 — Core Design Principles](ch20_principles.md) covers Single Responsibility (§20.7), Composition Over Inheritance (§20.8), and Domain Primitives (§20.10) — all of which build directly on OOP fundamentals.
