# Chapter 9 — Environment Variables

## 9.1 Why They Exist

Environment variables solved a specific historical problem: how do you configure
an application differently across development, staging, and production without
changing the code or shipping different binaries?

Before environment variables, teams did things like:

```csharp
// ❌ Old way — config baked into code, different branch per environment
#if DEBUG
    var dbConn = "Server=localhost;Database=myapp_dev;";
#else
    var dbConn = "Server=prod-db;Database=myapp;Password=secret123;";
#endif
```

Problems: secrets in source code, can't change config without recompiling,
different environments need different builds.

Environment variables fix all of this:

```
Code is identical across all environments.
Config and secrets live outside the code.
Operations team can change config without developers or redeployment.
Secrets never touch the git repository.
```

This is Principle 3 of the [12-Factor App](https://12factor.net/config) —
the foundational document for modern cloud-native applications.

---

## 9.2 What Environment Variables Are

```
Name=Value pairs injected into a process by the operating system at startup.

Every process inherits the env vars of its parent process.
Child processes see a copy — changes in the child don't affect the parent.

Linux/macOS:  export DATABASE_URL="postgresql://..."
Windows:      $env:DATABASE_URL = "postgresql://..."
Docker:       ENV DATABASE_URL postgresql://...
Kubernetes:   env: - name: DATABASE_URL value: postgresql://...
```

### Reading in C#

```csharp
// Direct read
string? dbUrl  = Environment.GetEnvironmentVariable("DATABASE_URL");
string? port   = Environment.GetEnvironmentVariable("PORT");
string  env    = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? "Production";

// With default
int port2 = int.TryParse(Environment.GetEnvironmentVariable("PORT"), out var p) ? p : 8080;
```

---

## 9.3 .NET's Configuration System — The Right Way

You should almost never read env vars directly in application code.
.NET's configuration system reads them and makes them available through
the typed `IOptions<T>` pattern.

### How It Works

```
Environment variables
appsettings.json              → IConfiguration → IOptions<T> → your class
appsettings.Production.json
Command-line args
```

All sources are merged. Later sources override earlier ones.
**Environment variables override appsettings.json** by default.

### Naming Convention — Double Underscore

.NET maps the `__` separator to `:` (section separator in config):

```bash
# These env vars:
export ConnectionStrings__Default="Server=prod-db;..."
export Smtp__Host="smtp.sendgrid.net"
export Smtp__Port="587"
export App__Features__EnableBeta="true"

# Map to this appsettings.json structure:
{
  "ConnectionStrings": { "Default": "Server=prod-db;..." },
  "Smtp": { "Host": "smtp.sendgrid.net", "Port": 587 },
  "App": { "Features": { "EnableBeta": true } }
}
```

On Windows use `:` directly — `__` is also supported for cross-platform scripts.

---

## 9.4 Reading Config — The Full Stack

### Step 1 — Define typed options

```csharp
// Config/DatabaseOptions.cs
public class DatabaseOptions
{
    public const string Section = "Database";

    [Required]
    public string ConnectionString { get; set; } = "";

    [Range(1, 500)]
    public int MaxPoolSize { get; set; } = 50;

    public bool EnableSensitiveLogging { get; set; } = false;
}

// Config/SmtpOptions.cs
public class SmtpOptions
{
    public const string Section = "Smtp";

    [Required] public string Host     { get; set; } = "";
    [Range(1, 65535)] public int Port { get; set; } = 587;
    [Required] public string Username { get; set; } = "";
    [Required] public string Password { get; set; } = "";
}
```

### Step 2 — Register with validation

```csharp
// Program.cs
builder.Services
    .AddOptions<DatabaseOptions>()
    .BindConfiguration(DatabaseOptions.Section)
    .ValidateDataAnnotations()
    .ValidateOnStart();  // fail at startup if required config is missing

builder.Services
    .AddOptions<SmtpOptions>()
    .BindConfiguration(SmtpOptions.Section)
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

### Step 3 — Inject and use

```csharp
public class EmailService
{
    private readonly SmtpOptions _smtp;
    public EmailService(IOptions<SmtpOptions> opts) => _smtp = opts.Value;

    public async Task SendAsync(string to, string subject)
    {
        // _smtp.Host, _smtp.Port, _smtp.Password are populated from wherever
        // the config came from: appsettings, env var, or secret manager
    }
}
```

### Step 4 — Provide values per environment

```bash
# Development: use appsettings.Development.json or .env.local (via direnv)
# Staging/Production: set real env vars in the deployment environment

export Database__ConnectionString="Server=prod-db;Database=myapp;User=app;Password=s3cr3t"
export Smtp__Host="smtp.sendgrid.net"
export Smtp__Password="SG.xxxxxxxxxxxx"
```

The application code is identical across all environments. Only the values differ.

---

## 9.5 Environment Files — Development Workflow

### `.env.local` with direnv (NixOS / Linux / macOS)

```bash
# .envrc (committed)
use flake
dotenv_if_exists .env.local

# .env.local (git-ignored — never commit this)
Database__ConnectionString=Server=localhost;Database=myapp_dev;User=dev;Password=devpass
Smtp__Host=localhost
Smtp__Port=1025
JWT__Secret=dev-secret-at-least-32-chars-long!!
Stripe__SecretKey=sk_test_xxxxxxxxxxxx
```

```bash
# .gitignore — always ignore these
.env
.env.local
.env.*.local
secrets.json
```

### `dotnet user-secrets` (Windows / macOS)

```bash
# Initialize (once per project)
dotnet user-secrets init

# Set secrets (stored outside the repo)
dotnet user-secrets set "Database:ConnectionString" "Server=localhost;..."
dotnet user-secrets set "Smtp:Password" "devpassword"
dotnet user-secrets set "JWT:Secret" "dev-secret-32-chars!!"

# List
dotnet user-secrets list

# Stored at:
# Linux/macOS: ~/.microsoft/usersecrets/{id}/secrets.json
# Windows:     %APPDATA%\Microsoft\UserSecrets\{id}\secrets.json
```

User secrets are automatically loaded in the `Development` environment.
They override `appsettings.json` values with the same keys.

---

## 9.6 Docker — Passing Environment Variables

```dockerfile
# Dockerfile — never put secrets here, only defaults
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY publish/ .

# Safe defaults only — no secrets
ENV DOTNET_ENVIRONMENT=Production
ENV App__Port=8080

EXPOSE 8080
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

```yaml
# docker-compose.yml — for local dev with real services
services:
  api:
    build: .
    environment:
      # Inline values for local dev (not production secrets)
      - DOTNET_ENVIRONMENT=Development
      - Database__ConnectionString=Server=db;Database=myapp;User=dev;Password=devpass
      - Smtp__Host=mailhog
      - Smtp__Port=1025
    env_file:
      - .env.local     # load from file for longer configs
    depends_on: [db, mailhog]

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: devpass

  mailhog:
    image: mailhog/mailhog   # local SMTP server for dev
    ports: ["8025:8025"]     # web UI to see sent emails
```

```bash
# Production: pass secrets at runtime, never in image
docker run \
  -e "Database__ConnectionString=Server=prod-db;Password=realpassword" \
  -e "Smtp__Password=SG.realkey" \
  myapp:latest
```

---

## 9.7 Kubernetes — Secrets and ConfigMaps

```yaml
# k8s/configmap.yaml — non-sensitive config
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
data:
  DOTNET_ENVIRONMENT: "Production"
  Smtp__Host: "smtp.sendgrid.net"
  Smtp__Port: "587"
  App__Features__EnableBeta: "false"

---
# k8s/secret.yaml — sensitive values (base64 encoded)
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secrets
type: Opaque
stringData:                              # stringData: plain text, k8s encodes it
  Database__ConnectionString: "Server=prod-db;Password=realpassword"
  Smtp__Password: "SG.realkey"
  JWT__Secret: "production-secret-32chars"

---
# k8s/deployment.yaml — reference both
spec:
  containers:
    - name: myapp
      envFrom:
        - configMapRef:
            name: myapp-config       # all keys from ConfigMap
        - secretRef:
            name: myapp-secrets      # all keys from Secret
```

---

## 9.8 The DOTNET_ENVIRONMENT Variable

This single variable changes which `appsettings.{Environment}.json` is loaded
and enables/disables framework features:

```bash
# Standard values (case-sensitive)
DOTNET_ENVIRONMENT=Development   # loads appsettings.Development.json, enables dev features
DOTNET_ENVIRONMENT=Staging       # loads appsettings.Staging.json
DOTNET_ENVIRONMENT=Production    # loads appsettings.Production.json (default if not set)

# ASPNETCORE_ENVIRONMENT is the older equivalent for ASP.NET Core apps
# Both work; DOTNET_ENVIRONMENT is preferred for .NET 6+
```

```csharp
// Check environment in code
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseDeveloperExceptionPage();
}

if (app.Environment.IsProduction())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}

// Custom environment check
if (app.Environment.IsEnvironment("Staging"))
{
    // staging-specific setup
}
```

---

## 9.9 Nix / direnv — The Full Workflow

```nix
# flake.nix — dev shell with env var support
devShells.default = pkgs.mkShell {
    packages = [ pkgs.dotnet-sdk_9 ];

    # Safe defaults for dev — no secrets here
    DOTNET_ENVIRONMENT         = "Development";
    DOTNET_CLI_TELEMETRY_OPTOUT = "1";
    DOTNET_NOLOGO              = "1";

    shellHook = ''
        echo "Dev environment ready"
        echo "DOTNET_ENVIRONMENT=$DOTNET_ENVIRONMENT"
    '';
};
```

```bash
# .envrc — load flake + secrets
use flake
dotenv_if_exists .env.local   # loads .env.local if it exists, silently skips if not

# .env.local — git-ignored secrets for local dev
Database__ConnectionString=Server=localhost;Database=myapp_dev;User=postgres;Password=postgres
Smtp__Password=devpassword
JWT__Secret=dev-secret-minimum-32-characters!!
Stripe__SecretKey=sk_test_xxxxxxxx
```

```bash
direnv allow    # trust the .envrc
cd .            # re-enter to apply

dotnet run      # all env vars are set, app reads them through IOptions
```

---

## 9.10 Security Rules

```
NEVER commit these to git:
  .env.local
  appsettings.*.local.json
  Any file with Password=, Secret=, Key=, Token= in it

NEVER put secrets in:
  Dockerfile (baked into the image layer permanently)
  docker-compose.yml if it's committed
  CI/CD pipeline definition files as plain text

DO use:
  dotnet user-secrets       (local development)
  .env.local + direnv       (local development, NixOS)
  Docker secrets            (Docker Swarm)
  Kubernetes Secrets        (k8s)
  Azure Key Vault           (Azure)
  AWS Secrets Manager       (AWS)
  HashiCorp Vault           (any cloud)
  GitHub/GitLab CI Secrets  (CI pipelines)
```

### Audit Script — Check for Accidentally Committed Secrets

```bash
#!/usr/bin/env bash
# check-secrets.sh — run before every commit or in CI
set -euo pipefail

PATTERNS=(
    "Password\s*="
    "Secret\s*="
    "ApiKey\s*="
    "ConnectionString.*Password"
    "sk_live_"
    "-----BEGIN.*PRIVATE KEY"
)

FOUND=0
for pattern in "${PATTERNS[@]}"; do
    if git diff --cached --name-only | xargs grep -rlE "$pattern" 2>/dev/null; then
        echo "⚠️  Possible secret matching: $pattern"
        FOUND=$((FOUND+1))
    fi
done

[ $FOUND -eq 0 ] || { echo "❌ Possible secrets detected in staged files"; exit 1; }
echo "✅ No secrets detected"
```

---

## 9.11 Validation at Startup — Never Fail in Production

Always validate required config at startup, not on first use:

```csharp
// ValidateOnStart() means if DATABASE__CONNECTIONSTRING is missing,
// the app refuses to start with a clear error message:
// "DataAnnotation validation failed for members: 'ConnectionString'
//  with the error: 'The ConnectionString field is required.'"
// instead of a NullReferenceException three hours into a production incident.

builder.Services
    .AddOptions<DatabaseOptions>()
    .BindConfiguration("Database")
    .ValidateDataAnnotations()
    .ValidateOnStart();   // ← this is the critical line
```

Pair with a startup health check that verifies the database is actually reachable:

```csharp
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>("database");

app.MapHealthChecks("/healthz/startup", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("startup")
});
```

This way the load balancer or orchestrator knows the app is truly ready
before sending traffic to it.

