# Chapter 25 — Attributes, Reflection & Source Generators

## 25.1 What Attributes Are

Attributes are metadata attached to types, methods, parameters, and assemblies.
They are not code — they do not execute. They are annotations that other code
reads at runtime (via reflection) or at compile time (via source generators or analyzers).

```csharp
// Built-in attributes you already use constantly:
[Required]                    // data annotations
[HttpGet("/orders")]          // ASP.NET Core routing
[JsonPropertyName("id")]      // System.Text.Json
[Obsolete("Use NewMethod()")]  // compiler warning
[DebuggerStepThrough]         // debugger hint
[Serializable]                // serialization hint
[Flags]                       // enum flags
[ThreadStatic]                // per-thread static field

// Every one of these is just a class that inherits from System.Attribute.
// There is no magic. The framework reads them via reflection.
```

---

## 25.2 Defining Custom Attributes

```csharp
// Step 1: Define the attribute class
[AttributeUsage(
    AttributeTargets.Method | AttributeTargets.Class,  // where it can be applied
    AllowMultiple = false,                              // can it appear more than once
    Inherited = true)]                                  // does it inherit to subclasses
public sealed class AuditAttribute : Attribute
{
    public string Action { get; }
    public bool RequiresAdminRole { get; init; }

    public AuditAttribute(string action)
    {
        Action = action;
    }
}

// Step 2: Apply it
[Audit("ViewOrders")]
public IActionResult GetOrders() => Ok(_orders.GetAll());

[Audit("DeleteOrder", RequiresAdminRole = true)]
public IActionResult DeleteOrder(int id) { /* ... */ return NoContent(); }
```

### AttributeTargets Reference

```csharp
AttributeTargets.Assembly       // assembly-level attribute
AttributeTargets.Class          // class declaration
AttributeTargets.Struct         // struct declaration
AttributeTargets.Interface      // interface declaration
AttributeTargets.Enum           // enum declaration
AttributeTargets.Constructor    // constructor
AttributeTargets.Method         // method
AttributeTargets.Property       // property
AttributeTargets.Field          // field
AttributeTargets.Parameter      // method parameter
AttributeTargets.ReturnValue    // method return value
AttributeTargets.GenericParameter // type parameter T
AttributeTargets.All            // everything
```

---

## 25.3 Reading Attributes via Reflection

```csharp
// Read attribute from a method at runtime
var method = typeof(OrdersController).GetMethod(nameof(GetOrders));
var audit   = method?.GetCustomAttribute<AuditAttribute>();

if (audit is not null)
{
    Console.WriteLine($"Action: {audit.Action}");
    Console.WriteLine($"RequiresAdmin: {audit.RequiresAdminRole}");
}

// Read all attributes of a type
var allAttribs = typeof(OrdersController)
    .GetCustomAttributes(inherit: true)
    .ToList();

// Check if attribute is present
bool hasAudit = method?.IsDefined(typeof(AuditAttribute), inherit: false) ?? false;

// Read from parameter
var param = method?.GetParameters().FirstOrDefault(p => p.Name == "id");
var fromRoute = param?.GetCustomAttribute<FromRouteAttribute>();
```

### Real-World Use: Audit Logging Middleware

```csharp
// Filter that reads the [Audit] attribute and logs accordingly
public class AuditFilter : IActionFilter
{
    private readonly ILogger<AuditFilter> _log;
    private readonly ICurrentUserService _user;

    public AuditFilter(ILogger<AuditFilter> log, ICurrentUserService user)
    { _log = log; _user = user; }

    public void OnActionExecuting(ActionExecutingContext context)
    {
        var audit = context.ActionDescriptor
            .EndpointMetadata
            .OfType<AuditAttribute>()
            .FirstOrDefault();

        if (audit is null) return;

        if (audit.RequiresAdminRole && !_user.IsAdmin)
        {
            context.Result = new ForbidResult();
            return;
        }

        _log.LogInformation("Audit: {Action} by {User}", audit.Action, _user.Name);
    }

    public void OnActionExecuted(ActionExecutedContext context) { }
}
```

---

## 25.4 Reflection — Reading Types at Runtime

Reflection lets you inspect and invoke types, methods, and properties at runtime
without knowing them at compile time. It powers: ORMs, DI containers, serializers,
test frameworks, attribute processors.

```csharp
// Inspect a type
Type t = typeof(Order);

Console.WriteLine(t.Name);           // "Order"
Console.WriteLine(t.FullName);       // "MyApp.Domain.Order"
Console.WriteLine(t.IsClass);        // true
Console.WriteLine(t.IsValueType);    // false
Console.WriteLine(t.BaseType?.Name); // "Object"

// Get methods
foreach (var method in t.GetMethods(BindingFlags.Public | BindingFlags.Instance))
    Console.WriteLine($"  {method.ReturnType.Name} {method.Name}()");

// Get properties
foreach (var prop in t.GetProperties())
    Console.WriteLine($"  {prop.PropertyType.Name} {prop.Name}");

// Create instance without knowing the type at compile time
var instance = Activator.CreateInstance(t);

// Invoke a method dynamically
var method2 = t.GetMethod("Ship");
method2?.Invoke(instance, null);

// Read/write a property dynamically
var prop2 = t.GetProperty("Status");
prop2?.SetValue(instance, OrderStatus.Shipped);
var status = prop2?.GetValue(instance);
```

### Performance Warning

```csharp
// Reflection is slow — avoid on hot paths
// For frequently called reflection, cache the MethodInfo/PropertyInfo

// ❌ Slow — looks up MethodInfo every call
public void InvokeMethod(object obj, string name)
{
    obj.GetType().GetMethod(name)?.Invoke(obj, null);  // lookup every time!
}

// ✅ Cache the delegate — call it at native speed
private static readonly Action<Order> _shipDelegate =
    (Action<Order>)Delegate.CreateDelegate(
        typeof(Action<Order>),
        typeof(Order).GetMethod(nameof(Order.Ship))!);

// Now call _shipDelegate(order) — no reflection overhead
```

---

## 25.5 Reflection — Scanning Assemblies

Common pattern: find all types that implement an interface and register them.

```csharp
// Auto-register all IValidator<T> implementations in an assembly
public static IServiceCollection AddValidatorsFromAssembly(
    this IServiceCollection services,
    Assembly assembly)
{
    var validatorType = typeof(IValidator<>);

    var validators = assembly.GetTypes()
        .Where(t => t.IsClass && !t.IsAbstract)
        .SelectMany(t => t.GetInterfaces()
            .Where(i => i.IsGenericType && i.GetGenericTypeDefinition() == validatorType)
            .Select(i => (ServiceType: i, Implementation: t)));

    foreach (var (serviceType, impl) in validators)
        services.AddScoped(serviceType, impl);

    return services;
}

// Usage
services.AddValidatorsFromAssembly(typeof(Program).Assembly);
// Finds CreateOrderRequestValidator, UpdateOrderRequestValidator, etc. automatically
```

---

## 25.6 Source Generators — Compile-Time Code Generation

Source generators run **during compilation** — they read your source, generate new C# files,
and add them to the compilation. Zero runtime overhead. The opposite of reflection.

```
Developer writes source code
         ↓
Roslyn compiler starts
         ↓
Source generators run → inspect syntax/symbols → emit new .cs files
         ↓
Compiler compiles everything (original + generated) together
         ↓
Final assembly
```

You have been using source generators already:
- `System.Text.Json` — `[JsonSerializable]` generates fast serializers
- `LoggerMessage.Define` → `[LoggerMessage]` attribute generates typed log methods
- `Regex.IsMatch` → `[GeneratedRegex]` generates a compiled state machine
- `LibraryImport` → generates P/Invoke marshalling code

### Generated Regex (NET 7+)

```csharp
// ❌ Compiled at runtime — startup cost, no AOT support
private static readonly Regex EmailRegex =
    new Regex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled);

// ✅ Source-generated — compiled at build time, AOT-friendly, faster
public partial class EmailValidator
{
    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.IgnoreCase)]
    private static partial Regex EmailPattern();

    [GeneratedRegex(@"^\+?[\d\s\-\(\)]{7,20}$")]
    private static partial Regex PhonePattern();

    public bool IsValidEmail(string email) => EmailPattern().IsMatch(email);
    public bool IsValidPhone(string phone) => PhonePattern().IsMatch(phone);
}
```

### Regex — Complete Reference

```csharp
using System.Text.RegularExpressions;

// Basic matching
bool isMatch = Regex.IsMatch("hello@example.com", @"^[^@]+@[^@]+\.[^@]+$");

// Extract match
var match = Regex.Match("Order #12345", @"#(\d+)");
if (match.Success)
    Console.WriteLine(match.Groups[1].Value);  // "12345"

// Named groups (preferred — readable and robust)
var m = Regex.Match("2025-01-15", @"(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})");
Console.WriteLine(m.Groups["year"].Value);   // 2025
Console.WriteLine(m.Groups["month"].Value);  // 01

// Find all matches
foreach (Match m2 in Regex.Matches("cat bat sat", @"[cbs]at"))
    Console.WriteLine(m2.Value);  // cat, bat, sat

// Replace
string clean = Regex.Replace("Hello   World", @"\s+", " ");  // "Hello World"

// Split
string[] parts = Regex.Split("one1two2three", @"\d");  // ["one","two","three"]

// Common patterns
const string Email    = @"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$";
const string Guid     = @"^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$";
const string IsoDate  = @"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2})?";
const string Url      = @"^https?://[^\s/$.?#].[^\s]*$";
const string IPv4     = @"^(\d{1,3}\.){3}\d{1,3}$";
```

---

## 25.7 DateOnly and TimeOnly (C# 10+ / NET 6+)

`DateTime` has been a source of bugs for two decades because it conflates a date,
a time, and sometimes a timezone. `DateOnly` and `TimeOnly` fix this.

```csharp
// DateOnly — just a calendar date, no time, no timezone
var birthday = new DateOnly(1990, 6, 15);
var today    = DateOnly.FromDateTime(DateTime.UtcNow);

Console.WriteLine(birthday.Year);   // 1990
Console.WriteLine(birthday.Month);  // 6
Console.WriteLine(birthday.Day);    // 15
Console.WriteLine(birthday.DayOfWeek); // Friday

var nextWeek   = birthday.AddDays(7);
var nextMonth  = birthday.AddMonths(1);
var diff       = today.DayNumber - birthday.DayNumber; // days between

// Parsing
var parsed   = DateOnly.Parse("2025-01-15");
var iso      = DateOnly.Parse("2025-01-15", CultureInfo.InvariantCulture);
var success  = DateOnly.TryParse("bad", out var _);

// TimeOnly — just a time of day, no date, no timezone
var openTime  = new TimeOnly(9, 0);   // 09:00
var closeTime = new TimeOnly(17, 30); // 17:30
var now       = TimeOnly.FromDateTime(DateTime.Now);

bool isOpen = now >= openTime && now <= closeTime;

// Duration between times (same day)
var duration = closeTime - openTime;  // TimeSpan(8, 30, 0)

// Scheduling: meeting at specific time on specific date
record Appointment(DateOnly Date, TimeOnly StartTime, TimeOnly EndTime)
{
    public DateTime ToDateTime() =>
        Date.ToDateTime(StartTime);

    public TimeSpan Duration => EndTime - StartTime;
}
```

### DateTime vs DateOnly vs DateTimeOffset

```
DateTime        — date + time, ambiguous timezone (local? UTC? unspecified?)
                  Use for: internal calculations only

DateTimeOffset  — date + time + explicit UTC offset
                  Use for: storing/transmitting timestamps

DateOnly        — date only, no ambiguity
                  Use for: birthdays, deadlines, calendar events

TimeOnly        — time of day, no ambiguity
                  Use for: business hours, schedules, recurring time slots

TimeSpan        — duration (not a point in time)
                  Use for: timeouts, durations, differences
```

```csharp
// Always use DateTimeOffset for storage and API boundaries
public record Order(
    OrderId Id,
    DateTimeOffset PlacedAt,    // ✅ exact moment in time, timezone-aware
    DateOnly DeliveryDate,      // ✅ just a date — no time needed
    TimeOnly PickupWindow);     // ✅ just a time — no date needed
```

> **Rider tip:** `Ctrl+Alt+B` on `AuditAttribute` shows every place it is applied.
> *Analyze → Inspect Code* with the *Attribute usage* inspection catches attributes
> applied to the wrong targets at design time rather than runtime.

> **VS tip:** `Ctrl+.` on a class name → *Generate attribute* stubs. The Regex
> tool window (`View → Other Windows → Regex Tester`) lets you test patterns with
> live match highlighting before baking them into code.
