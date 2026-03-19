# Chapter 17 — Testing: xUnit, NSubstitute, Integration & Containers

## 17.1 Project Setup

```xml
<!-- tests/MyApp.Tests/MyApp.Tests.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <!-- xUnit -->
    <PackageReference Include="xunit" Version="2.9.0" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" PrivateAssets="all" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.0" />

    <!-- Mocking -->
    <PackageReference Include="NSubstitute" Version="5.1.0" />
    <PackageReference Include="NSubstitute.Analyzers.CSharp" Version="1.0.17" PrivateAssets="all" />

    <!-- Assertions -->
    <PackageReference Include="FluentAssertions" Version="6.12.0" />

    <!-- ASP.NET Core integration testing -->
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="9.0.0" />

    <!-- Testcontainers -->
    <PackageReference Include="Testcontainers" Version="4.1.0" />
    <PackageReference Include="Testcontainers.PostgreSql" Version="4.1.0" />

    <!-- Bogus — fake data -->
    <PackageReference Include="Bogus" Version="35.5.1" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../../src/MyApp.Api/MyApp.Api.csproj" />
  </ItemGroup>
</Project>
```

### Test Project Structure

```
tests/MyApp.Tests/
├── Unit/
│   ├── Domain/
│   │   ├── OrderTests.cs
│   │   └── MoneyTests.cs
│   ├── Application/
│   │   ├── PlaceOrderHandlerTests.cs
│   │   └── GetOrderHandlerTests.cs
│   └── Infrastructure/
│       └── SmtpEmailSenderTests.cs
├── Integration/
│   ├── Api/
│   │   ├── OrdersApiTests.cs
│   │   └── UsersApiTests.cs
│   └── Database/
│       └── OrderRepositoryTests.cs
├── Fixtures/
│   ├── DatabaseFixture.cs
│   └── WebAppFixture.cs
├── Builders/
│   ├── OrderBuilder.cs
│   └── UserBuilder.cs
└── GlobalUsings.cs
```

---

## 17.2 xUnit Basics

```csharp
// GlobalUsings.cs
global using Xunit;
global using NSubstitute;
global using FluentAssertions;
global using MyApp.Domain;

// Basic test
public class MoneyTests
{
    [Fact]
    public void Add_SameCurrency_ReturnsSum()
    {
        var a = new Money(10m, "EUR");
        var b = new Money(5m, "EUR");

        var result = a + b;

        result.Amount.Should().Be(15m);
        result.Currency.Should().Be("EUR");
    }

    [Fact]
    public void Add_DifferentCurrency_Throws()
    {
        var a = new Money(10m, "EUR");
        var b = new Money(5m, "USD");

        var act = () => a + b;

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*currency*");
    }
}
```

### Theory — Parameterized Tests

```csharp
public class GradeCalculatorTests
{
    [Theory]
    [InlineData(95, "A")]
    [InlineData(85, "B")]
    [InlineData(75, "C")]
    [InlineData(65, "D")]
    [InlineData(55, "F")]
    public void GetGrade_ReturnsExpected(int score, string expected)
    {
        var grade = GradeCalculator.GetGrade(score);
        grade.Should().Be(expected);
    }

    // MemberData — data from a static property/method
    [Theory]
    [MemberData(nameof(InvalidScores))]
    public void GetGrade_InvalidScore_Throws(int score)
    {
        var act = () => GradeCalculator.GetGrade(score);
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    public static IEnumerable<object[]> InvalidScores => new[]
    {
        new object[] { -1 },
        new object[] { 101 },
        new object[] { int.MinValue },
    };

    // ClassData — data from a class (useful for complex types)
    [Theory]
    [ClassData(typeof(OrderTestData))]
    public void ProcessOrder_Works(Order order, decimal expectedTotal)
    {
        var result = OrderProcessor.Calculate(order);
        result.Total.Should().Be(expectedTotal);
    }
}

public class OrderTestData : TheoryData<Order, decimal>
{
    public OrderTestData()
    {
        Add(OrderBuilder.Simple(), 9.99m);
        Add(OrderBuilder.WithDiscount(0.1m), 8.99m);
        Add(OrderBuilder.Bulk(qty: 10), 99.90m);
    }
}
```

---

## 17.3 Fixtures and Shared State

```csharp
// Shared fixture — setup once per test class
public class OrderServiceFixture : IDisposable
{
    public IOrderRepository Repository { get; }
    public IEmailSender EmailSender { get; }
    public OrderService Service { get; }

    public OrderServiceFixture()
    {
        Repository  = Substitute.For<IOrderRepository>();
        EmailSender = Substitute.For<IEmailSender>();
        Service     = new OrderService(Repository, EmailSender, NullLogger<OrderService>.Instance);
    }

    public void Dispose() { /* cleanup */ }
}

// Use fixture
public class OrderServiceTests : IClassFixture<OrderServiceFixture>
{
    private readonly OrderServiceFixture _fix;
    public OrderServiceTests(OrderServiceFixture fix) => _fix = fix;

    [Fact]
    public async Task PlaceOrder_ValidOrder_SavesAndSendsEmail()
    {
        var order = new Order { CustomerId = "C1", Lines = [new OrderLine("SKU-1", 2, 9.99m)] };

        await _fix.Service.PlaceOrderAsync(order);

        await _fix.Repository.Received(1).AddAsync(Arg.Is<Order>(o => o.CustomerId == "C1"), Arg.Any<CancellationToken>());
        await _fix.EmailSender.Received(1).SendAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>());
    }
}

// Collection fixture — shared across multiple test classes
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }

[Collection("Database")]
public class UserRepositoryTests
{
    private readonly DatabaseFixture _db;
    public UserRepositoryTests(DatabaseFixture db) => _db = db;
    // ...
}
```

---

## 17.4 NSubstitute — Mocking

```csharp
// Create substitute (mock)
var repo = Substitute.For<IOrderRepository>();

// Setup return value
repo.GetByIdAsync(1, Arg.Any<CancellationToken>())
    .Returns(new Order { Id = 1, CustomerId = "C1" });

// Setup with dynamic return
repo.GetByIdAsync(Arg.Any<int>(), Arg.Any<CancellationToken>())
    .Returns(callInfo =>
    {
        var id = callInfo.ArgAt<int>(0);
        return id > 0 ? new Order { Id = id } : null;
    });

// Setup to throw
repo.AddAsync(Arg.Any<Order>(), Arg.Any<CancellationToken>())
    .ThrowsAsync(new DbUpdateException("Connection failed"));

// Verify calls
await repo.Received(1).GetByIdAsync(1, Arg.Any<CancellationToken>());
await repo.DidNotReceive().DeleteAsync(Arg.Any<int>(), Arg.Any<CancellationToken>());

// Verify with argument capture
await repo.Received().AddAsync(
    Arg.Is<Order>(o => o.CustomerId == "C1" && o.Lines.Count > 0),
    Arg.Any<CancellationToken>());

// Partial substitute (for abstract classes)
var service = Substitute.ForPartsOf<BaseService>();
service.WhenForAnyArgs(s => s.VirtualMethod()).DoNotCallBase();

// Multiple interfaces
var multi = Substitute.For<IFoo, IBar, IDisposable>();

// Setup property
var config = Substitute.For<IConfiguration>();
config["MyKey"].Returns("MyValue");
```

---

## 17.5 FluentAssertions

```csharp
// Basic
result.Should().Be(42);
result.Should().NotBe(0);
result.Should().BeGreaterThan(0).And.BeLessThan(100);
result.Should().BeInRange(1, 100);

// Strings
name.Should().Be("Alice");
name.Should().StartWith("Al");
name.Should().Contain("lic");
name.Should().MatchRegex(@"^[A-Z][a-z]+$");
name.Should().HaveLength(5);
name.Should().BeNullOrEmpty();
name.Should().NotBeNullOrWhiteSpace();

// Collections
list.Should().HaveCount(3);
list.Should().Contain(42);
list.Should().ContainInOrder(1, 2, 3);
list.Should().OnlyContain(x => x > 0);
list.Should().BeEquivalentTo(expected); // deep equality, order-independent
list.Should().BeInAscendingOrder();
list.Should().NotContainNulls();
list.Should().HaveCountGreaterThan(0);

// Objects
user.Should().BeEquivalentTo(expectedUser, opts =>
    opts.Excluding(u => u.CreatedAt)
        .Excluding(u => u.Id));

// Exceptions
var act = async () => await service.DoRiskyAsync();
await act.Should().ThrowAsync<InvalidOperationException>()
    .WithMessage("*order*")
    .Where(ex => ex.InnerException is null);

act.Should().NotThrow();

// Nullable
result.Should().NotBeNull();
result.Should().BeNull();

// Numeric precision
3.14159.Should().BeApproximately(Math.PI, precision: 0.0001);
```

---

## 17.6 Integration Testing with WebApplicationFactory

```csharp
// Fixture
public class WebAppFixture : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Replace real DB with in-memory SQLite
            var descriptor = services.SingleOrDefault(d =>
                d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            if (descriptor is not null) services.Remove(descriptor);

            services.AddDbContext<AppDbContext>(opt =>
                opt.UseSqlite($"Data Source=test_{Guid.NewGuid():N}.db"));

            // Seed test data
            var sp = services.BuildServiceProvider();
            using var scope = sp.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Database.EnsureCreated();
            SeedDatabase(db);
        });

        builder.UseEnvironment("Testing");
    }

    private static void SeedDatabase(AppDbContext db)
    {
        db.Users.AddRange(
            new User { Id = 1, Name = "Alice", Email = "alice@test.com" },
            new User { Id = 2, Name = "Bob",   Email = "bob@test.com" });
        db.SaveChanges();
    }
}

// Test class
[Collection("WebApp")]
public class UsersApiTests : IClassFixture<WebAppFixture>
{
    private readonly HttpClient _client;

    public UsersApiTests(WebAppFixture factory)
    {
        _client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Fact]
    public async Task GetUser_ExistingId_ReturnsUser()
    {
        var response = await _client.GetAsync("/api/users/1");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var user = await response.Content.ReadFromJsonAsync<UserDto>();
        user.Should().NotBeNull();
        user!.Name.Should().Be("Alice");
    }

    [Fact]
    public async Task CreateUser_ValidData_ReturnsCreated()
    {
        var newUser = new CreateUserRequest { Name = "Charlie", Email = "charlie@test.com" };

        var response = await _client.PostAsJsonAsync("/api/users", newUser);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var created = await response.Content.ReadFromJsonAsync<UserDto>();
        created!.Id.Should().BeGreaterThan(0);
        created.Name.Should().Be("Charlie");
    }

    [Fact]
    public async Task GetUser_NonExistentId_ReturnsNotFound()
    {
        var response = await _client.GetAsync("/api/users/9999");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

---

## 17.7 Testcontainers — Real Database Tests

```csharp
// DatabaseFixture.cs — starts a real PostgreSQL container
public class DatabaseFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16")
        .WithDatabase("testdb")
        .WithUsername("postgres")
        .WithPassword("password")
        .WithWaitStrategy(Wait.ForUnixContainer().UntilPortIsAvailable(5432))
        .Build();

    public AppDbContext Db { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        await _container.StartAsync();

        var opts = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_container.GetConnectionString())
            .Options;

        Db = new AppDbContext(opts);
        await Db.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        await Db.DisposeAsync();
        await _container.DisposeAsync();
    }
}

// Test using real PostgreSQL
[Collection("Database")]
public class OrderRepositoryTests
{
    private readonly DatabaseFixture _db;

    public OrderRepositoryTests(DatabaseFixture db) => _db = db;

    [Fact]
    public async Task AddOrder_Persists()
    {
        var repo = new SqlOrderRepository(_db.Db);
        var order = new Order
        {
            UserId = 1,
            Total = 49.99m,
            Lines = [new OrderLine { Sku = "SKU-1", Quantity = 1, UnitPrice = 49.99m }]
        };

        var id = await repo.AddAsync(order, TestContext.Current.CancellationToken);

        var saved = await repo.GetByIdAsync(id, TestContext.Current.CancellationToken);
        saved.Should().NotBeNull();
        saved!.Total.Should().Be(49.99m);
        saved.Lines.Should().HaveCount(1);
    }
}
```

---

## 17.8 Test Builders (Fake Data)

```csharp
// Using Bogus for realistic fake data
using Bogus;

public static class Fakers
{
    public static readonly Faker<User> UserFaker = new Faker<User>()
        .RuleFor(u => u.Name, f => f.Name.FullName())
        .RuleFor(u => u.Email, (f, u) => f.Internet.Email(u.Name))
        .RuleFor(u => u.CreatedAt, f => f.Date.Past(2));

    public static readonly Faker<Order> OrderFaker = new Faker<Order>()
        .RuleFor(o => o.Status, f => f.PickRandom("Pending", "Shipped", "Delivered"))
        .RuleFor(o => o.Total, f => f.Finance.Amount(5, 500))
        .RuleFor(o => o.PlacedAt, f => f.Date.Recent(30));
}

// Builder pattern
public class OrderBuilder
{
    private string _customerId = "C1";
    private decimal _total = 9.99m;
    private List<OrderLine> _lines = new();
    private string _status = "Pending";

    public static OrderBuilder Default() => new OrderBuilder()
        .WithLine("SKU-1", 1, 9.99m);

    public OrderBuilder ForCustomer(string id) { _customerId = id; return this; }
    public OrderBuilder WithTotal(decimal t) { _total = t; return this; }
    public OrderBuilder WithStatus(string s) { _status = s; return this; }

    public OrderBuilder WithLine(string sku, int qty, decimal price)
    {
        _lines.Add(new OrderLine { Sku = sku, Quantity = qty, UnitPrice = price });
        return this;
    }

    public Order Build() => new Order
    {
        CustomerId = _customerId,
        Total = _total,
        Status = _status,
        Lines = _lines,
    };
}

// Usage
var order = OrderBuilder.Default()
    .ForCustomer("C42")
    .WithLine("SKU-2", 3, 14.99m)
    .Build();
```

---

## 17.9 Code Coverage

```bash
# Run with coverage
dotnet test --collect:"XPlat Code Coverage" --results-directory ./coverage

# Generate HTML report (install reportgenerator)
dotnet tool install --global dotnet-reportgenerator-globaltool

reportgenerator \
    -reports:./coverage/**/coverage.cobertura.xml \
    -targetdir:./coverage/report \
    -reporttypes:HtmlInline_AzurePipelines

open ./coverage/report/index.html
```

```xml
<!-- Add to test .csproj for threshold enforcement -->
<ItemGroup>
  <PackageReference Include="coverlet.collector" Version="6.0.2" PrivateAssets="all" />
</ItemGroup>
```

> **Rider tip:** Rider has built-in code coverage (`Run → Cover`). After running, it highlights covered/uncovered lines directly in the editor with green/red/yellow gutters. No separate tool needed.

> **VS tip:** *Test → Analyze Code Coverage for All Tests* generates a coverage report. The Enterprise edition shows per-line coverage highlighting. The *Fine Code Coverage* extension adds this to Community/Pro editions for free.

