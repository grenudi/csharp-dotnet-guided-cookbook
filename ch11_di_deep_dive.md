# Chapter 11 — Dependency Injection: The Complete Picture

Every code example in this chapter is **fully standalone**.

```bash
dotnet new console -n DiLearn
cd DiLearn
# paste any example into Program.cs
dotnet run
```

---

## 11.1 What the Container Actually Is

Three objects do everything:

```
IServiceCollection   — recipe book  (write at startup)
IServiceProvider     — kitchen      (executes at runtime)
ServiceDescriptor    — one record: "when asked for X, build Y with lifetime Z"
```

```bash
dotnet new console -n DiMinimal
cd DiMinimal
dotnet add package Microsoft.Extensions.DependencyInjection
```

```csharp
// Program.cs — DI in its entirety, nothing hidden
using Microsoft.Extensions.DependencyInjection;

interface IGreeter        { void Greet(string name); }
class ConsoleGreeter : IGreeter
{
    public void Greet(string name) => Console.WriteLine($"Hello, {name}!");
}

var services = new ServiceCollection();
services.AddSingleton<IGreeter, ConsoleGreeter>();

IServiceProvider provider = services.BuildServiceProvider();

var greeter = provider.GetRequiredService<IGreeter>();
greeter.Greet("World");
// → Hello, World!
```

---

## 11.2 The Three Lifetimes

```
Scope 1 ────────────────────────────────────────
  Singleton  S ── (born once, lives until app dies)
  Scoped     A ── (born at scope open)
  Transient  X    (new on every resolve)
  Transient  Y    (different instance from X)
[scope 1 ends]  A, X, Y disposed

Scope 2 ────────────────────────────────────────
  Singleton  S ── (same S as scope 1)
  Scoped     B ── (new instance)
  Transient  Z    (new instance)
[scope 2 ends]  B, Z disposed
```

| Lifetime | New instance | Disposed |
|---|---|---|
| `Singleton` | Once ever | App shutdown |
| `Scoped` | Once per scope / request | End of scope |
| `Transient` | Every resolve | End of scope |

```bash
dotnet new console -n DiLifetimes
cd DiLifetimes
dotnet add package Microsoft.Extensions.DependencyInjection
```

```csharp
// Program.cs — see lifetimes with your own eyes
using Microsoft.Extensions.DependencyInjection;

class SingletonService { public Guid Id { get; } = Guid.NewGuid(); }
class ScopedService    { public Guid Id { get; } = Guid.NewGuid(); }
class TransientService { public Guid Id { get; } = Guid.NewGuid(); }

var services = new ServiceCollection();
services.AddSingleton<SingletonService>();
services.AddScoped<ScopedService>();
services.AddTransient<TransientService>();

var provider = services.BuildServiceProvider();

for (int i = 1; i <= 2; i++)
{
    Console.WriteLine($"\n── Scope {i} ──");
    using var scope = provider.CreateScope();
    var sp = scope.ServiceProvider;

    Console.WriteLine($"Singleton : {sp.GetRequiredService<SingletonService>().Id}");
    Console.WriteLine($"Singleton : {sp.GetRequiredService<SingletonService>().Id}  ← same");
    Console.WriteLine($"Scoped    : {sp.GetRequiredService<ScopedService>().Id}");
    Console.WriteLine($"Scoped    : {sp.GetRequiredService<ScopedService>().Id}  ← same in scope");
    Console.WriteLine($"Transient : {sp.GetRequiredService<TransientService>().Id}");
    Console.WriteLine($"Transient : {sp.GetRequiredService<TransientService>().Id}  ← different!");
}
```

### The Captive Dependency Bug

A Singleton holding a Scoped service. The Scoped gets disposed; the Singleton holds a dead reference. Silent until runtime.

```csharp
// ❌ Bug: Singleton captures a Scoped — Scoped gets disposed,
//         Singleton holds a dead reference, crashes later
class BadSingleton
{
    private readonly ScopedService _scoped;  // will be disposed!
    public BadSingleton(ScopedService scoped) => _scoped = scoped;
}

services.AddSingleton<BadSingleton>();
services.AddScoped<ScopedService>();
// Rider warns: yellow squiggle on the constructor parameter

// ✅ Fix: inject IServiceScopeFactory, create scope on demand
class GoodSingleton
{
    private readonly IServiceScopeFactory _factory;
    public GoodSingleton(IServiceScopeFactory factory) => _factory = factory;

    public void DoWork()
    {
        using var scope = _factory.CreateScope();
        var scoped = scope.ServiceProvider.GetRequiredService<ScopedService>();
        // scoped disposed when scope disposes — correct
    }
}
```

---

## 11.3 Constructor Injection

```bash
dotnet new console -n DiConstructor
cd DiConstructor
dotnet add package Microsoft.Extensions.DependencyInjection
```

```csharp
// Program.cs — full injection chain, container resolves everything
using Microsoft.Extensions.DependencyInjection;

interface IMessageStore  { void Save(string m); IReadOnlyList<string> GetAll(); }
interface INotifier      { void Notify(string m); }
interface IMessageService{ void Send(string m); }

class InMemoryStore : IMessageStore
{
    private readonly List<string> _items = new();
    public void Save(string m)              => _items.Add(m);
    public IReadOnlyList<string> GetAll()   => _items.AsReadOnly();
}

class ConsoleNotifier : INotifier
{
    public void Notify(string m) => Console.WriteLine($"[NOTIFY] {m}");
}

class MessageService : IMessageService
{
    private readonly IMessageStore _store;
    private readonly INotifier     _notifier;

    // Container resolves both parameters automatically
    public MessageService(IMessageStore store, INotifier notifier)
    { _store = store; _notifier = notifier; }

    public void Send(string m) { _store.Save(m); _notifier.Notify(m); }
}

var services = new ServiceCollection();
services.AddSingleton<IMessageStore,   InMemoryStore>();
services.AddSingleton<INotifier,       ConsoleNotifier>();
services.AddSingleton<IMessageService, MessageService>();

var provider = services.BuildServiceProvider();
var svc      = provider.GetRequiredService<IMessageService>();

svc.Send("Hello DI");
svc.Send("Second message");

Console.WriteLine($"\nStored: {provider.GetRequiredService<IMessageStore>().GetAll().Count}");
// → [NOTIFY] Hello DI
// → [NOTIFY] Second message
// → Stored: 2
```

---

## 11.4 Swapping Implementations

```bash
dotnet new console -n DiSwap
cd DiSwap
dotnet add package Microsoft.Extensions.DependencyInjection
```

```csharp
// Program.cs
using Microsoft.Extensions.DependencyInjection;

interface IGreeter { string Greet(string name); }

class FriendlyGreeter : IGreeter { public string Greet(string n) => $"Hey {n}! 👋"; }
class FormalGreeter   : IGreeter { public string Greet(string n) => $"Good day, {n}."; }

class WelcomeService
{
    private readonly IGreeter _greeter;
    public WelcomeService(IGreeter g) => _greeter = g;
    public void Welcome(string n) => Console.WriteLine(_greeter.Greet(n));
}

// One line change — WelcomeService never changes
bool formal = args.Contains("--formal");

var services = new ServiceCollection();
services.AddSingleton<IGreeter>(formal ? new FormalGreeter() : new FriendlyGreeter());
services.AddSingleton<WelcomeService>();

var provider = services.BuildServiceProvider();
var welcome  = provider.GetRequiredService<WelcomeService>();

welcome.Welcome("Alice");
welcome.Welcome("Bob");

// dotnet run           → Hey Alice! 👋 / Hey Bob! 👋
// dotnet run --formal  → Good day, Alice. / Good day, Bob.
```

---

## 11.5 Extension Methods — Self-Registration Pattern

Each layer owns its own registrations. Composition root only calls extension methods.

```bash
dotnet new console -n DiExtensions
cd DiExtensions
dotnet add package Microsoft.Extensions.Hosting
```

```csharp
// Program.cs
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

interface IRepository   { void Save(string item); IReadOnlyList<string> GetAll(); }
interface IEmailSender  { void Send(string to, string body); }
interface IOrderService { void PlaceOrder(string item, string email); }

class InMemoryRepository : IRepository
{
    private readonly List<string> _items = new();
    public void Save(string item)         => _items.Add(item);
    public IReadOnlyList<string> GetAll() => _items.AsReadOnly();
}

class ConsoleEmailSender : IEmailSender
{
    public void Send(string to, string body) =>
        Console.WriteLine($"[EMAIL → {to}] {body}");
}

class OrderService : IOrderService
{
    private readonly IRepository  _repo;
    private readonly IEmailSender _email;
    public OrderService(IRepository r, IEmailSender e) { _repo = r; _email = e; }
    public void PlaceOrder(string item, string email)
    {
        _repo.Save(item);
        _email.Send(email, $"Order confirmed: {item}");
    }
}

// Each layer registers itself — nobody touches another layer's internals
static class DataLayer  { public static IServiceCollection AddData(this IServiceCollection s)
    => s.AddSingleton<IRepository, InMemoryRepository>(); }

static class InfraLayer { public static IServiceCollection AddInfra(this IServiceCollection s)
    => s.AddSingleton<IEmailSender, ConsoleEmailSender>(); }

static class AppLayer   { public static IServiceCollection AddApp(this IServiceCollection s)
    => s.AddSingleton<IOrderService, OrderService>(); }

// Composition root — three lines, knows everything, does almost nothing
var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices(s => s.AddData().AddInfra().AddApp())
    .Build();

var orders = host.Services.GetRequiredService<IOrderService>();
orders.PlaceOrder("Keyboard", "alice@example.com");
orders.PlaceOrder("Monitor",  "bob@example.com");

// → [EMAIL → alice@example.com] Order confirmed: Keyboard
// → [EMAIL → bob@example.com] Order confirmed: Monitor
```

---

## 11.6 IServiceProvider vs IServiceCollection

```
IServiceCollection                   IServiceProvider
──────────────────                   ────────────────
Write-only                           Read-only
Lives at startup                     Lives at runtime
.Add*() goes here                    .GetRequiredService<T>() goes here
Recipe book                          Kitchen executing recipes
```

Injecting `IServiceProvider` into a service is the **Service Locator antipattern** —
hides dependencies, breaks testability. The one legitimate use: Singleton needs Scoped:

```bash
dotnet new console -n DiScopeFactory
cd DiScopeFactory
dotnet add package Microsoft.Extensions.DependencyInjection
```

```csharp
// Program.cs
using Microsoft.Extensions.DependencyInjection;

interface IRequestHandler { void Handle(string r); }

class RequestHandler : IRequestHandler, IDisposable
{
    private static int _n = 0;
    private readonly int _id = ++_n;
    public void Handle(string r) => Console.WriteLine($"  Handler #{_id}: {r}");
    public void Dispose()        => Console.WriteLine($"  Handler #{_id} disposed");
}

class RequestProcessor
{
    private readonly IServiceScopeFactory _factory;
    public RequestProcessor(IServiceScopeFactory f) => _factory = f;

    public void Process(string r)
    {
        Console.WriteLine($"Processing '{r}'");
        using var scope = _factory.CreateScope();
        scope.ServiceProvider.GetRequiredService<IRequestHandler>().Handle(r);
        // scope closes → handler disposed
    }
}

var services = new ServiceCollection();
services.AddSingleton<RequestProcessor>();
services.AddScoped<IRequestHandler, RequestHandler>();

var provider  = services.BuildServiceProvider();
var processor = provider.GetRequiredService<RequestProcessor>();
processor.Process("login");
processor.Process("logout");

// → Processing 'login'
// →   Handler #1: login
// →   Handler #1 disposed
// → Processing 'logout'
// →   Handler #2: logout
// →   Handler #2 disposed
```

---

## 11.7 IOptions — Typed Configuration

```bash
dotnet new console -n DiOptions
cd DiOptions
dotnet add package Microsoft.Extensions.Hosting
dotnet add package Microsoft.Extensions.Options.DataAnnotations
```

```json
// appsettings.json
{
  "Smtp": {
    "Host": "smtp.example.com",
    "Port": 587,
    "TimeoutSeconds": 30
  }
}
```

```csharp
// Program.cs
using System.ComponentModel.DataAnnotations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

class SmtpOptions
{
    public const string Section = "Smtp";
    [Required] public string Host           { get; set; } = "";
    [Range(1, 65535)] public int Port       { get; set; } = 587;
    [Range(1, 300)]   public int TimeoutSeconds { get; set; } = 30;
}

class EmailService
{
    private readonly SmtpOptions _opts;
    public EmailService(IOptions<SmtpOptions> opts) => _opts = opts.Value;
    public void Send(string to) =>
        Console.WriteLine($"Sending to {to} via {_opts.Host}:{_opts.Port}");
}

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, s) =>
    {
        s.AddOptions<SmtpOptions>()
         .BindConfiguration(SmtpOptions.Section)
         .ValidateDataAnnotations()
         .ValidateOnStart();  // fail at startup, not first use
        s.AddSingleton<EmailService>();
    })
    .Build();

host.Services.GetRequiredService<EmailService>().Send("alice@example.com");
// → Sending to alice@example.com via smtp.example.com:587
```

| Interface | Reloads | Use when |
|---|---|---|
| `IOptions<T>` | Never | Fixed for app lifetime |
| `IOptionsSnapshot<T>` | Per scope | May change between requests |
| `IOptionsMonitor<T>` | Live callback | React to changes immediately |

---

## 11.8 Multiple Implementations

```bash
dotnet new console -n DiMultiple
cd DiMultiple
dotnet add package Microsoft.Extensions.DependencyInjection
```

```csharp
// Program.cs — IEnumerable<T> injection: all registered implementations
using Microsoft.Extensions.DependencyInjection;

interface IValidator { (bool ok, string error) Validate(string input); }

class NotEmptyValidator  : IValidator { public (bool, string) Validate(string s) =>
    string.IsNullOrWhiteSpace(s) ? (false, "Cannot be empty") : (true, ""); }

class MaxLengthValidator : IValidator { public (bool, string) Validate(string s) =>
    s.Length > 20 ? (false, $"Too long ({s.Length}/20)") : (true, ""); }

class NoDigitsValidator  : IValidator { public (bool, string) Validate(string s) =>
    s.Any(char.IsDigit) ? (false, "No digits allowed") : (true, ""); }

class InputValidator
{
    private readonly IEnumerable<IValidator> _validators;
    public InputValidator(IEnumerable<IValidator> v) => _validators = v;

    public bool Validate(string input)
    {
        bool ok = true;
        foreach (var v in _validators)
        {
            var (valid, error) = v.Validate(input);
            if (!valid) { Console.WriteLine($"  ✗ {error}"); ok = false; }
        }
        return ok;
    }
}

var services = new ServiceCollection();
services.AddSingleton<IValidator, NotEmptyValidator>();
services.AddSingleton<IValidator, MaxLengthValidator>();
services.AddSingleton<IValidator, NoDigitsValidator>();
services.AddSingleton<InputValidator>();

var validator = services.BuildServiceProvider().GetRequiredService<InputValidator>();

foreach (var input in new[] { "Alice", "", "Alice123", new string('x', 25) })
{
    Console.WriteLine($"\n'{input}'");
    Console.WriteLine(validator.Validate(input) ? "  ✓ valid" : "  → invalid");
}
// Add a new rule: one new class + one AddSingleton. InputValidator never changes.
```

---

## 11.9 Testing With DI

```bash
dotnet new xunit -n DiTesting
cd DiTesting
dotnet add package Microsoft.Extensions.DependencyInjection
dotnet add package NSubstitute
```

```csharp
// UnitTest1.cs
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

interface IEmailSender { void Send(string to, string subject); }
interface IUserStore   { void Save(string name); bool Exists(string name); }

class UserService
{
    private readonly IUserStore   _store;
    private readonly IEmailSender _email;
    public UserService(IUserStore s, IEmailSender e) { _store = s; _email = e; }

    public bool Register(string name, string email)
    {
        if (_store.Exists(name)) return false;
        _store.Save(name);
        _email.Send(email, $"Welcome, {name}!");
        return true;
    }
}

public class UserServiceTests
{
    // Direct construction — preferred for unit tests, no container overhead
    [Fact]
    public void Register_NewUser_SavesAndSendsEmail()
    {
        var store = Substitute.For<IUserStore>();
        var email = Substitute.For<IEmailSender>();
        store.Exists("alice").Returns(false);

        var svc = new UserService(store, email);
        Assert.True(svc.Register("alice", "alice@example.com"));

        store.Received(1).Save("alice");
        email.Received(1).Send("alice@example.com", Arg.Any<string>());
    }

    [Fact]
    public void Register_ExistingUser_ReturnsFalse()
    {
        var store = Substitute.For<IUserStore>();
        var email = Substitute.For<IEmailSender>();
        store.Exists("alice").Returns(true);

        var svc = new UserService(store, email);
        Assert.False(svc.Register("alice", "alice@example.com"));
        email.DidNotReceive().Send(Arg.Any<string>(), Arg.Any<string>());
    }
}
```

---

## 11.10 BackgroundService + Scoped Dependencies

```bash
dotnet new worker -n DiWorker
cd DiWorker
```

```csharp
// Program.cs
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

interface IJobRepository { IReadOnlyList<string> GetPending(); void MarkDone(string job); }

class FakeJobRepository : IJobRepository, IDisposable
{
    private static readonly Queue<string> _jobs = new(["job-1", "job-2", "job-3"]);
    private readonly ILogger<FakeJobRepository> _log;
    public FakeJobRepository(ILogger<FakeJobRepository> log) => _log = log;
    public IReadOnlyList<string> GetPending() => _jobs.ToList();
    public void MarkDone(string job) { if (_jobs.TryDequeue(out var j)) _log.LogInformation("Done: {J}", j); }
    public void Dispose() => _log.LogDebug("Repo disposed");
}

class JobWorker : BackgroundService
{
    private readonly IServiceScopeFactory _factory;
    private readonly ILogger<JobWorker>   _log;
    public JobWorker(IServiceScopeFactory f, ILogger<JobWorker> l) { _factory = f; _log = l; }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(2));
        while (await timer.WaitForNextTickAsync(ct))
        {
            using var scope = _factory.CreateScope();
            var repo        = scope.ServiceProvider.GetRequiredService<IJobRepository>();
            var jobs        = repo.GetPending();
            if (jobs.Count == 0) { _log.LogInformation("No pending jobs"); break; }
            _log.LogInformation("Processing {N} jobs", jobs.Count);
            foreach (var job in jobs) repo.MarkDone(job);
        }
    }
}

await Host.CreateDefaultBuilder(args)
    .ConfigureServices(s =>
    {
        s.AddScoped<IJobRepository, FakeJobRepository>();
        s.AddHostedService<JobWorker>();
    })
    .Build()
    .RunAsync();
```

---

## 11.11 The Mental Model

```
IServiceCollection   — recipe book, write at startup, frozen after Build()
IServiceProvider     — kitchen, read at runtime, lives forever
Constructor params   — how ingredients arrive, never walk to the kitchen yourself
Extension methods    — each layer self-registers, composition root calls them
IServiceScopeFactory — the only legitimate reason to touch the provider at runtime
```

