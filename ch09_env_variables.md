# Chapter 9 — Environment Variables, Configuration & Secrets

> How does a production binary know which database to connect to without
> having that connection string in the source code? How does the same
> compiled artifact behave differently in development, staging, and
> production? This chapter answers both questions through environment
> variables and .NET's layered configuration system — the machinery that
> makes twelve-factor apps and container deployments work.

*Building on:* Ch 1 (how the runtime is started, what the process
environment is), Ch 10 (IOptions pattern, which is the typed consumer
of what this chapter produces)

---

## 9.1 The Problem: Config Must Be Separate From Code

Before modern practices, configuration was either compiled in or loaded
from files that shipped with the binary. Both approaches create serious
problems in deployed systems:

```csharp
// Approach 1 — config in code: cannot change without rebuilding
string dbConn = "Server=prod-db;Password=hunter2;Database=myapp";

// Approach 2 — config file shipped with binary:
// - Secrets end up in source control
// - Different environments need different binaries or different file management
// - Kubernetes cannot inject config without file volume mounts
```

The Twelve-Factor App methodology (https://12factor.net) crystallised the
solution that is now standard for cloud-native applications:

**Factor III: Store config in the environment.** Config is anything that
varies between environments (development, staging, production). Code
is identical across all environments. The environment — the process's
variable space — provides the differences.

This means:
- Zero secrets in source code or committed files
- One binary, any environment — point at different DB by changing one variable
- The operations team can change config without developer involvement
- Secret management is handled by the infrastructure, not the app

---

## 9.2 What Environment Variables Are

An environment variable is a name/value string pair that the operating
system injects into a process when it starts. Every process has its own
copy of its environment, inherited from its parent at launch. A child
process cannot see changes the parent makes after launch, and vice versa.

```
Each process has its own environment map:
  DATABASE_URL = "postgresql://user:pass@prod-db:5432/myapp"
  ASPNETCORE_ENVIRONMENT = "Production"
  PORT = "8080"
  ...

This map is:
  - Set by the OS, container runtime, systemd unit, or shell before launch
  - Readable by the process at any time via the OS API
  - NOT writable back to the parent — each process has its own copy
```

```bash
# Linux / macOS: set for the current shell session
export DATABASE_URL="postgresql://localhost/myapp_dev"

# Set only for one command (does not persist in the shell)
DATABASE_URL="postgresql://localhost/test" dotnet test

# Show all current env vars
env | grep -i database

# Windows PowerShell
$env:DATABASE_URL = "postgresql://localhost/myapp_dev"
[System.Environment]::GetEnvironmentVariable("DATABASE_URL")
```

In .NET, reading an environment variable directly:

```csharp
string? dbUrl = Environment.GetEnvironmentVariable("DATABASE_URL");
// Returns null if the variable is not set — always check
```

But reading raw environment variables directly in your services is not
the .NET way. .NET wraps them in a layered configuration system that is
more powerful and testable.

---

## 9.3 .NET's Configuration System — The Full Stack

.NET's `IConfiguration` is a unified facade over multiple configuration
sources. You configure which sources to include at startup. Sources form
a stack: later sources override earlier ones with the same key.

```
┌─────────────────────────────────────────────────────────┐
│               IConfiguration (the facade)               │
└────────────────────┬────────────────────────────────────┘
                     │ reads from (in priority order, last wins)
        ┌────────────┴───────────────────────────┐
        ▼                                        ▼
1. Default values in code              (lowest priority)
2. appsettings.json
3. appsettings.{Environment}.json      (e.g. appsettings.Production.json)
4. User Secrets                        (Development environment only)
5. Environment variables
6. Command-line arguments              (highest priority — useful for CI overrides)
```

`Host.CreateDefaultBuilder()` (and `WebApplication.CreateBuilder()`)
sets up this entire stack automatically. You only need to configure it
manually in special cases like console apps or worker services without
the Generic Host.

```csharp
// Automatic (recommended): Generic Host wires the full stack
var builder = WebApplication.CreateBuilder(args);
// IConfiguration is already set up with the full stack

// Manual (for console apps or custom scenarios):
var config = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile($"appsettings.{env}.json", optional: true)
    .AddUserSecrets<Program>(optional: true)
    .AddEnvironmentVariables()
    .AddCommandLine(args)
    .Build();
```

---

## 9.4 Reading Configuration

Once configured, you read values through the `IConfiguration` interface.
But reading raw strings is fragile. The preferred approach is the Options
pattern (Chapter 10 §10.2), which binds a section to a strongly-typed class.

```csharp
// Raw reading (for quick checks, not for production service code)
string? host = config["Smtp:Host"];              // : = section separator
int port = config.GetValue<int>("Smtp:Port", 587); // with default

// Bind an entire section to a class
var smtpOpts = config.GetSection("Smtp").Get<SmtpOptions>();

// Via IOptions<T> (preferred in services — see Ch 10)
public class EmailService(IOptions<SmtpOptions> opts)
{
    private readonly SmtpOptions _smtp = opts.Value;
}
```

### Environment Variable Naming

Environment variables use `__` (double underscore) to represent the `:`
hierarchy separator, because `:` is not a valid character in env var
names on Linux. The configuration system translates automatically:

```bash
# These environment variables...
export Smtp__Host=smtp.example.com
export Smtp__Port=587
export Database__ConnectionString="Data Source=/var/data/app.db"

# ...are read as config["Smtp:Host"], config["Smtp:Port"],
# and config["Database:ConnectionString"]
```

---

## 9.5 Environment-Specific Configuration Files

The standard pattern is a base file plus per-environment overrides. Only
values that differ between environments live in the override files. Secrets
never live in any committed file:

```
appsettings.json               ← committed, contains safe defaults
appsettings.Development.json   ← committed, dev-only overrides (verbose logging, local DB)
appsettings.Staging.json       ← committed, staging overrides (no secrets)
appsettings.Production.json    ← committed, production overrides (no secrets)
appsettings.Local.json         ← .gitignored, individual developer overrides
```

```json
// appsettings.json — safe defaults
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "Database": {
    "MaxRetries": 3,
    "CommandTimeoutSeconds": 30
  }
}

// appsettings.Development.json — development overrides
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "MyApp": "Debug"
    }
  },
  "Database": {
    "ConnectionString": "Data Source=dev.db"
  }
}
```

The environment is controlled by the `ASPNETCORE_ENVIRONMENT` (for web
apps) or `DOTNET_ENVIRONMENT` (for all apps) variable:

```bash
# Linux
export ASPNETCORE_ENVIRONMENT=Staging
dotnet run

# Windows
$env:ASPNETCORE_ENVIRONMENT = "Production"
dotnet run

# In launchSettings.json (loaded only by dotnet run, not in production)
{
  "profiles": {
    "http": {
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
```

---

## 9.6 Secrets — Development vs Production

Secrets are values that must never appear in source control: database
passwords, API keys, SMTP credentials, signing keys.

### Development: User Secrets

User Secrets stores secret values in your OS user profile directory,
outside the project directory — they are never accidentally committed.
They are only loaded when `DOTNET_ENVIRONMENT=Development`:

```bash
# Initialise (adds <UserSecretsId> GUID to .csproj)
dotnet user-secrets init

# Set secrets
dotnet user-secrets set "Smtp:Password" "mydevpassword"
dotnet user-secrets set "Database:ConnectionString" "Server=localhost;Password=dev"

# List all secrets in this project
dotnet user-secrets list

# Clear all
dotnet user-secrets clear
```

Stored at `~/.microsoft/usersecrets/{id}/secrets.json` on Linux/macOS.
These are *not* encrypted — they are just outside the repo.

### Production: Environment Variables

In production, secrets come from the environment. This means:
- Docker Compose: `environment:` section in `docker-compose.yml`
- Kubernetes: `Secret` objects mounted as env vars
- systemd: `EnvironmentFile=` pointing to a protected file
- Cloud: AWS Secrets Manager, Azure Key Vault, etc. injected as env vars

```yaml
# Kubernetes Secret
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secrets
stringData:
  Smtp__Password: "realpassword"
  Database__ConnectionString: "Server=prod-db;Password=realpassword;..."
---
# Referenced in Deployment
env:
  - name: Smtp__Password
    valueFrom:
      secretKeyRef:
        name: myapp-secrets
        key: Smtp__Password
```

```ini
# systemd EnvironmentFile — protected chmod 600
[Service]
EnvironmentFile=/etc/myapp/secrets.env
# /etc/myapp/secrets.env contains:
# Database__ConnectionString=Server=prod-db;Password=realpassword
```

### The Golden Rule

```
If it changes between environments → appsettings.{Env}.json
If it is a secret → environment variable (never a committed file)
If it is a development secret → User Secrets
If it needs to be encrypted at rest → ASP.NET Core Data Protection (see Ch 39)
```

---

## 9.7 Docker — Passing Configuration

Docker isolates the container's environment from the host. You must
explicitly pass environment variables into the container:

```bash
# Pass individual variables
docker run -e Smtp__Host=smtp.example.com -e Smtp__Port=587 myapp

# Pass from a file (never commit .env files with secrets)
docker run --env-file .env.prod myapp
```

```yaml
# docker-compose.yml
services:
  api:
    image: myapp:latest
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - Smtp__Host=smtp.example.com
    env_file:
      - secrets.env   # not committed to git
```

---

## 9.8 Nix / `direnv` — The Developer Workflow

On NixOS or any system with Nix+direnv, you can declare the entire
development environment — including environment variables — in a file
that activates automatically when you `cd` into the project directory:

```bash
# .envrc — activates automatically with direnv
use flake .

# Development env vars — loaded only in this directory
export DOTNET_ENVIRONMENT=Development
export Database__ConnectionString="Data Source=dev.db"
# Secrets go in .envrc.local which is .gitignored
```

```bash
# .gitignore
.envrc.local     # developer-specific secrets, never committed
.env             # same
*.db             # SQLite development databases
```

Chapter 22 covers the full Nix development environment setup.

---

## 9.9 Validation at Startup — Fail Fast on Bad Config

The worst time to discover that a configuration value is missing or
malformed is in production at 3am when the first request hits the code
path that reads it. The `ValidateOnStart()` extension makes the
application refuse to start if required config is absent or invalid:

```csharp
// Fails at startup if any required field is missing or invalid
services.AddOptions<DatabaseOptions>()
    .BindConfiguration("Database")
    .Validate(opts =>
    {
        if (string.IsNullOrWhiteSpace(opts.ConnectionString))
            return false;
        if (opts.MaxRetries < 1 || opts.MaxRetries > 10)
            return false;
        return true;
    }, "Database configuration is invalid. Check ConnectionString and MaxRetries (1-10).")
    .ValidateOnStart();
```

This converts a runtime failure into a startup failure — the application
won't deploy successfully if config is wrong, rather than deploying and
failing on first use.

---

## 9.10 Connecting Configuration to the Rest of the Book

- **Ch 10 (DI, Options, Logging)** — `IOptions<T>` is the strongly-typed
  consumer of configuration. This chapter shows where the config values
  come from; Chapter 10 shows how services consume them.
- **Ch 11 (DI Deep Dive)** — dependency injection wires configuration
  into every service. `IConfiguration` is itself registered in the DI
  container and injectable anywhere.
- **Ch 28 (Security)** — JWT signing keys, OAuth client secrets, and
  encryption keys are all secrets that follow the rules in this chapter.
- **Ch 39 (Pet Projects — Configuration)** — end-to-end worked examples
  of every program type (console, CLI, daemon, API) wired up with the
  full configuration stack.
