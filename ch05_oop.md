# Chapter 5 — OOP: Classes, Interfaces, Inheritance & Polymorphism

> Object-Oriented Programming is the dominant paradigm in C# and the
> foundation of every framework it runs on top of. But OOP is widely
> misunderstood — textbooks teach "classes and inheritance" while
> real-world C# emphasises "composition and interfaces". This chapter
> explains OOP as it is actually practised, not as it is theorised.

*Building on:* Ch 2 (types, records), Ch 3 (pattern matching),
Ch 4 (delegates, extension methods)

---

## 5.1 Classes — The Blueprint of an Object

A class is a blueprint that defines state (fields, properties) and
behaviour (methods). An instance is a particular object created from
that blueprint. The class defines what every instance knows and can do;
each instance holds its own copy of the state.

The key responsibility of a well-designed class is *encapsulation*: hiding
internal details and exposing only what consumers need. This protects
the class from being used incorrectly and allows the internals to change
without breaking callers.

```csharp
public class BankAccount
{
    // Private field: internal state, hidden from outside
    private decimal _balance;

    // Property: controlled public access to private state
    // Getter: anyone can read the balance
    // Setter: private — only this class can set it
    public decimal Balance { get; private set; }

    // Read-only identity — set once at construction
    public string  AccountId   { get; }
    public string  OwnerName   { get; }
    public DateTime OpenedAt   { get; }

    // Constructor: establishes valid initial state
    // The class enforces its own invariants here
    public BankAccount(string accountId, string ownerName, decimal initialDeposit)
    {
        if (string.IsNullOrWhiteSpace(accountId))
            throw new ArgumentException("Account ID required", nameof(accountId));
        if (initialDeposit < 0)
            throw new ArgumentOutOfRangeException(nameof(initialDeposit), "Cannot open with negative balance");

        AccountId = accountId;
        OwnerName = ownerName;
        Balance   = initialDeposit;
        OpenedAt  = DateTime.UtcNow;
    }

    // Behaviour: the only way to change the balance
    // Callers cannot set Balance directly — they must go through this method
    public void Deposit(decimal amount)
    {
        if (amount <= 0)
            throw new ArgumentOutOfRangeException(nameof(amount), "Deposit must be positive");
        Balance += amount;
    }

    public void Withdraw(decimal amount)
    {
        if (amount <= 0)
            throw new ArgumentOutOfRangeException(nameof(amount), "Withdrawal must be positive");
        if (amount > Balance)
            throw new InvalidOperationException($"Insufficient funds. Balance: {Balance:C}");
        Balance -= amount;
    }
}
```

This encapsulation is the difference between a class that *protects its
own invariants* and a data bag that could be put into any invalid state
by any caller.

### Access Modifiers — Who Can See What

| Modifier | Visibility |
|---|---|
| `public` | Everyone — part of the public API surface |
| `internal` | Only within the same assembly (project) |
| `protected` | Only this class and its subclasses |
| `protected internal` | Protected OR internal |
| `private protected` | Protected AND internal |
| `private` | Only this class (the default for class members) |
| `file` | Only within the same file (C# 11+) |

The practical rule: **start private, expose only what is necessary.**
Every public member is a commitment to maintain forever.

---

## 5.2 Inheritance — Sharing Behaviour Across Types

Inheritance allows a class to extend another class, inheriting all its
public and protected members and adding or overriding them. It expresses
an "is-a" relationship: a `SavingsAccount` *is a* `BankAccount`.

```csharp
public class SavingsAccount : BankAccount
{
    public decimal InterestRate { get; }

    public SavingsAccount(string id, string owner, decimal initial, decimal interestRate)
        : base(id, owner, initial)   // call the base class constructor
    {
        InterestRate = interestRate;
    }

    // Add new behaviour
    public void ApplyInterest()
    {
        Deposit(Balance * InterestRate);  // reuses inherited Deposit method
    }
}
```

### `virtual`, `override`, and `sealed`

Methods are not overridable by default. You must explicitly mark a base
class method `virtual` to allow subclasses to replace it:

```csharp
public class Shape
{
    // virtual: subclasses MAY override this
    public virtual double Area() => 0;

    // non-virtual: cannot be overridden — always this implementation
    public string Describe() => $"A shape with area {Area():F2}";
}

public class Circle(double radius) : Shape
{
    // override: replaces the base class implementation
    public override double Area() => Math.PI * radius * radius;
}

public sealed class Sphere : Circle    // sealed: cannot be subclassed further
{
    private double _radius;
    public Sphere(double r) : base(r) { _radius = r; }

    // sealed override: this is the final implementation
    public sealed override double Area() => 4 * Math.PI * _radius * _radius;
}
```

### `abstract` Classes — Force Subclasses to Implement

An abstract class cannot be instantiated. It exists to provide a partial
implementation and declare that subclasses must complete it:

```csharp
public abstract class Exporter
{
    // abstract: no implementation here — MUST be overridden
    protected abstract string FormatData(IEnumerable<Row> rows);

    // Template method: algorithm structure fixed here, steps delegated to subclasses
    public void Export(IEnumerable<Row> rows, Stream output)
    {
        var formatted = FormatData(rows);  // calls the subclass's implementation
        using var writer = new StreamWriter(output);
        writer.Write(formatted);
    }
}

public class CsvExporter : Exporter
{
    protected override string FormatData(IEnumerable<Row> rows) =>
        string.Join("\n", rows.Select(r => string.Join(",", r.Values)));
}
```

---

## 5.3 Interfaces — The Most Important OOP Tool in Real C#

An interface is a *contract*: it declares what methods, properties, and
events a type must provide, without any implementation. Any class that
wants to fulfil the contract declares it implements the interface.

While inheritance is hierarchical (one parent), a class can implement
*any number* of interfaces. This is what makes interfaces the preferred
abstraction in real-world C# design.

### Why Interfaces Over Abstract Classes?

The critical benefit of interfaces is **decoupling**. When code depends
on an interface rather than a concrete class, you can:

1. Replace the implementation without changing callers
2. Provide test doubles in unit tests
3. Register different implementations based on environment or config
4. Compose multiple behaviours without deep inheritance trees

```csharp
// Interface: the contract that all implementations must fulfil
public interface IEmailSender
{
    Task SendAsync(string to, string subject, string body, CancellationToken ct = default);
}

// Production implementation
public class SmtpEmailSender(SmtpOptions options) : IEmailSender
{
    public async Task SendAsync(string to, string subject, string body, CancellationToken ct)
    {
        // ... real SMTP logic ...
    }
}

// Test implementation — swapped in during unit tests
public class FakeEmailSender : IEmailSender
{
    public List<(string To, string Subject)> SentEmails { get; } = new();

    public Task SendAsync(string to, string subject, string body, CancellationToken ct)
    {
        SentEmails.Add((to, subject));
        return Task.CompletedTask;
    }
}

// The service depends on the interface, not any concrete class
public class OrderService(IEmailSender email)
{
    public async Task CompleteOrderAsync(Order order, CancellationToken ct)
    {
        // ... complete the order ...
        await email.SendAsync(order.CustomerEmail, "Order confirmed", "...", ct);
        // works whether email is SmtpEmailSender or FakeEmailSender
    }
}
```

This is the foundation of Dependency Injection (Chapter 10–11). The DI
container gives `OrderService` whichever `IEmailSender` is registered for
the current environment.

### Default Interface Members (C# 8+)

Interfaces can now provide default implementations, allowing you to add
methods to an existing interface without breaking all existing
implementations:

```csharp
public interface IRepository<T>
{
    Task<T?> GetByIdAsync(int id, CancellationToken ct);
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct);

    // Default implementation: any class that implements GetAllAsync
    // automatically gets Count — they can override it for efficiency
    async Task<int> CountAsync(CancellationToken ct)
    {
        var all = await GetAllAsync(ct);
        return all.Count;
    }
}
```

---

## 5.4 Abstract Classes vs. Interfaces — When to Use Each

This is one of the most common design questions. Here is the practical
guide:

| Situation | Use |
|---|---|
| Multiple unrelated types should share a contract | Interface |
| You want to replace an implementation in tests or config | Interface |
| You have shared implementation to provide to subclasses | Abstract class |
| You are implementing a template method (fixed algorithm, variable steps) | Abstract class |
| You need to add behaviour to an existing type without modifying it | Interface + extension method |
| You need to represent "can do X" orthogonally to class hierarchy | Interface |

The idiomatic .NET pattern:
- Define an *interface* for the abstraction
- Provide a *base class* as an optional convenience for implementations
  that share a lot of code

```csharp
// Interface: the contract
public interface ICache<TKey, TValue>
{
    bool TryGet(TKey key, out TValue? value);
    void Set(TKey key, TValue value, TimeSpan? ttl = null);
    void Invalidate(TKey key);
}

// Base class: partial implementation for implementations that use a Dictionary
public abstract class DictionaryCache<TKey, TValue> : ICache<TKey, TValue>
    where TKey : notnull
{
    protected readonly Dictionary<TKey, TValue> _store = new();

    public bool TryGet(TKey key, out TValue? value) =>
        _store.TryGetValue(key, out value);

    public void Invalidate(TKey key) => _store.Remove(key);

    // Set is still abstract — subclasses decide TTL strategy
    public abstract void Set(TKey key, TValue value, TimeSpan? ttl = null);
}
```

---

## 5.5 Properties — Smart Fields

Properties look like fields at the call site but execute code when read
or written. They let you add validation, lazy initialisation, change
notification, or computed values while keeping a clean public API.

```csharp
public class Product
{
    private decimal _price;
    private string  _name = "";

    // Validation in the setter
    public decimal Price
    {
        get => _price;
        set
        {
            if (value < 0)
                throw new ArgumentOutOfRangeException(nameof(value), "Price cannot be negative");
            _price = value;
        }
    }

    // Auto-property: compiler generates the backing field
    public string Category { get; set; } = "General";

    // Computed property: no backing field, calculated on access
    public string DisplayName => $"{_name} ({Category})";

    // Init-only: settable only in constructor or object initialiser (Ch 2 §2.6)
    public string Sku { get; init; } = "";
}
```

### Expression-Bodied Members

Single-expression methods, properties, and accessors can use `=>` syntax.
It is concise but should not be forced — use it where the body genuinely
fits on one line and reads clearly:

```csharp
// Fine: truly simple
public string FullName => $"{FirstName} {LastName}";
public bool IsAdult => Age >= 18;

// Do not force it for complex logic
public bool IsEligible =>  // better as a full method
    Age >= 18 && !IsBlocked && Tier != "restricted" && AccountBalance >= 0;
```

---

## 5.6 Object Initialisation Patterns

C# provides several ways to initialise objects. Each makes different
trade-offs between brevity, immutability, and validation.

```csharp
// Constructor: validation and complex setup
var account = new BankAccount("ACC001", "Alice", 1000m);

// Object initialiser: sets public properties after construction
// Properties must have public setters (or init)
var config = new ServerConfig
{
    Host = "localhost",
    Port = 5432,
    Database = "mydb"
};

// With init-only properties: safe for immutable types
public record ProductConfig
{
    public required string Name     { get; init; }
    public required decimal Price   { get; init; }
    public string Category          { get; init; } = "General";
}

var product = new ProductConfig
{
    Name  = "Widget",
    Price = 9.99m
    // Category defaults to "General"
};

// required keyword (C# 11): compiler error if not set at creation
// Guarantees the property is always initialised — no forgetting
```

---

## 5.7 Object Equality and `IComparable`

By default, class equality means *reference equality* — two objects are
equal only if they are the same object. Override this for types whose
identity is determined by content:

```csharp
public class EmailAddress : IEquatable<EmailAddress>
{
    public string Value { get; }

    public EmailAddress(string value)
    {
        if (!value.Contains('@'))
            throw new ArgumentException("Invalid email", nameof(value));
        Value = value.ToLowerInvariant();  // normalise on creation
    }

    // Implement IEquatable<T> for typed equality
    public bool Equals(EmailAddress? other) =>
        other is not null && Value == other.Value;

    // Override object.Equals for == and Equals(object) calls
    public override bool Equals(object? obj) => Equals(obj as EmailAddress);

    // Always override GetHashCode when overriding Equals
    // Rule: objects that are Equal MUST have the same hash code
    public override int GetHashCode() => Value.GetHashCode();

    // Operator overloads for natural syntax
    public static bool operator ==(EmailAddress? a, EmailAddress? b) =>
        a?.Equals(b) ?? b is null;
    public static bool operator !=(EmailAddress? a, EmailAddress? b) => !(a == b);
}
```

---

## 5.8 Covariance and Contravariance

Variance describes how type parameters behave under inheritance. It
affects collections and delegates in ways that can surprise you.

```csharp
// Covariance (out): a more derived type can be used where a base type is expected
IEnumerable<string> strings = new List<string>();
IEnumerable<object> objects = strings;  // works because IEnumerable<T> is covariant

// Contravariance (in): a less derived type can be used where a more derived is expected
Action<object>  objectAction = obj => Console.WriteLine(obj);
Action<string>  stringAction = objectAction;  // works because Action<T> is contravariant
stringAction("hello");
```

This matters when you write your own generic interfaces. Declare `out T`
if the type parameter only appears in return positions (covariant), and
`in T` if it only appears in input positions (contravariant).

---

## 5.9 The Composition Over Inheritance Principle

Inheritance creates a rigid hierarchy. If `CheckingAccount` inherits from
`BankAccount`, and you later need a `JointCheckingAccount`, you must either
create a three-level hierarchy or duplicate code. The deeper the hierarchy,
the more fragile it becomes.

*Composition* — giving your class references to other objects that
provide the capabilities it needs — is more flexible:

```csharp
// Instead of: CheckingAccount inherits BankAccount
// Composition:
public class CheckingAccount(
    IBalanceStore    balance,    // capability: stores and retrieves balance
    ITransactionLog  log,        // capability: records transactions
    IOverdraftPolicy overdraft   // capability: decides what happens when overdrawn
)
{
    public decimal Balance => balance.Current;

    public void Withdraw(decimal amount)
    {
        if (amount > Balance)
            overdraft.Handle(this, amount);  // policy is swappable
        balance.Deduct(amount);
        log.Record(new Transaction(amount, TransactionType.Withdrawal));
    }
}
```

Now `CheckingAccount` has no inheritance at all. Its behaviour is composed
from injected capabilities. Changing the overdraft policy is just
registering a different `IOverdraftPolicy` in DI — no class hierarchy
changes needed. This is Chapter 6's principle "Composition Over Inheritance"
and Chapter 18's entire architectural approach.

---

## 5.10 Connecting OOP to the Rest of the Book

- **Ch 6 (Principles)** — "Composition Over Inheritance" (§6.8) and
  "Single Responsibility" (§6.7) are OOP principles. The chapter explains
  what goes wrong when they are violated.
- **Ch 10–11 (DI)** — The entire DI system is built on interfaces.
  You register an interface and its implementation; the container
  constructs the implementation and injects it wherever the interface
  is requested.
- **Ch 17 (Testing)** — Interfaces enable test doubles (mocks, fakes,
  stubs). Without them, unit testing requires the real implementation
  of every dependency.
- **Ch 18 (Architectures)** — Onion, Clean, and Hexagonal architectures
  are all about which layer can depend on which. Interfaces are the
  mechanism that enforces those dependency rules.
- **Ch 29 (Design Patterns)** — Strategy, Decorator, Factory, and
  Repository all depend on interfaces to express their shape.
