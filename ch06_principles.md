# Chapter 6 — Core Design Principles

These are not style preferences. Each one eliminates a specific, recurring class of bugs.
Ignore them and you will write the bugs. Follow them and the bugs become impossible.

---

## 6.1 Make Illegal States Unrepresentable

**The principle:** model your types so that invalid domain states cannot be constructed.
The compiler becomes your validator.

### The Bug It Prevents

```csharp
// This class allows dozens of inconsistent states
class Order
{
    public string  Status;          // "Pending", "Shipped", "Delivered", "Cancelled"
    public DateTime? ShippedAt;     // null when Pending, set when Shipped
    public string?   TrackingNumber;// null until Shipped
    public DateTime? DeliveredAt;   // null until Delivered
    public string?   CancelReason;  // null unless Cancelled
}

// All of these compile and run with no error:
var bad1 = new Order { Status = "Delivered", ShippedAt = null };   // delivered but never shipped?
var bad2 = new Order { Status = "Cancelled", TrackingNumber = "123" }; // tracking on a cancelled order?
var bad3 = new Order { Status = "Pending",   DeliveredAt = DateTime.UtcNow }; // delivered while pending?

// You now need defensive checks everywhere:
void PrintOrder(Order o)
{
    if (o.Status == "Shipped" && o.TrackingNumber == null)
        throw new InvalidOperationException("Shipped order has no tracking"); // runtime, in production
}
```

### The Fix

```csharp
// Each state carries exactly what it can have — nothing more, nothing less
abstract record OrderState;
record Pending()                                               : OrderState;
record Shipped(DateTime At, string TrackingNumber)            : OrderState;
record Delivered(DateTime ShippedAt, DateTime DeliveredAt)    : OrderState;
record Cancelled(string Reason)                               : OrderState;

record Order(Guid Id, string CustomerId, OrderState State);

// These are now compile errors — illegal states literally cannot be constructed:
// new Shipped(DateTime.UtcNow, null!)       // TrackingNumber is required
// new Delivered(null!, DateTime.UtcNow)     // ShippedAt is required

// Consuming code is forced to handle every case:
string Describe(Order order) => order.State switch
{
    Pending()            => "Awaiting shipment",
    Shipped(var at, var tracking) => $"Shipped {at:d}, tracking: {tracking}",
    Delivered(_, var at)          => $"Delivered {at:d}",
    Cancelled(var reason)         => $"Cancelled: {reason}",
    // Compiler error if you add a new state and forget to handle it here
};
```

**Rule of thumb:** if you have nullable fields that are only valid in some states, you
have a modelling problem. Split the type.

---

## 6.2 Parse, Don't Validate

**The principle:** validate at the system boundary, return a typed proof of validity.
Never pass raw unvalidated data through the interior of your system.

### The Bug It Prevents

```csharp
// Validate-then-use pattern — validation is optional, can be skipped
bool IsValidEmail(string s) => s.Contains('@') && s.Length < 256;

void SendWelcomeEmail(string email)
{
    // Does the caller always validate? Maybe. Maybe not.
    // You cannot know without reading every call site.
    _smtp.Send(email, "Welcome!");
}

void RegisterUser(string name, string email)
{
    // Oops — forgot to validate. Compiles fine. Blows up at SendWelcomeEmail.
    _db.Save(name, email);
    SendWelcomeEmail(email);
}
```

### The Fix

```csharp
// Parse once at the boundary — carry proof of validity in the type
record Email
{
    public string Value { get; }

    private Email(string value) => Value = value;

    public static Result<Email, string> Parse(string s)
    {
        if (string.IsNullOrWhiteSpace(s))       return "Email cannot be empty";
        if (!s.Contains('@'))                    return "Email must contain @";
        if (s.Length > 255)                      return "Email too long";
        return new Email(s.ToLowerInvariant());
    }

    public override string ToString() => Value;
}

// SendWelcomeEmail cannot receive an invalid email — the type proves it
void SendWelcomeEmail(Email email) => _smtp.Send(email.Value, "Welcome!");

// Registration now forced to handle the parse failure:
void RegisterUser(string name, string rawEmail)
{
    var result = Email.Parse(rawEmail);
    if (result.IsError) { ShowError(result.Error); return; }

    _db.Save(name, result.Value);
    SendWelcomeEmail(result.Value);  // Email type — proven valid
}
```

**Corollary:** parse at the outermost layer (HTTP handler, CLI arg parser, file reader),
never deep in the domain. Once parsed, an `Email` is an `Email` — no re-checking ever.

---

## 6.3 Errors Are Values, Not Exceptions

**The principle:** expected failure paths are return values.
Exceptions are for programmer errors and infrastructure failures, not business outcomes.

### The Bug It Prevents

```csharp
// Exception for business logic — caller has no idea this can fail
// without reading the implementation or documentation
User GetUser(int id)
{
    var user = _db.Find(id);
    if (user == null) throw new UserNotFoundException(id); // ← invisible at call site
    return user;
}

// Caller writes:
var user = GetUser(42);             // looks safe
var name = user.Name.ToUpper();     // crashes if user not found — surprise!

// Or worse — caller swallows the exception:
try { var u = GetUser(42); DoWork(u); }
catch (Exception) { }  // silent failure — the worst possible outcome
```

### The Fix

```csharp
// Failure is part of the contract — visible at every call site
Result<User, string> GetUser(UserId id)
{
    var user = _db.Find(id.Value);
    return user is not null
        ? Result<User, string>.Ok(user)
        : Result<User, string>.Fail($"User {id} not found");
}

// Caller cannot ignore the failure case:
var result = GetUser(new UserId(42));

// Must handle both paths — compiler enforces it via Match
var name = result.Match(
    ok:   user  => user.Name.ToUpper(),
    fail: error => throw new InvalidOperationException(error));

// Or: propagate
if (result.IsError) return result.Error;
var user = result.Value;
```

### When to Use Exceptions

```csharp
// ✅ Exceptions: programmer error — should crash loudly
ArgumentNullException.ThrowIfNull(order);
ArgumentOutOfRangeException.ThrowIfNegative(amount);

// ✅ Exceptions: infrastructure failure — disk full, network down, OOM
// These are unrecoverable — crashing is correct behaviour

// ❌ Not exceptions: expected business outcomes
// "user not found", "payment declined", "validation failed", "quota exceeded"
// → use Result<T, TError>
```

---

## 6.4 Immutability by Default

**The principle:** data does not change after construction.
Mutations are explicit, visible, and traceable.

### The Bug It Prevents

```csharp
// Mutable shared state — classic threading bug
class Config
{
    public string Host { get; set; }
    public int    Port { get; set; }
}

var config = new Config { Host = "prod.example.com", Port = 443 };

// Thread A reads config.Host → "prod.example.com"
// Thread B sets config.Host = "staging.example.com"
// Thread A reads config.Port → 443 (but host is now staging!)
// Request goes to staging with prod port — wrong, silent, intermittent

// Another classic:
var defaults = new Config { Host = "localhost", Port = 5000 };
var prod     = defaults;    // you think this is a copy
prod.Host    = "prod.com";  // mutates defaults too! reference semantics
Console.WriteLine(defaults.Host); // → prod.com  ← surprise
```

### The Fix

```csharp
// Immutable record — cannot change after construction
record Config(string Host, int Port);

var defaults = new Config("localhost", 5000);
var prod     = defaults with { Host = "prod.com" };  // new instance, defaults unchanged

Console.WriteLine(defaults.Host); // → localhost  ✓
Console.WriteLine(prod.Host);     // → prod.com   ✓

// Thread-safe: nothing can mutate Config, no race condition possible
```

```csharp
// Immutable collections — same principle for data structures
using System.Collections.Immutable;

var original = ImmutableList.Create(1, 2, 3);
var modified = original.Add(4);      // new list — original unchanged

Console.WriteLine(original.Count);   // → 3  ✓
Console.WriteLine(modified.Count);   // → 4  ✓
```

**Default rule:** use `record` for domain types. Use mutable class only when you have
a specific performance reason and can isolate the mutation behind a clean API.

---

## 6.5 Totality — Handle Every Case

**The principle:** every function returns a valid result for every possible input.
Functions that crash or throw for some inputs are partial — ticking time bombs.

### The Bug It Prevents

```csharp
// Partial function — crashes when a new enum value is added
string Describe(OrderState state) => state switch
{
    Pending()   => "pending",
    Shipped(_, var t) => $"shipped, tracking: {t}",
    // Developer adds Cancelled next sprint
    // This crashes at runtime for all cancelled orders
    // No compile error, no warning without the right settings
};

// Also partial — returns null for some inputs, crashes callers
string? GetLabel(int code) => code switch
{
    200 => "OK",
    404 => "Not Found",
    _   => null   // caller forgets to null-check
};
```

### The Fix

```csharp
// Total — handles every case, compiler enforces exhaustiveness
string Describe(OrderState state) => state switch
{
    Pending()              => "pending",
    Shipped(_, var t)      => $"shipped: {t}",
    Delivered(_, var at)   => $"delivered {at:d}",
    Cancelled(var reason)  => $"cancelled: {reason}",
    // Add a new state → compiler error here immediately
    // Cannot forget to handle it
};

// Enable exhaustiveness warnings in .editorconfig:
// dotnet_diagnostic.CS8509.severity = error  (switch expression not exhaustive)
// dotnet_diagnostic.CS8524.severity = error  (switch statement not exhaustive)
```

```csharp
// Total alternative to null return — use Option/Result
Option<string> GetLabel(int code) => code switch
{
    200 => Option.Some("OK"),
    404 => Option.Some("Not Found"),
    _   => Option.None<string>()
};

// Caller is forced to handle the "no label" case:
var label = GetLabel(500).GetValueOrDefault("Unknown");
```

---

## 6.6 Explicit Over Implicit

**The principle:** everything a function needs appears in its signature.
Hidden inputs — global state, ambient context, thread-locals — cause invisible coupling.

### The Bug It Prevents

```csharp
// Hidden dependency on global state — creates invisible coupling
class OrderProcessor
{
    public decimal CalculateTax(decimal amount)
    {
        // Where does this rate come from? Not from the caller.
        // Changes to TaxConfig affect this silently.
        // Cannot test without setting up global state.
        return amount * TaxConfig.CurrentRate;
    }
}

// Hidden time dependency — test passes today, fails tomorrow
class SubscriptionService
{
    public bool IsExpired(Subscription s)
    {
        return s.ExpiresAt < DateTime.UtcNow; // untestable — "now" changes
    }
}
```

### The Fix

```csharp
// All dependencies explicit in signature
class OrderProcessor
{
    public decimal CalculateTax(decimal amount, TaxRate rate)
        => amount * rate.Value;  // pure, testable, no hidden inputs
}

// Inject the clock — control "now" in tests
interface ISystemClock { DateTimeOffset UtcNow { get; } }

class SubscriptionService
{
    private readonly ISystemClock _clock;
    public SubscriptionService(ISystemClock clock) => _clock = clock;

    public bool IsExpired(Subscription s) => s.ExpiresAt < _clock.UtcNow;
}

// In tests: inject a fixed clock → deterministic results forever
class FakeClock : ISystemClock
{
    public DateTimeOffset UtcNow { get; set; } = new DateTimeOffset(2025, 1, 1, 0, 0, 0, TimeSpan.Zero);
}
```

`DateTime.UtcNow` is the one BCL member worth abstracting — calling it twice returns
different results, making any function that uses it impure and untestable.

---

## 6.7 Single Responsibility

**The principle:** one class, one reason to change.
If you write "and" describing what a class does, split it.

### The Bug It Prevents

```csharp
// UserManager does three unrelated things:
// parse input AND store users AND send emails
// Change email provider → touch UserManager
// Change DB schema    → touch UserManager
// Change CSV format   → touch UserManager
// Three reasons to change = three opportunities to break the other two

class UserManager
{
    public void ImportFromCsv(string path)
    {
        var lines = File.ReadAllLines(path);       // parsing
        foreach (var line in lines)
        {
            var parts = line.Split(',');
            _db.Insert(parts[0], parts[1]);         // storage
            _smtp.Send(parts[1], "Welcome!");       // notification
        }
    }
}
```

### The Fix

```csharp
// Each class changes for exactly one reason
record CsvUser(string Name, string Email);

class CsvUserParser
{
    // Changes only if CSV format changes
    public IReadOnlyList<CsvUser> Parse(string csv) =>
        csv.Split('\n')
           .Where(l => l.Contains(','))
           .Select(l => { var p = l.Split(','); return new CsvUser(p[0], p[1]); })
           .ToList();
}

class UserRepository
{
    // Changes only if storage changes
    public void SaveAll(IReadOnlyList<CsvUser> users)
    {
        foreach (var u in users) _db.Insert(u.Name, u.Email);
    }
}

class WelcomeEmailService
{
    // Changes only if email logic changes
    public void SendAll(IReadOnlyList<CsvUser> users)
    {
        foreach (var u in users) _smtp.Send(u.Email, "Welcome!");
    }
}

class UserImportService
{
    // Orchestrates, delegates to specialists, changes only if the workflow changes
    private readonly CsvUserParser     _parser;
    private readonly UserRepository    _repo;
    private readonly WelcomeEmailService _email;

    public UserImportService(CsvUserParser p, UserRepository r, WelcomeEmailService e)
    { _parser = p; _repo = r; _email = e; }

    public void Import(string csv)
    {
        var users = _parser.Parse(csv);
        _repo.SaveAll(users);
        _email.SendAll(users);
    }
}
```

---

## 6.8 Composition Over Inheritance

**The principle:** assemble behaviour from independent pieces rather than inheriting it.
Inheritance is permanent coupling. Composition is flexible wiring.

### The Bug It Prevents

```csharp
// Inheritance explosion — each combination needs its own class
class Repository             { }
class LoggedRepository       : Repository { }  // adds logging
class CachedRepository       : Repository { }  // adds caching
class LoggedCachedRepository : Repository { }  // needs both? new class
class CachedLoggedRepository : Repository { }  // different order? another class?
// N features = 2^N classes
```

### The Fix

```csharp
// Decorator pattern — compose any combination at the wiring layer
interface IUserRepository { User? Find(int id); void Save(User user); }

class SqlUserRepository : IUserRepository
{
    public User? Find(int id)    => _db.Users.Find(id);
    public void  Save(User user) => _db.Users.Add(user);
}

class LoggingRepository : IUserRepository
{
    private readonly IUserRepository _inner;
    private readonly ILogger         _log;
    public LoggingRepository(IUserRepository inner, ILogger log)
    { _inner = inner; _log = log; }

    public User? Find(int id)
    {
        _log.LogInformation("Find user {Id}", id);
        return _inner.Find(id);
    }
    public void Save(User user)
    {
        _log.LogInformation("Save user {Name}", user.Name);
        _inner.Save(user);
    }
}

class CachingRepository : IUserRepository
{
    private readonly IUserRepository    _inner;
    private readonly IMemoryCache       _cache;
    public CachingRepository(IUserRepository inner, IMemoryCache cache)
    { _inner = inner; _cache = cache; }

    public User? Find(int id) =>
        _cache.GetOrCreate($"user:{id}", _ => _inner.Find(id));
    public void Save(User user) { _cache.Remove($"user:{user.Id}"); _inner.Save(user); }
}

// Wire any combination in one place:
services.AddSingleton<IUserRepository>(sp =>
    new LoggingRepository(
        new CachingRepository(
            new SqlUserRepository(sp.GetRequiredService<AppDbContext>()),
            sp.GetRequiredService<IMemoryCache>()),
        sp.GetRequiredService<ILogger<LoggingRepository>>()));
```

---

## 6.9 Fail Fast

**The principle:** detect and report invalid state at the earliest possible moment,
as close to the source as possible.

### The Bug It Prevents

```csharp
// Bad data travels deep into the system before causing a crash
void ProcessOrder(Order order)
{
    var user    = _users.Find(order.UserId);    // returns null — not checked
    var address = user.ShippingAddress;          // NullReferenceException here
    // Stack trace points here, not to where null came from
    // Root cause: UserId was invalid — 10 method calls ago
}
```

### The Fix

```csharp
// Crash at the entry point, with a clear message pointing to the actual cause
void ProcessOrder(Order order)
{
    ArgumentNullException.ThrowIfNull(order);

    var user = _users.Find(order.UserId)
        ?? throw new NotFoundException($"User {order.UserId} not found");

    var address = user.ShippingAddress
        ?? throw new InvalidOperationException($"User {user.Id} has no shipping address");

    // Everything below this line is guaranteed valid
    _shipper.Ship(order, address);
}
```

Or better — use `Result<T>` and push the failure back to the caller:

```csharp
Result<Unit, ProcessError> ProcessOrder(Order order) =>
    _users.Find(order.UserId) switch
    {
        null => ProcessError.UserNotFound(order.UserId),
        { ShippingAddress: null } u => ProcessError.NoAddress(u.Id),
        var user => _shipper.Ship(order, user.ShippingAddress)
    };
```

---

## 6.10 Domain Primitives — Wrap Naked Primitives

**The principle:** every primitive that has domain meaning gets its own type.
A `string` is not an email. A `string` is not a file path. A `string` is not a user ID.

### The Bug It Prevents

```csharp
// Which string is which? Easy to mix up at the call site.
void SendEmail(string from, string to, string subject, string body) { }

// Compiler accepts this wrong call silently:
SendEmail(subject, body, to, from);   // args transposed — wrong order, no error
SendEmail("", "", "", "");            // all empty — no validation, compiles fine
```

### The Fix

```csharp
record Email
{
    public string Value { get; }
    private Email(string v) => Value = v;
    public static Result<Email, string> Parse(string s) =>
        s.Contains('@') ? new Email(s) : $"'{s}' is not a valid email";
    public override string ToString() => Value;
}

record Subject
{
    public string Value { get; }
    private Subject(string v) => Value = v;
    public static Result<Subject, string> Parse(string s) =>
        !string.IsNullOrWhiteSpace(s) ? new Subject(s) : "Subject cannot be empty";
}

// Now this is a compile error — types prevent transposition:
void SendEmail(Email from, Email to, Subject subject, string body) { }

// SendEmail(subject, body, to, from);  // ← compile error — Subject is not Email
```

The entire class of "wrong argument order" bugs disappears. Not at runtime — at compile time.
---

## 6.11 No Magic Numbers or Hard-Coded Values

**The principle:** every value that has a name should have that name in code.
Numbers and strings without names are called magic — they are invisible knowledge.

### The Bug It Prevents

```csharp
// ❌ Magic — what does 86400 mean? Why 5? Why "admin"?
if (elapsed > 86400) RefreshToken();
if (failedAttempts >= 5) LockAccount();
if (role == "admin") ShowDashboard();

// Six months later: someone changes one of the 86400s but misses another.
// Two different timeout values now exist in the codebase.
```

### The Fix

```csharp
// ✅ Named constants
private const int    TokenLifetimeSeconds   = 86_400; // 24 hours
private const int    MaxFailedLoginAttempts = 5;
private const string AdminRole              = "admin";

if (elapsed > TokenLifetimeSeconds) RefreshToken();
if (failedAttempts >= MaxFailedLoginAttempts) LockAccount();
if (role == AdminRole) ShowDashboard();

// Better still: a validated config value (see Chapter 23)
public class SecurityOptions
{
    public int TokenLifetimeSeconds   { get; set; } = 86_400;
    public int MaxFailedAttempts      { get; set; } = 5;
}
```

Rule: if a value appears more than once, it must be a constant or config value.
If it appears once but represents a domain concept, it still needs a name.

---

## 6.12 Naming Conventions — Code Is Read, Not Run

**The principle:** names are the primary documentation of code. A well-named method,
variable, or type tells the reader what it is and what it does without them having
to read the implementation. Code is read ten times for every one time it is written.

### The Bug It Prevents

```csharp
// ❌ Real code from a production codebase
public bool Chk(Order o, int t, bool f)
{
    if (o.St != 1) return false;
    return o.Am > t && !f;
}

// Six months later: what is t? What is f? What does St == 1 mean?
// The only way to know is to find every call site and reverse-engineer the intent.
// Meanwhile the person who wrote it has left the company.

// ✅ Same logic, readable
public bool IsEligibleForDiscount(Order order, int minimumAmount, bool isExcluded)
{
    if (order.Status != OrderStatus.Active) return false;
    return order.Amount > minimumAmount && !isExcluded;
}
// Readable in one pass. Intent is obvious. No call site hunting required.
```

### C# Standards

```csharp
public class OrderService            { }  // PascalCase — type
public interface IOrderRepository    { }  // I + PascalCase — interface
public record OrderId(Guid Value)    { }  // PascalCase — record
public enum OrderStatus { Pending }       // PascalCase — enum + values

public string CustomerName { get; set; } // PascalCase — property
public void   PlaceOrder() { }           // PascalCase — method
public const  int MaxRetries = 3;        // PascalCase — constant

private readonly IOrderRepository _orders; // _camelCase — private field
private int _retryCount;

var orderId = Guid.NewGuid();            // camelCase — local
void Process(string customerId) { }      // camelCase — parameter

public async Task<Order> GetOrderAsync() { } // always Async suffix on async methods
```

### Name the Intent, Not the Type

```csharp
// ❌ Describes the type, not the purpose
List<Order> orderList;
string      nameString;
bool        isActiveFlag;
OrderDto    orderDtoObject;

// ✅ Describes the purpose
List<Order> pendingOrders;
string      customerName;
bool        isActive;
OrderDto    orderSummary;
```

### Boolean Names Are Assertions

```csharp
// ❌ Ambiguous
bool active;  bool process;  bool check;

// ✅ Read as true/false assertions
bool isActive;  bool hasShippingAddress;  bool canRefund;  bool wasEmailSent;
```

### Method Names Are Verbs

```csharp
// ❌ Noun methods — unclear what they do
Order Order(int id);
bool  Email(string address);

// ✅ Verb methods — action is explicit
Order GetOrderById(int id);
bool  IsValidEmail(string address);
Task  SendWelcomeEmailAsync(string to);
void  CancelOrder(OrderId id);
```

---

## 6.13 Boy Scout Rule — Leave It Cleaner Than You Found It

**The principle:** whenever you touch a file, leave it slightly better than you found it.
Not a refactor — just one small thing: rename a confusing variable, extract a magic number,
delete dead code, add a missing null check.

**Why it exists:** codebases decay. Every "I'll fix it later" comment that never gets
fixed, every magic number added under deadline pressure, every renamed concept that
kept its old name in three files — these accumulate. The result is the kind of codebase
where nobody wants to work because every change risks breaking something mysterious.
The Boy Scout Rule creates continuous passive improvement with zero dedicated cleanup time.

### The Bug It Prevents

```csharp
// ❌ What you found while fixing an unrelated bug:
public void ProcessBatch(List<Order> d, bool f2)   // d? f2?
{
    var x = d.Where(i => i.s == 1).ToList();        // s? 1?
    if (x.Count > 0 && !f2)
        _svc.Run(x, 86400);                         // magic number
}

// You were only here to fix a null reference in _svc.Run().
// Takes 3 minutes extra. You leave it like this:

// ✅ After your Boy Scout pass (same bug fix + cleanup):
public void ProcessBatch(List<Order> orders, bool skipNotification)
{
    var activeOrders = orders.Where(o => o.Status == OrderStatus.Active).ToList();
    if (activeOrders.Count > 0 && !skipNotification)
        _svc.Run(activeOrders, TokenLifetimeSeconds);
}
```

The codebase improves continuously. No cleanup sprint required. No big rewrite needed.
Each developer leaves the campsite cleaner than they found it.

---

## 6.14 YAGNI — You Aren't Gonna Need It

**The principle:** do not add functionality until you actually need it.
Build for the requirements you have, not the ones you imagine.

**Why it exists:** developers are pattern-recognizers. They see a simple case
and immediately imagine five future variations. The instinct to generalize is strong
and feels responsible. But imagined requirements arrive differently than expected —
if they arrive at all. Every abstraction built for a requirement that never came
is dead weight the next developer has to navigate around, understand, and maintain.
The cost is paid immediately; the benefit never arrives.

```csharp
// ❌ Over-engineered for imagined futures
public async Task<Order?> GetByIdAsync(
    OrderId id,
    bool includeDeleted = false,    // nobody asked for this
    bool bypassCache    = false,    // there is no cache yet
    string? tenantId    = null)     // single tenant for now
{ }

// ✅ Build what's needed
public async Task<Order?> GetByIdAsync(OrderId id, CancellationToken ct) { }
// Add caching when needed — via the decorator pattern (Ch 21 §21.8)
// Add multi-tenancy when needed — with a real design
```

Adding complexity for imagined requirements makes code harder to read today
and harder to change when the real requirement arrives — always differently than imagined.

---

## 6.15 DRY — Don't Repeat Yourself

**The principle:** every piece of knowledge has one authoritative representation
in the system. When knowledge is duplicated, the copies diverge. When they diverge,
one is wrong. The bug lives in whichever copy someone forgot to update.

**Why it exists:** copy-paste is fast. It feels harmless for "just this one case".
But every pasted copy is a future bug — not a possibility, a certainty. Requirements
change. The developer who changes one copy does not know to find the other. DRY
is not about avoiding identical characters — two functions that happen to look
similar but represent different concepts should not be merged. DRY is specifically
about duplicated *knowledge*: a business rule, a validation limit, a formula, a
decision that lives in more than one place.

**Note:** DRY is about duplicated knowledge, not duplicated characters.

```csharp
// ❌ Two places know the same business rule — will diverge
// OrderService.cs:
if (order.Total > 50_000) throw new DomainException("Order too large");
// OrderValidator.cs:
if (request.Amount > 50_000) return ValidationError("Amount too large");

// ✅ One source of truth
public static class OrderLimits
{
    public const decimal MaxOrderValue = 50_000m;
}

// Both files reference OrderLimits.MaxOrderValue — change in one place
```

---

## 6.16 KISS — Keep It Simple, Stupid

**The principle:** the simplest solution that works is the right solution.
Complexity is not a sign of intelligence. It is a liability.

The failure mode is specific: developers feel that a simple solution is embarrassing,
so they add abstraction, generalization, and cleverness to make it feel "proper".
The result is code that does the same thing but nobody can read or change.

### The Problem

```csharp
// ❌ Clever — someone was proud of this
public T GetOrSet<T>(
    string key,
    Func<IServiceProvider, T> factory,
    TimeSpan? expiry = null,
    CacheItemPriority priority = CacheItemPriority.Normal,
    Func<T, bool>? shouldCache = null)
{
    if (_cache.TryGetValue(key, out T? cached) && (shouldCache?.Invoke(cached) ?? true))
        return cached!;
    var value = factory(_provider);
    if (shouldCache?.Invoke(value) ?? true)
        _cache.Set(key, value, new MemoryCacheEntryOptions
            { AbsoluteExpirationRelativeToNow = expiry, Priority = priority });
    return value;
}

// This is called from exactly one place, with exactly one set of arguments.
// The generalization serves nobody.
```

### The Fix

```csharp
// ✅ Simple — does exactly what is needed, nothing more
public User? GetCachedUser(int id)
{
    if (_cache.TryGetValue($"user:{id}", out User? user)) return user;
    user = _db.Users.Find(id);
    if (user is not null) _cache.Set($"user:{id}", user, TimeSpan.FromMinutes(5));
    return user;
}
// When a second cache use case arrives, extract what they share at that point.
// Not before.
```

**The test:** can a new developer understand this in 30 seconds?
If not, it is too complex — regardless of how elegant it feels to the author.

---

## 6.17 Law of Demeter — Only Talk to Your Immediate Friends

**The principle:** a method should only call methods on objects it directly owns.
Not on objects returned by those objects. Not on objects returned by those.

Each `.` after the first one is a red flag.

### The Bug It Prevents

```csharp
// ❌ Three levels deep — Order knows about Customer knows about Address knows about City
// OrderService is now coupled to Order, Customer, Address, AND City
decimal CalculateShipping(Order order)
{
    var city    = order.Customer.Address.City;      // what if Customer is null?
    var country = order.Customer.Address.Country;   // what if Address is null?
    return _rates[country][city];
}

// When Address gains a Region field and City becomes part of Region:
// var city = order.Customer.Address.Region.City;
// OrderService must change — it has nothing to do with Region.
```

### The Fix

```csharp
// ✅ Tell Order to give you what you need — it handles its own structure
decimal CalculateShipping(Order order)
{
    var destination = order.GetShippingDestination(); // Order owns this
    return _rates.Calculate(destination);
}

// Order encapsulates access to its own data
public record ShippingDestination(string City, string Country);

public class Order
{
    private readonly Customer _customer;
    public ShippingDestination GetShippingDestination()
        => new(_customer.Address.City, _customer.Address.Country);
}
// Now Address can restructure — Order updates its method, nobody else changes.
```

**Rule:** one dot is fine. Two dots is a smell. Three dots is a bug waiting to happen.
Exception: fluent APIs and LINQ chains are designed for chaining — they are not violations.

---

## 6.18 Tell, Don't Ask

**The principle:** tell objects what to do rather than asking for their state
and making decisions externally.

This is the runtime consequence of the Anemic Domain Model anti-pattern (Ch 21 §21.10).
When you ask for state to make a decision, the decision belongs inside the object.

### The Bug It Prevents

```csharp
// ❌ Asking — decision logic is external, duplicated at every call site
// OrderController.cs:
if (order.Status == "Pending" && order.PaymentConfirmed && !order.IsExpired)
    order.Status = "Confirmed";

// OrderService.cs (same logic, slightly different):
if (order.Status == "Pending" && order.PaymentConfirmed)
    order.Status = "Confirmed";  // forgot IsExpired check — silent bug

// Two places know the confirmation rules. They will diverge.
```

### The Fix

```csharp
// ✅ Telling — the decision lives inside the object, one place, always correct
public class Order
{
    public void Confirm()
    {
        if (Status != OrderStatus.Pending)
            throw new DomainException("Only pending orders can be confirmed.");
        if (!PaymentConfirmed)
            throw new DomainException("Payment not confirmed.");
        if (IsExpired)
            throw new DomainException("Order has expired.");
        Status = OrderStatus.Confirmed;
    }
}

// OrderController.cs — just tells the order what to do:
order.Confirm();

// OrderService.cs — same:
order.Confirm();
// Both use the same logic. It cannot diverge.
```

---

## 6.19 Command Query Separation

**The principle:** a method either changes state (command) or returns data (query).
Never both.

### The Bug It Prevents

```csharp
// ❌ Does both — saves AND returns — caller cannot read without side effects
public Order SaveAndReturn(CreateOrderRequest req)
{
    var order = new Order(req);
    _db.Save(order);         // side effect
    return order;            // also returns data
}

// Now you cannot "just look" at an order without saving it.
// Cannot call this in a test to inspect the result without hitting the DB.
// Cannot call it twice without saving twice.

// Another common violation:
public bool IsActiveUser(int id)
{
    var user = _db.Find(id);
    user.LastChecked = DateTime.UtcNow;  // side effect hidden in a query!
    _db.Save(user);
    return user.IsActive;
}
```

### The Fix

```csharp
// ✅ Command — changes state, returns nothing (or Result for error signalling)
public Result<OrderId, DomainError> PlaceOrder(CreateOrderRequest req)
{
    var order = new Order(req);
    _db.Save(order);
    return order.Id;        // only the ID — not the full object
}

// ✅ Query — reads state, no side effects
public Order? GetOrder(OrderId id) => _db.Find(id.Value);

// Callers compose them:
var result = PlaceOrder(req);
if (result.IsOk)
{
    var order = GetOrder(result.Value); // separate, pure read
}
```

**Exception:** factory methods that both create and return an object are fine —
the creation IS the point. The rule applies to methods where the side effect is hidden.


---

## 6.20 The Order of Importance

If you could follow only three:

```
1. Make illegal states unrepresentable   — invalid data cannot exist
2. Errors are values                     — failure paths are visible and handled
3. Explicit over implicit                — code is readable without running it
```

The rest compound on top of those. Get these three right and the others follow naturally.

---

## 6.21 Checking Yourself

Before committing any class or method, ask:

```
Can this be constructed in an invalid state?        → §6.1  Make illegal states unrepresentable
Can callers ignore failure paths?                   → §6.3  Errors are values
Does it take/return naked primitives with meaning?  → §6.10 Domain primitives
Does this class do more than one thing?             → §6.7  Single responsibility
Does it depend on something not in its signature?   → §6.6  Explicit over implicit
Could a new enum/union case be silently ignored?    → §6.5  Totality
Is there a number or string literal with no name?   → §6.11 No magic numbers
Does a method chain through three or more objects?  → §6.17 Law of Demeter
Does code outside the object decide its state?      → §6.18 Tell, don't ask
Does a method both change state AND return data?    → §6.19 Command query separation
Did I write more than I need right now?             → §6.14 YAGNI
Is the simplest solution actually shipping?         → §6.16 KISS
```

Yes to any of these is a signal to redesign before the bug exists.

---

## 6.22 The One Idea Behind All of It

Every principle above is ultimately the same idea expressed from a different angle:
**localise change**.

When a requirement changes — and it always does — you want to touch as few places as
possible, and you want those places to be obvious. Bad design means a small requirement
change ripples across twenty files. Good design means it touches one. Every principle
is a strategy for achieving that localisation.

Once you see this thread, the principles stop feeling like a checklist and start
feeling derivable. You could almost rediscover them yourself by asking "what makes
change expensive?" and systematically eliminating each answer:

```
What makes change expensive?
  → Duplicated knowledge (DRY)
  → Hidden dependencies (Explicit over Implicit)
  → Scattered decisions (Tell Don't Ask)
  → Classes with multiple reasons to change (SRP)
  → Inheritance hierarchies that must all move together (Composition over Inheritance)
  → Invalid states that must be defended everywhere (Make Illegal States Unrepresentable)
  → Invisible failure paths (Errors are Values)
```

They are all the same answer, zoomed into different parts of the codebase.

---

## 6.23 The Anemic Domain Model — The Most Common Violation

Martin Fowler named this anti-pattern in 2003. Two decades later it remains
the dominant structure in enterprise C# codebases.

An anemic domain model is one where entities are passive data bags — public getters
and setters, no behaviour, no enforcement of their own rules. All the logic lives
in service classes that reach in, read state, make decisions, and mutate the entity
directly:

```csharp
// Anemic entity — a database row with C# syntax
public class Order
{
    public int      Id         { get; set; }
    public string   Status     { get; set; } = "pending"; // magic string
    public decimal  Total      { get; set; }
    public DateTime? ShippedAt { get; set; }
}

// OrderService does everything the entity should know about itself
public class OrderService
{
    public void Ship(Order order)
    {
        if (order.Status != "paid")
            throw new Exception("Cannot ship unpaid order");

        order.Status   = "shipped";       // anyone can do this directly
        order.ShippedAt = DateTime.Now;   // bypassing every rule
    }

    public void Cancel(Order order, string reason)
    {
        if (order.Status == "shipped")
            throw new Exception("Cannot cancel shipped order");
        if (order.Status == "delivered")    // same check, different method — will drift
            throw new Exception("Cannot cancel delivered order");

        order.Status = "cancelled";
    }
}
```

The problem is not the service itself — services are necessary. The problem is
that the *decision logic* lives outside the entity while the *data* lives inside it.
They are split. Now:

- Nothing stops `order.Status = "shipped"` directly — bypassing every check
- The cancellation rules are duplicated in every method that touches status
- A new developer has no idea the rules exist without reading all services
- The compiler sees nothing wrong with any illegal state

This violates §6.1 (illegal states unrepresentable), §6.18 (tell don't ask),
§6.15 (DRY — the rules for cancellation are duplicated), and §6.6 (explicit —
the rules are hidden in services, not declared in the type).

The seductive argument for anemic models is "the Core should have no dependencies,
and behaviour depends on services". This confuses two different things. An entity's
*invariant enforcement* requires no dependencies at all — knowing that a shipped
order must have been paid does not require a database, an email sender, or an HTTP
client. The rule "no dependencies in the domain" means no *infrastructure*
dependencies. It does not mean no *behaviour*.

---

## 6.24 The Rich Domain Model — Entities That Own Their Invariants

A rich domain model moves the decision logic back where it belongs — inside the
entity that owns the data. The entity becomes a gatekeeper: you can only modify
it through methods that enforce the rules. The compiler and the runtime make
illegal states impossible, not just discouraged.

```csharp
public class Order
{
    // Private setters — nothing outside this class can mutate state directly
    public OrderId     Id         { get; private set; }
    public OrderStatus Status     { get; private set; }  // enum, not string
    public Money       Total      { get; private set; }  // value object, not decimal
    public DateTime?   ShippedAt  { get; private set; }

    private readonly List<OrderItem> _items = new();
    public IReadOnlyList<OrderItem> Items => _items.AsReadOnly();

    // Factory method — the only valid way to create an Order
    public static Order Place(CustomerId customerId, IEnumerable<OrderItem> items)
    {
        var list = items.ToList();
        if (!list.Any())
            throw new OrderException(OrderError.OrderMustHaveItems, default);

        return new Order
        {
            Id     = OrderId.New(),
            Status = OrderStatus.Pending,
            Total  = list.Aggregate(Money.Zero("EUR"), (acc, i) => acc.Add(i.LineTotal))
        };
    }

    // Behaviour — the entity decides what shipping means and what allows it
    public Result Ship()
    {
        if (Status != OrderStatus.Paid)
            return Result.Fail(Error.CannotShipUnpaidOrder(Id));

        Status    = OrderStatus.Shipped;
        ShippedAt = DateTime.UtcNow;
        return Result.Ok();
    }

    public Result Cancel(string reason)
    {
        if (Status is OrderStatus.Shipped or OrderStatus.Delivered)
            return Result.Fail(Error.CannotCancelShippedOrder(Id));

        if (string.IsNullOrWhiteSpace(reason))
            return Result.Fail(new Error("REASON_REQUIRED", "Cancellation reason required."));

        Status       = OrderStatus.Cancelled;
        CancelReason = reason;
        return Result.Ok();
    }
}
```

Now `order.Status = "shipped"` is a compile error — `Status` has no public setter.
The only path to `Shipped` is through `Ship()`, which enforces payment first.
The rule exists in exactly one place. It cannot drift.

The service becomes a coordinator, not a decision-maker:

```csharp
public class ShipOrderHandler(IOrderRepository orders)
{
    public async Task<Result> HandleAsync(ShipOrderCommand cmd, CancellationToken ct)
    {
        var order = await orders.GetByIdAsync(cmd.OrderId, ct);
        if (order is null) return Result.Fail(Error.OrderNotFound(cmd.OrderId));

        var result = order.Ship();          // entity enforces the rule
        if (result.IsFailure) return result;

        await orders.SaveAsync(order, ct);
        return Result.Ok();
    }
}
```

The handler has no if-statements about order status. It does not need to.
The entity handles that. This is §6.18 (Tell Don't Ask) expressed architecturally.

---

## 6.25 Value Objects — Primitives With Domain Meaning

The principle in §6.10 says to wrap naked primitives. Here is the full picture of
what value objects are and why they are not just wrapper classes.

A value object is defined entirely by its content. Two value objects with the same
content are equal. They have no identity beyond their value. They are immutable.
They enforce their own validity at construction — if construction succeeds, the
object is valid. Always. No re-checking required anywhere in the system.

```csharp
// Without value objects: scattered rules, silent bugs
void SendEmail(string from, string to, string subject) { }
SendEmail(subject, to, from);   // transposed — compiles, fails silently

// With value objects: rules enforced once, bugs impossible
public sealed record EmailAddress
{
    public string Value { get; }

    public EmailAddress(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("Email cannot be empty");
        if (!value.Contains('@'))
            throw new ArgumentException($"'{value}' is not a valid email");

        Value = value.Trim().ToLowerInvariant(); // normalised at construction
    }

    public override string ToString() => Value;
    public static implicit operator string(EmailAddress e) => e.Value;
}

void SendEmail(EmailAddress from, EmailAddress to, Subject subject) { }
// SendEmail(subject, to, from) → compile error — Subject is not EmailAddress
```

Value objects collapse three things into one:
1. Validation — runs at construction, nowhere else
2. Normalisation — `ToLowerInvariant()` happens once, the value is always clean
3. Type safety — `EmailAddress` and `Subject` cannot be confused by position

The subtler benefit: when `EmailAddress` is accepted throughout your codebase, a new
developer immediately knows that any `EmailAddress` parameter is already valid and
normalised. They do not check again. They do not need to. The type is proof.

```csharp
// Strongly typed IDs — the most valuable and most ignored value object
public readonly record struct OrderId(Guid Value)
{
    public static OrderId New()             => new(Guid.NewGuid());
    public static OrderId From(Guid value)  => new(value);
    public override string ToString()       => Value.ToString();
}

public readonly record struct CustomerId(Guid Value)
{
    public static CustomerId New()           => new(Guid.NewGuid());
    public static CustomerId From(Guid value) => new(value);
}

// Without typed IDs: these compile and silently corrupt data
void ProcessOrder(Guid orderId, Guid customerId) { }
ProcessOrder(customerId, orderId);   // transposed — silent data corruption

// With typed IDs: compile error
void ProcessOrder(OrderId orderId, CustomerId customerId) { }
ProcessOrder(customerId, orderId);   // CS1503 — cannot convert CustomerId to OrderId
```

---

## 6.26 Failures as Values — The Full Result Pattern

§6.3 introduced the principle. This section shows the full implementation and
the philosophy behind choosing exceptions versus Result.

### The Two Categories of Failure

```
Infrastructure failure:          Business failure:
  Disk full                        Order cannot be shipped — not paid
  Network timeout                  User not found
  Database connection lost         Insufficient stock
  Out of memory                    Password validation failed

→ throw Exception                → return Result<T>
  (unrecoverable, log and crash)   (expected outcome, caller handles it)
```

The test: could a correct, well-behaved caller encounter this failure in normal
operation? If yes, it is a business failure — return Result. If the only way to
encounter it is through a programming error or infrastructure collapse — throw.

### Railway Oriented Programming

The mental model for working with Result chains. A computation is a railway track
with two rails: the success rail and the failure rail. Each function is a step on
the track. If a step succeeds, it stays on the success rail and the next step runs.
If a step fails, it switches to the failure rail and stays there — subsequent steps
are skipped automatically.

```csharp
// Without Railway — nested ifs, early returns, hard to follow
public async Task<Result<OrderId>> PlaceOrderAsync(PlaceOrderCommand cmd, CancellationToken ct)
{
    var customer = await _customers.GetByIdAsync(cmd.CustomerId, ct);
    if (customer is null)
        return Result<OrderId>.Fail(Error.CustomerNotFound(cmd.CustomerId));

    if (!customer.IsActive)
        return Result<OrderId>.Fail(Error.CustomerInactive(cmd.CustomerId));

    var order = Order.Place(cmd.CustomerId, cmd.Items);
    if (order.IsFailure)
        return Result<OrderId>.Fail(order.Error!);

    await _orders.AddAsync(order.Value!, ct);
    return Result<OrderId>.Ok(order.Value!.Id);
}

// With Railway — linear pipeline, failure short-circuits automatically
public async Task<Result<OrderId>> PlaceOrderAsync(PlaceOrderCommand cmd, CancellationToken ct)
{
    return await _customers.GetByIdAsync(cmd.CustomerId, ct)
        .ToResult(Error.CustomerNotFound(cmd.CustomerId))
        .Ensure(c => c.IsActive, Error.CustomerInactive(cmd.CustomerId))
        .Then(customer => Order.Place(customer.Id, cmd.Items))
        .ThenAsync(order => _orders.AddAsync(order, ct)
            .ContinueWith(_ => Result<OrderId>.Ok(order.Id)));
}
```

### Typed Error Codes — Machine-Readable and Stable

Throwing exceptions with string messages is honest about failure but forces callers
to parse strings to distinguish failure types — fragile and invisible. The solution
is an error type with a stable code and a human-readable message:

```csharp
public sealed record Error(string Code, string Message)
{
    // Static factories make usage read naturally at the call site
    public static Error CustomerNotFound(CustomerId id) =>
        new("CUSTOMER_NOT_FOUND", $"Customer {id} does not exist.");

    public static Error CannotShipUnpaidOrder(OrderId id) =>
        new("ORDER_NOT_PAID", $"Order {id} must be paid before shipping.");

    public static Error InsufficientStock(Guid productId, int requested) =>
        new("INSUFFICIENT_STOCK", $"Product {productId} has insufficient stock for {requested} units.");
}
```

The `Code` is for programs — it is stable, never changes even if the message wording
does. The `Message` is for developers and logs. The controller maps codes to HTTP
status codes without string parsing:

```csharp
return result.Match(
    onSuccess: id   => CreatedAtAction(...),
    onFailure: error => error.Code switch
    {
        "CUSTOMER_NOT_FOUND"  => NotFound(error.Message),
        "ORDER_NOT_PAID"      => UnprocessableEntity(error.Message),
        "INSUFFICIENT_STOCK"  => Conflict(error.Message),
        _                     => BadRequest(error.Message)
    });
```

### Exception Messages in the Domain Layer

Hardcoded strings in `throw` statements inside domain entities are fine for one
purpose: developer diagnostics. Exception messages appear in logs and test failure
output where a human reads them. For that purpose, a clear descriptive string is
correct and hardcoding is appropriate.

They are wrong when passed directly to API consumers or when callers need to
distinguish failure types programmatically. For those cases use typed errors
(as above) or the Result pattern. The rule is simple:

```
Domain entity throws → use for programmer errors (null args, broken invariants)
Domain entity returns Result → use for expected business failures
API controller catches → map typed errors to HTTP codes, never string-match messages
```

---

## 6.27 Domain Services — Behaviour That Does Not Belong to One Entity

When a business rule involves multiple aggregates and cannot logically belong to
either alone, it belongs in a Domain Service. The smell that tells you one is needed:
you find yourself writing `order.ApplyCustomerDiscount(customer)` — one entity
reaching into another entity's data to make a decision.

```csharp
// WRONG: Order knows about Customer internals
public class Order
{
    public void ApplyDiscount(Customer customer)
    {
        if (customer.TierLevel == "Gold")   // Order coupled to Customer structure
            Total = Total.Multiply(0.9m);
    }
}

// CORRECT: Domain Service knows both, neither entity knows the other
// Lives in the Domain layer — pure logic, no infrastructure
public class OrderPricingService
{
    public Result<Money> CalculateFinalPrice(Order order, Customer customer)
    {
        var discount = customer.Tier switch
        {
            CustomerTier.Gold     => 0.10m,
            CustomerTier.Silver   => 0.05m,
            _                     => 0.00m
        };

        var discounted = order.Total.Multiply(1 - discount);

        if (discounted.Amount > customer.CreditLimit)
            return Result<Money>.Fail(new Error("OVER_CREDIT_LIMIT",
                $"Order total {discounted} exceeds credit limit {customer.CreditLimit}."));

        return Result<Money>.Ok(discounted);
    }
}
```

The boundary between Domain Service and Application Service (handler) is sharp:

```
Domain Service:
  ✓ Pure business logic involving multiple entities or value objects
  ✓ No infrastructure dependencies — no DB, no HTTP, no email
  ✓ Lives in the Domain project
  ✓ Returns domain objects or Result<T>

Application Service / Handler:
  ✓ Orchestrates: loads aggregates, calls domain, persists, publishes events
  ✓ Has infrastructure dependencies via interfaces
  ✓ Lives in the Application project
  ✗ Never contains business rules — only coordination
```

If you find yourself putting an `IOrderRepository` into a Domain Service, stop —
you are writing an Application Service. Domain Services receive already-loaded
domain objects as parameters. They never load them themselves.

---

## 6.28 Aggregate Roots — Consistency Boundaries

An aggregate is a cluster of objects that must be consistent with each other at all
times. The aggregate root is the single gatekeeper — all modifications to the cluster
must go through it. This directly implements §6.1 (illegal states unrepresentable)
and §6.18 (tell don't ask) at the object graph level.

```csharp
// Without aggregate root: the items collection is publicly exposed
// Nothing prevents bypassing Order's rules
order.Items.Add(new OrderItem(...));   // Total is now wrong
order.Items.Clear();                   // order has no items — invalid state
order.Items[0].Quantity = 0;           // invalid quantity, unchecked

// With aggregate root: all mutations go through methods that maintain invariants
public class Order   // aggregate root
{
    private readonly List<OrderItem> _items = new();
    public IReadOnlyList<OrderItem> Items => _items.AsReadOnly(); // read-only view

    public Result AddItem(Guid productId, string name, int quantity, Money unitPrice)
    {
        if (Status != OrderStatus.Pending)
            return Result.Fail(new Error("ORDER_LOCKED",
                "Items can only be added to Pending orders."));

        if (quantity <= 0)
            return Result.Fail(new Error("INVALID_QUANTITY", "Quantity must be positive."));

        var existing = _items.FirstOrDefault(i => i.ProductId == productId);
        if (existing is not null)
            existing.IncreaseQuantity(quantity);  // merge, not duplicate
        else
            _items.Add(new OrderItem(productId, name, quantity, unitPrice));

        RecalculateTotal();  // invariant maintained here, not by the caller
        return Result.Ok();
    }

    private void RecalculateTotal()
    {
        Total      = _items.Aggregate(Money.Zero(Total.Currency), (a, i) => a.Add(i.LineTotal));
        IsPriority = Total.Amount >= 500m;
    }
}
```

### The Aggregate Boundary Is a Transaction Boundary

Everything inside one aggregate saves atomically. Changes across two aggregates
require two transactions — they achieve consistency eventually via domain events,
not by sharing a transaction.

```csharp
// WRONG: two aggregates in one transaction
// If Inventory save fails, Order is in a corrupt state
await _db.SaveChangesAsync();   // saves Order AND Inventory together

// CORRECT: each aggregate has its own transaction
// Consistency across aggregates via domain events
await _orders.AddAsync(order, ct);          // transaction 1: save order

await _events.PublishAsync(                  // signals Inventory to decrement
    new OrderPlacedEvent(order.Id, order.Items), ct);
// Inventory handler runs separately, in its own transaction
// If it fails, a compensating event is raised — not a transaction rollback
```

### How Large Should an Aggregate Be?

Small. The temptation is to aggregate eagerly. Resist it.

```
WRONG — Customer swallowed by Order:    CORRECT — separate aggregates:
Order                                   Order
  ├── OrderItems ✓                        ├── OrderItems ✓
  ├── Customer ✗ (own lifecycle)          └── CustomerId (reference only)
  ├── ShippingAddress ✓ (value object)
  └── Invoice ✗ (own lifecycle)         Customer (separate)
                                         Invoice (separate)
```

If an object has its own identity, its own lifecycle, and its own invariants, it
is its own aggregate. Reference it by ID, not by navigation property. This keeps
aggregates small, transactions fast, and concurrency conflicts rare.

---

## 6.29 CQRS — Reads and Writes Are Different Problems

Command Query Responsibility Segregation is §6.19 (Command Query Separation) applied
at the architectural level. The insight it adds: not only should individual methods
be either commands or queries, but the entire stack for reads and writes should be
separate, because they have fundamentally different needs.

The rich domain model built in §6.24 is optimised for enforcing invariants. It is
wrong for reads. Loading an `Order` aggregate with its items, value objects, and
factory methods just to render a list page is wasteful in three ways:
- It loads more data than the query needs
- It cannot naturally join `Customer.Name` without a second query
- It forces every read to pay the overhead of the write model

```csharp
// WRONG for reads: loads the full aggregate, triggers N+1 for CustomerName
var orders   = await _orderRepo.GetAllAsync(ct);
var summaries = await Task.WhenAll(orders.Select(async o => new OrderSummaryDto(
    o.Id.Value,
    (await _customerRepo.GetByIdAsync(o.CustomerId, ct))!.Name,  // N+1
    o.Status.ToString(),
    o.Total.ToString(),
    o.Items.Count)));

// CORRECT for reads: direct SQL, one query, exactly the shape needed
public class GetOrdersHandler(IDbConnectionFactory db)
{
    public async Task<IReadOnlyList<OrderSummaryDto>> HandleAsync(
        GetOrdersQuery query, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);

        return (await conn.QueryAsync<OrderSummaryDto>("""
            SELECT
                o.id,
                c.name           AS customer_name,
                o.status,
                o.total_amount,
                o.total_currency,
                o.is_priority,
                o.created_at,
                COUNT(i.id)      AS item_count
            FROM orders o
            JOIN customers c ON c.id = o.customer_id
            LEFT JOIN order_items i ON i.order_id = o.id
            WHERE (@Status IS NULL OR o.status = @Status)
            GROUP BY o.id, c.name, o.status,
                     o.total_amount, o.total_currency,
                     o.is_priority, o.created_at
            ORDER BY o.created_at DESC
            LIMIT @PageSize OFFSET @Offset
            """, new { query.Status, query.PageSize, Offset = query.Page * query.PageSize }))
            .ToList();
    }
}
```

The read handler has no domain entity, no repository interface, no value objects.
It runs one SQL query and maps the result. It is completely independent of the write
stack. Optimise the SQL, add an index, add a new column — no domain class changes.

### The File Structure That Makes CQRS Visible

```
Application/
└── Orders/
    ├── Commands/              ← write stack
    │   ├── PlaceOrder/
    │   │   ├── PlaceOrderCommand.cs
    │   │   └── PlaceOrderHandler.cs
    │   └── ShipOrder/
    │       ├── ShipOrderCommand.cs
    │       └── ShipOrderHandler.cs
    └── Queries/               ← read stack
        ├── GetOrders/
        │   ├── GetOrdersQuery.cs
        │   ├── GetOrdersHandler.cs
        │   └── OrderSummaryDto.cs     ← read model, flat, optimised for display
        └── GetOrderById/
            ├── GetOrderByIdQuery.cs
            ├── GetOrderByIdHandler.cs
            └── OrderDetailDto.cs
```

The directory structure makes the separation visible. A new developer opening
`Commands/` knows they are in write territory. Opening `Queries/` knows they are
in read territory. The models never cross.

---

## 6.30 Where DTOs and Persistence Models Live

This question resolves naturally once you accept that every model has exactly one
master. The mistake that leads to polluted domain entities is asking one model to
serve multiple masters simultaneously.

```
Model              Master              Location
─────────────────────────────────────────────────────────────
Domain Entity      Business rules      Domain project
Persistence Model  Database schema     Infrastructure project
Command/Query DTO  Application use     Application project
Request/Response   HTTP contract       API project
```

```
OrderApp/
├── Domain/
│   └── Orders/
│       ├── Order.cs              ← no [Column], no [JsonProperty], pure domain
│       └── IOrderRepository.cs  ← interface only, defined by the domain
│
├── Infrastructure/
│   └── Persistence/
│       ├── Models/
│       │   └── OrderDbModel.cs  ← EF Core entity, flat, maps to table columns
│       ├── Mappings/
│       │   └── OrderMapping.cs  ← domain ↔ db translation, the only place that knows both
│       └── OrderRepository.cs   ← implements IOrderRepository
│
├── Application/
│   └── Orders/
│       └── Queries/
│           └── GetOrders/
│               └── OrderSummaryDto.cs  ← read model for this specific query
│
└── Api/
    └── Orders/
        ├── Requests/
        │   └── PlaceOrderRequest.cs   ← JSON shape the API accepts
        ├── Responses/
        │   └── OrderResponse.cs       ← JSON shape the API returns
        └── Mappings/
            └── OrderApiMapping.cs     ← request/response ↔ command/query, the only place that knows both
```

Yes, this is duplication. The `Order.Id` field exists as `OrderId Id` in the domain,
as `Guid Id` in the persistence model, and as `Guid id` in the response DTO. That
duplication is not a smell — it is the cost of having each model be honest about
what it is for. The alternative — one model carrying `[Column("id")]` and
`[JsonPropertyName("id")]` next to domain methods — is a model lying in all three
directions at once.

The duplication cost is a few mapping files. The benefit is that when the
database schema renames a column, you touch the persistence model and its mapping.
The domain entity never changes. The API response never changes. Each layer is
protected from the other's changes.

---

## 6.31 Connascence — The Deep Theory of Coupling

Most developers know "coupling is bad" but cannot say precisely what it is.
Connascence is the precise definition. Two components are connascent if a change
to one requires a change to the other to preserve correctness.

There is a hierarchy from weakest (tolerable) to strongest (catastrophic):

**Connascence of Name** — they share a name. Method name, variable name.
The weakest form — refactoring tools handle it automatically.
```csharp
order.Ship();   // OrderController and ShipOrderHandler both call Ship() — name connascence
```

**Connascence of Type** — they share a type. Normal and acceptable.
```csharp
void Process(Order order) { }   // caller and callee share the Order type
```

**Connascence of Meaning** — they share an implicit convention. The most insidious.
```csharp
// "0 = success, 1 = validation failure, 2 = not found" — where is this documented?
// Change one side and nothing tells you to update the other.
int result = ProcessOrder(request);
if (result == 1) ShowValidationError();  // what if ProcessOrder changes 1 to mean something else?
```

**Connascence of Position** — they depend on argument order.
```csharp
CreateUser("Alice", "Smith", 30);   // which is first name? second name? age?
// Swap two strings — compiles, wrong, silent
// Value objects (§6.10 and §6.25) eliminate this entirely
```

**Connascence of Algorithm** — both sides must use the same algorithm.
```csharp
// Client hashes password with SHA-256 before sending
// Server validates the hash with SHA-256
// Change one → the other breaks silently — no compiler error, no test failure
// Fix: own the algorithm in one shared type
```

**Connascence of Execution** — they must be called in a specific order.
```csharp
var service = new OrderService();
service.Init();          // must call before Process
service.Process(order);  // must call before Complete
service.Complete();      // temporal coupling — the worst kind
// Fix: constructor establishes valid initial state, no Init() required
```

Once you have this vocabulary you can name exactly what is wrong with a piece of
code. "This is connascence of algorithm between the client and the server —
we need to own this in a shared library." Naming the problem precisely is
halfway to solving it.

### The Stability Direction Rule

Depend in the direction of stability. A module that changes rarely should not
depend on a module that changes frequently.

```
Stable (changes rarely):     Unstable (changes often):
  Domain rules                 API contract
  Core algorithms              Database schema
  Mathematical operations      UI layout
  Business invariants          Configuration format

Rule: unstable things depend on stable things.
      Stable things never depend on unstable things.

This is why the Domain has no dependencies.
This is why Infrastructure depends on Domain, not the other way around.
This is why the API project depends on Application, which depends on Domain.
The arrow always points toward the most stable thing.
```

---

## 6.32 The Revised Self-Check

The original checklist in §6.21 plus the structural questions from this section:

```
On any class or method:
  Can this be constructed in an invalid state?             → §6.1  Illegal states
  Can callers ignore failure paths?                        → §6.3  Errors are values
  Does it take/return naked primitives with domain meaning? → §6.10 Domain primitives
  Does this class have more than one reason to change?     → §6.7  SRP
  Does it depend on something not in its signature?        → §6.6  Explicit over implicit
  Could a new enum case be silently ignored?               → §6.5  Totality
  Is there a number or string literal with no name?        → §6.11 No magic numbers
  Does a method chain through three or more objects?       → §6.17 Law of Demeter
  Does code outside an entity decide its state?            → §6.18 Tell, don't ask
  Does a method both change state AND return data?         → §6.19 CQS
  Did I write more than the current requirement needs?     → §6.14 YAGNI
  Is the simplest solution actually shipping?              → §6.16 KISS

On domain entities:
  Can an entity be put into an invalid state by any caller? → §6.23 Rich domain model
  Are business rules for this entity scattered in services? → §6.23 Anemic domain model
  Do primitives carry domain meaning without a wrapper?     → §6.25 Value objects
  Does a rule involve two entities but live in one of them? → §6.27 Domain services
  Can anything bypass the aggregate root to mutate items?   → §6.28 Aggregates

On architecture:
  Is a read operation using the full write-side domain model? → §6.29 CQRS
  Does a model serve more than one master (DB + JSON + rules)? → §6.30 DTO placement
  Does a stable module depend on an unstable one?             → §6.31 Connascence / stability
  Can a failure type be distinguished without parsing strings? → §6.26 Typed errors
```

Yes to any of these is a signal to redesign before the bug exists.

