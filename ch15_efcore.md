# Chapter 15 — Entity Framework Core & Data Access

> A relational database stores data as tables of rows. Your C# code works
> with objects and graphs. Bridging the two worlds — without writing SQL
> for every operation, without loading entire tables into memory, and
> without introducing security holes — is the job of an ORM. EF Core is
> .NET's built-in ORM. This chapter explains how it maps objects to SQL,
> how to use it correctly, and when to bypass it.

*Building on:* Ch 2 (classes, records, nullable), Ch 5 (OOP — entity
classes), Ch 8 (async — all DB calls should be async), Ch 9 (configuration
— connection strings), Ch 10 (DI — DbContext lifetime), Ch 15a (SQL — read
that chapter first; EF Core generates SQL and you must be able to read it)

---

## 15.1 The ORM Mental Model — What EF Core Is and Is Not

EF Core is not a magic layer that makes SQL invisible. It is a tool that
translates LINQ expression trees (Ch 4 §4.7) into SQL, tracks which
objects you have changed (change tracking), and maps result rows back to
objects. The generated SQL is real SQL — you can log it, read it, and
optimise it.

Understanding this prevents the most common EF Core bugs:
- Queries that load entire tables into memory (because you broke out of
  `IQueryable` too early — see §15.12)
- N+1 queries (because you accessed a navigation property in a loop)
- Missing indexes (because you wrote a LINQ query that EF translated to
  a full table scan)
- Slow inserts (because you called `SaveChanges` inside a loop)

The relationship between your code and the database:

```
Your C# code
    ↓ LINQ expression trees
EF Core (query translator)
    ↓ SQL string
ADO.NET (SqlConnection / NpgsqlConnection / SqliteConnection)
    ↓ TCP/socket
Database engine (SQLite / PostgreSQL / SQL Server)
```

---

## 15.2 Setup — Packages and Connection

```bash
# SQLite (file-based, great for development and small apps)
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design   # for migrations CLI

# PostgreSQL
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL

# SQL Server
dotnet add package Microsoft.EntityFrameworkCore.SqlServer

# Install the EF Core CLI tool
dotnet tool install --global dotnet-ef
```

---

## 15.3 Defining the Domain — Entity Classes

Entity classes are plain C# classes. EF Core requires no base class,
no attributes on most properties. By convention, a property named `Id`
or `{TypeName}Id` becomes the primary key.

```csharp
// A minimal but complete domain for a task tracker
public class Project
{
    public int    Id          { get; set; }
    public string Name        { get; set; } = "";
    public string? Description { get; set; }
    public DateTime CreatedAt { get; set; }

    // Navigation property: EF Core will fill this when you .Include(p => p.Tasks)
    public List<TaskItem> Tasks { get; set; } = [];
}

public class TaskItem
{
    public int    Id          { get; set; }
    public string Title       { get; set; } = "";
    public TaskStatus Status  { get; set; }
    public DateTime? DueDate  { get; set; }

    // Foreign key — EF Core maps this to a NOT NULL FK column
    public int     ProjectId  { get; set; }
    // Navigation property — the related Project object
    public Project Project    { get; set; } = null!;   // null! = EF will populate this
}

public enum TaskStatus { Todo, InProgress, Done, Cancelled }
```

---

## 15.4 `DbContext` — The Unit of Work

`DbContext` is EF Core's central class. It represents a session with the
database and contains `DbSet<T>` properties for each entity type you want
to query and manipulate. It does three jobs simultaneously:

1. **Query**: translates LINQ to SQL and materialises results
2. **Change tracking**: remembers which entities you loaded and what changed
3. **Unit of Work**: accumulates changes and commits them all at once via `SaveChangesAsync`

```csharp
public class AppDbContext : DbContext
{
    public DbSet<Project>  Projects { get; set; } = null!;
    public DbSet<TaskItem> Tasks    { get; set; } = null!;

    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    protected override void OnModelCreating(ModelBuilder builder)
    {
        // Fluent API: fine-grained schema control beyond conventions
        builder.Entity<Project>(e =>
        {
            e.HasKey(p => p.Id);
            e.Property(p => p.Name).HasMaxLength(200).IsRequired();
            e.Property(p => p.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");
            e.HasIndex(p => p.Name).IsUnique();
        });

        builder.Entity<TaskItem>(e =>
        {
            e.HasKey(t => t.Id);
            e.Property(t => t.Title).HasMaxLength(500).IsRequired();
            e.Property(t => t.Status)
             .HasConversion<string>()          // store enum as string, not int
             .HasDefaultValue(TaskStatus.Todo);

            // Relationship: many tasks belong to one project
            e.HasOne(t => t.Project)
             .WithMany(p => p.Tasks)
             .HasForeignKey(t => t.ProjectId)
             .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
```

---

## 15.5 Registering `DbContext` with Dependency Injection

`DbContext` is a Scoped service — one instance per HTTP request (or per
unit of work in non-HTTP code). This is intentional: change tracking is
per-instance and DbContext is not thread-safe. Never share a DbContext
across threads.

```csharp
// ASP.NET Core or Generic Host
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(builder.Configuration["Database:ConnectionString"])
           .EnableSensitiveDataLogging(builder.Environment.IsDevelopment())
           .EnableDetailedErrors(builder.Environment.IsDevelopment())
           .LogTo(Console.WriteLine, LogLevel.Information));

// Inject into a service or endpoint
public class ProjectService(AppDbContext db)
{
    // db is a Scoped instance, alive for one request
}
```

---

## 15.6 Querying — LINQ Over `DbSet<T>`

Every query starts from a `DbSet<T>` which is an `IQueryable<T>`. LINQ
operators chain on it. Nothing is executed until you call a terminal
operator (`ToListAsync`, `FirstOrDefaultAsync`, etc.).

```csharp
// Get all active projects
var projects = await db.Projects
    .Where(p => p.Tasks.Any(t => t.Status != TaskStatus.Done))
    .OrderBy(p => p.Name)
    .ToListAsync(ct);
// SQL: SELECT * FROM Projects p WHERE EXISTS (SELECT 1 FROM Tasks t WHERE t.ProjectId = p.Id AND t.Status != 'Done') ORDER BY p.Name

// Load a project with its tasks (eager loading via Include)
var project = await db.Projects
    .Include(p => p.Tasks.Where(t => t.Status != TaskStatus.Cancelled))
    .FirstOrDefaultAsync(p => p.Id == id, ct);
// SQL: SELECT p.*, t.* FROM Projects p LEFT JOIN Tasks t ON t.ProjectId = p.Id WHERE p.Id = @id

// Projection: select only the columns you need
var summaries = await db.Projects
    .Select(p => new ProjectSummary(
        p.Id, p.Name,
        p.Tasks.Count(t => t.Status == TaskStatus.Done),
        p.Tasks.Count(t => t.Status != TaskStatus.Done)))
    .ToListAsync(ct);
// SQL: SELECT p.Id, p.Name, COUNT(done tasks), COUNT(pending tasks) FROM...
// Only those columns are returned — much more efficient than loading full entities
```

### N+1 — The Most Common Performance Bug

```csharp
// BUG: N+1 queries — 1 query for projects + 1 per project for tasks
var projects = await db.Projects.ToListAsync(ct);
foreach (var project in projects)
{
    // EF Core lazily loads Tasks for each project — one SQL query per project!
    Console.WriteLine($"{project.Name}: {project.Tasks.Count} tasks");
}

// FIX: eager loading with Include
var projects2 = await db.Projects
    .Include(p => p.Tasks)
    .ToListAsync(ct);
// One query with a JOIN — all data in one round trip
```

Never enable lazy loading in production code (the `virtual` navigation
property pattern). It makes N+1 the default behaviour, hiding the
performance problem until production load exposes it.

---

## 15.7 CRUD — Creating, Updating, Deleting

```csharp
// CREATE
var project = new Project { Name = "Website Redesign", CreatedAt = DateTime.UtcNow };
db.Projects.Add(project);
await db.SaveChangesAsync(ct);
// project.Id is now populated by the database

// UPDATE — load, modify, save
var task = await db.Tasks.FindAsync([taskId], ct);
if (task is null) throw new NotFoundException($"Task {taskId} not found");
task.Status = TaskStatus.Done;
await db.SaveChangesAsync(ct);  // EF detects the change and generates UPDATE

// UPDATE without loading the entity (ExecuteUpdateAsync — EF Core 7+)
await db.Tasks
    .Where(t => t.ProjectId == projectId && t.Status == TaskStatus.Todo)
    .ExecuteUpdateAsync(setters => setters
        .SetProperty(t => t.Status, TaskStatus.Cancelled), ct);
// One SQL UPDATE statement — no entity loading, no change tracking

// DELETE — load then remove
db.Tasks.Remove(task);
await db.SaveChangesAsync(ct);

// DELETE without loading (ExecuteDeleteAsync — EF Core 7+)
int deleted = await db.Tasks
    .Where(t => t.DueDate < DateTime.UtcNow && t.Status == TaskStatus.Done)
    .ExecuteDeleteAsync(ct);
```

---

## 15.8 Transactions

`SaveChangesAsync` is implicitly transactional — all changes in one call
succeed or fail together. For operations that span multiple `SaveChanges`
calls, use explicit transactions:

```csharp
await using var transaction = await db.Database.BeginTransactionAsync(ct);
try
{
    project.Status = ProjectStatus.Archived;
    await db.SaveChangesAsync(ct);

    await db.Tasks
        .Where(t => t.ProjectId == project.Id && t.Status == TaskStatus.Todo)
        .ExecuteUpdateAsync(s => s.SetProperty(t => t.Status, TaskStatus.Cancelled), ct);

    await transaction.CommitAsync(ct);
}
catch
{
    await transaction.RollbackAsync(ct);
    throw;
}
```

---

## 15.9 Migrations — Managing Schema Evolution

Migrations are C# classes that describe how to transform the database
schema from one version to the next. They are the Git history of your
schema — commit them alongside the code that requires them.

```bash
# Create a migration after changing entity classes
dotnet ef migrations add AddTaskPriority

# Review the generated migration file before applying
# It's in Migrations/YYYYMMDDHHMMSS_AddTaskPriority.cs

# Apply all pending migrations
dotnet ef database update

# Generate a SQL script (review before running in production)
dotnet ef migrations script --idempotent > migrate.sql

# Roll back to a specific migration
dotnet ef database update PreviousMigrationName
```

```csharp
// Auto-apply migrations at startup (appropriate for development and small apps)
// In production, prefer the SQL script approach with DBA review
await using var scope = app.Services.CreateAsyncScope();
await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
```

---

## 15.10 Dapper — Raw SQL When EF Cannot Express It

Dapper is a micro-ORM that maps SQL query results to C# objects. It is
the right tool for complex analytical queries, stored procedures, or
any case where you know exactly what SQL you want and EF Core's
translation would be awkward or inefficient.

```bash
dotnet add package Dapper
```

```csharp
using Dapper;
using Microsoft.Data.Sqlite;

// Simple query
await using var conn = new SqliteConnection(connectionString);

var projects = await conn.QueryAsync<ProjectSummary>("""
    SELECT
        p.Id,
        p.Name,
        COUNT(t.Id) FILTER (WHERE t.Status = 'Done')    AS CompletedTasks,
        COUNT(t.Id) FILTER (WHERE t.Status != 'Done')   AS PendingTasks,
        MAX(t.DueDate)                                   AS NextDue
    FROM Projects p
    LEFT JOIN Tasks t ON t.ProjectId = p.Id
    GROUP BY p.Id, p.Name
    ORDER BY NextDue
    """);

// With parameters (never concatenate user input — always use parameters)
var overdue = await conn.QueryAsync<TaskItem>(
    "SELECT * FROM Tasks WHERE DueDate < @cutoff AND Status != @done",
    new { cutoff = DateTime.UtcNow, done = "Done" });
```

EF Core and Dapper coexist perfectly in the same application. Use EF
for entity-level CRUD; use Dapper for complex reports and analytics.

---

## 15.11 Change Tracking and Performance

EF Core tracks every entity it loads. When you call `SaveChangesAsync`,
it compares current values with the snapshot taken at load time and
generates the minimum SQL to sync the changes. This is powerful but has
a cost.

```csharp
// AsNoTracking: disable change tracking for read-only queries
// Faster: no snapshot, no comparison at save time
var projects = await db.Projects
    .AsNoTracking()           // no change tracking — purely reading
    .Include(p => p.Tasks)
    .ToListAsync(ct);

// AsNoTrackingWithIdentityResolution: no tracking but still deduplicates
// entities if the same entity appears multiple times in the results
var withShared = await db.Orders
    .AsNoTrackingWithIdentityResolution()
    .Include(o => o.Customer)
    .ToListAsync(ct);

// Bulk operations without tracking overhead
await db.Tasks
    .Where(t => t.Status == TaskStatus.Cancelled)
    .ExecuteDeleteAsync(ct);   // one DELETE statement, no entity loading
```

---

## 15.12 `IEnumerable<T>` vs `IQueryable<T>` — The Critical Distinction

This is the most important EF Core concept to internalise. It determines
whether your query runs in the database or in your process.

`IQueryable<T>` is a query waiting to be executed. Every LINQ operator
you apply adds to the expression tree — a description of what SQL to
generate. Nothing touches the database until you materialise.

`IEnumerable<T>` runs in .NET. Once you cross into `IEnumerable`, the
data is already in memory and every subsequent operator runs in C#.

```csharp
// WRONG: loads EVERY row from the database, then filters in .NET
var results = db.Tasks
    .ToList()                           // ← materialises all rows into memory HERE
    .Where(t => t.Status == TaskStatus.Done);  // filter runs in .NET

// WRONG: AsEnumerable also materialises all rows
var results2 = db.Tasks
    .AsEnumerable()                     // ← switches to in-memory
    .Where(t => t.Status == TaskStatus.Done);  // in .NET, not SQL

// CORRECT: WHERE is part of the SQL
var results3 = await db.Tasks
    .Where(t => t.Status == TaskStatus.Done)   // added to SQL expression tree
    .ToListAsync(ct);                           // NOW executes — one filtered SQL query

// You can call non-translatable methods AFTER materialising,
// but be aware that ALL rows matching the IQueryable conditions are loaded first:
var formatted = await db.Tasks
    .Where(t => t.Status == TaskStatus.Done)   // filter IN database
    .ToListAsync(ct)                            // load filtered results
    .ContinueWith(t => t.Result.Select(task => FormatTask(task)).ToList());
// FormatTask is arbitrary C# — cannot be translated to SQL
```

The rule: **Stay `IQueryable` until you need to be `IEnumerable`.** Call
`ToListAsync`, `FirstOrDefaultAsync`, `CountAsync`, or `AnyAsync` to
materialise only when you are done filtering and projecting.

---

## 15.13 Connecting EF Core to the Rest of the Book

- **Ch 15a (SQL)** — read it before this chapter. You should understand
  what `JOIN`, `WHERE`, `GROUP BY` mean in SQL before trusting EF Core
  to generate them.
- **Ch 10 (DI)** — `DbContext` is registered as Scoped. The captive
  dependency bug (Singleton holding Scoped DbContext) is a real risk.
- **Ch 11 (DI Deep Dive)** — `IServiceScopeFactory` is how BackgroundService
  gets a fresh DbContext per work cycle.
- **Ch 17 (Testing)** — Testcontainers gives you a real database for
  integration tests. In-memory providers are inadequate — they don't
  enforce constraints or run real SQL.
- **Ch 18 (Architectures)** — the Repository pattern (Ch 32) wraps
  DbContext behind an interface. Clean Architecture puts DbContext in
  the Infrastructure layer, away from domain logic.
- **Ch 40 (Pet Projects — Databases)** — three complete projects
  demonstrating code-first migrations, bulk operations, and multi-tenant
  schema patterns.
