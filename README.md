# The .NET 9 Bible

A comprehensive reference for C# 9–13, .NET 9, and the full ecosystem —
from language basics through production architecture, security, and design patterns.

**32 chapters · 304 sections · ~535 KB**

---

## Reading Order

Chapters are ordered **simple → complex**. Each builds on what came before.

| Chapters | Theme |
|---|---|
| Ch 1–5 | The language: types, control flow, methods, OOP |
| Ch 6 | Design principles — read before picking up any framework |
| Ch 7–8 | More language: collections, async/concurrency |
| Ch 9–11 | Config, environment variables, dependency injection |
| Ch 12–14 | Infrastructure: IO, networking, HTTP request pipeline |
| Ch 15–17 | Data, background workers, testing |
| Ch 18 | Architectures — structure everything you now know |
| Ch 19–21 | Presentation, UI, performance |
| Ch 22–24 | Tooling reference: Nix, Rider, Visual Studio |
| Ch 25–27 | Deep dives: reflection, memory management, caching |
| Ch 28–32 | Senior essentials: security, patterns, observability, SignalR |

Open in **Markor** (Android) or **Obsidian** — every `##` heading is a
tap-navigable section in the outline panel.

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

*Each principle: why it exists, the exact bug it prevents, the fix.*

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
`6.21` Checking Yourself

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

## Quick Reference

### By Task

| I want to... | Go to |
|---|---|
| Set up a new .NET project | Ch 1 §1.4–1.7 |
| Understand C# types and nullability | Ch 2 |
| Use pattern matching | Ch 3 §3.3 |
| Write async code correctly | Ch 8 §8.3–8.4 |
| Understand design principles | **Ch 6** |
| Set up environment variables and secrets | Ch 9 |
| Set up dependency injection | Ch 10–11 |
| Write a REST API | Ch 14 |
| Secure an API (JWT, OAuth, CORS) | **Ch 28** |
| Use the right design pattern | **Ch 29** |
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
