# Chapter 17 — Testing: xUnit, NSubstitute, Integration & Testcontainers

> Code that is not tested is code that works until it does not. Testing
> is not a separate activity from writing software — it is the practice
> that tells you whether your software does what you think it does. This
> chapter covers the .NET testing ecosystem from first principles: why
> each tool exists, how to structure tests that remain readable and
> maintainable as the codebase grows, and how to test code that talks
> to real infrastructure.

*Building on:* Ch 5 (interfaces — testability depends on abstraction),
Ch 10–11 (DI — tests replace real services with fakes via the same
container), Ch 15 (EF Core — Testcontainers gives you real DB tests)

---

## 17.1 The Testing Pyramid — How Much of Each Kind

Tests are not interchangeable. They have different costs and different
assurances. Understanding the trade-off shapes how you structure a test suite:

```
           ▲  End-to-End / UI Tests
          ▲▲▲  Slow, expensive, brittle, few
         ▲▲▲▲▲
        ▲▲▲▲▲▲▲  Integration Tests
       ▲▲▲▲▲▲▲▲▲  Test real infrastructure; moderate speed
      ▲▲▲▲▲▲▲▲▲▲▲
     ▲▲▲▲▲▲▲▲▲▲▲▲▲
    ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲  Unit Tests
   ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲  Fast, isolated, many, cheap to maintain
```

- **Unit tests** — test one class or function in isolation. All
  dependencies are replaced with test doubles. Fast (milliseconds),
  deterministic, run on every save.
- **Integration tests** — test the collaboration between real components:
  an API endpoint talking to a real database, a background service
  processing real messages. Slower, but test what actually matters in
  production.
- **End-to-end tests** — drive the real UI or real system. Slow, brittle,
  expensive. Reserve for critical user journeys only.

Most teams maintain a large base of unit tests and a smaller but critical
set of integration tests. The goal is confidence at speed.

---

## 17.2 Setting Up xUnit

xUnit is the standard test framework for .NET. It uses attributes to
mark test methods and constructor/`IAsyncLifetime` for setup and teardown.
Unlike NUnit or MSTest, xUnit creates a new test class instance per test —
this enforces test isolation by design.

```bash
dotnet new xunit -n MyApp.Tests
dotnet add package FluentAssertions
dotnet add package NSubstitute
dotnet add package Microsoft.AspNetCore.Mvc.Testing
dotnet add package Testcontainers.PostgreSql
```

```csharp
public class OrderServiceTests
{
    // xUnit runs the constructor for each test — fresh state every time
    // No [SetUp] method needed — just the constructor
    private readonly FakeEmailSender _email;
    private readonly IOrderRepository _repo;
    private readonly OrderService _sut;  // System Under Test

    public OrderServiceTests()
    {
        _email = new FakeEmailSender();
        _repo  = Substitute.For<IOrderRepository>();   // NSubstitute mock
        _sut   = new OrderService(_repo, _email);
    }

    [Fact]
    public async Task CreateOrder_saves_order_and_sends_confirmation()
    {
        // Arrange
        var request = new CreateOrderRequest("C001", [new("PROD01", 2)]);

        // Act
        var order = await _sut.CreateAsync(request, CancellationToken.None);

        // Assert
        await _repo.Received(1).AddAsync(Arg.Any<Order>(), Arg.Any<CancellationToken>());
        Assert.Single(_email.SentEmails);
        _email.SentEmails[0].To.Should().Be("C001");
    }

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData(null)]
    public async Task CreateOrder_with_invalid_customerId_throws(string? customerId)
    {
        var request = new CreateOrderRequest(customerId!, []);
        await Assert.ThrowsAsync<ValidationException>(
            () => _sut.CreateAsync(request, CancellationToken.None));
    }
}
```

### Fact vs Theory

- `[Fact]` — one test with no parameters.
- `[Theory]` with `[InlineData]`, `[MemberData]`, or `[ClassData]` —
  the same test run with multiple sets of inputs. Each combination
  appears as a separate test in the runner.

---

## 17.3 Test Fixtures — Sharing Expensive Setup

Creating a database connection or starting a container for every test is
slow. xUnit's `IClassFixture<T>` shares one fixture instance across all
tests in a class, while still creating a new test instance per test:

```csharp
// Fixture: expensive resource shared across all tests in the class
public class DatabaseFixture : IAsyncLifetime
{
    public AppDbContext Db { get; private set; } = null!;
    private ServiceProvider _provider = null!;

    public async Task InitializeAsync()
    {
        var services = new ServiceCollection();
        services.AddDbContext<AppDbContext>(o =>
            o.UseInMemoryDatabase("test-" + Guid.NewGuid()));  // fresh DB per fixture
        _provider = services.BuildServiceProvider();
        Db = _provider.GetRequiredService<AppDbContext>();
        await Db.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        await Db.DisposeAsync();
        await _provider.DisposeAsync();
    }
}

// The test class receives the fixture via constructor injection
public class OrderRepositoryTests(DatabaseFixture fixture)
    : IClassFixture<DatabaseFixture>
{
    [Fact]
    public async Task GetByCustomer_returns_only_that_customers_orders()
    {
        fixture.Db.Orders.AddRange(
            new Order { CustomerId = "C001", Total = 10 },
            new Order { CustomerId = "C002", Total = 20 });
        await fixture.Db.SaveChangesAsync();

        var results = await new OrderRepository(fixture.Db)
            .GetByCustomerAsync("C001", CancellationToken.None);

        results.Should().HaveCount(1).And.OnlyContain(o => o.CustomerId == "C001");
    }
}
```

---

## 17.4 NSubstitute — Creating Test Doubles

A test double stands in for a real dependency during testing. NSubstitute
creates doubles (mocks) that let you control what they return and verify
how they were called:

```csharp
// Create a substitute for any interface or virtual class
var repo = Substitute.For<IOrderRepository>();

// Configure return values
repo.GetByIdAsync(Arg.Any<int>(), Arg.Any<CancellationToken>())
    .Returns(new Order { Id = 1, CustomerId = "C001" });

// Configure exceptions
repo.AddAsync(Arg.Any<Order>(), Arg.Any<CancellationToken>())
    .ThrowsAsync(new DbException("Connection lost"));

// Verify calls
await repo.Received(1).AddAsync(
    Arg.Is<Order>(o => o.CustomerId == "C001"),
    Arg.Any<CancellationToken>());

await repo.DidNotReceive().DeleteAsync(Arg.Any<int>(), Arg.Any<CancellationToken>());

// Capture arguments
Order? captured = null;
await repo.AddAsync(Arg.Do<Order>(o => captured = o), Arg.Any<CancellationToken>());
// ... call the code under test ...
Assert.Equal("C001", captured?.CustomerId);
```

### When to Use Mocks vs Fakes

- **Mock** (NSubstitute): when you need to verify *that* something was
  called, or set up specific return values per test.
- **Fake** (hand-written): when the mock setup would be more complex
  than a real simple implementation. A `FakeEmailSender` that collects
  sent emails in a list is often clearer than elaborate NSubstitute setup.

```csharp
// A hand-written fake: simple, readable, reusable
public class FakeEmailSender : IEmailSender
{
    public record SentEmail(string To, string Subject, string Body);
    public List<SentEmail> SentEmails { get; } = [];

    public Task SendAsync(string to, string subject, string body, CancellationToken ct)
    {
        SentEmails.Add(new(to, subject, body));
        return Task.CompletedTask;
    }
}
```

---

## 17.5 FluentAssertions — Readable Assertions

FluentAssertions provides a fluent, readable assertion API:

```csharp
// Primitive values
result.Should().Be(42);
result.Should().BeGreaterThan(0);
text.Should().StartWith("Hello").And.EndWith("World").And.HaveLength(11);

// Collections
list.Should().HaveCount(3);
list.Should().Contain(item => item.Id == 1);
list.Should().BeInAscendingOrder(x => x.Name);
list.Should().OnlyContain(x => x.IsActive);
list.Should().BeEmpty();

// Objects
order.Should().BeEquivalentTo(expected,      // deep equality
    opts => opts.Excluding(o => o.CreatedAt)); // exclude timestamps

// Exceptions
var act = () => service.ProcessAsync(null!, ct);
await act.Should().ThrowAsync<ArgumentNullException>()
    .WithMessage("*request*");

// Nullable
value.Should().NotBeNull();
value.Should().BeNull();
```

The error messages from FluentAssertions are far more informative than
`Assert.Equal` — they show the actual and expected values in context.

---

## 17.6 Integration Testing with `WebApplicationFactory`

`WebApplicationFactory<T>` boots your entire ASP.NET Core application in
memory — with its real `Program.cs`, real middleware pipeline, and real
DI container — and gives you an `HttpClient` to talk to it. You can
replace specific services (like external APIs) with fakes.

```csharp
public class OrderApiTests(OrderApiFactory factory)
    : IClassFixture<OrderApiFactory>
{
    [Fact]
    public async Task POST_orders_creates_order_and_returns_201()
    {
        var client = factory.CreateClient();
        // Authenticate if needed
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", factory.GenerateTestToken("user-1"));

        var response = await client.PostAsJsonAsync("/api/orders", new
        {
            CustomerId = "C001",
            Items = new[] { new { ProductId = "P01", Quantity = 2 } }
        });

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var created = await response.Content.ReadFromJsonAsync<OrderResponse>();
        created!.CustomerId.Should().Be("C001");
    }
}

// Factory: customise the DI container for tests
public class OrderApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private PostgreSqlContainer _db = null!;

    public async Task InitializeAsync()
    {
        _db = new PostgreSqlBuilder().WithImage("postgres:16-alpine").Build();
        await _db.StartAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            // Replace the real DB with a test DB
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o =>
                o.UseNpgsql(_db.GetConnectionString()));

            // Replace the real email sender with a fake
            services.RemoveAll<IEmailSender>();
            services.AddSingleton<IEmailSender, FakeEmailSender>();
        });
    }

    public string GenerateTestToken(string userId) =>
        // ... generate a valid JWT for tests
        JwtTestHelper.Generate(userId);

    public async Task DisposeAsync() => await _db.DisposeAsync();
}
```

---

## 17.7 Testcontainers — Real Database Tests

In-memory databases (like EF Core's InMemory provider) do not enforce
foreign keys, unique constraints, or null constraints. Your tests can
pass while your production query fails. Testcontainers starts a real
database in Docker for your tests and tears it down after:

```bash
dotnet add package Testcontainers.PostgreSql
# or
dotnet add package Testcontainers.MsSql
dotnet add package Testcontainers.MySql
```

```csharp
public class OrderRepositoryIntegrationTests : IAsyncLifetime
{
    private PostgreSqlContainer _pg = null!;
    private AppDbContext _db = null!;

    public async Task InitializeAsync()
    {
        _pg = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .WithDatabase("testdb")
            .Build();

        await _pg.StartAsync();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_pg.GetConnectionString())
            .Options;

        _db = new AppDbContext(options);
        await _db.Database.MigrateAsync();  // run real migrations
    }

    [Fact]
    public async Task GetByStatus_returns_matching_orders_from_real_db()
    {
        _db.Orders.AddRange(
            new Order { Status = OrderStatus.Pending,    CustomerId = "C1" },
            new Order { Status = OrderStatus.Processing, CustomerId = "C2" },
            new Order { Status = OrderStatus.Pending,    CustomerId = "C3" });
        await _db.SaveChangesAsync();

        var repo    = new OrderRepository(_db);
        var pending = await repo.GetByStatusAsync(OrderStatus.Pending, default);

        pending.Should().HaveCount(2)
               .And.OnlyContain(o => o.Status == OrderStatus.Pending);
    }

    public async Task DisposeAsync()
    {
        await _db.DisposeAsync();
        await _pg.DisposeAsync();
    }
}
```

Testcontainers images are cached — the first run pulls the image, subsequent
runs start in seconds. For CI/CD, ensure Docker is available on the build
agent.

---

## 17.8 Test Builders — Constructing Complex Test Data

When entities have many required properties, constructing them in every
test is verbose and fragile — changing the entity's constructor breaks
every test. A Builder (or AutoFaker) provides sensible defaults that
individual tests override only for what matters:

```csharp
// Builder pattern for test data
public class OrderBuilder
{
    private string _customerId = "test-customer";
    private OrderStatus _status = OrderStatus.Pending;
    private decimal _total = 100m;
    private List<OrderLine> _lines = [new("PROD01", 1, 100m)];

    public OrderBuilder WithCustomer(string id) { _customerId = id; return this; }
    public OrderBuilder WithStatus(OrderStatus s) { _status = s; return this; }
    public OrderBuilder WithTotal(decimal t) { _total = t; return this; }

    public Order Build() => new Order
    {
        CustomerId = _customerId,
        Status     = _status,
        Total      = _total,
        Lines      = _lines,
        CreatedAt  = DateTime.UtcNow,
    };
}

// Tests only set what matters for that specific test
[Fact]
public async Task HighValueOrders_get_flagged_for_review()
{
    var order = new OrderBuilder().WithTotal(5000m).Build();
    // ...
}

[Fact]
public async Task CancelledOrders_cannot_be_updated()
{
    var order = new OrderBuilder().WithStatus(OrderStatus.Cancelled).Build();
    // ...
}
```

---

## 17.9 Connecting Testing to the Rest of the Book

- **Ch 5 (OOP)** — interfaces are what make unit testing possible.
  A service that depends on `IEmailSender` can be tested with a fake;
  one that newed up `SmtpEmailSender` directly cannot.
- **Ch 11 (DI)** — tests use the same DI container as production.
  `WebApplicationFactory.ConfigureTestServices` replaces specific
  registrations while keeping everything else real.
- **Ch 15 (EF Core)** — Testcontainers is the right tool for EF Core
  tests. In-memory providers hide real constraint and migration bugs.
- **Ch 18 (Architectures)** — clean architecture with a domain layer
  makes unit tests fast and numerous; the domain has no infrastructure
  dependencies to mock.
