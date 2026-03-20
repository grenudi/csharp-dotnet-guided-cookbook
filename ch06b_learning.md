# Chapter 6b — How to Figure It Out Yourself

> Every senior developer you admire is not smarter than you. They have
> a more refined process for turning uncertainty into understanding. They
> know which tools to reach for, which questions to ask first, and how
> to read code they have never seen before. This chapter teaches that
> process explicitly — because nobody else does.

*Building on:* Ch 1 (the SDK and CLI), Ch 6 (design principles — knowing
what good looks like helps you evaluate what you find)

---

## 6b.1 The Core Skill: Building Mental Models From Evidence

When you encounter an unfamiliar library, API, or BCL type, the goal is
not to memorise its methods. It is to build a mental model: what problem
does this solve, how does it think about that problem, what are the
constraints it operates under. Once you have the model, the API
surface becomes obvious — you can predict what methods exist before
reading them.

The process that builds models from evidence is the scientific method
applied to code:

```
1. Observe      — what does the type look like? What does it implement?
                  What does it inherit from? What are its constructors?

2. Hypothesise  — based on the interface and naming, what must it do?
                  What problem is it solving?

3. Experiment   — write a minimal test or script. Push it to its edges.
                  What happens on null input? On empty input? On overflow?

4. Explain      — can you explain it to someone else in one paragraph?
                  If not, you do not have the model yet.

5. Connect      — where does this fit in the stack from Ch 1?
                  What does it build on? What builds on top of it?
```

This process works on everything: a new NuGet package, a BCL type you
have never used, a framework you are evaluating, even a piece of your
own codebase written six months ago.

---

## 6b.2 Navigating the BCL and FCL Source Code

The entire .NET runtime and BCL is open source. Reading the actual
source code of the types you use every day is one of the highest-leverage
learning activities available to you. You stop guessing about what
`Dictionary<K,V>` does internally and start knowing.

### The Three Places to Read Source

**1. GitHub — dotnet/runtime**

The canonical source. Every BCL type lives here:

```
https://github.com/dotnet/runtime

Key paths:
  src/libraries/System.Collections/         → List<T>, Dictionary<K,V>, etc.
  src/libraries/System.Text.Json/           → JsonSerializer
  src/libraries/System.Net.Http/            → HttpClient, HttpClientHandler
  src/libraries/System.Threading.Channels/  → Channel<T>
  src/coreclr/                              → the CLR runtime itself
  src/libraries/System.Linq/               → all LINQ operators
```

When you want to understand *why* `List<T>` doubles its capacity rather
than growing by one, reading the constructor and `EnsureCapacity` method
in 10 minutes answers it definitively. No blog post required.

**2. source.dot.net — The Searchable Reference**

```
https://source.dot.net
```

A search-friendly, cross-referenced browser of the BCL source. Type any
class name and get to the source immediately, with clickable references
to every type and method it uses. Faster than GitHub for exploration.

**3. The Decompiler — ILSpy or Rider's Built-In**

For closed-source assemblies — third-party NuGet packages, Windows-only
libraries, legacy code you cannot get the source for — a decompiler
reconstructs C# from IL. The reconstructed code is not identical to
the original but is close enough to understand the logic.

```bash
# ILSpy CLI
dotnet tool install --global ilspycmd
ilspycmd path/to/SomeLibrary.dll -p -o ./decompiled/

# Or install ILSpy GUI from https://github.com/icsharpcode/ILSpy
```

In Rider: open any .dll in the solution, or Ctrl+click any external
type to jump directly to its decompiled source. The decompiler runs
automatically — no setup required.

### What to Look For When Reading Source

Reading source code with no strategy produces information without
understanding. Read with these questions:

**What does it implement?**
The `class` declaration tells you the inheritance chain and every interface
implemented. This is the most information-dense line in the file:

```csharp
// Reading this one line tells you:
// - Dictionary is sealed (cannot be subclassed — a design choice)
// - implements IDictionary<TKey,TValue> (the keyed collection contract)
// - implements IReadOnlyDictionary (can be passed as read-only)
// - implements IDictionary (old non-generic version — for interop)
// - implements ISerializable (supports BinaryFormatter serialisation)
// - implements IDeserializationCallback (hook for post-deserialisation)
public sealed class Dictionary<TKey, TValue>
    : IDictionary<TKey, TValue>,
      IDictionary,
      IReadOnlyDictionary<TKey, TValue>,
      ISerializable,
      IDeserializationCallback
```

**What are the private fields?**
The fields reveal the internal data structure. For `Dictionary<K,V>`:

```csharp
private int[]      _buckets;      // hash table — buckets[hashCode % buckets.Length]
private Entry[]    _entries;      // the actual stored key-value pairs
private int        _count;        // number of entries in use
private int        _freeList;     // linked list of free slots for reuse
private int        _freeCount;    // how many free slots exist
private ulong      _fastModMultiplier; // for fast modulo without division
```

Now you know: `Dictionary` is an open-addressing hash table with separate
chaining via arrays, not linked lists. This explains why removing items
does not shrink the array (just marks slots free), why iteration order is
not guaranteed, and why it has O(1) average lookup but O(n) worst case.

**What do the hot-path methods do?**
Read `TryGetValue` and `Add`/`TryAdd`. These are called millions of times —
any complexity here is intentional and worth understanding.

**What guards does it have?**
Read the first few lines of any public method. The guards tell you the
type's invariants — what it considers invalid input and what it assumes
about its own state.

---

## 6b.3 Tools for Experimentation

The fastest path to understanding is a tight feedback loop: write code,
run it, observe, change, repeat. These tools make that loop as short as
possible.

### LINQPad — The .NET Scratchpad

LINQPad is the single most useful exploration tool for .NET. It is a
standalone executable that runs C# expressions, statements, or programs
instantly with no project setup. The `.Dump()` extension method renders
any object in a rich interactive tree:

```csharp
// In LINQPad — runs immediately, no project, no Main()
var dict = new Dictionary<string, int>
{
    ["alice"] = 1,
    ["bob"]   = 2
};

dict.Dump("My Dictionary");           // renders as an interactive table
dict.Keys.OrderBy(k => k).Dump();    // rendered inline

// Explore internals
typeof(Dictionary<string,int>)
    .GetFields(BindingFlags.NonPublic | BindingFlags.Instance)
    .Select(f => new { f.Name, f.FieldType.Name })
    .Dump("Private fields");          // shows _buckets, _entries, etc.
```

LINQPad connects to databases, runs EF Core queries, and lets you inspect
actual SQL generated. For exploring an unfamiliar API, it replaces a full
project setup with a single file.

```
https://www.linqpad.net
Free version: full C# scratchpad
Paid version: NuGet references, autocomplete, debugger
```

### `dotnet-script` — Scripts Without Projects

```bash
dotnet tool install --global dotnet-script

# Create a .csx file and run it immediately
echo 'Console.WriteLine(typeof(List<int>).BaseType);' > explore.csx
dotnet-script explore.csx
```

Scripts can reference NuGet packages inline:

```csharp
// explore.csx
#r "nuget: Dapper, 2.1.28"
#r "nuget: Microsoft.Data.Sqlite, 8.0.0"

using Dapper;
using Microsoft.Data.Sqlite;

using var conn = new SqliteConnection("Data Source=:memory:");
conn.Open();
conn.Execute("CREATE TABLE t (id INTEGER, name TEXT)");
conn.Execute("INSERT INTO t VALUES (1, 'Alice')");
var rows = conn.Query("SELECT * FROM t").ToList();
foreach (var r in rows) Console.WriteLine(r);
```

This is faster than creating a project for a one-off exploration.

### Polyglot Notebooks — Literate Exploration

The VS Code Polyglot Notebooks extension turns `.ipynb` files into
executable C# notebooks — code cells mixed with markdown, output
rendered inline, shareable as documents.

```bash
# VS Code extension
code --install-extension ms-dotnettools.dotnet-interactive-vscode
```

Useful when you want to document your exploration as you go — the
notebook becomes the notes, not just the experiment.

### `dotnet-repl` — Interactive REPL

```bash
dotnet tool install --global dotnet-repl
dotnet-repl
```

A full C# REPL in the terminal. Type expressions, see results instantly.
Supports `using` directives, can load NuGet packages. Useful for quick
one-liners when LINQPad is not open.

### BenchmarkDotNet — Measuring, Not Guessing

When you have a hypothesis about performance ("I think `StringBuilder`
is faster here") you need a measurement, not an opinion. BenchmarkDotNet
runs code in controlled conditions and produces statistically valid results:

```csharp
// Never measure performance with Stopwatch in a loop — too much noise
// BenchmarkDotNet controls for JIT warmup, GC, CPU frequency scaling

[MemoryDiagnoser]   // also reports allocations
public class StringConcatenationBenchmarks
{
    private const int N = 1000;

    [Benchmark(Baseline = true)]
    public string PlusOperator()
    {
        string s = "";
        for (int i = 0; i < N; i++) s += i;
        return s;
    }

    [Benchmark]
    public string StringBuilder()
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < N; i++) sb.Append(i);
        return sb.ToString();
    }

    [Benchmark]
    public string StringCreate()
        => string.Concat(Enumerable.Range(0, N).Select(i => i.ToString()));
}

// Run: dotnet run -c Release
// BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
```

The output tells you mean time, standard deviation, and allocations per
call. Numbers replace arguments. "StringBuilder is 50× faster and
allocates 0 bytes in the hot path" ends the discussion.

---

## 6b.4 Reading a New Library — A Systematic Process

When a new library lands in your project (either you chose it or
someone else did), this is the order to approach it:

### Step 1 — Read the Repository README in Full

Not skim. Read. The README tells you:
- What problem the author thought they were solving
- What the intended use cases are
- What the library explicitly does NOT do
- The quickstart — the simplest meaningful example

The simplest example is the most information-dense thing in any
documentation. It shows you the primary abstraction, the entry point,
and the expected mental model in ten lines.

### Step 2 — Look at the Tests

Library tests are the second-best documentation, often better than the
README. They show:
- Every feature with a concrete example
- Edge cases the author anticipated
- Error conditions and what happens
- The vocabulary the author uses to describe their concepts

```bash
# Clone and navigate to the test project
git clone https://github.com/some/library
find . -name "*.Tests.csproj" -o -name "*Test*.csproj"
# Read the test files — filter by the class you care about
```

### Step 3 — Find the Primary Abstraction

Every library has one or two types that are its centre of gravity. Everything
else orbits them. Finding these first means understanding the rest faster.

Ask: what type do I construct first? What is the entry point?

For `HttpClient` → `HttpClient` is the centre, `HttpRequestMessage` and
`HttpResponseMessage` orbit it.

For `System.Text.Json` → `JsonSerializer` is the centre, `JsonSerializerOptions`
is the main configuration type, `JsonConverter<T>` is the extension point.

For EF Core → `DbContext` is the centre, `DbSet<T>` orbits it.

Once you have identified the primary abstraction, read its constructor(s)
and its most-called methods. Everything else connects back to this.

### Step 4 — Write the Minimum Working Example

Do not copy the README example. Type it. Then delete it and type it again
from memory. Then modify it:
- What happens when I pass null here?
- What happens when I call this method twice?
- What does the exception message say when I do it wrong?

The errors are as informative as the successes. A library that gives you
a clear error message when you misuse it is telling you exactly what
its invariants are.

### Step 5 — Read the CHANGELOG or Release Notes

The changelog tells you what the library got wrong the first time. When
a method is deprecated and replaced, the new method represents the team's
improved understanding of the problem. The deprecated method represents
a trap — knowing it is a trap is more useful than not knowing it exists.

### Step 6 — Search for "[LibraryName] pitfalls" or "[LibraryName] gotchas"

Someone has already hit every non-obvious problem with any library that
has more than a thousand users. The first page of results for
"HttpClient pitfalls" or "Entity Framework performance gotchas" will
save you days of debugging.

---

## 6b.5 Reading IL — Understanding What the Compiler Actually Does

C# is compiled to IL (Intermediate Language) before JIT compilation.
Reading IL reveals what the C# compiler actually produces — sometimes
very different from what you expect. This matters for:

- Understanding what `async`/`await` actually generates
- Understanding what `foreach` does on different types
- Understanding the cost of lambdas and closures
- Confirming that `readonly struct` avoids copies

### Reading IL in Practice

```bash
# Compile and inspect IL with ildasm (built into SDK)
dotnet build -c Release
ildasm bin/Release/net9.0/MyApp.dll /output:MyApp.il
# Read MyApp.il in any text editor

# Or use ILSpy (GUI) — decompiles back to C# or shows IL
# Or use sharplab.io (browser-based) — fastest for one-offs
```

### SharpLab — The Essential Browser Tool

```
https://sharplab.io
```

Paste any C# snippet. Select "IL" or "JIT Asm" output on the right.
Instantly see exactly what the compiler produces. This is the fastest
way to answer "what does this syntax actually cost":

```csharp
// Type this into SharpLab, select "C# (Decompile)" output:
async Task<int> GetValueAsync()
{
    await Task.Delay(100);
    return 42;
}

// SharpLab shows you the state machine the compiler generated:
// - A private struct implementing IAsyncStateMachine
// - A MoveNext() method with a switch on the state
// - The awaiter stored as a field
// - The continuation registered on the awaiter
// This is why async methods are slightly more expensive than sync —
// they allocate a state machine struct and register a callback
```

```csharp
// Another example: what does foreach actually do on a List<T>?
// SharpLab shows: it calls GetEnumerator() and uses the struct enumerator
// This is why foreach on List<T> does NOT allocate — the enumerator is a struct

// But foreach on IEnumerable<T> (the interface) DOES allocate
// because the virtual call requires a heap-allocated enumerator object
```

---

## 6b.6 Effective Use of Official Documentation

Microsoft's documentation has gotten much better but is inconsistent.
Knowing which parts are trustworthy and which to supplement:

### The Good Parts

**API Reference (learn.microsoft.com/dotnet/api)** — mechanical and
accurate. Every method, every parameter, every exception thrown. Use it
to confirm what you already mostly know.

**Fundamental Concepts articles** — the deeper conceptual articles
(Memory and Spans, Async overview, Garbage collection, Threading) are
excellent. Written by the runtime team, they explain the why, not just
the what.

**dotnet/runtime GitHub discussions** — when you need to understand a
design decision ("why does `Dictionary` not shrink on remove?"), the
GitHub issues and discussions often contain the actual reasoning from the
people who designed it. Search: `site:github.com/dotnet/runtime [your question]`

### The Weak Parts

Getting-started tutorials on Microsoft's docs tend to be outdated or
oversimplified. For practical patterns, prefer:

- **Andrew Lock's .NET blog** — deeply detailed, regularly updated,
  explains the internals of ASP.NET Core
- **Steven Cleary's blog** — the definitive resource on async patterns
- **Nick Chapsas on YouTube** — practical, benchmark-driven, current
- **Khalid Abuhakmeh's blog** — Entity Framework and ASP.NET Core
- **The .NET team's own blog** (devblogs.microsoft.com/dotnet) — release
  posts explain the reasoning behind new features

### How to Evaluate a Blog Post or StackOverflow Answer

Any answer older than two years may describe .NET Framework, .NET Core,
or .NET 5 behaviour that has changed. Check the date first. Then check
the version number mentioned. Then:

1. Does it cite the source? (official docs, GitHub issue, benchmark)
2. Does the accepted StackOverflow answer have significant downvotes?
   Read the downvote comments — they often contain the correction.
3. Can you reproduce the answer in a scratch project?

The test for any claim about performance: "show me the benchmark".
Opinions about which is faster are worthless. Numbers are not.

---

## 6b.7 Using the Debugger as a Learning Tool

The debugger is not just for finding bugs. It is one of the most powerful
learning tools available. Stepping through code you do not understand is
worth more than reading about it.

### Stepping Into BCL and Framework Source

Rider and Visual Studio both support stepping into the actual BCL source
code — not the decompiled version, the real annotated source with comments:

```
Rider:
  Settings → Build, Execution, Deployment → Debugger
  Enable "Allow stepping into library code"
  Enable "Use .NET Framework symbol server"

Visual Studio:
  Tools → Options → Debugging → General
  Enable "Enable .NET Source Link support"
  Uncheck "Enable Just My Code"
```

With this configured, you can set a breakpoint in your code, step into
`JsonSerializer.Serialize(...)`, and walk through the actual BCL
implementation. Watch the call stack. Watch the variables. Understand
exactly what path your data takes through the framework.

### What to Watch in the Debugger When Exploring

When stepping through unfamiliar code, focus on:

**The call stack** — shows you the chain of method calls. In async code
this is truncated, but it still shows the immediate context. The call
stack is the "how did we get here" answer.

**The locals and watch window** — put expressions in the watch window
to observe intermediate state. You can evaluate any valid C# expression
while paused, including LINQ queries:
```csharp
// In Watch window while paused:
_items.Where(i => i.Price.Amount > 100).Count()
typeof(Dictionary<string,int>).GetFields(BindingFlags.NonPublic | BindingFlags.Instance)
```

**The Immediate Window** — execute arbitrary code in the context of the
paused program. Call methods, inspect objects, test hypotheses without
restarting.

### The Exploratory Breakpoint Technique

When you encounter code you do not understand, put a breakpoint on the
first suspicious line and run. Do not read the code before running —
observe the actual values first, then read the code with those values
in mind. The values make the code concrete in a way that abstract reading
does not.

---

## 6b.8 Approaching a New Framework — The Same Process Scaled Up

A framework is just a larger, more opinionated library. The same process
applies but at a higher level. When you encounter ASP.NET Core,
Entity Framework, MAUI, or any other full framework for the first time:

### Find the Seam

Every framework has a seam — the boundary between your code and the
framework's code. Understanding the seam is understanding the framework.

For ASP.NET Core the seam is `Program.cs` — the pipeline builder.
Everything above the seam is yours. Everything below is the framework.

For EF Core the seam is `DbContext` — specifically `OnModelCreating`.
Above it: your domain. Below it: the ORM and the database.

For MAUI the seam is `MauiProgram.cs` and the `ContentPage` base class.

### Read the Source of One Request

For any framework that processes requests (HTTP, database queries, events),
pick one request and follow it from entry to exit. Do not try to understand
the whole framework. Understand one path completely.

For ASP.NET Core: set a breakpoint in a Minimal API handler. Step out
until you see the framework code. Step in until you see the socket read.
Now you understand the pipeline from raw bytes to your handler.

### Find the Extension Points

Every framework has designed-in extension points — places where it
invites you to add behaviour. Finding them tells you the framework's
philosophy about what belongs to it and what belongs to you.

```
ASP.NET Core:      Middleware, IActionFilter, IResultFilter, ModelBinder
EF Core:           IInterceptor, IEntityTypeConfiguration, ValueConverter
Serilog:           ILogEventSink, Destructuring Policy
MediatR:           IPipelineBehavior, INotificationHandler
```

These extension points are also the best place to read framework source —
the code that calls your extension shows you exactly what the framework
expects from you.

---

## 6b.9 Search Strategies — Finding Answers Efficiently

### The Hierarchy of Sources (Best First)

```
1. Official docs + GitHub source          → accurate, authoritative
2. GitHub issues / discussions            → explains design decisions
3. The library's own test suite           → shows every feature in use
4. Curated blogs (Lock, Cleary, Chapsas) → accurate, explained well
5. StackOverflow (recent, high-voted)    → check date and comments
6. Random blogs                          → verify before trusting
7. AI assistants                         → useful for orientation,
                                           must verify all specifics
```

### Precise Search Queries

Vague queries produce vague results. Be specific about version, context,
and the exact phenomenon:

```
BAD:  "C# dictionary performance"
GOOD: "Dictionary<TKey,TValue> GetOrAdd thread safety .NET 9"

BAD:  "EF Core slow"
GOOD: "Entity Framework Core N+1 query Include vs Select projection"

BAD:  "async deadlock"
GOOD: "async await deadlock SynchronizationContext WPF .Result"
```

Include the version number when the behaviour has changed between versions.
Include the error message verbatim when you have one — someone has already
hit your exact error.

### Reading a GitHub Issue Efficiently

GitHub issues are dense with information but unstructured. Efficient reading:

1. Read the OP (original post) — states the problem and initial hypothesis
2. Jump to the last three comments — often contains the resolution
3. Look for comments from repository contributors — these carry authority
4. Look for comments linking to a commit or PR — the fix is there

The label on the issue tells you whether it is a bug, a feature request,
or a design discussion. "By design" issues are particularly valuable —
they explain why the library does something that seems wrong.

### The "Minimal Reproduction" Discipline

When you hit a problem you cannot solve with documentation alone, create
a minimal reproduction before asking for help:

```csharp
// Minimal reproduction: the smallest program that shows the problem
// No database. No HTTP. No file system. Just the broken behaviour.

var channel = Channel.CreateBounded<int>(1);
var writer  = channel.Writer;
var reader  = channel.Reader;

// I expect this to block when the channel is full
await writer.WriteAsync(1);   // fills the channel
await writer.WriteAsync(2);   // should block — does it?
```

The act of creating the minimal reproduction solves the problem
surprisingly often — removing unnecessary parts forces you to identify
which part is actually broken. If it does not solve it, you now have
something precise enough to post on StackOverflow or GitHub.

---

## 6b.10 Building Lasting Understanding — Notes and the Feynman Technique

### The Problem With Reading

Reading without synthesis produces a feeling of understanding rather than
actual understanding. You finish an article, nod, close the tab, and two
weeks later cannot recall a single specific thing. The feeling was real;
the retention was not.

The fix is not to read more slowly. It is to output as well as input.
Output forces synthesis, and synthesis creates the connections that
make knowledge retrievable.

### The Feynman Technique Applied to Code

Richard Feynman's learning method: after learning something, explain it
to a complete beginner in plain language, without jargon. Where you reach
for jargon and cannot find the plain-language version, you do not
understand it yet. Return to the source. Repeat.

Applied to .NET:

```
1. Learn: read the source of Dictionary<K,V> TryGetValue
2. Explain (write in your notes):
   "TryGetValue computes the hash of the key, then uses fast modulo
    to find the bucket index. It walks the entries starting at that
    bucket until it finds a matching key or an empty slot. If found,
    it writes to the out parameter and returns true. If the key is not
    found, out is set to default(TValue) and it returns false."
3. Identify the gap:
   "I said 'fast modulo' but I don't know what that means. Back to source."
4. Fill the gap, re-explain.
```

When you can explain it completely in plain language, you own it.

### What to Write Down

Not everything — that creates overwhelming notes you never read. Write:

**The non-obvious thing.** Not "List.Add adds an item" — that is obvious.
"List<T> doubles capacity when it fills, so repeated single-item adds
amortise to O(1) even though each resize is O(n)."

**The trap.** "If you materialise a LINQ query with ToList() inside a
foreach loop, you evaluate the query N+1 times. Materialise before the loop."

**The mental model.** "CancellationToken is cooperative, not preemptive.
The cancellation check must be explicit — the thread is not interrupted."

**The connection.** "IQueryable<T> uses expression trees (Ch 4 §4.7)
rather than compiled delegates. This is why you cannot call arbitrary
C# methods inside a LINQ-to-EF query — the database cannot execute them."

---

## 6b.11 The Developer's Toolkit for Discovery — Summary

```
Tool                    Use                                 Install
──────────────────────────────────────────────────────────────────────
LINQPad                 .NET scratchpad, rich output        linqpad.net
SharpLab                See compiler/JIT output             sharplab.io
dotnet-script           Run .csx files with NuGet           dotnet tool install -g dotnet-script
BenchmarkDotNet         Measure, not guess                  NuGet: BenchmarkDotNet
ILSpy                   Decompile closed-source assemblies  github.com/icsharpcode/ILSpy
Rider decompiler        Step into any assembly              Built into Rider
source.dot.net          Browse BCL source with search       source.dot.net
dotnet/runtime GitHub   The actual BCL source               github.com/dotnet/runtime
Polyglot Notebooks      Literate exploration in VS Code     VS Code extension
dotnet-repl             Quick terminal REPL                 dotnet tool install -g dotnet-repl
```

```
Source                  Best for
──────────────────────────────────────────────────────────────────────
Official docs           API signatures, parameter meanings
GitHub source           Internal implementation, design rationale
GitHub issues           Why it works this way, edge case handling
Library tests           Every feature with a working example
Andrew Lock blog        ASP.NET Core internals
Steven Cleary blog      Async/await, threading correctness
Nick Chapsas YouTube    Practical benchmarks, new .NET features
devblogs.microsoft.com  Release rationale, feature design
sharplab.io             What C# syntax compiles to
```

---

## 6b.12 The Habits That Compound

Skills that pay compound interest over a career, in order of impact:

**Read source before reading blogs.** The source is authoritative. Blogs
are summaries with interpretation errors. Form your own model from
source, then validate it against blogs.

**Measure before optimising.** Every performance intuition you have is
probably wrong about at least one case. BenchmarkDotNet takes ten minutes
to set up and produces certainty. Arguments without benchmarks are not
about performance — they are about feelings.

**Break things deliberately.** The most memorable learning is watching
something fail in a way you predicted. Set up a race condition on purpose.
Trigger a GC at a specific point. Cause a deadlock. When you understand
how to create the bug, you understand how to avoid it.

**Keep a code journal.** Not a blog — a private file where you write
one paragraph per week about the non-obvious thing you learned. After
a year you have a personalised reference of the things that were hard
to learn the first time. The act of writing crystallises the understanding.

**Follow the issue tracker of the libraries you depend on.** Not all
issues — use GitHub's notification filters. Watch for issues labelled
`bug` or `breaking-change` in the libraries your production systems
depend on. Five minutes a week prevents production incidents.

**When you hit a bug, document the symptom AND the cause.** Not just
"fixed by adding ConfigureAwait(false)" but "async deadlock caused by
SynchronizationContext capture in WPF — await was resuming on the UI
thread which was blocked by .Result on the calling thread — lesson:
never block on async in sync context." The cause is what you need when
you see the symptom again in a different form.
