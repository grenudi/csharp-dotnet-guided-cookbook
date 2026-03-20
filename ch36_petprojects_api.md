# Chapter 36 — Pet Projects IV: REST API Server

> Build a complete, production-shaped REST API: routes, validation,
> auth, error handling, SQLite storage, OpenAPI docs, integration tests.

---

## 36.1 Project — `taskapi`: A Task Management API

**What it does:** Full CRUD for tasks and users. JWT authentication.
SQLite persistence via EF Core. OpenAPI spec auto-generated.

**Concepts:** Minimal API (Ch 14 §14.8), EF Core (Ch 15), JWT (Ch 28),
DI (Ch 10), integration testing (Ch 17)

```bash
dotnet new webapi -n taskapi --use-minimal-apis
cd taskapi
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer
dotnet add package BCrypt.Net-Next
```

---

## 36.2 Domain and Persistence

```csharp
// Models.cs
public class AppUser
{
    public int    Id           { get; set; }
    public string Email        { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string Name         { get; set; } = "";
    public DateTime CreatedAt  { get; set; }
}

public class TaskItem
{
    public int      Id          { get; set; }
    public int      UserId      { get; set; }
    public string   Title       { get; set; } = "";
    public string?  Description { get; set; }
    public bool     Done        { get; set; }
    public Priority Priority    { get; set; }
    public DateTime CreatedAt   { get; set; }
    public DateTime? DueAt      { get; set; }
    public AppUser  User        { get; set; } = null!;
}

public enum Priority { Low, Medium, High }

// AppDbContext.cs
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> o) : base(o) { }
    public DbSet<AppUser>  Users => Set<AppUser>();
    public DbSet<TaskItem> Tasks => Set<TaskItem>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<AppUser>().HasIndex(u => u.Email).IsUnique();
        b.Entity<TaskItem>().HasOne(t => t.User)
            .WithMany().HasForeignKey(t => t.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}
```

---

## 36.3 Program.cs — Complete Wiring

```csharp
// Program.cs
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// ── Database ──────────────────────────────────────────────────────────────
builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseSqlite(builder.Configuration.GetConnectionString("Default") ?? "Data Source=taskapi.db"));

// ── Auth ──────────────────────────────────────────────────────────────────
var jwtKey = builder.Configuration["Jwt:Key"]
    ?? throw new InvalidOperationException("Jwt:Key is required.");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey         = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ValidateIssuer           = false,   // simplify for this project
            ValidateAudience         = false,
            ClockSkew                = TimeSpan.Zero,
        };
    });
builder.Services.AddAuthorization();

// ── OpenAPI ───────────────────────────────────────────────────────────────
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    o.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization", Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "bearer", BearerFormat = "JWT", In = Microsoft.OpenApi.Models.ParameterLocation.Header,
    });
    o.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        [new() { Reference = new() { Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme, Id = "Bearer" } }] = [],
    });
});

// ── Validation helper ─────────────────────────────────────────────────────
builder.Services.AddSingleton<ITokenService, JwtTokenService>();

var app = builder.Build();

// ── Migrate on startup ─────────────────────────────────────────────────────
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

app.UseAuthentication();
app.UseAuthorization();
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// ── Routes ─────────────────────────────────────────────────────────────────
app.MapAuthRoutes();
app.MapTaskRoutes();

await app.RunAsync();
```

---

## 36.4 Auth Routes

```csharp
// AuthRoutes.cs
public static class AuthRouteExtensions
{
    public static IEndpointRouteBuilder MapAuthRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/auth").WithTags("Auth");

        // POST /auth/register
        group.MapPost("/register", async (RegisterRequest req, AppDbContext db, ITokenService tokens) =>
        {
            if (await db.Users.AnyAsync(u => u.Email == req.Email))
                return Results.Conflict(new { error = "Email already registered." });

            var user = new AppUser
            {
                Email        = req.Email.ToLower().Trim(),
                Name         = req.Name,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password),
                CreatedAt    = DateTime.UtcNow,
            };
            db.Users.Add(user);
            await db.SaveChangesAsync();
            return Results.Ok(new { token = tokens.Generate(user) });
        });

        // POST /auth/login
        group.MapPost("/login", async (LoginRequest req, AppDbContext db, ITokenService tokens) =>
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == req.Email.ToLower());
            if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
                return Results.Unauthorized();
            return Results.Ok(new { token = tokens.Generate(user) });
        });

        return app;
    }
}

record RegisterRequest(string Email, string Password, string Name);
record LoginRequest(string Email, string Password);
```

---

## 36.5 Task Routes — Full CRUD

```csharp
// TaskRoutes.cs
public static class TaskRouteExtensions
{
    public static IEndpointRouteBuilder MapTaskRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/tasks")
            .WithTags("Tasks")
            .RequireAuthorization();   // ALL routes require JWT

        // GET /tasks?done=false&priority=High
        group.MapGet("/", async (
            AppDbContext db, ClaimsPrincipal user,
            bool? done, Priority? priority, int page = 1, int pageSize = 20) =>
        {
            var userId = GetUserId(user);
            var query  = db.Tasks.Where(t => t.UserId == userId).AsQueryable();

            if (done.HasValue)     query = query.Where(t => t.Done == done.Value);
            if (priority.HasValue) query = query.Where(t => t.Priority == priority.Value);

            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(t => TaskDto.From(t))
                .ToListAsync();

            return Results.Ok(new PagedResult<TaskDto>(items, total, page, pageSize));
        });

        // GET /tasks/{id}
        group.MapGet("/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal user) =>
        {
            var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id && t.UserId == GetUserId(user));
            return task is null ? Results.NotFound() : Results.Ok(TaskDto.From(task));
        });

        // POST /tasks
        group.MapPost("/", async (CreateTaskRequest req, AppDbContext db, ClaimsPrincipal user) =>
        {
            if (string.IsNullOrWhiteSpace(req.Title))
                return Results.ValidationProblem(new Dictionary<string, string[]>
                    { ["title"] = ["Title is required."] });

            var task = new TaskItem
            {
                UserId      = GetUserId(user),
                Title       = req.Title.Trim(),
                Description = req.Description?.Trim(),
                Priority    = req.Priority,
                DueAt       = req.DueAt,
                CreatedAt   = DateTime.UtcNow,
            };
            db.Tasks.Add(task);
            await db.SaveChangesAsync();
            return Results.Created($"/tasks/{task.Id}", TaskDto.From(task));
        });

        // PATCH /tasks/{id}
        group.MapPatch("/{id:int}", async (int id, UpdateTaskRequest req, AppDbContext db, ClaimsPrincipal user) =>
        {
            var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id && t.UserId == GetUserId(user));
            if (task is null) return Results.NotFound();

            if (req.Title       is not null) task.Title       = req.Title.Trim();
            if (req.Description is not null) task.Description = req.Description;
            if (req.Done        is not null) task.Done        = req.Done.Value;
            if (req.Priority    is not null) task.Priority    = req.Priority.Value;
            if (req.DueAt       is not null) task.DueAt       = req.DueAt;

            await db.SaveChangesAsync();
            return Results.Ok(TaskDto.From(task));
        });

        // DELETE /tasks/{id}
        group.MapDelete("/{id:int}", async (int id, AppDbContext db, ClaimsPrincipal user) =>
        {
            var task = await db.Tasks.FirstOrDefaultAsync(t => t.Id == id && t.UserId == GetUserId(user));
            if (task is null) return Results.NotFound();
            db.Tasks.Remove(task);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        return app;
    }

    private static int GetUserId(ClaimsPrincipal user)
        => int.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);
}

// DTOs
record TaskDto(int Id, string Title, string? Description, bool Done, Priority Priority, DateTime CreatedAt, DateTime? DueAt)
{
    public static TaskDto From(TaskItem t) =>
        new(t.Id, t.Title, t.Description, t.Done, t.Priority, t.CreatedAt, t.DueAt);
}

record CreateTaskRequest(string Title, string? Description = null, Priority Priority = Priority.Medium, DateTime? DueAt = null);
record UpdateTaskRequest(string? Title, string? Description, bool? Done, Priority? Priority, DateTime? DueAt);
record PagedResult<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize);
```

---

## 36.6 JWT Token Service

```csharp
// TokenService.cs
public interface ITokenService { string Generate(AppUser user); }

public sealed class JwtTokenService : ITokenService
{
    private readonly string _key;
    public JwtTokenService(IConfiguration cfg)
        => _key = cfg["Jwt:Key"] ?? throw new InvalidOperationException("Jwt:Key missing");

    public string Generate(AppUser user)
    {
        var key   = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_key));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Email,          user.Email),
            new Claim(ClaimTypes.Name,           user.Name),
        };

        var token = new System.IdentityModel.Tokens.Jwt.JwtSecurityToken(
            claims:   claims,
            expires:  DateTime.UtcNow.AddDays(30),
            signingCredentials: creds);

        return new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler().WriteToken(token);
    }
}
```

---

## 36.7 Integration Test

```csharp
// taskapi.Tests/TaskApiTests.cs
// dotnet add package Microsoft.AspNetCore.Mvc.Testing
public class TaskApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public TaskApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.WithWebHostBuilder(b =>
            b.ConfigureServices(s => {
                // Use in-memory SQLite for tests
                s.AddDbContext<AppDbContext>(o => o.UseSqlite("Data Source=:memory:"));
            })).CreateClient();
    }

    [Fact]
    public async Task Register_and_create_task_succeeds()
    {
        // Register
        var reg = await _client.PostAsJsonAsync("/auth/register",
            new { Email = "test@test.com", Password = "P@ss1234", Name = "Test User" });
        reg.StatusCode.Should().Be(HttpStatusCode.OK);

        var token = (await reg.Content.ReadFromJsonAsync<TokenResponse>())!.Token;
        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        // Create task
        var create = await _client.PostAsJsonAsync("/tasks",
            new { Title = "Write tests", Priority = "High" });
        create.StatusCode.Should().Be(HttpStatusCode.Created);

        // List
        var list = await _client.GetFromJsonAsync<PagedResult<TaskDto>>("/tasks");
        list!.Items.Should().ContainSingle(t => t.Title == "Write tests");
    }

    record TokenResponse(string Token);
}
```

---

## 36.8 Running and Testing

```bash
# Set a JWT key in env
export Jwt__Key="super-secret-development-key-32chars"

# Run
dotnet run

# Test via httpie / curl
http POST localhost:5000/auth/register email=a@b.com password=Test123 name=Alice
http POST localhost:5000/tasks title="Buy milk" priority=Low \
    "Authorization: Bearer <token>"
http GET localhost:5000/tasks "Authorization: Bearer <token>"

# OpenAPI
open http://localhost:5000/swagger
```
