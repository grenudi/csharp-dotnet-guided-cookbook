# Chapter 23 — JetBrains Rider: Killer Features

Rider is a cross-platform .NET IDE built on the IntelliJ platform with a full ReSharper engine embedded. This chapter covers the features that make experienced developers dramatically more productive.

---

## 23.1 Navigation

### Go To Everything (`Shift+Shift` / `⇧⇧`)

The most important shortcut. Opens a unified search over:
- Files, classes, symbols, methods, properties
- Recent files and locations
- Actions and settings
- Git branches, TODO items

**Power tips:**
- Type `User` → finds `User.cs`, `IUserRepository`, `UserService`
- Type `:42` → go to line 42 in current file
- Type `u/p:` → find property `p` in class `u`
- Type `#` → search only symbols

### Go To Declaration / Implementation

```
Ctrl+B / ⌘B              → Go to declaration (e.g., interface definition)
Ctrl+Alt+B / ⌘⌥B         → Go to implementation(s) — shows popup if multiple
Ctrl+U / ⌘U              → Go to base (parent class or overridden method)
Ctrl+Alt+U / ⌘⌥U         → Go to derived types (type hierarchy)
```

### Find Usages (`Alt+F7` / `⌥F7`)

Shows all usages of a symbol grouped by: Read, Write, Invocation, etc. The **Usages** tool window lets you see context without jumping.

**Advanced:**
- `Ctrl+Alt+F7` / `⌘⌥F7` → Find Usages Settings (include/exclude tests, generated code)
- Right-click a symbol → *Inspect → Incoming calls* — shows full call tree

### File Structure (`Ctrl+F12` / `⌘F12`)

Popup showing all members in the current file. Start typing to filter. Press `Enter` to jump. Stays open with `Alt+7` / `⌥7`.

### Recent Files / Locations

```
Ctrl+E / ⌘E        → Recent files (with search)
Ctrl+Shift+E / ⌘⇧E → Recent locations (shows code snippets)
```

### Bookmarks (`F11`)

```
F11                    → Toggle anonymous bookmark
Ctrl+F11 / ⌘F11       → Toggle mnemonic bookmark (assign a letter/number)
Shift+F11 / ⇧F11      → Show all bookmarks
Ctrl+[1-9]            → Jump to mnemonic bookmark
```

---

## 23.2 Editing & Refactoring

### Alt+Enter — The Action Menu

**The single most important key in Rider.** Position cursor on any highlighted code and press `Alt+Enter` / `⌥↩` to see every available action:
- Fix a warning or error
- Apply a code intention (e.g., "Convert to switch expression")
- Apply a refactoring
- Generate code
- Import a missing namespace

### Rename (`Shift+F6` / `⇧F6`)

Renames a symbol across the entire solution — including string usages, XML docs, and test method names. Preview changes before applying.

### Extract Method (`Ctrl+Alt+M` / `⌘⌥M`)

Select code → Extract Method. Rider infers parameters, return type, and names intelligently.

```csharp
// Before: selected code block
var total = items.Sum(x => x.Price * x.Quantity);
var tax = total * 0.19m;
var final = total + tax;

// After Extract Method → Rider generates:
private static decimal CalculateTotal(IEnumerable<OrderItem> items)
{
    var total = items.Sum(x => x.Price * x.Quantity);
    var tax = total * 0.19m;
    return total + tax;
}
```

### Extract Interface / Superclass (`Refactor → Extract Interface`)

Rider analyzes which members of a class could form an interface. Automatically implements the new interface on the original class.

### Inline (`Ctrl+Alt+N` / `⌘⌥N`)

Inline a method, variable, or property — replaces all usages with the body.

### Move / Copy (`F6` / `F5`)

Move a class to a different namespace or file. Rider updates all references automatically.

### Change Signature (`Ctrl+F6` / `⌘F6`)

Add, remove, reorder, or rename parameters. Rider updates all call sites.

### Safe Delete (`Alt+Delete` / `⌥⌦`)

Deletes a type/member only if it has no usages. If usages exist, shows them before proceeding.

### Introduce Variable / Field / Parameter

```
Ctrl+Alt+V / ⌘⌥V  → Introduce Variable
Ctrl+Alt+F / ⌘⌥F  → Introduce Field
Ctrl+Alt+P / ⌘⌥P  → Introduce Parameter
Ctrl+Alt+C / ⌘⌥C  → Introduce Constant
```

### Code Generation (`Alt+Insert` / `⌘N`)

Generate: constructor, properties, `Equals`/`GetHashCode`, `ToString`, `IDisposable`, `INotifyPropertyChanged`, delegating members, and more.

---

## 23.3 Code Analysis & Inspections

### Inspection Severity Levels

Rider runs hundreds of inspections continuously:
- **Error** (red) — won't compile or definite bug
- **Warning** (yellow) — likely bug (null dereference, unused variable)
- **Suggestion** (green wave) — code style improvement
- **Hint** (gray) — minor improvement

### Run Code Cleanup (`Ctrl+Alt+L` / `⌘⌥L`)

Applies configurable rules:
- Remove unused imports
- Apply code style (naming, braces, var vs explicit type)
- Reformat code
- Run custom inspections

Create a **Code Cleanup Profile**:
*Settings → Editor → Code Cleanup → Add Profile* — define which rules run.

### Structural Search and Replace

*Edit → Find → Search Structurally*

Find code patterns that match a shape:
```
Pattern: $x$.Where($y$).First($z$)
Replace: $x$.First($z$)  // more efficient
```

### Architecture Diagram

*Tools → Diagrams → Show Diagram* — visualizes class inheritance, dependencies.
*Analyze → Dependencies* — shows coupling between projects.

---

## 23.4 Debugging

### Smart Step Into (`Shift+F7` / `⇧F7`)

When stepping into a chained call, Rider shows a popup to choose which method to step into.

```csharp
var result = repo.GetAll().Where(x => x.IsActive).OrderBy(x => x.Name).First();
//                  ↑ step into GetAll?  Where?  OrderBy?  First?
// Smart Step Into shows a popup with all options
```

### Evaluate Expression (`Alt+F8` / `⌥F8`)

Evaluate any C# expression during debug, including LINQ queries, method calls, and assignments. Changes can be applied.

### Set Value

Right-click a variable in the debugger → *Set Value* — change a variable's value at runtime without restarting.

### Conditional Breakpoints

Right-click a breakpoint → *Edit Breakpoint*:
- **Condition**: `user.Age > 18 && user.Country == "DE"`
- **Log**: print an expression without stopping
- **Disable after hit count**: stop after N hits

### Exception Breakpoints

*Run → View Breakpoints → Add Exception Breakpoint*:
- Break on any `Exception` type
- Break on first chance (before catch) or unhandled
- Filter by exception type: `NullReferenceException`, `HttpRequestException`, etc.

### Memory View & Heap Explorer

*Debug → Windows → Memory* — inspect raw memory.
*Run → dotMemory Session* — attach dotMemory profiler, analyze object allocations.

### Async Stacks

When debugging async code, Rider shows the **logical async call chain** — not just the current thread's physical stack. The *Async Stacks* view shows the full continuation chain.

### Pin to Editor

Hover a variable → click the 🔍 pin icon. The variable's value shows inline in the editor as you step, without needing to look at the debug window.

### Step Through Code Without Source (`Decompile`)

When stepping into framework code without PDB symbols, Rider decompiles the code on-the-fly and steps through the decompiled source.

---

## 23.5 Documentation

### Quick Documentation (`Ctrl+Q` / `⌘J` on hover)

Shows XML doc summary, param descriptions, exceptions, and remarks for any symbol. No need to leave the editor.

### Parameter Info (`Ctrl+P` / `⌘P`)

Shows method signature and highlights the current parameter position as you type.

### External Documentation (`Shift+F1` / `⇧F1`)

Opens the official Microsoft docs page for the symbol in your browser.

### Generate XML Documentation

Position on any member → `Alt+Enter` → *Generate XML doc comment*:

```csharp
/// <summary>
/// Processes the order and sends a confirmation email.
/// </summary>
/// <param name="order">The order to process.</param>
/// <param name="ct">A cancellation token.</param>
/// <returns>The processed order ID.</returns>
/// <exception cref="ArgumentNullException">Thrown when order is null.</exception>
/// <exception cref="OrderException">Thrown when processing fails.</exception>
public async Task<int> ProcessAsync(Order order, CancellationToken ct = default)
```

---

## 23.6 Building and Running

### Multiple Run Configurations

*Run → Edit Configurations*:
- Define multiple configurations with different environment variables, arguments, working directories
- Compound configuration: run multiple projects simultaneously (API + Worker + UI)
- Docker configuration: build and run in container

```
API (Debug)         → src/MyApp.Api  env: Development  port: 5000
API (Production)    → src/MyApp.Api  env: Production    port: 8080
Worker              → src/MyApp.Worker  env: Development
Full Stack          → [Compound: API + Worker]
```

### Build and Inspect Warnings

*View → Tool Windows → Build* — all build output with clickable errors.
*Analyze → Inspect Code* — run all Roslyn analyzers offline.

### NuGet Window

*Tools → NuGet → Manage NuGet Packages* — search, install, update packages with version comparison.

---

## 23.7 Version Control & Git

### Git Log (`Alt+9` / `⌥9` or `Git → Log`)

Visual git history with branch graph, file diffs, and commit search.

### Annotate / Blame

Right-click in gutter → *Annotate with Git Blame* — shows who changed each line and when. Hover a commit to see the full diff.

### Resolve Conflicts

Rider's 3-way merge tool resolves conflicts with syntax highlighting. *Local / Base / Remote* panes with *Accept Left / Accept Right / Accept Both* buttons per conflict chunk.

### Shelve / Unshelve

*Git → Shelve Changes* — save changes without committing (Rider-native alternative to `git stash`).

---

## 23.8 HTTP Client (Built-In)

Create `.http` files for testing APIs without leaving Rider:

```http
### List all users
GET https://localhost:5000/api/users
Accept: application/json

### Create user
POST https://localhost:5000/api/users
Content-Type: application/json

{
  "name": "Alice",
  "email": "alice@example.com"
}

### Get user by ID
GET https://localhost:5000/api/users/{{userId}}
Authorization: Bearer {{token}}
```

*Run* each request individually. Responses shown with syntax-highlighted JSON.
Variables (`{{token}}`) defined in `http-client.env.json`.

---

## 23.9 Database Tool Window

*View → Tool Windows → Database*:
- Connect to PostgreSQL, MySQL, SQLite, SQL Server
- Browse schema, tables, views
- Run queries with IntelliSense
- Export query results as CSV, JSON, SQL INSERT
- View EF Core migration SQL preview

---

## 23.10 Essential Shortcuts Summary

| Action | Windows | macOS |
|--------|---------|-------|
| Search everywhere | `Shift+Shift` | `⇧⇧` |
| Alt+Enter (action) | `Alt+Enter` | `⌥↩` |
| Rename | `Shift+F6` | `⇧F6` |
| Extract method | `Ctrl+Alt+M` | `⌘⌥M` |
| Find usages | `Alt+F7` | `⌥F7` |
| Go to declaration | `Ctrl+B` | `⌘B` |
| Go to implementation | `Ctrl+Alt+B` | `⌘⌥B` |
| Go to base | `Ctrl+U` | `⌘U` |
| Quick doc | `Ctrl+Q` | `⌘J` |
| Reformat code | `Ctrl+Alt+L` | `⌘⌥L` |
| Recent files | `Ctrl+E` | `⌘E` |
| Run | `Shift+F10` | `⌘R` |
| Debug | `Shift+F9` | `⌘D` |
| Step over | `F8` | `F8` |
| Step into | `F7` | `F7` |
| Smart step into | `Shift+F7` | `⇧F7` |
| Evaluate expression | `Alt+F8` | `⌥F8` |
| Toggle breakpoint | `Ctrl+F8` | `⌘F8` |
| Conditional breakpoint | `Ctrl+Shift+F8` | `⌘⇧F8` |
| Surround with | `Ctrl+Alt+T` | `⌘⌥T` |
| Move statement up/down | `Ctrl+Shift+Up/Down` | `⌘⇧↑/↓` |
| Duplicate line | `Ctrl+D` | `⌘D` |
| Delete line | `Ctrl+Y` | `⌘⌫` |
| Multi-cursor | `Alt+Shift+Click` | `⌥⇧Click` |

