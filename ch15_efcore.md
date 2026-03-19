# Chapter 15 — Entity Framework Core

## 15.1 Project Setup

```xml
<!-- MyApp.Infrastructure.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <!-- Core -->
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />
    <!-- Providers -->
    <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="9.0.0" />
    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="9.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="9.0.0" />
    <!-- Tooling (design-time) -->
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="9.0.0" PrivateAssets="all" />
    <!-- For migration generation from separate project -->
    <PackageReference Include="Microsoft.EntityFrameworkCore.Tools" Version="9.0.0" PrivateAssets="all" />
  </ItemGroup>
</Project>
```

---

## 15.2 Defining the Domain

```csharp
// Domain/Entities/User.cs
public class User
{
    public int Id { get; set; }
    public required string Email { get; set; }
    public required string Name { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsActive { get; set; } = true;

    // Navigation properties
    public ICollection<Order> Orders { get; set; } = new List<Order>();
    public UserProfile? Profile { get; set; }
}

// Domain/Entities/Order.cs
public class Order
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Status { get; set; } = "Pending";
    public DateTime PlacedAt { get; set; } = DateTime.UtcNow;
    public decimal Total { get; set; }

    // Navigation
    public User User { get; set; } = null!;
    public ICollection<OrderLine> Lines { get; set; } = new List<OrderLine>();
}

public class OrderLine
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public string Sku { get; set; } = "";
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal => Quantity * UnitPrice;

    public Order Order { get; set; } = null!;
}

public class UserProfile
{
    public int UserId { get; set; }  // PK + FK (one-to-one)
    public string? AvatarUrl { get; set; }
    public string? Bio { get; set; }
    public User User { get; set; } = null!;
}
```

---

## 15.3 DbContext

```csharp
// Infrastructure/Persistence/AppDbContext.cs
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User>       Users      => Set<User>();
    public DbSet<Order>      Orders     => Set<Order>();
    public DbSet<OrderLine>  OrderLines => Set<OrderLine>();
    public DbSet<UserProfile> Profiles  => Set<UserProfile>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Apply all IEntityTypeConfiguration<T> classes in this assembly
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

        // Or individually:
        // modelBuilder.ApplyConfiguration(new UserConfiguration());

        // Global query filter (e.g. soft delete)
        modelBuilder.Entity<User>().HasQueryFilter(u => u.IsActive);
    }

    // Intercept saves for audit fields
    public override async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        foreach (var entry in ChangeTracker.Entries())
        {
            if (entry.Entity is IAuditableEntity auditable)
            {
                if (entry.State == EntityState.Added)
                    auditable.CreatedAt = DateTime.UtcNow;
                if (entry.State is EntityState.Added or EntityState.Modified)
                    auditable.UpdatedAt = DateTime.UtcNow;
            }
        }
        return await base.SaveChangesAsync(ct);
    }
}
```

---

## 15.4 Fluent API Configuration

Use `IEntityTypeConfiguration<T>` to keep configuration out of `OnModelCreating`:

```csharp
// Infrastructure/Persistence/Configurations/UserConfiguration.cs
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> b)
    {
        b.ToTable("users");

        b.HasKey(u => u.Id);

        b.Property(u => u.Email)
            .IsRequired()
            .HasMaxLength(256)
            .IsUnicode(false);  // ASCII for emails — smaller index

        b.HasIndex(u => u.Email).IsUnique();

        b.Property(u => u.Name)
            .IsRequired()
            .HasMaxLength(100);

        b.Property(u => u.CreatedAt)
            .HasDefaultValueSql("CURRENT_TIMESTAMP");  // SQLite/PostgreSQL

        // One-to-one: User → UserProfile
        b.HasOne(u => u.Profile)
            .WithOne(p => p.User)
            .HasForeignKey<UserProfile>(p => p.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        // One-to-many: User → Orders
        b.HasMany(u => u.Orders)
            .WithOne(o => o.User)
            .HasForeignKey(o => o.UserId)
            .OnDelete(DeleteBehavior.Restrict); // don't cascade delete orders

        // Owned entity (value object embedded in same table)
        // b.OwnsOne(u => u.Address, a => {
        //     a.Property(x => x.City).HasColumnName("city");
        //     a.Property(x => x.Country).HasColumnName("country");
        // });

        // Seed data
        b.HasData(new User
        {
            Id = 1,
            Email = "admin@example.com",
            Name = "Admin",
            IsActive = true,
            CreatedAt = new DateTime(2024, 1, 1)
        });
    }
}

// OrderConfiguration.cs
public class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> b)
    {
        b.ToTable("orders");

        b.Property(o => o.Status)
            .HasMaxLength(50)
            .HasDefaultValue("Pending");

        b.Property(o => o.Total)
            .HasColumnType("decimal(18,2)");

        b.HasMany(o => o.Lines)
            .WithOne(l => l.Order)
            .HasForeignKey(l => l.OrderId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
```

---

## 15.5 Registration and Connection

```csharp
// SQLite
services.AddDbContext<AppDbContext>(opt =>
    opt.UseSqlite(
        configuration.GetConnectionString("Default") ?? "Data Source=app.db",
        sqlite =>
        {
            sqlite.MigrationsAssembly("MyApp.Infrastructure");
            sqlite.CommandTimeout(30);
        })
       .EnableSensitiveDataLogging(env.IsDevelopment())
       .EnableDetailedErrors(env.IsDevelopment())
       .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTrackingWithIdentityResolution)
);

// SQLite pragmas for performance
services.AddDbContext<AppDbContext>((sp, opt) =>
{
    opt.UseSqlite("Data Source=app.db");
    opt.AddInterceptors(sp.GetRequiredService<SqlitePragmaInterceptor>());
});

// SqlitePragmaInterceptor
public class SqlitePragmaInterceptor : DbConnectionInterceptor
{
    public override async Task ConnectionOpenedAsync(
        DbConnection connection, ConnectionEndEventData eventData, CancellationToken ct)
    {
        using var cmd = connection.CreateCommand();
        cmd.CommandText = """
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA cache_size = -64000;   -- 64MB cache
            PRAGMA foreign_keys = ON;
            PRAGMA temp_store = MEMORY;
            """;
        await cmd.ExecuteNonQueryAsync(ct);
    }
}

// PostgreSQL
services.AddDbContext<AppDbContext>(opt =>
    opt.UseNpgsql(
        configuration.GetConnectionString("Default"),
        npg => npg.MigrationsAssembly("MyApp.Infrastructure")));
```

---

## 15.6 Querying

### Basic LINQ Queries

```csharp
// Inject via constructor
public class UserRepository : IUserRepository
{
    private readonly AppDbContext _db;
    public UserRepository(AppDbContext db) => _db = db;

    // Find by PK (uses key lookup)
    public async Task<User?> GetByIdAsync(int id, CancellationToken ct)
        => await _db.Users.FindAsync([id], ct);

    // Single with no tracking (read-only — faster)
    public async Task<User?> GetByEmailAsync(string email, CancellationToken ct)
        => await _db.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == email, ct);

    // Include navigation properties (eager loading)
    public async Task<User?> GetWithOrdersAsync(int id, CancellationToken ct)
        => await _db.Users
            .Include(u => u.Orders)
                .ThenInclude(o => o.Lines)
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.Id == id, ct);

    // Projection — only load what you need (avoids over-fetching)
    public async Task<UserSummaryDto[]> GetSummariesAsync(CancellationToken ct)
        => await _db.Users
            .AsNoTracking()
            .Where(u => u.IsActive)
            .Select(u => new UserSummaryDto(
                u.Id,
                u.Name,
                u.Email,
                u.Orders.Count))
            .OrderBy(u => u.Name)
            .ToArrayAsync(ct);

    // Pagination
    public async Task<PagedResult<User>> GetPagedAsync(
        int page, int pageSize, CancellationToken ct)
    {
        var query = _db.Users.AsNoTracking().OrderBy(u => u.Name);
        var total = await query.CountAsync(ct);
        var items = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);
        return new PagedResult<User>(items, total, page, pageSize);
    }
}
```

### Raw SQL and FromSqlRaw

```csharp
// Parameterized raw SQL (safe from injection)
var users = await _db.Users
    .FromSqlRaw("SELECT * FROM users WHERE email = {0}", email)
    .AsNoTracking()
    .ToListAsync(ct);

// FormattableString (interpolation — also parameterized, C# 8+)
var users2 = await _db.Users
    .FromSql($"SELECT * FROM users WHERE email = {email}")
    .ToListAsync(ct);

// Execute non-query SQL
await _db.Database.ExecuteSqlRawAsync(
    "UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = {0}", id);

// Mixed LINQ + raw
var orders = await _db.Orders
    .FromSqlRaw("SELECT * FROM orders WHERE status = 'Pending'")
    .Include(o => o.Lines)
    .Where(o => o.Total > 100)
    .ToListAsync(ct);
```

### Bulk Operations (EF Core 7+)

```csharp
// ExecuteUpdateAsync / ExecuteDeleteAsync — bypass change tracker, direct SQL
int updated = await _db.Users
    .Where(u => !u.IsActive && u.CreatedAt < DateTime.UtcNow.AddYears(-1))
    .ExecuteDeleteAsync(ct);  // DELETE FROM users WHERE ...

int activated = await _db.Users
    .Where(u => u.Orders.Any(o => o.PlacedAt > DateTime.UtcNow.AddDays(-7)))
    .ExecuteUpdateAsync(s => s
        .SetProperty(u => u.IsActive, true)
        .SetProperty(u => u.Name, u => u.Name + " (active)"),
        ct);
```

### Compiled Queries — Eliminate LINQ Translation Overhead

```csharp
// Define once as static — translation happens at startup, not per call
private static readonly Func<AppDbContext, string, Task<User?>> _getUserByEmail =
    EF.CompileAsyncQuery((AppDbContext db, string email) =>
        db.Users.AsNoTracking().FirstOrDefault(u => u.Email == email));

private static readonly Func<AppDbContext, int, IAsyncEnumerable<Order>> _getUserOrders =
    EF.CompileAsyncQuery((AppDbContext db, int userId) =>
        db.Orders.Where(o => o.UserId == userId).OrderByDescending(o => o.PlacedAt));

// Usage
var user = await _getUserByEmail(_db, "alice@example.com");
await foreach (var order in _getUserOrders(_db, userId)) { ... }
```

---

## 15.7 CRUD Operations

```csharp
// Create
var user = new User { Email = "alice@example.com", Name = "Alice" };
_db.Users.Add(user);
await _db.SaveChangesAsync(ct);
// user.Id is now set

// AddRange
var users = new[] { user1, user2, user3 };
await _db.Users.AddRangeAsync(users, ct);
await _db.SaveChangesAsync(ct);

// Update (tracked entity)
var existing = await _db.Users.FindAsync([id], ct);
if (existing is not null)
{
    existing.Name = "New Name";
    existing.Email = "new@example.com";
    await _db.SaveChangesAsync(ct); // only changed properties are updated
}

// Update disconnected entity
_db.Users.Update(user); // marks ALL properties as modified
await _db.SaveChangesAsync(ct);

// Attach and set modified (selective)
_db.Users.Attach(user);
_db.Entry(user).Property(u => u.Name).IsModified = true;
await _db.SaveChangesAsync(ct);

// Delete
var toDelete = await _db.Users.FindAsync([id], ct);
if (toDelete is not null)
{
    _db.Users.Remove(toDelete);
    await _db.SaveChangesAsync(ct);
}

// Delete by ID (no extra query)
_db.Users.Remove(new User { Id = id }); // create stub with just PK
await _db.SaveChangesAsync(ct);
```

---

## 15.8 Transactions

```csharp
// Implicit transaction (default — single SaveChanges is atomic)
_db.Users.Add(user);
_db.Orders.Add(order);
await _db.SaveChangesAsync(ct); // both saved atomically

// Explicit transaction
await using var tx = await _db.Database.BeginTransactionAsync(ct);
try
{
    _db.Users.Add(user);
    await _db.SaveChangesAsync(ct);

    _db.Orders.Add(new Order { UserId = user.Id, Total = 99.99m });
    await _db.SaveChangesAsync(ct);

    await tx.CommitAsync(ct);
}
catch
{
    await tx.RollbackAsync(ct);
    throw;
}

// Savepoints (EF Core 5+)
await using var tx2 = await _db.Database.BeginTransactionAsync(ct);
_db.Users.Add(user);
await _db.SaveChangesAsync(ct);
await tx2.CreateSavepointAsync("after_user", ct);

try
{
    DoRiskyOperation();
    await _db.SaveChangesAsync(ct);
    await tx2.CommitAsync(ct);
}
catch
{
    await tx2.RollbackToSavepointAsync("after_user", ct);
    // user is still saved, risky op is rolled back
    await tx2.CommitAsync(ct);
}
```

---

## 15.9 Migrations

```bash
# Install EF Core tools (once per machine)
dotnet tool install --global dotnet-ef

# Add a migration
dotnet ef migrations add InitialCreate \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api

# Add to specific folder
dotnet ef migrations add AddUserProfile \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --output-dir Persistence/Migrations

# Apply migrations
dotnet ef database update \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api

# Apply to specific migration
dotnet ef database update InitialCreate ...

# Rollback
dotnet ef database update PreviousMigration ...

# List migrations
dotnet ef migrations list ...

# Remove last migration (before applying)
dotnet ef migrations remove ...

# Generate SQL script (for production deployments)
dotnet ef migrations script \
    --idempotent \
    --project src/MyApp.Infrastructure \
    --startup-project src/MyApp.Api \
    --output deploy/migrate.sql
```

### Apply Migrations at Startup

```csharp
// In Program.cs or a hosted service
if (app.Environment.IsDevelopment())
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync(); // apply pending migrations
}

// Or use a migration service
public class MigrationService : IHostedService
{
    private readonly IServiceScopeFactory _scopeFactory;
    public MigrationService(IServiceScopeFactory f) => _scopeFactory = f;

    public async Task StartAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync(ct);
    }

    public Task StopAsync(CancellationToken ct) => Task.CompletedTask;
}
```

---

## 15.10 Dapper — Micro-ORM for Complex Queries

```xml
<PackageReference Include="Dapper" Version="2.1.35" />
```

```csharp
using Dapper;
using Microsoft.Data.Sqlite;

// Use Dapper alongside EF Core for complex queries
public class ReportRepository
{
    private readonly string _connectionString;

    public ReportRepository(IConfiguration config)
        => _connectionString = config.GetConnectionString("Default")!;

    public async Task<IEnumerable<OrderSummary>> GetOrderSummaryAsync(
        DateTime from, DateTime to, CancellationToken ct)
    {
        const string sql = """
            SELECT
                u.name          AS UserName,
                COUNT(o.id)     AS OrderCount,
                SUM(o.total)    AS TotalSpent,
                MAX(o.placed_at) AS LastOrder
            FROM orders o
            JOIN users u ON u.id = o.user_id
            WHERE o.placed_at BETWEEN @From AND @To
            GROUP BY u.id, u.name
            ORDER BY TotalSpent DESC
            """;

        await using var conn = new SqliteConnection(_connectionString);
        return await conn.QueryAsync<OrderSummary>(
            sql,
            new { From = from, To = to },
            commandTimeout: 60);
    }

    public async Task<OrderDetail?> GetOrderDetailAsync(int orderId)
    {
        const string sql = """
            SELECT o.*, l.sku, l.quantity, l.unit_price
            FROM orders o
            LEFT JOIN order_lines l ON l.order_id = o.id
            WHERE o.id = @OrderId
            """;

        await using var conn = new SqliteConnection(_connectionString);
        // Multi-mapping (join result)
        var orderDict = new Dictionary<int, OrderDetail>();
        await conn.QueryAsync<OrderDetail, OrderLineDetail, OrderDetail>(
            sql,
            (order, line) =>
            {
                if (!orderDict.TryGetValue(order.Id, out var o))
                    orderDict[order.Id] = o = order;
                if (line is not null) o.Lines.Add(line);
                return o;
            },
            new { OrderId = orderId },
            splitOn: "sku");

        return orderDict.Values.FirstOrDefault();
    }
}
```

---

## 15.11 Change Tracking & Performance Tips

```csharp
// 1. AsNoTracking for read-only queries (no snapshot, no change tracking)
var users = await _db.Users.AsNoTracking().ToListAsync();

// 2. AsNoTrackingWithIdentityResolution — dedup entities but no tracking
var orders = await _db.Orders
    .AsNoTrackingWithIdentityResolution()
    .Include(o => o.Lines)
    .ToListAsync();

// 3. Select projections — never load more columns than needed
var names = await _db.Users.Select(u => u.Name).ToListAsync();

// 4. Split queries — for Include that causes cartesian explosion
var users = await _db.Users
    .Include(u => u.Orders)
    .ThenInclude(o => o.Lines)
    .AsSplitQuery()   // generates 3 separate queries instead of one JOIN
    .ToListAsync();

// 5. Lazy loading — install proxy package and enable (use carefully)
services.AddDbContext<AppDbContext>(opt => opt
    .UseSqlite(cs)
    .UseLazyLoadingProxies()); // virtual navigation properties needed

// 6. Batching with Chunk for large datasets
await foreach (var chunk in _db.Users.AsNoTracking().AsChunkedAsync(100))
{
    await ProcessBatchAsync(chunk);
}
// Or:
var i = 0;
while (true)
{
    var batch = await _db.Users.Skip(i * 100).Take(100).ToListAsync();
    if (batch.Count == 0) break;
    await ProcessBatch(batch);
    i++;
}
```

> **Rider tip:** Rider's *Database* tool window (`View → Tool Windows → Database`) connects directly to SQLite, PostgreSQL, and SQL Server. You can run queries, browse the schema, and execute migration scripts without leaving the IDE.

> **VS tip:** *View → SQL Server Object Explorer* for SQL Server. For SQLite, use the *SQLite/SQL Server Compact Toolbox* extension. The EF Core Power Tools extension adds a visual schema diagram and reverse-engineering tools.


---

## 15.12 IEnumerable vs IQueryable — Critical Distinction

This distinction directly affects whether your queries run in the database or in memory.

```csharp
// IEnumerable<T> — in-memory, evaluated locally
IEnumerable<User> query = _db.Users.AsEnumerable()
    .Where(u => u.Age > 18);
// SQL: SELECT * FROM users    ← ALL rows loaded into memory FIRST
// Then C# filters in memory. Returns 5 rows from 1 million.

// IQueryable<T> — translated to SQL, evaluated at the database
IQueryable<User> query = _db.Users
    .Where(u => u.Age > 18);
// SQL: SELECT * FROM users WHERE age > 18    ← database filters
// Only the 5 matching rows are transferred. The rest never leave the DB.
```

### When Each Is Used

```csharp
// IQueryable: LINQ against DbSet — composed into SQL
var adults = _db.Users.Where(u => u.Age > 18);           // IQueryable
var named  = adults.Where(u => u.Name.StartsWith("A")); // still IQueryable
// One SQL query: WHERE age > 18 AND name LIKE 'A%'

// IEnumerable: anything after ToList/ToArray/AsEnumerable/foreach
var list = _db.Users.ToList();              // IEnumerable — all rows in memory
var filtered = list.Where(u => u.Age > 18); // in-memory LINQ

// The classic mistake
var report = _db.Orders
    .AsEnumerable()                              // ← switches to in-memory!
    .Where(o => ExpensiveLocalFunction(o))       // .NET function, can't translate
    .ToList();
// Loads ALL orders, then filters. Use AsEnumerable() only when:
// - you need a .NET function that can't be translated to SQL
// - you know the dataset is small

// The right way when you need mixed filtering
var preFiltered = _db.Orders
    .Where(o => o.Status == OrderStatus.Active)  // SQL filter first
    .AsEnumerable()                              // then in-memory for complex logic
    .Where(o => ComplexLocalCheck(o))
    .ToList();
```

### IQueryable Pitfalls

```csharp
// Deferred execution — query runs when enumerated, not when declared
IQueryable<Order> query = _db.Orders.Where(o => o.Status == status);
// Nothing happens yet

status = OrderStatus.Cancelled; // change the captured variable
var orders = query.ToList();    // query now uses "Cancelled", not original value!

// Fix: force evaluation early if you need a snapshot
var orders = _db.Orders.Where(o => o.Status == status).ToList(); // immediate
```

---

