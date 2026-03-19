# Chapter 28 — Security: Authentication, Authorization & Cryptography

## 28.1 The Landscape

Security in ASP.NET Core is split into three concerns that work together
but are completely separate:

```
Authentication  — WHO are you?       (identity, tokens, cookies)
Authorization   — WHAT can you do?   (roles, policies, claims)
Data Protection — HOW is data safe?  (encryption, secrets, HTTPS)
```

Understanding that split is the foundation. Most security bugs come from
confusing them or skipping one.

---

## 28.2 HTTPS — The Non-Negotiable Baseline

Always serve over HTTPS. HTTP is never acceptable for anything that carries
a cookie, a token, or user data.

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Redirect all HTTP to HTTPS (add early in pipeline)
app.UseHttpsRedirection();

// HSTS — tell browsers to always use HTTPS for this domain
// Only add in production — development uses self-signed certs
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();  // sets Strict-Transport-Security header
}
```

```bash
# Development: trust the dev certificate once
dotnet dev-certs https --trust
```

```csharp
// Configure HSTS options
builder.Services.AddHsts(opts =>
{
    opts.MaxAge            = TimeSpan.FromDays(365);
    opts.IncludeSubDomains = true;
    opts.Preload           = true;
});
```

---

## 28.3 Authentication — Proving Identity

### Cookie Authentication (Server-Rendered Apps / MVC)

The server issues a signed, encrypted cookie after login. The browser
sends it with every request automatically.

```csharp
builder.Services
    .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(opts =>
    {
        opts.LoginPath        = "/account/login";
        opts.LogoutPath       = "/account/logout";
        opts.AccessDeniedPath = "/account/forbidden";
        opts.ExpireTimeSpan   = TimeSpan.FromHours(8);
        opts.SlidingExpiration = true;
        opts.Cookie.HttpOnly  = true;     // JS cannot read the cookie
        opts.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        opts.Cookie.SameSite  = SameSiteMode.Lax;
    });

// Sign in after verifying credentials
var claims = new List<Claim>
{
    new(ClaimTypes.NameIdentifier, user.Id.ToString()),
    new(ClaimTypes.Name,           user.Username),
    new(ClaimTypes.Email,          user.Email),
    new(ClaimTypes.Role,           "admin"),
};
var identity  = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
var principal = new ClaimsPrincipal(identity);
await httpContext.SignInAsync(principal);

// Sign out
await httpContext.SignOutAsync();
```

### JWT Bearer Authentication (APIs / SPAs / Mobile)

The client sends a signed token in the `Authorization: Bearer <token>` header.
The server validates the signature — no database lookup needed.

```csharp
// Install: Microsoft.AspNetCore.Authentication.JwtBearer

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts =>
    {
        opts.Authority    = builder.Configuration["Auth:Authority"];  // e.g. https://login.microsoftonline.com/{tenantId}
        opts.Audience     = builder.Configuration["Auth:Audience"];   // your API's identifier
        opts.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ClockSkew                = TimeSpan.FromMinutes(1),
        };
    });
```

### Generating JWT Tokens (Self-Issued)

For APIs that issue their own tokens (not delegating to an IdP):

```csharp
// Install: System.IdentityModel.Tokens.Jwt

public class TokenService
{
    private readonly IConfiguration _cfg;
    public TokenService(IConfiguration cfg) => _cfg = cfg;

    public string GenerateToken(User user)
    {
        var key     = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(_cfg["Jwt:Secret"]!));  // min 32 chars
        var creds   = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var expires = DateTime.UtcNow.AddHours(8);

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub,   user.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
            new Claim(JwtRegisteredClaimNames.Jti,   Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.Role,               user.Role),
        };

        var token = new JwtSecurityToken(
            issuer:   _cfg["Jwt:Issuer"],
            audience: _cfg["Jwt:Audience"],
            claims:   claims,
            expires:  expires,
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

// Validate self-issued JWT
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts =>
    {
        opts.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidIssuer              = builder.Configuration["Jwt:Issuer"],
            ValidateAudience         = true,
            ValidAudience            = builder.Configuration["Jwt:Audience"],
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey         = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]!)),
        };
    });
```

### Refresh Tokens Pattern

Access tokens are short-lived (15 min). Refresh tokens allow getting a new
access token without re-logging in (hours to days).

```csharp
public record TokenPair(string AccessToken, string RefreshToken, DateTime ExpiresAt);

public class TokenService
{
    // Generate access + refresh token pair
    public async Task<TokenPair> GenerateTokenPairAsync(User user, CancellationToken ct)
    {
        var accessToken  = GenerateAccessToken(user);      // short-lived JWT
        var refreshToken = GenerateRefreshToken();         // opaque random string

        // Store refresh token hash in DB (never store the token itself)
        await _db.RefreshTokens.AddAsync(new RefreshTokenEntity
        {
            UserId    = user.Id,
            TokenHash = HashToken(refreshToken),
            ExpiresAt = DateTime.UtcNow.AddDays(30),
        }, ct);
        await _db.SaveChangesAsync(ct);

        return new TokenPair(accessToken, refreshToken, DateTime.UtcNow.AddMinutes(15));
    }

    private string GenerateRefreshToken()
    {
        var bytes = new byte[64];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToBase64String(bytes);
    }

    private string HashToken(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
```

---

## 28.4 OAuth 2.0 and OpenID Connect

**OAuth 2.0** is an authorization protocol — it lets a user grant your app access
to their data at another service.

**OpenID Connect** is an identity layer on top of OAuth 2.0 — it also proves who the user is.

```
User → Your App → Identity Provider (Google, Azure AD, Auth0, Keycloak)
                ↑ redirects for login
                ↓ returns tokens (ID token + access token)
Your App validates tokens → user is authenticated
```

```csharp
// Login with external provider
builder.Services
    .AddAuthentication()
    .AddGoogle(opts =>
    {
        opts.ClientId     = builder.Configuration["Google:ClientId"]!;
        opts.ClientSecret = builder.Configuration["Google:ClientSecret"]!;
    })
    .AddMicrosoftAccount(opts =>
    {
        opts.ClientId     = builder.Configuration["Microsoft:ClientId"]!;
        opts.ClientSecret = builder.Configuration["Microsoft:ClientSecret"]!;
    })
    // Generic OIDC provider (Auth0, Keycloak, Okta, etc.)
    .AddOpenIdConnect("oidc", opts =>
    {
        opts.Authority    = builder.Configuration["Oidc:Authority"];
        opts.ClientId     = builder.Configuration["Oidc:ClientId"];
        opts.ClientSecret = builder.Configuration["Oidc:ClientSecret"];
        opts.ResponseType = "code";               // authorization code flow
        opts.SaveTokens   = true;
        opts.Scope.Add("openid");
        opts.Scope.Add("profile");
        opts.Scope.Add("email");
    });
```

### When to Use What

```
Cookie auth     → server-rendered web app (MVC, Razor Pages, Blazor Server)
JWT bearer      → REST API consumed by SPA, mobile, or other services
External OIDC   → "Login with Google/Microsoft" — never implement your own auth
                  if you can delegate to a trusted provider
```

---

## 28.5 Authorization — What Can You Do?

### Role-Based

```csharp
// Assign roles to users at login (claims)
new Claim(ClaimTypes.Role, "admin")
new Claim(ClaimTypes.Role, "moderator")

// Require role on endpoint
[Authorize(Roles = "admin")]
public IActionResult AdminPanel() { }

// Minimal API
app.MapGet("/admin", AdminHandler).RequireAuthorization("AdminOnly");

// Multiple roles (OR)
[Authorize(Roles = "admin,moderator")]
```

### Policy-Based (Recommended — More Flexible)

```csharp
// Register policies
builder.Services.AddAuthorization(opts =>
{
    opts.AddPolicy("AdminOnly", p => p.RequireRole("admin"));

    opts.AddPolicy("Over18", p =>
        p.RequireClaim("DateOfBirth")
         .AddRequirements(new MinimumAgeRequirement(18)));

    opts.AddPolicy("CanEditPosts", p =>
        p.RequireAuthenticatedUser()
         .RequireClaim("permission", "posts:write"));

    // Require authenticated user everywhere by default
    opts.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
    // Now every endpoint requires auth UNLESS explicitly marked [AllowAnonymous]
});

// Custom requirement
public class MinimumAgeRequirement : IAuthorizationRequirement
{
    public int MinimumAge { get; }
    public MinimumAgeRequirement(int age) => MinimumAge = age;
}

public class MinimumAgeHandler : AuthorizationHandler<MinimumAgeRequirement>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext ctx,
        MinimumAgeRequirement req)
    {
        var dob = ctx.User.FindFirstValue("DateOfBirth");
        if (dob is null) return Task.CompletedTask;

        var age = (DateTime.Today - DateTime.Parse(dob)).Days / 365;
        if (age >= req.MinimumAge) ctx.Succeed(req);
        return Task.CompletedTask;
    }
}

builder.Services.AddSingleton<IAuthorizationHandler, MinimumAgeHandler>();
```

### Resource-Based Authorization

```csharp
// Check if user can edit THIS specific resource
public class DocumentAuthorizationHandler
    : AuthorizationHandler<EditDocumentRequirement, Document>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext ctx,
        EditDocumentRequirement req,
        Document document)
    {
        var userId = ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (document.OwnerId.ToString() == userId)
            ctx.Succeed(req);
        return Task.CompletedTask;
    }
}

// Usage in controller/handler
var authResult = await _authService.AuthorizeAsync(
    User, document, new EditDocumentRequirement());
if (!authResult.Succeeded) return Forbid();
```

### Reading Claims

```csharp
// In a controller or minimal API handler
var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
var email  = User.FindFirstValue(ClaimTypes.Email);
var role   = User.FindFirstValue(ClaimTypes.Role);
bool isAdmin = User.IsInRole("admin");

// In a service (inject IHttpContextAccessor)
public class CurrentUserService
{
    private readonly IHttpContextAccessor _ctx;
    public CurrentUserService(IHttpContextAccessor ctx) => _ctx = ctx;

    public string? UserId => _ctx.HttpContext?.User
        .FindFirstValue(ClaimTypes.NameIdentifier);

    public bool IsAuthenticated => _ctx.HttpContext?.User.Identity?.IsAuthenticated ?? false;
}

// Register
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUserService, CurrentUserService>();
```

---

## 28.6 CORS — Cross-Origin Resource Sharing

Browsers block requests from one origin to another unless the server explicitly
permits it via CORS headers. This is a browser security feature — not a server
security mechanism (it does not protect your API from non-browser clients).

```csharp
builder.Services.AddCors(opts =>
{
    // Specific origins (production)
    opts.AddPolicy("AllowFrontend", policy =>
        policy.WithOrigins("https://app.example.com", "https://admin.example.com")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials());   // required for cookies

    // Development — allow all
    opts.AddPolicy("AllowAll", policy =>
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader());
    // Note: AllowAnyOrigin() and AllowCredentials() cannot be combined
});

// Apply in pipeline (must be after UseRouting, before UseAuthentication)
app.UseCors("AllowFrontend");

// Or per endpoint
app.MapGet("/public", handler).RequireCors("AllowAll");
app.MapGet("/api/data", handler).RequireCors("AllowFrontend");
```

---

## 28.7 Data Protection — Encrypting Sensitive Data

ASP.NET Core Data Protection encrypts data at rest (cookies, tokens, query string
parameters). It manages key rotation automatically.

```csharp
// Basic setup (keys stored in ~/.aspnet/DataProtection-Keys by default)
builder.Services.AddDataProtection();

// Production: store keys in a safe location
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo("/var/app/keys"))
    .SetDefaultKeyLifetime(TimeSpan.FromDays(90))
    .ProtectKeysWithCertificate("thumbprint");  // encrypt at rest

// Or with Azure Blob + Key Vault
builder.Services.AddDataProtection()
    .PersistKeysToAzureBlobStorage(connectionString, "keys", "keys.xml")
    .ProtectKeysWithAzureKeyVault(keyId, credential);

// Usage: protect/unprotect any string
public class SecureTokenService
{
    private readonly IDataProtector _protector;

    public SecureTokenService(IDataProtectionProvider provider)
        => _protector = provider.CreateProtector("SecureTokens.v1");

    public string Protect(string value)   => _protector.Protect(value);
    public string Unprotect(string value) => _protector.Unprotect(value);

    // Time-limited protection
    private readonly ITimeLimitedDataProtector _timed;
    public SecureTokenService(IDataProtectionProvider p)
        => _timed = p.CreateProtector("ResetTokens").ToTimeLimitedDataProtector();

    public string CreateResetToken(string userId) =>
        _timed.Protect(userId, TimeSpan.FromHours(1));

    public bool TryValidateResetToken(string token, out string userId)
    {
        try { userId = _timed.Unprotect(token); return true; }
        catch { userId = ""; return false; }
    }
}
```

---

## 28.8 Password Hashing

Never store passwords. Store a hash. Use `PasswordHasher<T>` from ASP.NET Core
Identity — it uses PBKDF2 with HMAC-SHA512 and a random salt.

```csharp
using Microsoft.AspNetCore.Identity;

public class UserService
{
    private readonly IPasswordHasher<User> _hasher;

    public UserService(IPasswordHasher<User> hasher) => _hasher = hasher;

    public User Register(string username, string password)
    {
        var user = new User { Username = username };
        user.PasswordHash = _hasher.HashPassword(user, password);
        return user;
    }

    public bool VerifyPassword(User user, string password)
    {
        var result = _hasher.VerifyHashedPassword(user, user.PasswordHash, password);
        return result is PasswordVerificationResult.Success
            or PasswordVerificationResult.SuccessRehashNeeded;
    }
}

// Register
builder.Services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();
```

---

## 28.9 Common Vulnerabilities — The OWASP Top 10 in .NET Context

### SQL Injection

```csharp
// ❌ Vulnerable — user input in raw SQL
var users = db.Database.ExecuteSqlRaw(
    $"SELECT * FROM Users WHERE name = '{userInput}'");
// Input: '; DROP TABLE Users; --

// ✅ Safe — parameterized
var users = db.Users.Where(u => u.Name == userInput).ToList();
// EF Core always parameterizes LINQ queries

// ✅ Safe — explicit parameterized raw SQL
var users = db.Database.ExecuteSqlRaw(
    "SELECT * FROM Users WHERE name = {0}", userInput);
```

### Cross-Site Scripting (XSS)

```csharp
// Razor automatically encodes output — no action needed
<p>@Model.UserInput</p>  // safe — HTML encoded

// Explicit encoding when needed outside Razor
var safe = System.Net.WebUtility.HtmlEncode(userInput);

// Content Security Policy header
app.Use(async (ctx, next) =>
{
    ctx.Response.Headers.Append("Content-Security-Policy",
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'");
    await next();
});
```

### Mass Assignment / Over-Posting

```csharp
// ❌ Dangerous — user can POST any field including IsAdmin
public async Task<IActionResult> Update(User user)
{
    _db.Update(user);  // user.IsAdmin could be set to true by the client
}

// ✅ Safe — only accept what the form allows
public async Task<IActionResult> Update(UpdateUserDto dto)
{
    var user = await _db.Users.FindAsync(dto.Id);
    user!.Name  = dto.Name;
    user.Email  = dto.Email;
    // IsAdmin is NOT on UpdateUserDto — client cannot set it
    await _db.SaveChangesAsync();
}
```

### Security Headers

```csharp
app.Use(async (ctx, next) =>
{
    ctx.Response.Headers.Append("X-Content-Type-Options", "nosniff");
    ctx.Response.Headers.Append("X-Frame-Options", "DENY");
    ctx.Response.Headers.Append("X-XSS-Protection", "1; mode=block");
    ctx.Response.Headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");
    await next();
});

// Or use the NWebSec or SecurityHeaders NuGet package for comprehensive headers
```

---

## 28.10 ASP.NET Core Identity — Full User Management

For apps that manage their own users (not delegating to an IdP):

```csharp
// Install: Microsoft.AspNetCore.Identity.EntityFrameworkCore

public class AppUser : IdentityUser
{
    public string? DisplayName { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class AppDbContext : IdentityDbContext<AppUser>
{
    public AppDbContext(DbContextOptions opts) : base(opts) { }
}

// Program.cs
builder.Services
    .AddIdentity<AppUser, IdentityRole>(opts =>
    {
        opts.Password.RequiredLength         = 12;
        opts.Password.RequireDigit           = true;
        opts.Password.RequireUppercase       = true;
        opts.Password.RequireNonAlphanumeric = true;
        opts.Lockout.MaxFailedAccessAttempts = 5;
        opts.Lockout.DefaultLockoutTimeSpan  = TimeSpan.FromMinutes(15);
        opts.User.RequireUniqueEmail         = true;
        opts.SignIn.RequireConfirmedEmail    = true;
    })
    .AddEntityFrameworkStores<AppDbContext>()
    .AddDefaultTokenProviders();

// Usage
public class AccountService
{
    private readonly UserManager<AppUser> _users;
    private readonly SignInManager<AppUser> _signIn;

    public AccountService(UserManager<AppUser> users, SignInManager<AppUser> signIn)
    { _users = users; _signIn = signIn; }

    public async Task<IdentityResult> RegisterAsync(string email, string password)
    {
        var user = new AppUser { UserName = email, Email = email };
        return await _users.CreateAsync(user, password);
    }

    public async Task<SignInResult> LoginAsync(string email, string password, bool rememberMe)
        => await _signIn.PasswordSignInAsync(email, password, rememberMe, lockoutOnFailure: true);

    public async Task<AppUser?> GetByEmailAsync(string email)
        => await _users.FindByEmailAsync(email);
}
```

---

## 28.11 Rate Limiting (NET 7+)

Protect against brute force and DDoS:

```csharp
builder.Services.AddRateLimiter(opts =>
{
    // Fixed window: 100 requests per minute per IP
    opts.AddFixedWindowLimiter("api", o =>
    {
        o.PermitLimit         = 100;
        o.Window              = TimeSpan.FromMinutes(1);
        o.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        o.QueueLimit          = 5;
    });

    // Sliding window (smoother — less bursty)
    opts.AddSlidingWindowLimiter("login", o =>
    {
        o.PermitLimit         = 5;
        o.Window              = TimeSpan.FromMinutes(15);
        o.SegmentsPerWindow   = 3;
        o.QueueLimit          = 0;
    });

    // Per-user (authenticated)
    opts.AddPolicy("PerUser", ctx =>
    {
        var userId = ctx.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "anon";
        return RateLimitPartition.GetFixedWindowLimiter(userId, _ =>
            new FixedWindowRateLimiterOptions
            {
                PermitLimit = 200, Window = TimeSpan.FromMinutes(1)
            });
    });

    // Response when limited
    opts.OnRejected = async (ctx, ct) =>
    {
        ctx.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        await ctx.HttpContext.Response.WriteAsync("Too many requests.", ct);
    };
});

app.UseRateLimiter();

// Apply per endpoint
app.MapPost("/api/auth/login", LoginHandler).RequireRateLimiting("login");
app.MapGet("/api/data", DataHandler).RequireRateLimiting("PerUser");
```

