# Chapter 1 — The .NET Ecosystem

> Before writing a single line of C#, you need a map. This chapter
> explains what .NET actually is, how its parts relate, and how to
> navigate the toolchain with confidence. Everything in later chapters
> runs on top of what is described here. Understanding this stack
> prevents a class of confusion that trips up developers for years.

---

## 1.1 What Is .NET?

Most developers first encounter .NET as "the thing that runs C#". That
framing is too narrow and leads to confusion when you hit terms like CLR,
runtime, SDK, BCL, or TFM with no mental model to place them in.

.NET is a *platform* — a stack of three distinct layers that together
take your source code and turn it into a running process on any supported
operating system:

```
┌──────────────────────────────────────────────────────────────┐
│                      Your Application                        │
│   Console │ Web API │ Desktop │ Mobile │ Embedded │ WASM     │
├──────────────────────────────────────────────────────────────┤
│   Application Frameworks — the wheel you do not reinvent     │
│   ASP.NET Core │ EF Core │ MAUI │ WinForms │ WPF │ Blazor   │
├──────────────────────────────────────────────────────────────┤
│   BCL — Base Class Library                                   │
│   System.* namespaces: collections, I/O, networking,         │
│   threading, reflection, JSON, cryptography, dates, text…    │
├──────────────────────────────────────────────────────────────┤
│   Runtime — CoreCLR / NativeAOT / Mono                       │
│   JIT compiler, garbage collector, thread scheduler,          │
│   exception handling, type system, native interop            │
├──────────────────────────────────────────────────────────────┤
│   OS: Linux │ Windows │ macOS │ Android │ iOS │ WASM         │
└──────────────────────────────────────────────────────────────┘
```

**Layer 1 — The Runtime** is the execution engine. The C# compiler does
*not* produce machine code directly. It produces IL (Intermediate
Language) — a CPU-independent instruction set that is the same whether
you compile on x64, ARM, or a Mac. The runtime's JIT (just-in-time)
compiler translates IL to native machine code the first time each method
is called. The same IL binary therefore runs on any supported platform
without recompilation. This is how a `dotnet publish` on Linux can produce
a binary that runs on macOS ARM. Beyond execution, the runtime owns the
garbage collector that manages memory for you (Chapter 26), the type
system that enforces types at runtime, and the interop bridges that allow
calling native OS code.

**Layer 2 — The BCL** (Base Class Library) is the standard library that
ships with every .NET installation. It provides the building blocks every
program needs regardless of domain: `List<T>`, `Dictionary<K,V>`,
`Stream`, `HttpClient`, `Task`, `JsonSerializer`, `Regex`, `File`,
`Console`. The BCL is your first vocabulary as a C# developer. You will
use it in every chapter of this book, every project you write.

**Layer 3 — Application Frameworks** are optional and domain-specific.
ASP.NET Core is for HTTP servers. EF Core is for relational databases.
MAUI is for mobile and desktop. These are not part of the runtime — they
are libraries built on top of the BCL. You choose which ones to include
based on what your application does.

This three-layer view matters because it tells you where blame lies when
something goes wrong. A slow query is an EF Core (layer 3) or SQL issue.
A memory leak is a runtime (layer 1) concern. A missing method is a BCL
(layer 2) question. A startup crash is often a runtime misconfiguration.

### The Vocabulary You Will See Everywhere

| Term | What it actually means |
|------|------------------------|
| **CLR** | Common Language Runtime — the JIT-based VM that executes IL |
| **IL / CIL** | Intermediate Language — the portable bytecode the C# compiler produces |
| **JIT** | Just-In-Time compiler — translates IL to native machine code at runtime |
| **GC** | Garbage Collector — automatic memory management (covered in depth in Ch 26) |
| **BCL** | Base Class Library — `System.*` namespaces, available everywhere |
| **SDK** | Software Development Kit — the `dotnet` compiler, BCL, and CLI tooling |
| **Runtime** | Just the CLR + BCL, without the compiler — what production servers need |
| **TFM** | Target Framework Moniker: `net9.0`, `net9.0-android`, `netstandard2.1` |
| **RID** | Runtime Identifier: `linux-x64`, `win-arm64`, `osx-arm64` |
| **NuGet** | The package manager for .NET — like npm for Node or cargo for Rust |

The distinction between SDK and Runtime matters in deployment: your build
machine needs the full SDK; your production server only needs the runtime,
which is smaller and carries a smaller attack surface.

---

## 1.2 The Version History — Why There Are So Many Names

If you have searched for a .NET error and found contradictory answers
from 2011, 2016, and 2022, this section explains why. The history is
messier than it should be. The current situation is clean.

```
.NET Framework 1.0–4.8.x  (2002–present)
│  Windows-only. Ships as part of Windows. Will never be discontinued
│  because too much enterprise software depends on it. Not recommended
│  for new projects — it will receive security fixes but no new features.
│  When you see "for .NET Framework" in a StackOverflow answer, most of
│  it does not apply to modern .NET.
│
.NET Core 1.0–3.1         (2016–2019, now end-of-life)
│  The cross-platform reboot. "Core" indicated a clean break from the
│  Windows-only framework. Architected to run on Linux and macOS.
│  Performance-focused. All versions now end-of-life.
│
.NET 5                    (2020)
│  Unified: "Core" dropped from the name. One .NET to rule them all.
│  The version jump from 4.x to 5 was intentional — avoids confusion
│  with .NET Framework 4.8.
│
.NET 6 LTS                (2021, supported to May 2024)
│  Minimal APIs for ASP.NET Core. Hot Reload in development. Blazor
│  unified across server and client.
│
.NET 7 STS                (2022, now end-of-life)
│  Major performance leap via PGO (Profile-Guided Optimization). The
│  JIT learned to optimise based on observed runtime behavior.
│
.NET 8 LTS                (2023, supported to Nov 2026)
│  Native AOT reaches production stability. Primary Constructors in C# 12.
│  Blazor SSR + WebAssembly unified. System.Text.Json improvements.
│  Most stable choice for production systems today.
│
.NET 9 STS                (2024, supported to May 2026)
│  Current release. Task.WhenEach, SearchValues, LINQ improvements,
│  HybridCache. Recommended for new projects where long-term support
│  is not the primary concern.
│
.NET 10 LTS               (arriving Nov 2025, in preview at time of writing)
   Three-year support lifecycle. Will be the next recommended LTS.
```

**LTS = Long-Term Support (3 years), even-numbered releases.**
**STS = Standard-Term Support (18 months), odd-numbered releases.**

For new projects: use the latest LTS unless you need a feature specific
to the current STS. Both LTS and STS receive security updates for their
entire support lifetime.

The term ".NET Standard" (versions 1.0 through 2.1) appears in older
library code. It was a compatibility contract that let a single library
target both .NET Framework and .NET Core. It is largely obsolete now.
New libraries target `net8.0` or `net9.0` directly, and use multi-
targeting (`<TargetFrameworks>net9.0;net48</TargetFrameworks>`) for the
rare case where Framework compatibility is still needed.

---

## 1.3 Installing the SDK

The SDK is the `dotnet` command-line tool. It creates projects, builds,
runs, tests, publishes, manages packages and tools, formats code, and
generates code (EF migrations, OpenAPI clients). There is one binary,
it is cross-platform, and it does everything.

### Linux — NixOS (Recommended for Reproducibility)

Nix pins the exact SDK version in a `flake.nix` file so every developer
on the project gets identical tools regardless of what is installed
globally on their machine. The environment activates per-directory via
`direnv`. Nothing is installed globally — the environment disappears
when you leave the directory. Chapter 22 covers Nix in depth.

```nix
# flake.nix — minimal dev shell
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in pkgs.mkShell {
      packages = [
        pkgs.dotnet-sdk_9       # SDK 9 — includes the runtime, CLI, and BCL
        pkgs.omnisharp-roslyn   # language server for editors
        pkgs.netcoredbg         # debugger
        pkgs.dotnet-ef          # EF Core CLI tool
      ];
      DOTNET_ROOT = "${pkgs.dotnet-sdk_9}";
    };
  };
}
```

```bash
direnv allow      # activates the shell; dotnet is now in PATH
dotnet --version  # confirms the right version
```

### Linux — Manual Install

```bash
# Official Microsoft install script — installs to ~/.dotnet
curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0

# Add to ~/.bashrc or ~/.zshrc
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
```

### Windows

```powershell
winget install Microsoft.DotNet.SDK.9
# Or download from https://dotnet.microsoft.com/download
```

### macOS

```bash
brew install dotnet@9
# Or the official .pkg from https://dotnet.microsoft.com/download
```

### Verify

```bash
dotnet --version          # e.g. 9.0.101
dotnet --list-sdks        # all installed SDKs
dotnet --list-runtimes    # all installed runtimes
```

---

## 1.4 The `dotnet` CLI — Complete Reference

The CLI is your primary interface with the entire .NET ecosystem. Rider
and Visual Studio call it under the hood for every build, test, and
publish operation. Understanding it gives you full visibility into what
the IDE is doing and lets you automate anything in CI.

### Creating Projects

Templates are the starting point. Each template produces a project with
the correct `.csproj`, `Program.cs`, and dependencies for its purpose.

```bash
dotnet new console    -n MyApp           # console application
dotnet new webapi     -n MyApi           # ASP.NET Core Web API
dotnet new classlib   -n MyLib           # reusable class library
dotnet new worker     -n MyWorker        # background service
dotnet new blazorwasm -n MyBlazor        # Blazor WebAssembly
dotnet new xunit      -n MyApp.Tests     # xUnit test project

# See all templates
dotnet new list

# Create, navigate, run — the three-command start
dotnet new console -n Hello && cd Hello && dotnet run
```

### Building

Building compiles C# source to IL and resolves NuGet packages. You
almost never need to think about this separately from running, but
understanding the difference between Debug and Release builds matters:

```bash
dotnet build                     # Debug: no optimisations, full debug info
dotnet build -c Release          # Release: JIT and compiler optimisations applied
                                 # Benchmarks and production must use Release.
dotnet build --no-restore        # skip NuGet restore if already done
```

### Running and Testing

```bash
dotnet run                           # build + run the project in current dir
dotnet run --project src/MyApp       # specify which project
dotnet run -- --port 8080            # -- separates dotnet args from program args

dotnet test                          # run all test projects in the solution
dotnet test -c Release --no-build    # use already-built Release output
dotnet test --filter "Category=Unit" # run tests matching a filter

dotnet watch run                     # rebuild and restart on any file change
dotnet watch test                    # rerun tests on file change
```

### Managing NuGet Packages

```bash
dotnet add package Serilog                    # add latest stable
dotnet add package Serilog --version 3.1.1   # pin a version
dotnet remove package Serilog

dotnet list package                  # what is in this project
dotnet list package --outdated       # which packages have newer versions
dotnet list package --vulnerable     # which have known CVEs
```

### Publishing for Deployment

Publishing prepares a release build for deployment. It is distinct from
building: it resolves all dependencies, applies release-mode optimisations,
and writes a deployable directory.

```bash
# Framework-dependent: smallest output, but requires runtime on target machine
dotnet publish -c Release -r linux-x64

# Self-contained: includes the runtime — works on machines with no .NET installed
dotnet publish -c Release -r linux-x64 --self-contained

# Native AOT: compiles directly to a native binary — no JIT, no startup overhead
# Trade-off: some dynamic features (reflection-heavy code) need adaption
dotnet publish -c Release -r linux-x64 /p:PublishAot=true

# Single-file: everything bundled into one executable
dotnet publish -c Release -r linux-x64 /p:PublishSingleFile=true --self-contained
```

Chapter 21 covers Native AOT in depth including what you need to change
in your code to make it AOT-compatible.

---

## 1.5 The Project File (`.csproj`) — Demystified

Every .NET project is described by an XML file with the `.csproj`
extension. MSBuild (the build engine) reads this file and translates it
into a sequence of compilation steps. Understanding the most important
properties removes all the "magic" from IDE project setup.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <!--
    Sdk="Microsoft.NET.Sdk" imports a huge set of default build targets.
    For web projects: Sdk="Microsoft.NET.Sdk.Web"
    For workers:      Sdk="Microsoft.NET.Sdk.Worker"
    Each Sdk variant imports different defaults and sets different properties.
  -->

  <PropertyGroup>
    <!--
      OutputType determines the kind of binary produced.
      Exe     = runnable program with an entry point (console app, daemon)
      Library = a .dll with no entry point (shared library)
      WinExe  = a Windows GUI app; no console window appears on launch
    -->
    <OutputType>Exe</OutputType>

    <!--
      TargetFramework selects which BCL and runtime you compile against.
      This affects which APIs are available and which platform you run on.

      net9.0          = .NET 9 for all platforms (recommended default)
      net9.0-windows  = .NET 9 + Windows-specific APIs (WinForms, WPF, registry)
      net9.0-android  = .NET 9 + Android APIs (for MAUI Android)
      net9.0-ios      = .NET 9 + iOS APIs (for MAUI iOS)
      netstandard2.1  = maximum compatibility with older frameworks (legacy only)

      For multi-platform targets, use TargetFrameworks (plural):
      <TargetFrameworks>net9.0;net8.0</TargetFrameworks>
    -->
    <TargetFramework>net9.0</TargetFramework>

    <!--
      ImplicitUsings adds a set of global using directives automatically
      based on the project type. For console apps this includes:
      System, System.Collections.Generic, System.IO, System.Linq,
      System.Net.Http, System.Threading, System.Threading.Tasks, and more.
      This eliminates 10+ boilerplate using lines from every file.
    -->
    <ImplicitUsings>enable</ImplicitUsings>

    <!--
      Nullable enables Nullable Reference Types (NRT), introduced in C# 8.
      With this enabled, the compiler tracks whether a reference type can
      hold null, and warns if you dereference a possibly-null value.
      This eliminates an entire class of NullReferenceException bugs at
      compile time rather than at runtime at 3am.
      Chapter 2 §2.5 explains NRT in full.
    -->
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <!--
      PackageReference declares a NuGet dependency.
      The Version attribute pins the exact version.
      dotnet restore downloads it from nuget.org into a local cache.

      In a solution using Central Package Management (Directory.Packages.props),
      the Version attribute is omitted here and specified centrally.
    -->
    <PackageReference Include="Serilog"               Version="3.1.1" />
    <PackageReference Include="Serilog.Sinks.Console" Version="5.0.1" />
  </ItemGroup>

  <ItemGroup>
    <!--
      ProjectReference declares a dependency on another project in the solution.
      The build system ensures MyApp.Core is compiled before MyApp.Web.
      No version needed — it always uses the current source.
    -->
    <ProjectReference Include="..\MyApp.Core\MyApp.Core.csproj" />
  </ItemGroup>

</Project>
```

---

## 1.6 Solution-Level Configuration — `global.json` and `Directory.Build.props`

### `global.json` — Pinning the SDK Version

Without this file, `dotnet` uses the most recent SDK installed on the
machine. This creates "works on my machine" problems when teammates have
different SDK versions. The fix is a `global.json` at the solution root:

```json
{
  "sdk": {
    "version": "9.0.101",
    "rollForward": "latestPatch"
    // rollForward options:
    // "patch"        → only exact patch; fails if not installed
    // "latestPatch"  → newest patch of same major.minor (recommended)
    // "minor"        → also accepts newer minor versions
    // "major"        → accepts any newer version
    // "disable"      → fails if exact version not present
  }
}
```

### `Directory.Build.props` — Properties Shared Across All Projects

MSBuild automatically imports `Directory.Build.props` from the solution
root (or any parent directory) into every project. This lets you set
`<Nullable>`, `<LangVersion>`, analysis configuration, and other
shared settings exactly once rather than in every `.csproj`:

```xml
<!-- Directory.Build.props — solution root -->
<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <!-- In CI, all warnings become errors. Locally they are suggestions. -->
    <TreatWarningsAsErrors Condition="'$(CI)' == 'true'">true</TreatWarningsAsErrors>
    <!-- Enable the full Roslyn analyzer suite -->
    <AnalysisMode>AllEnabledByDefault</AnalysisMode>
    <!-- Enforce .editorconfig code style rules at build time -->
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  </PropertyGroup>
</Project>
```

### `Directory.Packages.props` — Central Package Version Management

When a solution has many projects that share NuGet packages, version
conflicts become a real maintenance problem. Central Package Management
(CPM) puts every version in one file:

```xml
<!-- Directory.Packages.props — solution root -->
<Project>
  <PropertyGroup>
    <!-- Enables CPM. PackageReferences in .csproj files must omit Version. -->
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Serilog"                           Version="3.1.1" />
    <PackageVersion Include="Serilog.Sinks.Console"             Version="5.0.1" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore"     Version="9.0.0" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Sqlite" Version="9.0.0" />
  </ItemGroup>
</Project>
```

```xml
<!-- Any .csproj in the solution -->
<PackageReference Include="Serilog" />   <!-- no Version; it comes from the props file -->
```

---

## 1.7 Solution Structure — Organising Your Projects

A solution (`.sln` file) is a container for related projects. The
structure of your solution should make the dependency direction visible
in the file system. Chapter 18 covers architectural patterns in depth;
here is a practical starting point for any new project:

```
MyApp/
├── MyApp.sln
├── global.json                    ← pins SDK version
├── Directory.Build.props          ← shared properties for all projects
├── Directory.Packages.props       ← central NuGet version management
├── .editorconfig                  ← strict code style rules
│
├── src/
│   ├── MyApp.Core/                ← domain logic, zero external dependencies
│   │   └── MyApp.Core.csproj
│   ├── MyApp.Infrastructure/      ← database, HTTP, file system
│   │   └── MyApp.Infrastructure.csproj
│   └── MyApp.Web/                 ← ASP.NET Core entry point, DI wiring
│       └── MyApp.Web.csproj
│
└── tests/
    ├── MyApp.Core.Tests/          ← pure unit tests, no infrastructure
    └── MyApp.Integration.Tests/   ← real database, real HTTP
```

```bash
# Bootstrap the entire structure
dotnet new sln -n MyApp
dotnet new classlib -n MyApp.Core          -o src/MyApp.Core
dotnet new classlib -n MyApp.Infrastructure -o src/MyApp.Infrastructure
dotnet new webapi   -n MyApp.Web           -o src/MyApp.Web
dotnet new xunit    -n MyApp.Core.Tests    -o tests/MyApp.Core.Tests

dotnet sln add src/**/*.csproj tests/**/*.csproj

# Wire up dependencies
dotnet add src/MyApp.Infrastructure reference src/MyApp.Core
dotnet add src/MyApp.Web            reference src/MyApp.Core
dotnet add src/MyApp.Web            reference src/MyApp.Infrastructure
dotnet add tests/MyApp.Core.Tests   reference src/MyApp.Core
```

---

## 1.8 The Three Execution Models: JIT, R2R, and Native AOT

Understanding how your code executes matters not just for performance
but for deployment decisions, container size, and startup time
requirements. .NET offers three models with different trade-offs.

### JIT — The Standard Model

The default execution model. The C# compiler produces IL. The JIT
compiler translates IL to native machine code the first time each method
runs. The trade-off: the first few seconds of a process pay compilation
overhead, but the JIT can produce highly optimised code tuned to the
exact CPU it is running on — sometimes matching C++ performance on hot
paths. .NET's JIT has grown extremely capable and includes PGO (Profile-
Guided Optimisation) that recompiles hot methods with observed runtime
data.

### ReadyToRun (R2R)

A hybrid: the SDK pre-compiles IL to native code during publish, reducing
startup time. The JIT still runs for methods not covered. This is the
default for production ASP.NET Core publishes and gives you faster cold
starts with no code changes.

```bash
dotnet publish -c Release -r linux-x64 /p:PublishReadyToRun=true
```

### Native AOT — Ahead-of-Time Compilation

No JIT. No IL. No CLR startup overhead. The .NET toolchain compiles your
code directly to a native binary at publish time, similar to how Go or
Rust work. The result: single-file binaries, millisecond cold starts,
and tiny container images (often under 10 MB).

The trade-off: anything that relies on runtime code generation requires
explicit support. The most common friction points are serialisation
libraries that use reflection, and dynamic assembly loading. Chapter 21
covers what to do about each of these.

```bash
dotnet publish -c Release -r linux-x64 /p:PublishAot=true
```

---

## 1.9 The Big Picture: What Every Chapter Builds On

This chapter established the map. Every concept in this book sits in one
of the three layers described in §1.1.

The chapters that follow progress through those layers from the bottom up:

- **Ch 2–5** teach the language as enforced by the C# compiler and the
  runtime type system. Nullable reference types (Ch 2), pattern matching
  (Ch 3), delegates (Ch 4), and interfaces (Ch 5) are all compiler and
  runtime features.

- **Ch 6** teaches design principles. Language-agnostic in spirit, but
  expressed through the types and constraints you learned in Ch 2–5.

- **Ch 7–8** complete the language with BCL-level collections and the
  BCL's async/Task infrastructure.

- **Ch 9–14** cover the application layer: how configuration flows in,
  how DI wires components together, how ASP.NET Core handles HTTP.

- **Ch 15a and Ch 15** cover data: raw SQL (the language below every ORM)
  and EF Core (the ORM that generates it).

- **Ch 16–17** cover hosting and testing — the practices that make
  everything else reliable in production.

- **Ch 18** zooms out and discusses how to arrange all the pieces. By
  that point you will have seen every piece individually.

- **Ch 19–32** are deep dives: UI, performance, security, patterns,
  observability.

- **Ch 33–40** are complete projects that exercise everything at once.

At every point, when you encounter a concept, its position in the stack
tells you what it depends on and what depends on it. That is the whole
purpose of this chapter.
