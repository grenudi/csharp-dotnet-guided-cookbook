# The .NET 9 Bible

A comprehensive reference for C# 9–13, .NET 9, and the full ecosystem —
from language basics through production architecture, security, design
patterns, and real-world pet projects you can build and run today.

**42 chapters · 400+ sections · ~900 KB**

---

## Reading Order

Chapters are ordered **simple → complex**. Each builds on what came before.

| Chapters | Theme |
|---|---|
| Ch 1–5 | The language: types, control flow, methods, OOP |
| Ch 6 | Design principles — read before picking up any framework |
| Ch 6b | **How to figure it out yourself** — source navigation, tools, learning habits |
| Ch 7–8 | More language: collections, async/concurrency |
| Ch 9–11 | Config, environment variables, dependency injection |
| Ch 12–14 | Infrastructure: IO, networking, HTTP request pipeline |
| Ch 15a | **SQL: the language under the ORM** |
| Ch 15 | EF Core and data access |
| Ch 16–17 | Background workers, testing |
| Ch 18 | Architectures — structure everything you now know |
| Ch 19–21 | Presentation, UI, performance |
| Ch 22–24 | Tooling reference: Nix, Rider, Visual Studio |
| Ch 25–27 | Deep dives: reflection, memory management, caching |
| Ch 28–32 | Senior essentials: security, patterns, observability, SignalR |
| **Ch 33–40** | **Pet projects by difficulty** |

Open in **Markor** (Android) or **Obsidian** — every `##` heading is a
tap-navigable section in the outline panel.

---

## Pet Projects Path

Eight chapters forming a complete learning ladder from your first console
app to concurrent pipelines and production-grade database work:

```
Ch 33 — Console Apps           (timer, wc, password gen, dup finder, weather)
   ↓ types · async · LINQ · HttpClient
Ch 34 — CLI Tools              (todocli, sysinfo, difftool)
   ↓ System.CommandLine · Spectre.Console · rich terminal output
Ch 34b — Interactive TUI       (budget tracker, live dashboard, wizard form)
   ↓ AnsiConsole.Live · SelectionPrompt · multi-step wizard · SQLite
Ch 35 — Background Daemons     (file watcher, log alerter, job runner)
   ↓ Generic Host · BackgroundService · Channels · systemd
Ch 36 — REST API               (task manager with auth, SQLite, OpenAPI)
   ↓ Minimal API · EF Core · JWT · integration tests
Ch 37 — Real-Time & gRPC       (SignalR chat, streaming exchange rates)
   ↓ SignalR · gRPC server streaming · broadcast hub
Ch 38 — Multithreading         (parallel image resizer, channel pipeline, thread-safe cache)
   ↓ Parallel.ForEachAsync · Channels · Interlocked · locks · race conditions
Ch 39 — Configuration          (secrets, env vars, options validation, live reload)
   ↓ IOptions · IOptionsMonitor · User Secrets · Data Protection
Ch 40 — Databases              (SQLite notes app, PostgreSQL analytics, multi-tenant API)
   ↓ EF Core migrations · Dapper · bulk insert · Testcontainers · safe deploys
```

---

## Table of Contents

---

### [Chapter 1 — The .NET Ecosystem](ch01_ecosystem.md)

`1.1` What Is .NET? ·
`1.2` .NET Version Timeline ·
`1.3` Installing the SDK ·
`1.4` The dotnet CLI — Complete Reference ·
`1.5` Project File (`.csproj`) Deep Dive ·
`1.6` Global Usings ·
`1.7` Solution Structure Patterns ·
`1.8` `global.json` — Pin the SDK Version ·
`1.9` `.editorconfig` — Consistent Code Style ·
`1.10` NuGet Configuration ·
`1.11` Runtimes & AOT Modes ·
`1.12` IDE Setup

---

### [Chapter 2 — Types: Value, Reference, Nullable, Records, Structs](ch02_types.md)

`2.1` The Type System at a Glance ·
`2.2` Built-In Value Types ·
`2.3` Strings ·
`2.4` Nullable Value Types (`T?`) ·
`2.5` Nullable Reference Types (NRT) — C# 8+ ·
`2.6` Records ·
`2.7` Structs ·
`2.8` Enums ·
`2.9` Generics ·
`2.10` Type Aliases (C# 12+) ·
`2.11` Tuple Types ·
`2.12` `dynamic` and `object` ·
`2.13` Primary Constructors (C# 12)

---

### [Chapter 3 — Control Flow & Pattern Matching](ch03_control_flow.md)

`3.1` Basic Control Flow ·
`3.2` Switch Statement vs. Switch Expression ·
`3.3` Pattern Matching — Complete Reference ·
`3.4` Exception Handling ·
`3.5` `using` Statement and `IDisposable` ·
`3.6` Iteration and `yield return` ·
`3.7` goto (and When to Avoid It)

---

### [Chapter 4 — Methods, Delegates, Lambdas & Functional Patterns](ch04_methods_lambdas.md)

`4.1` Method Signatures ·
`4.2` Local Functions ·
`4.3` Extension Methods ·
`4.4` Delegates ·
`4.5` Lambdas & Closures ·
`4.6` Events ·
`4.7` Functional Patterns in C# ·
`4.8` Expression Trees ·
`4.9` Operator Overloading

---

### [Chapter 5 — OOP: Classes, Interfaces, Inheritance & Polymorphism](ch05_oop.md)

`5.1` Classes — Full Anatomy ·
`5.2` Inheritance ·
`5.3` Interfaces ·
`5.4` Abstract Classes vs. Interfaces ·
`5.5` Properties — Advanced ·
`5.6` Object Initialization Patterns ·
`5.7` Object Comparison and Equality ·
`5.8` Covariance and Contravariance in OOP

---

### [Chapter 6 — Core Design Principles](ch06_principles.md)

*Each principle: why it exists, the exact bug it prevents, the fix. The second half
shows how the principles connect into a complete design worldview — from anemic vs
rich domain models through value objects, domain services, aggregates, CQRS, and
the deep theory of coupling.*

`6.1` Make Illegal States Unrepresentable ·
`6.2` Parse, Don't Validate ·
`6.3` Errors Are Values, Not Exceptions ·
`6.4` Immutability by Default ·
`6.5` Totality — Handle Every Case ·
`6.6` Explicit Over Implicit ·
`6.7` Single Responsibility ·
`6.8` Composition Over Inheritance ·
`6.9` Fail Fast ·
`6.10` Domain Primitives — Wrap Naked Primitives ·
`6.11` No Magic Numbers or Hard-Coded Values ·
`6.12` Naming Conventions — Code Is Read, Not Run ·
`6.13` Boy Scout Rule — Leave It Cleaner Than You Found It ·
`6.14` YAGNI — You Aren't Gonna Need It ·
`6.15` DRY — Don't Repeat Yourself ·
`6.16` KISS — Keep It Simple, Stupid ·
`6.17` Law of Demeter — Only Talk to Your Immediate Friends ·
`6.18` Tell, Don't Ask ·
`6.19` Command Query Separation ·
`6.20` The Order of Importance ·
`6.21` Checking Yourself ·
`6.22` The One Idea Behind All of It ·
`6.23` The Anemic Domain Model — The Most Common Violation ·
`6.24` The Rich Domain Model — Entities That Own Their Invariants ·
`6.25` Value Objects — Primitives With Domain Meaning ·
`6.26` Failures as Values — The Full Result Pattern ·
`6.27` Domain Services — Behaviour That Does Not Belong to One Entity ·
`6.28` Aggregate Roots — Consistency Boundaries ·
`6.29` CQRS — Reads and Writes Are Different Problems ·
`6.30` Where DTOs and Persistence Models Live ·
`6.31` Connascence — The Deep Theory of Coupling ·
`6.32` The Revised Self-Check

---

### [Chapter 6b — How to Figure It Out Yourself](ch06b_learning.md)

*Source navigation, experimentation tools, and the learning habits that compound.*

`6b.1` The Core Skill: Building Mental Models From Evidence ·
`6b.2` Navigating BCL and FCL Source Code — GitHub, source.dot.net, decompilers ·
`6b.3` Tools for Experimentation — LINQPad, dotnet-script, SharpLab, BenchmarkDotNet ·
`6b.4` Reading a New Library — A Systematic Process ·
`6b.5` Reading IL — Understanding What the Compiler Actually Does ·
`6b.6` Effective Use of Official Documentation ·
`6b.7` Using the Debugger as a Learning Tool ·
`6b.8` Approaching a New Framework — The Same Process Scaled Up ·
`6b.9` Search Strategies — Finding Answers Efficiently ·
`6b.10` Building Lasting Understanding — Notes and the Feynman Technique ·
`6b.11` The Developer's Toolkit for Discovery — Summary ·
`6b.12` The Habits That Compound

---

### [Chapter 7 — Collections & LINQ](ch07_collections_linq.md)

`7.1` Array ·
`7.2` List\<T\> ·
`7.3` Dictionary\<TKey, TValue\> ·
`7.4` HashSet\<T\> and SortedSet\<T\> ·
`7.5` Queue, Stack, LinkedList, PriorityQueue ·
`7.6` Immutable Collections ·
`7.7` Concurrent Collections ·
`7.8` Span\<T\> and Memory\<T\> ·
`7.9` LINQ — Complete Operator Reference

---

### [Chapter 8 — Async/Await & Concurrency](ch08_async.md)

`8.1` The Async/Await Mental Model ·
`8.2` Task, Task\<T\>, and ValueTask\<T\> ·
`8.3` Writing Correct Async Code ·
`8.4` CancellationToken ·
`8.5` Task Combinators ·
`8.6` Channels — Producer/Consumer ·
`8.7` SemaphoreSlim — Async Rate Limiting ·
`8.8` async/await Patterns ·
`8.9` Parallel Programming ·
`8.10` Async Streams (IAsyncEnumerable\<T\>) ·
`8.11` Thread Safety Primitives

---

### [Chapter 9 — Environment Variables](ch09_env_variables.md)

`9.1` Why They Exist ·
`9.2` What Environment Variables Are ·
`9.3` .NET's Configuration System — The Right Way ·
`9.4` Reading Config — The Full Stack ·
`9.5` Environment Files — Development Workflow ·
`9.6` Docker — Passing Environment Variables ·
`9.7` Kubernetes — Secrets and ConfigMaps ·
`9.8` The DOTNET_ENVIRONMENT Variable ·
`9.9` Nix / direnv — The Full Workflow ·
`9.10` Security Rules ·
`9.11` Validation at Startup — Never Fail in Production

---

### [Chapter 10 — Dependency Injection, Configuration & Logging](ch10_di_config_logging.md)

`10.1` Dependency Injection (DI) ·
`10.2` Options Pattern ·
`10.3` Configuration ·
`10.4` Logging

---

### [Chapter 11 — Dependency Injection: The Complete Picture](ch11_di_deep_dive.md)

*Every example is fully standalone — each has its own `dotnet new` command.*

`11.1` What the Container Actually Is ·
`11.2` The Three Lifetimes ·
`11.3` Constructor Injection ·
`11.4` Swapping Implementations ·
`11.5` Extension Methods — Self-Registration Pattern ·
`11.6` IServiceProvider vs IServiceCollection ·
`11.7` IOptions — Typed Configuration ·
`11.8` Multiple Implementations ·
`11.9` Testing With DI ·
`11.10` BackgroundService + Scoped Dependencies ·
`11.11` The Mental Model

---

### [Chapter 12 — IO: Streams, Pipelines & File System](ch12_io.md)

`12.1` File and Directory Operations ·
`12.2` Streams ·
`12.3` System.IO.Pipelines ·
`12.4` FileSystemWatcher ·
`12.5` Path Utilities and Cross-Platform Paths ·
`12.6` Serialization

---

### [Chapter 13 — Networking: HttpClient, gRPC, WebSockets & QUIC](ch13_networking.md)

`13.1` HttpClient — Best Practices ·
`13.2` gRPC ·
`13.3` WebSockets ·
`13.4` HTTP/3 and QUIC (NET 9+) ·
`13.5` mDNS / Zeroconf (Service Discovery) ·
`13.6` SignalR — Real-Time Communication

---

### [Chapter 14 — ASP.NET Core: Request Pipeline, Middleware, Controllers & Services](ch14_request_pipeline.md)

`14.1` The Problem This All Solves ·
`14.2` The Request Pipeline — What Actually Happens ·
`14.3` Building the Pipeline — `Program.cs` ·
`14.4` Writing Middleware ·
`14.5` Routing ·
`14.6` Controllers — The Right Way ·
`14.7` Services — Where the Work Happens ·
`14.8` Minimal APIs — The Modern Alternative ·
`14.9` Controllers vs Minimal APIs — Choose One ·
`14.10` Model Binding — How Request Data Arrives ·
`14.11` Response Types — What to Return ·
`14.12` Filters vs Middleware ·
`14.13` The Full Picture — Wiring It Together ·
`14.14` Seeing the Pipeline in Rider ·
`14.15` OpenAPI / Swagger — Document Your API ·
`14.16` API Versioning

---

### [Chapter 15a — SQL: The Language Under the ORM](ch15a_sql.md)

*Read this before or alongside Ch 15. Understand the SQL EF Core generates.*

`15a.1` What SQL Is and How .NET Talks to It ·
`15a.2` Installing a Database (SQLite, PostgreSQL, SQL Server) ·
`15a.3` Creating a Schema — DDL: CREATE TABLE, Indexes, Constraints ·
`15a.4` The SELECT Statement — Complete Reference ·
`15a.5` JOINs — INNER, LEFT, RIGHT, FULL, Self-Join ·
`15a.6` DML — INSERT, UPDATE, DELETE, UPSERT ·
`15a.7` Subqueries and CTEs (WITH clause) ·
`15a.8` Window Functions — ROW_NUMBER, LAG, Running Totals ·
`15a.9` Transactions and Isolation Levels ·
`15a.10` Practical Schema: the Complete Sync.Mesh Example ·
`15a.11` Common SQL Patterns You Will Write Every Week ·
`15a.12` Using SQL Directly in .NET — ADO.NET and Dapper ·
`15a.13` Reading the EF Core SQL Log ·
`15a.14` Useful SQLite Pragmas

---

### [Chapter 15 — Entity Framework Core](ch15_efcore.md)

`15.1` Project Setup ·
`15.2` Defining the Domain ·
`15.3` DbContext ·
`15.4` Fluent API Configuration ·
`15.5` Registration and Connection ·
`15.6` Querying ·
`15.7` CRUD Operations ·
`15.8` Transactions ·
`15.9` Migrations ·
`15.10` Dapper — Micro-ORM for Complex Queries ·
`15.11` Change Tracking & Performance Tips ·
`15.12` IEnumerable vs IQueryable — Critical Distinction

---

### [Chapter 16 — Worker Services & Background Jobs](ch16_workers.md)

`16.1` Worker Service Project ·
`16.2` BackgroundService ·
`16.3` Timer-Based Worker (Periodic Timer) ·
`16.4` Scoped Services in BackgroundService ·
`16.5` IHostedService — Custom Lifecycle ·
`16.6` systemd Unit File ·
`16.7` Health Checks ·
`16.8` Hangfire — Scheduled & Recurring Jobs

---

### [Chapter 17 — Testing: xUnit, NSubstitute, Integration & Containers](ch17_testing.md)

`17.1` Project Setup ·
`17.2` xUnit Basics ·
`17.3` Fixtures and Shared State ·
`17.4` NSubstitute — Mocking ·
`17.5` FluentAssertions ·
`17.6` Integration Testing with WebApplicationFactory ·
`17.7` Testcontainers — Real Database Tests ·
`17.8` Test Builders (Fake Data) ·
`17.9` Code Coverage

---

### [Chapter 18 — Software Architectures](ch18_architectures.md)

*Each architecture explained by the problem that created it, with full file trees.*

`18.1` The Problem That All Architectures Are Solving ·
`18.2` Layered Architecture (N-Tier) — The Origin ·
`18.3` Onion Architecture — Dependency Inversion Applied ·
`18.4` Clean Architecture — Onion With Explicit Use Cases ·
`18.5` Hexagonal Architecture (Ports & Adapters) ·
`18.6` Vertical Slice Architecture — Features, Not Layers ·
`18.7` CQRS — Commands and Queries Never Mix ·
`18.8` Modular Monolith — The Middle Path ·
`18.9` Decision Guide ·
`18.10` The Anti-Patterns to Avoid ·
`18.11` Seeing Architecture in Rider

---

### [Chapter 19 — Localization & Internationalization](ch19_localization.md)

`19.1` Why Bake It In From Day One ·
`19.2` Core Concepts ·
`19.3` .resx Resource Files — The Standard Approach ·
`19.4` Using IStringLocalizer ·
`19.5` Data Annotations Localization ·
`19.6` Number, Date & Currency Formatting ·
`19.7` Route-Based Culture (URL Contains Language) ·
`19.8` Blazor Localization ·
`19.9` MAUI Localization ·
`19.10` Extracting Strings — Practical Workflow ·
`19.11` Testing Localization ·
`19.12` The Architecture Rule

---

### [Chapter 20 — Blazor & MAUI](ch20_blazor_maui.md)

`20.1` Blazor Fundamentals ·
`20.2` Blazor Directives — Complete Reference ·
`20.3` Data Binding ·
`20.4` Component Parameters and Cascading Values ·
`20.5` Lifecycle ·
`20.6` Forms and Validation ·
`20.7` JavaScript Interop ·
`20.8` .NET MAUI ·
`20.9` Photino.Blazor — Desktop App

---

### [Chapter 21 — Native AOT, P/Invoke & Performance](ch21_native_aot.md)

`21.1` Native AOT Overview ·
`21.2` AOT Restrictions and Workarounds ·
`21.3` AOT-Compatible Minimal API ·
`21.4` P/Invoke — Calling Native Code ·
`21.5` Unsafe Code and Pointers ·
`21.6` Performance — SIMD and Hardware Intrinsics ·
`21.7` Benchmarking with BenchmarkDotNet

---

### [Chapter 22 — NixOS: Reproducible .NET Development with Nix](ch22_nix.md)

`22.1` Why Nix for .NET? ·
`22.2` Basic `flake.nix` for .NET Development ·
`22.3` `direnv` Integration ·
`22.4` NixOS System Configuration for Development ·
`22.5` Building a .NET App with Nix ·
`22.6` CI/CD with Nix ·
`22.7` Useful Nix Commands ·
`22.8` Home Manager for Developer Config

---

### [Chapter 23 — JetBrains Rider: Killer Features](ch23_rider.md)

`23.1` Navigation ·
`23.2` Editing & Refactoring ·
`23.3` Code Analysis & Inspections ·
`23.4` Debugging ·
`23.5` Documentation ·
`23.6` Building and Running ·
`23.7` Version Control & Git ·
`23.8` HTTP Client (Built-In) ·
`23.9` Database Tool Window ·
`23.10` Essential Shortcuts Summary

---

### [Chapter 24 — Visual Studio 2022: Killer Features](ch24_vs.md)

`24.1` IntelliSense & Code Completion ·
`24.2` Quick Actions & Refactoring (`Ctrl+.`) ·
`24.3` Navigation ·
`24.4` Debugging — Deep Features ·
`24.5` Hot Reload ·
`24.6` Code Analysis & Analyzers ·
`24.7` Live Unit Testing (Enterprise) ·
`24.8` IntelliTest (Enterprise) ·
`24.9` Building & Publishing ·
`24.10` Azure & Docker Integration ·
`24.11` Productivity Shortcuts Summary ·
`24.12` Useful Extensions

---

### [Chapter 25 — Attributes, Reflection & Source Generators](ch25_attributes_reflection.md)

`25.1` What Attributes Are ·
`25.2` Defining Custom Attributes ·
`25.3` Reading Attributes via Reflection ·
`25.4` Reflection — Reading Types at Runtime ·
`25.5` Reflection — Scanning Assemblies ·
`25.6` Source Generators — Compile-Time Code Generation ·
`25.7` DateOnly and TimeOnly (C# 10+ / NET 6+)

---

### [Chapter 26 — Memory Management & the Garbage Collector](ch26_memory_gc.md)

`26.1` Why This Matters ·
`26.2` How the GC Works — The Heap ·
`26.3` The IDisposable Pattern — Correctly ·
`26.4` Common Memory Leak Patterns ·
`26.5` Reducing GC Pressure ·
`26.6` GC Modes and Configuration ·
`26.7` Diagnosing Memory Problems

---

### [Chapter 27 — Caching](ch27_caching.md)

`27.1` Why Caching Exists ·
`27.2` IMemoryCache — In-Process Cache ·
`27.3` IDistributedCache — Shared Cache ·
`27.4` Output Caching (NET 7+) ·
`27.5` Cache-Aside Pattern — The Standard Approach ·
`27.6` Stampede Prevention ·
`27.7` When Not to Cache

---

### [Chapter 28 — Security: Authentication, Authorization & Cryptography](ch28_security.md)

*JWT, OAuth, CORS, Data Protection, OWASP Top 10 — the security chapter every .NET dev needs.*

`28.1` The Landscape ·
`28.2` HTTPS — The Non-Negotiable Baseline ·
`28.3` Authentication — Proving Identity ·
`28.4` OAuth 2.0 and OpenID Connect ·
`28.5` Authorization — What Can You Do? ·
`28.6` CORS — Cross-Origin Resource Sharing ·
`28.7` Data Protection — Encrypting Sensitive Data ·
`28.8` Password Hashing ·
`28.9` Common Vulnerabilities — The OWASP Top 10 in .NET Context ·
`28.10` ASP.NET Core Identity — Full User Management ·
`28.11` Rate Limiting (NET 7+)

---

### [Chapter 29 — Design Patterns](ch29_design_patterns.md)

*The 10 most important GoF patterns in C# with real-world code.*

`29.1` Why Patterns Matter ·
`29.2` Strategy — Swap Algorithms at Runtime ·
`29.3` Decorator — Add Behaviour Without Modifying ·
`29.4` Factory Method and Abstract Factory ·
`29.5` Observer — React to Events ·
`29.6` Builder — Construct Complex Objects Step by Step ·
`29.7` Singleton — One Instance for the Application ·
`29.8` Repository — Abstract Data Access ·
`29.9` Mediator — Decouple Senders from Receivers ·
`29.10` Facade — Simplify a Complex Subsystem ·
`29.11` Template Method — Fixed Algorithm, Variable Steps ·
`29.12` Quick Reference — Which Pattern When

---

### [Chapter 30 — Observability: OpenTelemetry, Metrics & Distributed Tracing](ch30_observability.md)

`30.1` Why Observability Matters ·
`30.2` OpenTelemetry Setup ·
`30.3` Distributed Tracing — Custom Spans ·
`30.4` Metrics — Custom Measurements ·
`30.5` Structured Logging Integration ·
`30.6` .NET Aspire — Cloud-Native Orchestration (NET 9+)

---

### [Chapter 31 — SignalR: Real-Time Communication](ch31_signalr.md)

`31.1` Why SignalR Exists ·
`31.2` Setup ·
`31.3` Defining a Hub ·
`31.4` Pushing from Services — IHubContext ·
`31.5` JavaScript Client ·
`31.6` Blazor Client ·
`31.7` Scaling SignalR — Redis Backplane

---

### [Chapter 32 — Common Design Patterns: MediatR, ErrorOr, Repository & More](ch32_patterns.md)

`32.1` Why These Patterns ·
`32.2` Mediator Pattern — MediatR ·
`32.3` Result Pattern — ErrorOr ·
`32.4` Repository Pattern ·
`32.5` Specification Pattern

---

## Pet Projects — Chapters 33–40

*Complete, runnable projects grouped by difficulty. Every project
references the Bible chapters that explain its underlying concepts.*

---

### [Chapter 33 — Pet Projects I: Console Applications](ch33_petprojects_console.md)

*Beginner — no framework, pure C#.*

`33.1` Why Start With Console Apps ·
`33.2` **Countdown Timer** — `Task.Delay`, `CancellationToken`, `\r` cursor control ·
`33.3` **Word & Line Counter** — `IAsyncEnumerable`, LINQ, stdin piping ·
`33.4` **Password Generator** — `RandomNumberGenerator`, `ReadOnlySpan<char>` ·
`33.5` **File Duplicate Finder** — `SHA256`, directory walk, LINQ GroupBy ·
`33.6` **Weather CLI** — `HttpClient`, `System.Text.Json`, record types, free API ·
`33.7` What to Build Next

**Concepts exercised:** Ch 2 (records, spans), Ch 3 (pattern matching), Ch 7 (LINQ),
Ch 8 (async/await, IAsyncEnumerable), Ch 12 (file I/O), Ch 13 (HttpClient), Ch 28 (crypto)

---

### [Chapter 34 — Pet Projects II: CLI Tools](ch34_petprojects_cli.md)

*Intermediate — proper argument parsing, rich terminal output.*

`34.1` The Two Libraries: System.CommandLine + Spectre.Console ·
`34.2` **todocli** — subcommands, JSON storage, colour tables ·
`34.3` **sysinfo** — live CPU bar, `AnsiConsole.Live`, `DriveInfo` ·
`34.4` **difftool** — directory comparison, tree output ·
`34.5` Spectre.Console Quick Reference — markup, prompts, progress, tables, panels

**Concepts exercised:** Ch 2, Ch 7 (Dictionary, GroupBy), Ch 8 (PeriodicTimer),
Ch 12 (file I/O), Ch 26 (process info)

---

### [Chapter 35 — Pet Projects III: Background Daemons](ch35_petprojects_daemon.md)

*Intermediate-Advanced — long-running services, systemd.*

`35.1` The Generic Host as Daemon Chassis ·
`35.2` **File Watcher Daemon** — `FileSystemWatcher`, debounce, `Channel<T>`, JSONL log ·
`35.3` **Log Tail & Alerter** — `FileStream` seek, `Regex`, webhook push (ntfy.sh) ·
`35.4` **Scheduled Job Runner** — `PeriodicTimer`, `Task.WhenAll`, job registry pattern ·
`35.5` Installing as a systemd Service — unit file, `UseSystemd()`, graceful shutdown

**Concepts exercised:** Ch 8 (Channels, PeriodicTimer), Ch 10 (IOptions),
Ch 12 (FileSystemWatcher, streams), Ch 16 (BackgroundService, systemd)

---

### [Chapter 36 — Pet Projects IV: REST API Server](ch36_petprojects_api.md)

*Advanced — production-shaped API with auth, DB, docs, tests.*

`36.1` Project: `taskapi` — a Task Management API ·
`36.2` Domain and EF Core persistence ·
`36.3` `Program.cs` — complete wiring: DB, auth, OpenAPI ·
`36.4` Auth routes — register, login, JWT issuance ·
`36.5` Task routes — full CRUD, pagination, filtering ·
`36.6` JWT Token Service ·
`36.7` Integration test with `WebApplicationFactory` ·
`36.8` Running and testing with httpie / Swagger

**Concepts exercised:** Ch 14 (Minimal API), Ch 15a (SQL), Ch 15 (EF Core),
Ch 17 (integration testing), Ch 28 (JWT, BCrypt)

---

### [Chapter 37 — Pet Projects V: Real-Time Server & gRPC](ch37_petprojects_realtime_grpc.md)

*Advanced — WebSocket hub, server streaming, broadcast architecture.*

`37.1` **SignalR Chat** — multi-room hub, message history, JavaScript client ·
`37.2` **gRPC Exchange Rate Service** — server streaming, `Channel<T>` broadcaster,
rate simulator BackgroundService, `grpcurl` testing ·
`37.3` What to Build After These Five Chapters — independent project ideas

**Concepts exercised:** Ch 8 (Channels), Ch 13 (gRPC, streaming),
Ch 15 (EF Core), Ch 16 (BackgroundService), Ch 31 (SignalR)

---

### [Chapter 38 — Pet Projects VI: Multithreading, Race Conditions & Concurrency](ch38_petprojects_multithreading.md)

*Advanced — the exact bugs, the exact fixes, three real projects.*

`38.1` The Three Kinds of Concurrency in .NET ·
`38.2` The Race Condition Zoo — Lost Update, Check-Then-Act, Async + Shared State ·
`38.3` **`imgresizer`** — Parallel image resizer: `Parallel.ForEachAsync`, bounded parallelism,
progress, cancellation ·
`38.4` **`pipeline`** — Producer/consumer pipeline: bounded `Channel<T>`, backpressure,
fan-out workers, graceful shutdown ·
`38.5` **`threadcache`** — Thread-safe cache: `ReaderWriterLockSlim`, `ConcurrentDictionary`,
`ImmutableDictionary` + `Interlocked.CompareExchange` ·
`38.6` Synchronisation Primitive Cheat Sheet ·
`38.7` The Five Rules You Must Not Break

**Concepts exercised:** Ch 7 (concurrent collections), Ch 8 (Channels, Parallel,
Task.WhenAll, SemaphoreSlim, CancellationToken), Ch 26 (Interlocked, volatile)

---

### [Chapter 39 — Pet Projects VII: Configuration, Secrets & Settings](ch39_petprojects_config.md)

*All skill levels — the complete picture in one place.*

`39.1` The Configuration Stack ·
`39.2` The `IOptions<T>` Pattern ·
`39.3` Console App — Minimal Config Setup ·
`39.4` Generic Host — Config in a Daemon or API ·
`39.5` Secrets — User Secrets, Environment Variables, Data Protection ·
`39.6` Environment-Specific Configuration Files ·
`39.7` Config Validation at Startup — `ValidateOnStart` ·
`39.8` `IOptionsMonitor<T>` — Live Reloading Without Restart ·
`39.9` CLI App — Config from Arguments + File + Env ·
`39.10` The Settings Summary Table

**Concepts exercised:** Ch 9 (env vars, 12-factor), Ch 10 (IOptions),
Ch 11 (DI), Ch 28 (secrets, Data Protection)

---

### [Chapter 40 — Pet Projects VIII: Databases in Real Projects](ch40_petprojects_databases.md)

*Intermediate–Advanced — schema to query to test in three projects.*

`40.1` Choosing the Right Database for Your Pet Project ·
`40.2` **`notesdb`** — SQLite note app: EF Core code-first, migrations,
IQueryable queries, repository pattern ·
`40.3` **`pganalytics`** — PostgreSQL analytics service: Npgsql bulk insert (COPY),
Dapper for analytics queries, window functions, index design ·
`40.4` Migrations in Production — The Safe Pattern ·
`40.5` **`tenantapi`** — Multi-tenant API: schema-per-tenant, DbContext factory,
dynamic connection strings ·
`40.6` Testing With Testcontainers — Real Database, No Mocks ·
`40.7` The IEnumerable vs IQueryable Trap (Reprise)

**Concepts exercised:** Ch 15a (SQL), Ch 15 (EF Core, Dapper, IQueryable),
Ch 17 (Testcontainers), Ch 18 (Repository pattern), Ch 28 (no SQL injection)

---

## Quick Reference

### By Task

| I want to... | Go to |
|---|---|
| Set up a new .NET project | Ch 1 §1.4–1.7 |
| Understand C# types and nullability | Ch 2 |
| Use pattern matching | Ch 3 §3.3 |
| Write async code correctly | Ch 8 §8.3–8.4 |
| Understand design principles | **Ch 6** |
| Understand anemic vs rich domain model | **Ch 6 §6.23–6.24** |
| Understand value objects in depth | **Ch 6 §6.25** |
| Use the Result pattern / Railway Oriented | **Ch 6 §6.26** |
| Know when to use a Domain Service | **Ch 6 §6.27** |
| Understand aggregate roots | **Ch 6 §6.28** |
| Apply CQRS | **Ch 6 §6.29** |
| Know where DTOs live | **Ch 6 §6.30** |
| Understand coupling precisely | **Ch 6 §6.31** |
| Navigate BCL/FCL source code | **Ch 6b §6b.2** |
| Set up LINQPad / SharpLab / dotnet-script | **Ch 6b §6b.3** |
| Systematically learn a new library | **Ch 6b §6b.4** |
| Read IL and understand compiler output | **Ch 6b §6b.5** |
| Search efficiently for .NET answers | **Ch 6b §6b.9** |
| Build lasting technical knowledge | **Ch 6b §6b.10–6b.12** |
| Set up environment variables and secrets | Ch 9 |
| Set up dependency injection | Ch 10–11 |
| Write a REST API | Ch 14 |
| Secure an API (JWT, OAuth, CORS) | **Ch 28** |
| Use the right design pattern | **Ch 29** |
| Write SQL from scratch | **Ch 15a** |
| Use EF Core with migrations | Ch 15 §15.9 |
| Know IEnumerable vs IQueryable | Ch 15 §15.12 |
| Write testable code | Ch 6 + Ch 17 |
| Choose the right architecture | Ch 18 §18.9 |
| Implement caching | Ch 27 |
| Understand GC and memory leaks | Ch 26 |
| Use reflection and attributes | Ch 25 |
| Add real-time with SignalR | Ch 31 |
| Add observability / tracing | Ch 30 |
| Localize an app | Ch 19 |
| Set up Nix dev environment | Ch 22 §22.2–22.3 |
| Find Rider shortcuts | Ch 23 §23.10 |
| Find VS shortcuts | Ch 24 §24.11 |
| Build a console tool | **Ch 33** |
| Build a CLI with rich output | **Ch 34** |
| Build an interactive TUI | **Ch 34b** |
| Build a background daemon | **Ch 35** |
| Build a REST API with auth | **Ch 36** |
| Build a real-time or gRPC service | **Ch 37** |
| Fix a race condition | **Ch 38 §38.2** |
| Run tasks in parallel safely | **Ch 38 §38.3** |
| Build a producer/consumer pipeline | **Ch 38 §38.4** |
| Set up config and secrets correctly | **Ch 39** |
| Add live-reloading config | **Ch 39 §39.8** |
| Pick the right database | **Ch 40 §40.1** |
| Write safe production migrations | **Ch 40 §40.4** |
| Test against a real database | **Ch 40 §40.6** |

### By Concept

| Concept | Chapter |
|---|---|
| Nullable reference types | Ch 2 §2.5 |
| Primary constructors (C# 12) | Ch 2 §2.13 |
| Error handling | Ch 3 §3.4, Ch 6 §6.3 |
| Design principles | Ch 6 |
| Dependency injection | Ch 10, Ch 11 |
| Configuration and secrets | Ch 9, Ch 10 §10.2–10.3 |
| Immutability and value objects | Ch 2 §2.6, Ch 6 §6.4, Ch 6 §6.10 |
| Architecture patterns | Ch 18 |
| Request pipeline and middleware | Ch 14 |
| OpenAPI / Swagger | Ch 14 §14.15 |
| API versioning | Ch 14 §14.16 |
| Background workers | Ch 16 |
| Security (JWT, OAuth, CORS) | **Ch 28** |
| Design patterns (GoF) | **Ch 29** |
| MediatR, ErrorOr, Repository | Ch 32 |
| Performance and AOT | Ch 21 |
| Memory management and GC | Ch 26 |
| Caching | Ch 27 |
| Reflection and source generators | Ch 25 |
| SignalR real-time | Ch 31 |
| Observability / OpenTelemetry | Ch 30 |
| IEnumerable vs IQueryable | Ch 15 §15.12 |
| Localization / i18n | Ch 19 |
| Cross-platform scripting | Ch 22 |
| SQL fundamentals | **Ch 15a** |
| SQLite, PostgreSQL, SQL Server install | **Ch 15a §15a.2** |
| Schema design (DDL) | **Ch 15a §15a.3** |
| JOINs, CTEs, window functions | **Ch 15a §15a.5–15a.8** |
| Transactions and isolation | **Ch 15a §15a.9** |
| Pet projects: console apps | **Ch 33** |
| Pet projects: CLI tools | **Ch 34** |
| Pet projects: interactive TUI | **Ch 34b** |
| Pet projects: daemons | **Ch 35** |
| Pet projects: REST API | **Ch 36** |
| Pet projects: real-time/gRPC | **Ch 37** |
| Pet projects: multithreading | **Ch 38** |
| Race conditions and fixes | **Ch 38 §38.2** |
| Parallel.ForEachAsync | **Ch 38 §38.3** |
| Channel<T> pipelines | **Ch 38 §38.4** |
| Synchronisation primitives | **Ch 38 §38.6** |
| Configuration and secrets | **Ch 39** |
| IOptions / IOptionsMonitor | **Ch 39 §39.2, §39.8** |
| Database project patterns | **Ch 40** |
| EF Core migrations in production | **Ch 40 §40.4** |
| Testcontainers for DB tests | **Ch 40 §40.6** |
