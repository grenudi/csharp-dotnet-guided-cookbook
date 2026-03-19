# Chapter 24 — Visual Studio 2022: Killer Features

Visual Studio 2022 is the Windows-native .NET IDE with deep OS integration, powerful debugging, and the best ASP.NET/Azure tooling available.

---

## 24.1 IntelliSense & Code Completion

### Full-Line IntelliSense (AI-Powered)

VS 2022 (v17.6+) includes **GitHub Copilot** integration and Microsoft's own IntelliCode:
- **Whole-line completion**: grays out an entire predicted line — press `Tab` to accept
- **IntelliCode** (free): ranks completions by what developers commonly write next
- **GitHub Copilot** (subscription): multi-line suggestions, docstring generation, test generation

### Quick Info (`Ctrl+K, Ctrl+I` or hover)

Shows type info, documentation summary, and parameter details for any symbol.

### Signature Help (`Ctrl+Shift+Space`)

Shows all overloads of a method and highlights the current parameter.

---

## 24.2 Quick Actions & Refactoring (`Ctrl+.`)

**`Ctrl+.`** is VS's equivalent of Rider's `Alt+Enter`. Shows all available:
- Code fixes (fix errors/warnings)
- Refactorings
- Quick actions (generate code, convert expressions)

### Key Quick Actions

| Trigger | Action |
|---------|--------|
| `Ctrl+.` on `if` | Convert to switch expression / pattern matching |
| `Ctrl+.` on `string` concat | Convert to interpolated string |
| `Ctrl+.` on lambda | Convert to local function |
| `Ctrl+.` on property | Generate backing field |
| `Ctrl+.` on class name | Add missing interface member implementations |
| `Ctrl+.` on `using` | Remove unnecessary usings |
| `Ctrl+.` on incomplete switch | Add all missing cases |

### Rename (`Ctrl+R, Ctrl+R` or `F2`)

Inline rename — renames across the solution with a preview before commit. Tracks string occurrences optionally.

### Extract Method (`Ctrl+R, Ctrl+M`)

Select code block → Extract Method. VS infers parameters and names.

### Extract Interface

*Right-click class → Quick Actions → Extract Interface* — creates `IMyClass` and implements it.

### Change Signature (`Ctrl+R, Ctrl+O`)

Add, remove, reorder parameters with automatic call-site updates.

---

## 24.3 Navigation

### Go to All (`Ctrl+T`)

The universal search: types, files, members, symbols, recent files. Fastest navigation shortcut in VS.

### Go to Definition (`F12`)

Jump to the source of a symbol. If no source is available, VS shows decompiled source (with ILSpy integration).

### Go to Implementation (`Ctrl+F12`)

For interfaces and virtual members — jumps directly to concrete implementation(s).

### Peek Definition (`Alt+F12`)

Opens the definition **inline** as a floating window — no navigation, see and edit without leaving current context.

### Find All References (`Shift+F12` or `Ctrl+K, Ctrl+R`)

Lists all usages in the *Find Symbol Results* pane with file/line context.

### Navigate Forward/Backward (`Ctrl+-` / `Ctrl+Shift+-`)

Like browser back/forward — navigate through your editing history.

### Solution Explorer Filters

In the Solution Explorer, use the search box to filter files. Right-click → *Open Containing Folder*, *Copy Full Path*.

---

## 24.4 Debugging — Deep Features

### DataTips and Variable Inspection

Hover any variable during debugging to see its value. Click the 📌 icon to pin it to the editor — the value persists across steps.

**Nested expansion**: expand objects, collections, and LINQ results inline.

### Watch Windows

| Window | Purpose |
|--------|---------|
| **Watch 1-4** (`Ctrl+Alt+W, 1-4`) | Evaluate and monitor expressions continuously |
| **Autos** | Variables in current/prev statement automatically |
| **Locals** | All local variables in current scope |
| **Immediate** (`Ctrl+Alt+I`) | REPL — evaluate expressions, call methods, change values |

### Immediate Window (REPL)

During a debug break:
```
? user.Name              → "Alice"
? orders.Count(o => o.Total > 100)  → 3
user.Name = "Bob"        → changes the variable live
await repo.SaveAsync()   → you can even await!
```

### Conditional Breakpoints

Right-click breakpoint → *Conditions*:
```csharp
// Condition
userId == 42 && order.Total > 100

// Hit Count: break every 10 hits
// Dependent on: break only after another breakpoint was hit
```

### Tracepoints (Non-breaking)

Right-click → *Actions*:
```
Log: "Order {order.Id} processed, total: {order.Total}"
```
Logs to Output window without stopping execution — great for timing and flow tracing.

### Exception Settings (`Ctrl+Alt+E`)

*Debug → Windows → Exception Settings*:
- **Break when thrown**: break on any throw, even caught exceptions
- Check `Common Language Runtime Exceptions` → `System.NullReferenceException` to always break on NPE
- Checkbox per exception type

### Step Back (Enterprise edition)

*Debug → Step Backward* — literally step backward in execution. Useful for understanding what led to a bug state.

### Snapshot Debugging (Azure)

For production debugging: attach to Azure App Service and take a **snapshot** when an exception occurs — no restart, no performance impact.

### Parallel Stacks (`Ctrl+Shift+D, S`)

*Debug → Windows → Parallel Stacks*: visual display of all thread stacks simultaneously. Identify which threads are blocked, waiting, or running. Click any frame to jump to it.

### Tasks Window (`Ctrl+Shift+D, K`)

*Debug → Windows → Tasks*: shows all active `Task` objects and their states (Running, Awaiting, Scheduled, Faulted). Essential for async debugging.

### CPU Usage Profiler (During Debug)

*Debug → Performance Profiler → CPU Usage*: runs alongside your debug session. Click "Take Sample" to capture a flame graph at any point.

---

## 24.5 Hot Reload

### Code Hot Reload (`Alt+F10`)

While the app is running (debug or run), change code and apply without restarting:
- Method bodies: always supported
- New methods: supported
- Class structure changes: limited
- Works with: ASP.NET Core, MAUI, Console apps, WPF

```csharp
// Change this while running:
private string Greet(string name) => $"Hello, {name}!";
// to:
private string Greet(string name) => $"Bonjour, {name}!";
// Press Alt+F10 → change takes effect immediately
```

### XAML Hot Reload (MAUI / WPF)

Change XAML and see it update live on the running device/emulator.

### Blazor Hot Reload

Change Razor components while the browser is open — updates propagate immediately via SignalR.

---

## 24.6 Code Analysis & Analyzers

### Run Code Analysis

*Analyze → Run Code Analysis → On Solution*: runs all Roslyn analyzers.

Output shows warnings with rule IDs (`CA1234`). Click any warning to jump to the code.

### Suppress Warnings

```csharp
#pragma warning disable CA1822 // Mark members as static
private void MyMethod() { }
#pragma warning restore CA1822

// Or with SuppressMessage attribute
[System.Diagnostics.CodeAnalysis.SuppressMessage("Performance", "CA1822")]
private void MyMethod() { }
```

### EditorConfig Integration

VS reads `.editorconfig` for naming rules, indentation, and style. *Tools → Options → Text Editor → C# → Code Style* lets you configure and export `.editorconfig`.

### .editorconfig Violation Fixes

VS shows rule violations with light bulbs. `Ctrl+.` → *Fix all occurrences in → Solution*.

---

## 24.7 Live Unit Testing (Enterprise)

*Test → Live Unit Testing → Start*:
- Continuously runs affected unit tests as you type
- Shows green ✓ / red ✗ / grey ⊘ icons in the editor gutter per line
- Click an icon to see which tests cover that line and their status

---

## 24.8 IntelliTest (Enterprise)

*Right-click method → Create IntelliTest*: automatically generates test inputs that cover all code paths.

---

## 24.9 Building & Publishing

### Build Output

*View → Output → Build* — full MSBuild output. Search for `error` or `warning`.

### Build Configuration Manager

*Build → Configuration Manager*: manage Debug/Release configurations per project.

### Publish Profiles

*Right-click project → Publish*:
- Folder, FTP, Azure App Service, Docker container
- Settings: Framework-dependent vs self-contained, single-file, trimmed
- Saves as `.pubxml` files for repeatable publishing

```xml
<!-- Properties/PublishProfiles/FolderProfile.pubxml -->
<Project ToolsVersion="4.0">
  <PropertyGroup>
    <PublishProtocol>FileSystem</PublishProtocol>
    <Configuration>Release</Configuration>
    <Platform>Any CPU</Platform>
    <TargetFramework>net9.0</TargetFramework>
    <PublishDir>bin\Release\net9.0\publish\</PublishDir>
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>linux-x64</RuntimeIdentifier>
    <PublishSingleFile>true</PublishSingleFile>
    <PublishTrimmed>true</PublishTrimmed>
  </PropertyGroup>
</Project>
```

---

## 24.10 Azure & Docker Integration

### Azure Tools

*View → Cloud Explorer* (or install Azure Toolkit extension):
- Browse and manage Azure resources
- Deploy directly to App Service, Functions, Container Apps
- Stream live application logs from Azure

### Docker Support

*Right-click project → Add → Docker Support*:
- Generates optimized `Dockerfile`
- `docker-compose.yml` for multi-service projects
- Debug directly in a Docker container (`F5` → runs in container)

### Containers Window

*View → Other Windows → Containers*: manage running Docker containers, view logs, inspect environment variables.

---

## 24.11 Productivity Shortcuts Summary

| Action | Shortcut |
|--------|----------|
| Quick action / fix | `Ctrl+.` |
| Go to All | `Ctrl+T` |
| Go to definition | `F12` |
| Peek definition | `Alt+F12` |
| Go to implementation | `Ctrl+F12` |
| Find all references | `Shift+F12` |
| Rename | `Ctrl+R, R` |
| Extract method | `Ctrl+R, M` |
| Navigate back | `Ctrl+-` |
| Navigate forward | `Ctrl+Shift+-` |
| Immediate window | `Ctrl+Alt+I` |
| Breakpoint conditions | right-click → Conditions |
| Exception settings | `Ctrl+Alt+E` |
| Parallel stacks | `Ctrl+Shift+D, S` |
| Tasks window | `Ctrl+Shift+D, K` |
| Hot reload | `Alt+F10` |
| Format document | `Ctrl+K, D` |
| Comment lines | `Ctrl+K, C` |
| Uncomment lines | `Ctrl+K, U` |
| Surround with | `Ctrl+K, S` |
| Collapse all | `Ctrl+M, O` |
| Expand all | `Ctrl+M, P` |
| Toggle outlining | `Ctrl+M, M` |
| Duplicate line | `Ctrl+D` |
| Move line up | `Alt+Up` |
| Move line down | `Alt+Down` |
| Multiple cursors | `Alt+Shift+click` |
| Box selection | `Shift+Alt+drag` |
| Select all occurrences | `Ctrl+Shift+Alt+N` (Copilot) |

---

## 24.12 Useful Extensions

| Extension | Purpose |
|-----------|---------|
| **GitHub Copilot** | AI completion, chat, test generation |
| **ReSharper** | Full JetBrains refactoring engine (subscription) |
| **OzCode** | Magic wand debugging visualizations |
| **Fine Code Coverage** | Coverage highlighting for Community/Pro |
| **EF Core Power Tools** | Visual DB schema, reverse engineering |
| **SQLite Toolbox** | Browse SQLite databases |
| **Markdown Editor** | Preview `.md` files |
| **Rainbow Braces** | Color-matched brackets |
| **Output Enhancer** | Color-code build output |
| **VSColorOutput** | Color regex rules for output window |

