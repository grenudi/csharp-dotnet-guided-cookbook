# Chapter 40 — Pet Projects VIII: Databases in Real Projects

> Three complete database-centric projects: a local SQLite note app,
> a PostgreSQL analytics service, and a multi-tenant API with proper
> migration strategy. Every project shows the full path from schema
> to query to test.

**Concepts exercised:** Ch 15a (SQL), Ch 15 (EF Core, Dapper,
IEnumerable vs IQueryable), Ch 17 (Testcontainers), Ch 18 (Repository
pattern), Ch 28 (no SQL injection ever)

---

## 40.1 Choosing the Right Database for Your Pet Project

| Need | Use |
|---|---|
| Local app, single user, no server | SQLite |
| Multi-user web app, free tier | PostgreSQL |
| Windows ecosystem, SSMS familiarity | SQL Server (LocalDB for dev) |
| Lots of reads, schema evolves | PostgreSQL |
| Mobile app (Android / iOS) | SQLite |
| Embedded / offline-first | SQLite |

Rule: **start with SQLite** unless you have a specific reason not to.
You can migrate to PostgreSQL later — EF Core migrations handle it
with one provider swap.

---

## 40.2 Project: `notesdb` — SQLite Note App With EF Core

**What it does:** a CRUD note-taking app. No web server. No HTTP. Just
EF Core + SQLite, a clean domain, and a console UI. Demonstrates: code-
first schema, migrations, querying, and correct disposal.

```bash
dotnet new console -n notesdb
cd notesdb
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet tool install --global dotnet-ef
```

### Domain

```csharp
// Note.cs
public class Note
{
    public int    Id        { get; private set; }
    public string Title     { get; set; } = "";
    public string Body      { get; set; } = "";
    public string[] Tags    { get; set; } = [];
    public DateTime CreatedAt  { get; private set; } = DateTime.UtcNow;
    public DateTime UpdatedAt  { get; set; }          = DateTime.UtcNow;

    public static Note Create(string title, string body, string[] tags)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        return new Note { Title = title, Body = body, Tags = tags };
    }
}
```

### DbContext

```csharp
// AppDbContext.cs
public class AppDbContext : DbContext
{
    public DbSet<Note> Notes { get; set; } = null!;

    public AppDbContext(DbContextOptions<AppDbContext> opts) : base(opts) { }

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Note>(e =>
        {
            e.HasKey(n => n.Id);
            e.Property(n => n.Title).HasMaxLength(200).IsRequired();
            e.Property(n => n.Body).IsRequired();

            // SQLite stores arrays as JSON
            e.Property(n => n.Tags)
                .HasConversion(
                    v  => System.Text.Json.JsonSerializer.Serialize(v, (System.Text.Json.JsonSerializerOptions?)null),
                    v  => System.Text.Json.JsonSerializer.Deserialize<string[]>(v, (System.Text.Json.JsonSerializerOptions?)null) ?? [])
                .HasColumnType("TEXT");

            e.Property(n => n.CreatedAt).IsRequired();
            e.Property(n => n.UpdatedAt).IsRequired();
            e.HasIndex(n => n.CreatedAt);
        });
    }
}
```

### Migrations

```bash
dotnet ef migrations add InitialSchema
dotnet ef database update         # creates notes.db
dotnet ef migrations list
dotnet ef migrations remove       # undo last migration
```

Generated migration contains `CreateTable` and `DropTable`. Commit
migrations to git — they are your schema history.

### Repository

```csharp
// NoteRepository.cs
public class NoteRepository(AppDbContext db)
{
    public async Task<Note> CreateAsync(
        string title, string body, string[] tags, CancellationToken ct)
    {
        var note = Note.Create(title, body, tags);
        db.Notes.Add(note);
        await db.SaveChangesAsync(ct);
        return note;
    }

    public async Task<Note?> GetByIdAsync(int id, CancellationToken ct) =>
        await db.Notes.FindAsync([id], ct);

    // IQueryable: the WHERE happens in SQLite, not .NET
    public async Task<IReadOnlyList<Note>> SearchAsync(
        string? tag, string? query, int page, int pageSize, CancellationToken ct) =>
        await db.Notes
            .Where(n => tag   == null || n.Tags.Contains(tag))    // EF translates to SQL LIKE or JSON extract
            .Where(n => query == null || n.Title.Contains(query) || n.Body.Contains(query))
            .OrderByDescending(n => n.UpdatedAt)
            .Skip(page * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

    public async Task<bool> UpdateAsync(
        int id, string? title, string? body, string[]? tags, CancellationToken ct)
    {
        var note = await db.Notes.FindAsync([id], ct);
        if (note is null) return false;

        if (title is not null) note.Title     = title;
        if (body  is not null) note.Body      = body;
        if (tags  is not null) note.Tags      = tags;
        note.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken ct)
    {
        var rows = await db.Notes.Where(n => n.Id == id).ExecuteDeleteAsync(ct);
        return rows > 0;
    }
}
```

### Wiring

```csharp
// Program.cs
var dbPath = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
    ".notesdb", "notes.db");
Directory.CreateDirectory(Path.GetDirectoryName(dbPath)!);

var services = new ServiceCollection();
services.AddDbContext<AppDbContext>(o => o.UseSqlite($"Data Source={dbPath}"));
services.AddScoped<NoteRepository>();

await using var provider = services.BuildServiceProvider();

// Auto-apply migrations on startup
await using (var scope = provider.CreateAsyncScope())
{
    await scope.ServiceProvider.GetRequiredService<AppDbContext>()
        .Database.MigrateAsync();
}

// Use the repository
await using var scope2 = provider.CreateAsyncScope();
var repo = scope2.ServiceProvider.GetRequiredService<NoteRepository>();

var note = await repo.CreateAsync(
    "Shopping list", "Milk, eggs, bread", ["personal", "todo"],
    CancellationToken.None);

Console.WriteLine($"Created note #{note.Id}: {note.Title}");
```

---

## 40.3 Project: `pganalytics` — PostgreSQL Analytics Service

**What it does:** ingests page view events, stores them in PostgreSQL,
and serves aggregated reports. Demonstrates: Npgsql, bulk insert, raw SQL
with Dapper for analytics queries, index design.

```bash
dotnet new webapi -n pganalytics --no-openapi
cd pganalytics
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package Dapper
dotnet add package Npgsql
```

### Setup PostgreSQL Locally

```bash
# Docker (fastest for local dev)
docker run -d \
  --name pg-dev \
  -e POSTGRES_USER=dev \
  -e POSTGRES_PASSWORD=dev \
  -e POSTGRES_DB=analytics \
  -p 5432:5432 \
  postgres:16-alpine

# Or on NixOS:
services.postgresql.enable = true;
services.postgresql.package = pkgs.postgresql_16;
```

```bash
# Verify
psql postgresql://dev:dev@localhost/analytics -c "SELECT version();"
```

### Schema — Hand-Written DDL (reference Ch 15a)

```sql
-- migrations/001_init.sql  (run once, then use EF migrations)
CREATE TABLE page_views (
    id         BIGSERIAL PRIMARY KEY,
    session_id UUID        NOT NULL,
    path       TEXT        NOT NULL,
    referrer   TEXT,
    user_agent TEXT,
    ip_hash    TEXT,          -- hashed, never store raw IPs
    viewed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_page_views_path       ON page_views (path);
CREATE INDEX idx_page_views_viewed_at  ON page_views (viewed_at DESC);
CREATE INDEX idx_page_views_session    ON page_views (session_id);

-- Partitioning by month for large datasets (optional):
-- CREATE TABLE page_views PARTITION BY RANGE (viewed_at);
-- CREATE TABLE page_views_2025_01 PARTITION OF page_views
--     FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

### Bulk Insert

```csharp
// For high-volume ingestion, use Npgsql COPY — far faster than INSERT
using var conn = new NpgsqlConnection(connectionString);
await conn.OpenAsync(ct);

await using var writer = await conn.BeginBinaryImportAsync(
    "COPY page_views (session_id, path, referrer, viewed_at) FROM STDIN (FORMAT BINARY)", ct);

foreach (var ev in events)
{
    await writer.StartRowAsync(ct);
    await writer.WriteAsync(ev.SessionId, NpgsqlTypes.NpgsqlDbType.Uuid, ct);
    await writer.WriteAsync(ev.Path,      NpgsqlTypes.NpgsqlDbType.Text, ct);
    await writer.WriteAsync(ev.Referrer,  NpgsqlTypes.NpgsqlDbType.Text, ct);
    await writer.WriteAsync(ev.ViewedAt,  NpgsqlTypes.NpgsqlDbType.TimestampTz, ct);
}

await writer.CompleteAsync(ct);
// Typical throughput: 100k–500k rows/second
```

### Analytics Queries with Dapper

```csharp
// AnalyticsRepository.cs
public class AnalyticsRepository(NpgsqlDataSource ds)
{
    // Top pages in last N days — Dapper, raw SQL
    public async Task<IReadOnlyList<PageStats>> GetTopPagesAsync(
        int days, int limit, CancellationToken ct)
    {
        await using var conn = await ds.OpenConnectionAsync(ct);

        // Dapper maps the result set to PageStats record automatically
        return (await conn.QueryAsync<PageStats>(
            """
            SELECT
                path,
                COUNT(*)                           AS views,
                COUNT(DISTINCT session_id)          AS unique_visitors,
                MAX(viewed_at)                      AS last_view
            FROM page_views
            WHERE viewed_at >= NOW() - $1::interval
            GROUP BY path
            ORDER BY views DESC
            LIMIT $2
            """,
            new { days = $"{days} days", limit })).ToList();
    }

    // Daily unique visitors — window function for rolling 7-day average
    public async Task<IReadOnlyList<DailyStats>> GetDailyStatsAsync(
        DateTime from, DateTime to, CancellationToken ct)
    {
        await using var conn = await ds.OpenConnectionAsync(ct);

        return (await conn.QueryAsync<DailyStats>(
            """
            WITH daily AS (
                SELECT
                    viewed_at::date                       AS day,
                    COUNT(DISTINCT session_id)             AS visitors
                FROM page_views
                WHERE viewed_at BETWEEN @From AND @To
                GROUP BY 1
            )
            SELECT
                day,
                visitors,
                AVG(visitors) OVER (
                    ORDER BY day
                    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
                ) AS rolling7d
            FROM daily
            ORDER BY day
            """,
            new { From = from, To = to })).ToList();
    }
}

public record PageStats(string Path, long Views, long UniqueVisitors, DateTime LastView);
public record DailyStats(DateOnly Day, long Visitors, double Rolling7d);
```

---

## 40.4 Migrations in Production — The Safe Pattern

**The problem:** you can't run `dotnet ef database update` in production
during a zero-downtime deploy. The old binary is still running while
the new schema is being applied.

**The safe pattern:**

```
1. Every migration must be backward compatible:
   - Add columns as nullable first
   - Never rename a column in one step (add + copy + drop in three separate deploys)
   - Never drop a column the old binary still reads

2. Apply migrations separately from code deploy:
   - Run migrations before deploying new code
   - New code must handle both old and new schema
   - Remove backward-compat code in a later deploy
```

```csharp
// Generate a migration SQL script for review before applying:
dotnet ef migrations script --idempotent > migrations.sql
// Review migrations.sql, then apply in DB console or via CI pipeline

// Or apply programmatically with timeout:
await using var scope = provider.CreateAsyncScope();
var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
var strategy = db.Database.CreateExecutionStrategy();
await strategy.ExecuteAsync(async () =>
{
    await db.Database.MigrateAsync(ct);
});
```

---

## 40.5 Project: `tenantapi` — Multi-Tenant API With Schema-per-Tenant

**What it does:** each tenant gets their own PostgreSQL schema.
Demonstrates: DbContext factory, dynamic connection strings,
schema isolation, and tenant resolution from the request.

```csharp
// TenantDbContext.cs
public class TenantDbContext : DbContext
{
    private readonly string _schema;
    public DbSet<Order> Orders { get; set; } = null!;

    public TenantDbContext(DbContextOptions<TenantDbContext> opts, string schema)
        : base(opts)
    {
        _schema = schema;
    }

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.HasDefaultSchema(_schema);
        b.Entity<Order>().HasKey(o => o.Id);
    }
}

// TenantDbContextFactory.cs
public class TenantDbContextFactory(IConfiguration config)
{
    public TenantDbContext Create(string tenantId)
    {
        // Each tenant gets its own schema: "tenant_acme", "tenant_globex"
        var schema = $"tenant_{tenantId.ToLowerInvariant()}";
        var opts = new DbContextOptionsBuilder<TenantDbContext>()
            .UseNpgsql(config["Database:ConnectionString"])
            .Options;

        return new TenantDbContext(opts, schema);
    }
}

// In your endpoint:
app.MapGet("/orders", async (
    HttpContext http,
    TenantDbContextFactory factory,
    CancellationToken ct) =>
{
    var tenantId = http.Request.Headers["X-Tenant-Id"].FirstOrDefault()
        ?? throw new BadHttpRequestException("Missing X-Tenant-Id header");

    await using var db = factory.Create(tenantId);
    await db.Database.EnsureCreatedAsync(ct);   // creates schema if first request

    return await db.Orders.ToListAsync(ct);
});
```

---

## 40.6 Testing With Testcontainers — Real Database, No Mocks

```csharp
// Sync.Mesh.Integration.Tests / OrderRepositoryTests.cs
using Testcontainers.PostgreSql;

public class OrderRepositoryTests : IAsyncLifetime
{
    private PostgreSqlContainer _pg = null!;
    private AppDbContext        _db = null!;

    public async Task InitializeAsync()
    {
        _pg = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .WithUsername("test")
            .WithPassword("test")
            .Build();

        await _pg.StartAsync();

        var opts = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_pg.GetConnectionString())
            .Options;

        _db = new AppDbContext(opts);
        await _db.Database.MigrateAsync();
    }

    [Fact]
    public async Task Insert_and_query_note()
    {
        var repo = new NoteRepository(_db);
        var note = await repo.CreateAsync("Hello", "World", ["test"], default);

        var found = await repo.GetByIdAsync(note.Id, default);

        Assert.NotNull(found);
        Assert.Equal("Hello", found.Title);
    }

    public async Task DisposeAsync()
    {
        await _db.DisposeAsync();
        await _pg.DisposeAsync();
    }
}
```

**Why Testcontainers beats an in-memory provider:**
- In-memory EF does not enforce referential integrity, unique constraints,
  or nullable constraints — your tests pass, your production query fails
- Testcontainers starts a real PostgreSQL Docker container, runs your
  actual migrations, and gives you a clean database per test class
- Tests are slow the first time (image pull), then fast (container reuse)

---

## 40.7 The IEnumerable vs IQueryable Trap (Again)

This mistake is so common it appears in its own section here (see Ch 15 §15.12 for the full explanation):

```csharp
// BROKEN: loads ALL rows into memory, then filters in .NET
var expensive = await db.Orders
    .ToListAsync()          // materialises entire table
    .ContinueWith(t => t.Result.Where(o => o.Status == "pending").ToList());

// BROKEN: AsEnumerable also materialises
var alsoExpensive = db.Orders
    .AsEnumerable()         // switches from IQueryable to IEnumerable
    .Where(o => o.Status == "pending")  // now runs in .NET, not SQL
    .ToList();

// CORRECT: stays as IQueryable until ToListAsync — WHERE is in SQL
var correct = await db.Orders
    .Where(o => o.Status == "pending")  // translated to SQL WHERE
    .OrderByDescending(o => o.CreatedAt)
    .Take(20)
    .ToListAsync(ct);
// SQL: SELECT TOP 20 * FROM orders WHERE status = 'pending' ORDER BY created_at DESC
```

The rule: **keep it `IQueryable` until you call `ToListAsync`, `FirstOrDefaultAsync`,
`CountAsync`, or `AnyAsync`.** Every LINQ operator applied before that goes to SQL.
Every operator applied after runs in your process.
