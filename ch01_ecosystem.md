# Chapter 1 — The .NET Ecosystem

## 1.1 What Is .NET?

.NET is a free, open-source, cross-platform developer platform maintained by Microsoft and the community. It is *not* one thing — it is a family of runtimes, libraries, compilers, and SDKs.

```
┌─────────────────────────────────────────────────────────┐
│                      Your Application                   │
├─────────────────────────────────────────────────────────┤
│          BCL — Base Class Library (mscorlib etc.)       │
├─────────────────────────────────────────────────────────┤
│     ASP.NET Core │ EF Core │ MAUI │ WinForms │ WPF      │
├─────────────────────────────────────────────────────────┤
│           CoreCLR / NativeAOT / Mono runtime            │
├─────────────────────────────────────────────────────────┤
│        OS: Linux │ Windows │ macOS │ Android │ iOS      │
└─────────────────────────────────────────────────────────┘
```

### Key Terms

| Term | Meaning |
|------|---------|
| **CLR** | Common Language Runtime — the JIT-based VM that executes IL |
| **IL / CIL** | Intermediate Language — what the C# compiler produces |
| **BCL** | Base Class Library — `System.*` namespaces |
| **SDK** | Software Development Kit — compiler + BCL + tooling |
| **Runtime** | Just the CLR + BCL, no compiler |
| **TFM** | Target Framework Moniker: `net9.0`, `net9.0-android`, `netstandard2.1` |
| **RID** | Runtime Identifier: `linux-x64`, `win-arm64`, `osx-arm64` |

---

## 1.2 .NET Version Timeline

```
.NET Framework 1.0–4.8.x  ← Windows only, legacy (still supported, not recommended for new projects)
.NET Core 1.0–3.1          ← cross-platform reboot (EOL)
.NET 5                      ← unified, "Core" dropped
.NET 6 LTS                  ← 3 years support, minimal APIs, hot reload
.NET 7                      ← STS, performance leap (PGO)
.NET 8 LTS                  ← 3 years support, Native AOT stable, Blazor SSR/WASM united
.NET 9 STS                  ← current (Nov 2024), Task.WhenEach, SearchValues, more AOT
.NET 10 LTS                 ← arriving Nov 2025 (preview available)
```

**LTS = Long-Term Support (3 years). STS = Standard-Term Support (18 months).**

> **Rider tip:** *Help → About* shows which SDK Rider is using. Set the SDK per-project in *Project Properties → Framework*.

---

## 1.3 Installing the SDK

### Linux (NixOS — recommended approach)

```nix
# flake.nix excerpt
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in pkgs.mkShell {
      packages = [
        pkgs.dotnet-sdk_9   # includes runtime + SDK
        pkgs.omnisharp-roslyn
        pkgs.netcoredbg
      ];
      DOTNET_ROOT = "${pkgs.dotnet-sdk_9}";
    };
  };
}
```

```bash
# activate
direnv allow
dotnet --version   # 9.x.x
```

### Linux (apt / snap)

```bash
# Ubuntu 24.04
sudo apt install dotnet-sdk-9.0

# Or via Microsoft feed:
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt update && sudo apt install dotnet-sdk-9.0
```

### Windows

```powershell
winget install Microsoft.DotNet.SDK.9
```

### macOS

```bash
brew install dotnet
```

### Verify

```bash
dotnet --version          # e.g. 9.0.100
dotnet --list-sdks        # all installed SDKs
dotnet --list-runtimes    # all installed runtimes
```

---

## 1.4 The dotnet CLI — Complete Reference

The `dotnet` CLI is the primary tool for creating, building, running, testing, and publishing .NET applications.

### New Project / Solution

```bash
# List all available templates
dotnet new list

# Common templates
dotnet new console -n MyApp -o ./MyApp
dotnet new classlib -n MyLib -o ./MyLib
dotnet new web -n MyApi
dotnet new webapi -n MyApi --use-controllers   # with controllers
dotnet new minimal-api -n MyApi               # explicit minimal
dotnet new worker -n MyDaemon
dotnet new blazor -n MyBlazor                 # interactive Blazor
dotnet new blazorwasm -n MyBlazorWasm
dotnet new maui -n MyMaui
dotnet new xunit -n MyTests
dotnet new sln -n MySolution

# Install additional templates
dotnet new install "Avalonia.Templates"
dotnet new install "Amazon.Lambda.Templates"
```

### Solution Management

```bash
dotnet sln MySolution.sln add src/MyApp/MyApp.csproj
dotnet sln MySolution.sln add src/MyLib/MyLib.csproj
dotnet sln MySolution.sln add tests/MyTests/MyTests.csproj
dotnet sln MySolution.sln list
dotnet sln MySolution.sln remove src/OldProject/OldProject.csproj
```

### Build & Run

```bash
dotnet build                        # debug build
dotnet build -c Release             # release build
dotnet build -c Release --no-restore
dotnet run                          # build + run (debug)
dotnet run -c Release               # build + run (release)
dotnet run -- --port 8080           # pass args after --
dotnet watch run                    # hot reload
dotnet watch test                   # run tests on save
```

### NuGet / Package Management

```bash
dotnet add package Serilog
dotnet add package Serilog --version 3.1.1
dotnet add package Microsoft.EntityFrameworkCore.Sqlite --prerelease
dotnet remove package Serilog
dotnet list package
dotnet list package --outdated
dotnet list package --vulnerable       # security audit
dotnet restore                         # restore all packages
dotnet nuget locals all --clear        # clear NuGet cache
```

### Test

```bash
dotnet test
dotnet test -c Release
dotnet test --filter "Category=Unit"
dotnet test --filter "FullyQualifiedName~MyNamespace"
dotnet test --logger "trx;LogFileName=results.trx"
dotnet test --collect:"XPlat Code Coverage"
```

### Publish

```bash
# Framework-dependent (requires runtime on target)
dotnet publish -c Release -o ./publish

# Self-contained (bundles runtime)
dotnet publish -c Release -r linux-x64 --self-contained -o ./publish

# Native AOT (compile to native binary)
dotnet publish -c Release -r linux-x64 /p:PublishAot=true -o ./publish

# Single file
dotnet publish -c Release -r linux-x64 --self-contained /p:PublishSingleFile=true

# Trimmed
dotnet publish -c Release -r linux-x64 --self-contained /p:PublishTrimmed=true
```

### Diagnostics

```bash
dotnet-trace collect --process-id <pid>
dotnet-counters monitor --process-id <pid>
dotnet-dump collect --process-id <pid>
dotnet-dump analyze ./core_20240101_120000.dmp
dotnet-gcdump collect --process-id <pid>
```

---

## 1.5 Project File (`.csproj`) Deep Dive

The `.csproj` is an MSBuild XML file. Understanding it is essential.

### Minimal Console App

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>false</AllowUnsafeBlocks>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>
</Project>
```

### Class Library

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <!-- Multi-target for NuGet packages: -->
    <!-- <TargetFrameworks>net9.0;net8.0;netstandard2.1</TargetFrameworks> -->
  </PropertyGroup>
</Project>
```

### Web API / ASP.NET Core

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <InvariantGlobalization>true</InvariantGlobalization> <!-- smaller binary -->
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="9.0.0" />
  </ItemGroup>
</Project>
```

### Full-Featured Production Project

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <!-- Framework & Language -->
    <TargetFramework>net9.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>

    <!-- Warnings as errors in CI -->
    <TreatWarningsAsErrors>$(CI)</TreatWarningsAsErrors>
    <WarningsAsErrors />
    <!-- Suppress specific warnings -->
    <NoWarn>CS1591</NoWarn>   <!-- missing XML doc -->

    <!-- Analyzer strictness -->
    <AnalysisMode>Recommended</AnalysisMode>
    <EnableNETAnalyzers>true</EnableNETAnalyzers>

    <!-- NuGet package metadata (for library projects) -->
    <PackageId>Acme.MyLib</PackageId>
    <Version>1.0.0</Version>
    <Authors>Your Name</Authors>
    <Description>Does something useful</Description>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
    <RepositoryUrl>https://github.com/you/mylib</RepositoryUrl>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>

    <!-- Publish -->
    <PublishReadyToRun>true</PublishReadyToRun>
    <RuntimeIdentifiers>linux-x64;win-x64;osx-arm64</RuntimeIdentifiers>
  </PropertyGroup>

  <!-- Central package versions (if using CPM) -->
  <!-- <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally> -->

  <ItemGroup>
    <PackageReference Include="Serilog" Version="3.1.1" />
    <PackageReference Include="Serilog.Sinks.Console" Version="5.0.1" />
  </ItemGroup>

  <!-- Project reference -->
  <ItemGroup>
    <ProjectReference Include="../MyLib/MyLib.csproj" />
  </ItemGroup>

  <!-- Embed files -->
  <ItemGroup>
    <EmbeddedResource Include="Resources/**/*" />
    <None Include="appsettings*.json" CopyToOutputDirectory="PreserveNewest" />
  </ItemGroup>

  <!-- Conditional: Debug only -->
  <ItemGroup Condition="'$(Configuration)' == 'Debug'">
    <PackageReference Include="Microsoft.Extensions.Logging.Debug" Version="9.0.0" />
  </ItemGroup>
</Project>
```

### Directory.Build.props — Shared Settings

Place `Directory.Build.props` at the solution root to apply settings to **all** projects:

```xml
<!-- Directory.Build.props -->
<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>$(CI)</TreatWarningsAsErrors>
    <AnalysisMode>Recommended</AnalysisMode>
    <Authors>Acme Corp</Authors>
    <Copyright>Copyright © 2025 Acme Corp</Copyright>
  </PropertyGroup>
</Project>
```

### Directory.Packages.props — Central Package Management

```xml
<!-- Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <!-- Define versions centrally; reference without Version in each .csproj -->
    <PackageVersion Include="Serilog" Version="3.1.1" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="9.0.0" />
    <PackageVersion Include="xunit" Version="2.9.0" />
    <PackageVersion Include="NSubstitute" Version="5.1.0" />
  </ItemGroup>
</Project>
```

Then in each `.csproj`:

```xml
<PackageReference Include="Serilog" />  <!-- no Version attribute needed -->
```

---

## 1.6 Global Usings

With `<ImplicitUsings>enable</ImplicitUsings>`, the SDK automatically adds common usings based on project type. You can add your own in a `GlobalUsings.cs` file:

```csharp
// GlobalUsings.cs
global using System.Text.Json;
global using System.Diagnostics;
global using Microsoft.Extensions.Logging;
global using MyApp.Domain;
global using MyApp.Infrastructure;
```

You can also declare them in the `.csproj`:

```xml
<ItemGroup>
  <Using Include="System.Text.Json" />
  <Using Include="MyApp.Domain" />
  <!-- Alias -->
  <Using Include="System.Collections.Generic.List`1" Alias="List" />
</ItemGroup>
```

---

## 1.7 Solution Structure Patterns

### Pattern A — Simple App (small team / single service)

```
MyApp/
├── MyApp.sln
├── Directory.Build.props
├── Directory.Packages.props
├── .gitignore
├── README.md
└── src/
    └── MyApp/
        ├── MyApp.csproj
        ├── Program.cs
        ├── Domain/
        │   ├── Entities/
        │   └── ValueObjects/
        ├── Application/
        │   ├── Commands/
        │   └── Queries/
        ├── Infrastructure/
        │   ├── Persistence/
        │   └── Http/
        └── Presentation/
            └── Endpoints/
```

### Pattern B — Clean Architecture (medium project)

```
Acme.Orders/
├── Acme.Orders.sln
├── Directory.Build.props
├── Directory.Packages.props
├── global.json
├── .editorconfig
├── src/
│   ├── Acme.Orders.Domain/           ← entities, value objects, domain events, no deps
│   │   ├── Acme.Orders.Domain.csproj
│   │   ├── Entities/
│   │   │   └── Order.cs
│   │   ├── ValueObjects/
│   │   │   └── Money.cs
│   │   ├── Events/
│   │   │   └── OrderPlaced.cs
│   │   └── Repositories/
│   │       └── IOrderRepository.cs   ← interfaces defined here
│   │
│   ├── Acme.Orders.Application/      ← use cases, CQRS, no framework deps
│   │   ├── Acme.Orders.Application.csproj
│   │   ├── Commands/
│   │   │   ├── PlaceOrder/
│   │   │   │   ├── PlaceOrderCommand.cs
│   │   │   │   ├── PlaceOrderHandler.cs
│   │   │   │   └── PlaceOrderValidator.cs
│   │   └── Queries/
│   │       └── GetOrder/
│   │           ├── GetOrderQuery.cs
│   │           └── GetOrderHandler.cs
│   │
│   ├── Acme.Orders.Infrastructure/   ← EF Core, HttpClient, file system, etc.
│   │   ├── Acme.Orders.Infrastructure.csproj
│   │   ├── Persistence/
│   │   │   ├── AppDbContext.cs
│   │   │   ├── Migrations/
│   │   │   └── Repositories/
│   │   │       └── OrderRepository.cs
│   │   └── Http/
│   │       └── PaymentGatewayClient.cs
│   │
│   └── Acme.Orders.Api/              ← ASP.NET Core, entry point
│       ├── Acme.Orders.Api.csproj
│       ├── Program.cs
│       └── Endpoints/
│           └── OrderEndpoints.cs
│
└── tests/
    ├── Acme.Orders.Domain.Tests/
    ├── Acme.Orders.Application.Tests/
    └── Acme.Orders.Integration.Tests/
```

### Pattern C — Microservices / Multi-Service Monorepo

```
AcmePlatform/
├── AcmePlatform.sln
├── Directory.Build.props
├── Directory.Packages.props
├── shared/
│   ├── Acme.Shared.Contracts/        ← DTOs, events (shared via NuGet or project ref)
│   └── Acme.Shared.Infrastructure/  ← common infra (auth, logging setup)
├── services/
│   ├── orders/
│   │   ├── src/
│   │   │   ├── Orders.Domain/
│   │   │   ├── Orders.Application/
│   │   │   ├── Orders.Infrastructure/
│   │   │   └── Orders.Api/
│   │   └── tests/
│   ├── inventory/
│   │   └── ...
│   └── notifications/
│       └── ...
├── tools/
│   └── Acme.Cli/                     ← internal tooling
└── docker/
    ├── docker-compose.yml
    ├── orders.Dockerfile
    └── inventory.Dockerfile
```

### Pattern D — MAUI + API (mobile app + backend)

```
AcmeApp/
├── AcmeApp.sln
├── Directory.Build.props
├── src/
│   ├── AcmeApp.Shared/               ← shared models, interfaces (netstandard2.1)
│   ├── AcmeApp.Api/                  ← ASP.NET Core API (net9.0)
│   ├── AcmeApp.Maui/                 ← MAUI shell (net9.0-android;net9.0-ios)
│   └── AcmeApp.Core/                 ← business logic (net9.0)
└── tests/
    └── AcmeApp.Tests/
```

---

## 1.8 `global.json` — Pin the SDK Version

Place `global.json` at the solution root to pin the exact SDK version for reproducible builds:

```json
{
  "sdk": {
    "version": "9.0.100",
    "rollForward": "latestPatch",
    "allowPrerelease": false
  }
}
```

| `rollForward` value | Behavior |
|---------------------|----------|
| `patch` | Use exact or latest patch |
| `latestPatch` | Always use latest patch (recommended) |
| `minor` | Roll forward to latest minor |
| `latestMinor` | Roll to latest minor |
| `major` | Roll forward across major versions |
| `latestMajor` | Use whatever is installed |
| `disable` | Exact version only — fail if missing |

---

## 1.9 `.editorconfig` — Consistent Code Style

```ini
# .editorconfig (at solution root)
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{cs,csx}]
# Naming rules
dotnet_naming_rule.private_fields_should_be_camel_case.symbols = private_fields
dotnet_naming_rule.private_fields_should_be_camel_case.style = camel_case_style
dotnet_naming_rule.private_fields_should_be_camel_case.severity = warning

dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private

dotnet_naming_style.camel_case_style.capitalization = camel_case
dotnet_naming_style.camel_case_style.required_prefix = _

# Prefer var
csharp_style_var_for_built_in_types = true:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = false:suggestion

# Expression bodies
csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = true:suggestion

# Pattern matching
csharp_style_pattern_matching_over_is_with_cast_check = true:warning
csharp_style_pattern_matching_over_as_with_null_check = true:warning

# Null checks
csharp_style_prefer_null_check_over_type_check = true:suggestion
dotnet_style_null_propagation = true:suggestion
dotnet_style_coalesce_expression = true:suggestion

# Imports
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false

[*.{json,yml,yaml}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

> **Rider tip:** Rider reads `.editorconfig` automatically. Use *Code → Reformat Code* (`Ctrl+Alt+L` / `⌘⌥L`) to apply. *Settings → Editor → Code Style → C#* lets you export/import styles and sync with `.editorconfig`.

---

## 1.10 NuGet Configuration

### `nuget.config`

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    <!-- Private feed (Azure Artifacts, GitHub Packages, etc.) -->
    <add key="acme-feed" value="https://pkgs.dev.azure.com/acme/_packaging/acme/nuget/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <!-- Only allow specific packages from private feed -->
    <packageSource key="acme-feed">
      <package pattern="Acme.*" />
    </packageSource>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
```

---

## 1.11 Runtimes & AOT Modes

### Execution Modes

```
Source (.cs)
    │
    ▼
Roslyn compiler
    │
    ▼
IL (intermediate language)
    │
    ├── JIT (default)
    │     CoreCLR compiles IL → native at runtime
    │     Tiered compilation: interpreted → Quick JIT → Optimized JIT
    │
    └── Native AOT
          IL → native binary at publish time (no CLR needed)
          Restrictions: no dynamic code gen, limited reflection
```

### Tiered Compilation

```csharp
// Hot path gets Optimized JIT automatically after enough calls.
// You can hint with RuntimeHelpers:
using System.Runtime.CompilerServices;

[MethodImpl(MethodImplOptions.AggressiveInlining)]
private static int Add(int a, int b) => a + b;

[MethodImpl(MethodImplOptions.AggressiveOptimization)]
private void HotLoop()
{
    for (int i = 0; i < 10_000_000; i++) { /* ... */ }
}
```

### ReadyToRun (R2R)

Ahead-of-time JIT-compiled IL bundled into the assembly. Faster startup, slightly larger binary.

```xml
<PublishReadyToRun>true</PublishReadyToRun>
```

---

## 1.12 IDE Setup

### Rider (JetBrains) — Recommended

- Open solution: `File → Open → select .sln`
- SDK detection: automatic from `global.json` or PATH
- NuGet restore: automatic on open
- **Essential first steps:**
  - *Settings → Editor → Code Style → C#*: import `.editorconfig`
  - *Settings → Tools → External Tools*: add `dotnet watch`
  - *Settings → Plugins*: install *GitToolBox*, *IdeaVim* (optional)

### Visual Studio 2022

- Install workloads: `.NET desktop development`, `ASP.NET and web development`, `Mobile development with .NET`
- Extensions: *ReSharper* (JetBrains), *GitHub Copilot*, *OzCode* (debugging)
- **Essential settings:**
  - *Tools → Options → Text Editor → C# → Advanced*: enable *Enable full solution analysis*
  - *Tools → Options → Projects and Solutions → Build and Run*: set *On Run, when projects are out of date* to *Always build*

### VS Code

```bash
code --install-extension ms-dotnettools.csdevkit     # C# DevKit (official)
code --install-extension ms-dotnettools.csharp       # C# language support
code --install-extension ms-dotnettools.vscode-dotnet-runtime
```

`.vscode/launch.json`:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": ".NET Core Launch (console)",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "build",
      "program": "${workspaceFolder}/bin/Debug/net9.0/MyApp.dll",
      "args": [],
      "cwd": "${workspaceFolder}",
      "console": "internalConsole",
      "stopAtEntry": false
    }
  ]
}
```


> **Rider tip:** Use *File → New Solution* for full project scaffolding with templates. The *NuGet* tool window (`Tools → NuGet → Manage NuGet Packages`) manages packages with version comparison. `global.json` and `Directory.Build.props` are auto-detected and respected.

> **VS tip:** *File → New → Project* opens the template picker. *Tools → NuGet Package Manager → Manage NuGet Packages for Solution* manages packages across all projects at once. Set *Tools → Options → Projects → SDK-style projects → Default SDK* to control which .NET version new projects target.
