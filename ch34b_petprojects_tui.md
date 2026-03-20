# Chapter 34b — Pet Projects IIb: Interactive Terminal UI (TUI)

> A CLI tool is invoked and exits. An interactive TUI stays running and
> responds to user input, redraws the screen, tracks state, and feels
> like a real application — all inside a terminal. This chapter builds
> three projects that span the spectrum from a simple prompt loop to a
> full live-updating dashboard.

**Concepts exercised:** Ch 2 (records), Ch 3 (pattern matching), Ch 7 (LINQ,
Dictionary), Ch 8 (async/await, PeriodicTimer, Channels), Ch 10 (IOptions),
Ch 12 (file I/O), Ch 15a (SQLite), Ch 29 (Strategy pattern for menu actions)

```bash
dotnet add package Spectre.Console
dotnet add package Spectre.Console.Cli
dotnet add package Microsoft.Data.Sqlite
```

---

## 34b.1 The Mental Model: Spectre.Console as the Rendering Engine

`Console.Write` is append-only — you can write but not erase. Spectre
gives you two tools that break that constraint:

```
AnsiConsole.Live(table)       — re-renders a renderable on a timer
AnsiConsole.Status()          — spinner + message while work runs
AnsiConsole.Progress()        — one or more progress bars
AnsiConsole.Prompt<T>()       — blocking input with validation
SelectionPrompt<T>            — arrow-key menu
MultiSelectionPrompt<T>       — checkbox list
```

The golden rule: **never mix `Console.Write` with Spectre** in the same
block. Spectre owns the terminal. Use `AnsiConsole.Write` / `MarkupLine`
for everything.

---

## 34b.2 Project: `budgettui` — A Personal Finance Tracker

**What it does:** add income/expense entries, categorise them, view a
live summary table that updates as you type. Data persists in SQLite.

```bash
dotnet new console -n budgettui
cd budgettui
dotnet add package Spectre.Console
dotnet add package Microsoft.Data.Sqlite
```

### Domain

```csharp
// Models.cs
public enum EntryType { Income, Expense }

public record Entry(
    int    Id,
    string Description,
    string Category,
    decimal Amount,
    EntryType Type,
    DateTime OccurredAt
);
```

### Persistence — Plain ADO.NET on SQLite

```csharp
// Database.cs
using Microsoft.Data.Sqlite;

public class Database : IDisposable
{
    private readonly SqliteConnection _conn;

    public Database(string path)
    {
        _conn = new SqliteConnection($"Data Source={path}");
        _conn.Open();
        Migrate();
    }

    private void Migrate()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS entries (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                description TEXT NOT NULL,
                category    TEXT NOT NULL,
                amount      REAL NOT NULL,
                type        TEXT NOT NULL,
                occurred_at TEXT NOT NULL
            );
            """;
        cmd.ExecuteNonQuery();
    }

    public void Insert(string description, string category,
                       decimal amount, EntryType type)
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = """
            INSERT INTO entries (description, category, amount, type, occurred_at)
            VALUES ($desc, $cat, $amount, $type, $at);
            """;
        cmd.Parameters.AddWithValue("$desc",   description);
        cmd.Parameters.AddWithValue("$cat",    category);
        cmd.Parameters.AddWithValue("$amount", (double)amount);
        cmd.Parameters.AddWithValue("$type",   type.ToString());
        cmd.Parameters.AddWithValue("$at",     DateTime.UtcNow.ToString("O"));
        cmd.ExecuteNonQuery();
    }

    public IReadOnlyList<Entry> GetAll()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM entries ORDER BY occurred_at DESC";
        using var reader = cmd.ExecuteReader();

        var result = new List<Entry>();
        while (reader.Read())
        {
            result.Add(new Entry(
                reader.GetInt32(0),
                reader.GetString(1),
                reader.GetString(2),
                (decimal)reader.GetDouble(3),
                Enum.Parse<EntryType>(reader.GetString(4)),
                DateTime.Parse(reader.GetString(5))
            ));
        }
        return result;
    }

    public void Dispose() => _conn.Dispose();
}
```

### Main Menu Loop

```csharp
// Program.cs
using Spectre.Console;

var dbPath = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
    ".budgettui", "budget.db");

Directory.CreateDirectory(Path.GetDirectoryName(dbPath)!);
using var db = new Database(dbPath);

while (true)
{
    AnsiConsole.Clear();
    PrintSummary(db);

    var choice = AnsiConsole.Prompt(
        new SelectionPrompt<string>()
            .Title("[bold]What would you like to do?[/]")
            .AddChoices("Add income", "Add expense",
                        "View all entries", "Exit"));

    switch (choice)
    {
        case "Add income":  AddEntry(db, EntryType.Income);  break;
        case "Add expense": AddEntry(db, EntryType.Expense); break;
        case "View all entries": ViewEntries(db); break;
        case "Exit": return;
    }
}
```

### Printing the Summary Table

```csharp
static void PrintSummary(Database db)
{
    var entries  = db.GetAll();
    var income   = entries.Where(e => e.Type == EntryType.Income).Sum(e => e.Amount);
    var expenses = entries.Where(e => e.Type == EntryType.Expense).Sum(e => e.Amount);
    var balance  = income - expenses;

    var balanceColor = balance >= 0 ? "green" : "red";

    AnsiConsole.Write(new Panel(
        $"[green]Income:[/]   {income,10:C}\n" +
        $"[red]Expenses:[/] {expenses,10:C}\n" +
        $"[bold {balanceColor}]Balance:  {balance,10:C}[/]")
        .Header("[bold]Budget Summary[/]")
        .Expand()
        .RoundedBorder());

    // Category breakdown table
    var byCategory = entries
        .GroupBy(e => e.Category)
        .Select(g => (
            Category: g.Key,
            Total: g.Sum(e => e.Type == EntryType.Income ? e.Amount : -e.Amount)
        ))
        .OrderByDescending(x => Math.Abs(x.Total))
        .Take(5);

    var table = new Table().Expand().RoundedBorder();
    table.AddColumn("Category");
    table.AddColumn(new TableColumn("Amount").RightAligned());

    foreach (var (cat, total) in byCategory)
    {
        var color  = total >= 0 ? "green" : "red";
        table.AddRow(cat, $"[{color}]{total:C}[/]");
    }

    AnsiConsole.Write(table);
}
```

### Adding an Entry

```csharp
static void AddEntry(Database db, EntryType type)
{
    var typeLabel = type == EntryType.Income ? "[green]income[/]" : "[red]expense[/]";
    AnsiConsole.MarkupLine($"\n[bold]Add {typeLabel}[/]");

    var description = AnsiConsole.Prompt(
        new TextPrompt<string>("Description:")
            .ValidationErrorMessage("[red]Description cannot be empty.[/]")
            .Validate(s => !string.IsNullOrWhiteSpace(s)));

    var category = AnsiConsole.Prompt(
        new TextPrompt<string>("Category:")
            .DefaultValue("Uncategorised"));

    var amount = AnsiConsole.Prompt(
        new TextPrompt<decimal>("Amount:")
            .ValidationErrorMessage("[red]Enter a positive number.[/]")
            .Validate(a => a > 0));

    db.Insert(description, category, amount, type);
    AnsiConsole.MarkupLine("[green]✓ Entry saved.[/]");
    Thread.Sleep(800);   // brief confirmation before redraw
}
```

### Viewing All Entries with Pagination

```csharp
static void ViewEntries(Database db)
{
    const int pageSize = 15;
    var entries = db.GetAll();

    if (entries.Count == 0)
    {
        AnsiConsole.MarkupLine("[yellow]No entries yet.[/]");
        AnsiConsole.Prompt(new TextPrompt<string>("Press Enter to continue.")
            .AllowEmpty());
        return;
    }

    var pages = (int)Math.Ceiling(entries.Count / (double)pageSize);
    var page  = 0;

    while (true)
    {
        AnsiConsole.Clear();
        var slice = entries.Skip(page * pageSize).Take(pageSize);

        var table = new Table().Expand().RoundedBorder();
        table.AddColumn("Date");
        table.AddColumn("Description");
        table.AddColumn("Category");
        table.AddColumn(new TableColumn("Amount").RightAligned());
        table.AddColumn("Type");

        foreach (var e in slice)
        {
            var amtColor = e.Type == EntryType.Income ? "green" : "red";
            table.AddRow(
                e.OccurredAt.ToLocalTime().ToString("yyyy-MM-dd"),
                e.Description,
                e.Category,
                $"[{amtColor}]{e.Amount:C}[/]",
                e.Type.ToString());
        }

        AnsiConsole.Write(table);
        AnsiConsole.MarkupLine($"[grey]Page {page + 1} / {pages}[/]");

        var nav = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .AddChoices(
                    page > 0        ? "← Previous" : null,
                    page < pages - 1 ? "→ Next"     : null,
                    "← Back to menu")
                .WherePossible(s => s is not null)!);

        if (nav.StartsWith("←") && nav.Contains("Back"))  break;
        if (nav.StartsWith("→"))  page++;
        if (nav.StartsWith("←") && !nav.Contains("Back")) page--;
    }
}
```

---

## 34b.3 Project: `syswatch` — Live System Dashboard

**What it does:** redraws every second showing CPU, memory, top processes,
disk usage. Pure Spectre.Console `Live` rendering.

```bash
dotnet new console -n syswatch
cd syswatch
dotnet add package Spectre.Console
```

```csharp
// Program.cs
using System.Diagnostics;
using Spectre.Console;

// ── Sample system metrics ──────────────────────────────────────────
static float GetCpuPercent()
{
    using var proc = Process.GetCurrentProcess();
    // Real implementation uses PerformanceCounter (Windows)
    // or /proc/stat parsing (Linux). Simplified here:
    return Random.Shared.NextSingle() * 100f;
}

static (long Used, long Total) GetMemory()
{
    var info = GC.GetGCMemoryInfo();
    return (info.MemoryLoadBytes, info.TotalAvailableMemoryBytes);
}

// ── Dashboard ──────────────────────────────────────────────────────
var layout = new Layout("Root")
    .SplitRows(
        new Layout("Header"),
        new Layout("Body").SplitColumns(
            new Layout("Left"),
            new Layout("Right")));

await AnsiConsole.Live(layout)
    .AutoClear(false)
    .StartAsync(async ctx =>
    {
        while (!Console.KeyAvailable)
        {
            var cpu   = GetCpuPercent();
            var (used, total) = GetMemory();
            var usedMb  = used  / 1_048_576.0;
            var totalMb = total / 1_048_576.0;

            // Header panel
            layout["Header"].Update(
                new Panel($"[bold]syswatch[/] — {DateTime.Now:HH:mm:ss}")
                    .Expand()
                    .NoBorder());

            // CPU bar chart
            var cpuChart = new BarChart()
                .Width(40)
                .AddItem("CPU", Math.Round(cpu, 1), Color.Green);
            layout["Left"].Update(
                new Panel(cpuChart).Header("[bold]CPU %[/]").Expand());

            // Memory bar
            var memRatio    = usedMb / totalMb;
            var memColor    = memRatio > 0.8 ? Color.Red
                            : memRatio > 0.5 ? Color.Yellow
                            : Color.Green;
            var memBarWidth = 30;
            var filled      = (int)(memRatio * memBarWidth);
            var bar         = new string('█', filled) + new string('░', memBarWidth - filled);

            layout["Right"].Update(
                new Panel($"[{memColor}]{bar}[/]\n{usedMb:N0} / {totalMb:N0} MB")
                    .Header("[bold]Memory[/]")
                    .Expand());

            ctx.Refresh();
            await Task.Delay(TimeSpan.FromSeconds(1));
        }
    });

AnsiConsole.MarkupLine("[grey]Exited.[/]");
```

**Key techniques:**
- `Layout` splits the terminal into named regions
- `AnsiConsole.Live(layout)` owns the whole terminal, redraws only changed regions
- `ctx.Refresh()` triggers the redraw
- `Console.KeyAvailable` lets you exit with any keypress without blocking

---

## 34b.4 Project: `wizardform` — Multi-Step Input Wizard

**What it does:** guides the user through a multi-step form with
validation, branching (different questions based on previous answers),
and a final confirmation review before committing.

```csharp
// Models.cs
public record ServerConfig(
    string  Hostname,
    int     Port,
    bool    UseTls,
    string? CertPath,   // only asked when UseTls = true
    string  Username,
    string  Environment // dev | staging | prod
);
```

```csharp
// Program.cs
using Spectre.Console;

AnsiConsole.Write(
    new FigletText("Server Setup")
        .LeftJustified()
        .Color(Color.Blue));

AnsiConsole.MarkupLine("[grey]Answer each question. Press Ctrl+C to cancel.[/]\n");

// ── Step 1: Hostname ───────────────────────────────────────────────
var hostname = AnsiConsole.Prompt(
    new TextPrompt<string>("Hostname or IP:")
        .Validate(h =>
            Uri.CheckHostName(h) != UriHostNameType.Unknown
                ? ValidationResult.Success()
                : ValidationResult.Error("[red]Enter a valid hostname or IP.[/]")));

// ── Step 2: Port ───────────────────────────────────────────────────
var port = AnsiConsole.Prompt(
    new TextPrompt<int>("Port:")
        .DefaultValue(443)
        .Validate(p => p is > 0 and <= 65535
            ? ValidationResult.Success()
            : ValidationResult.Error("[red]Port must be 1–65535.[/]")));

// ── Step 3: TLS — branching ────────────────────────────────────────
var useTls = AnsiConsole.Confirm("Use TLS?", defaultValue: true);

string? certPath = null;
if (useTls)
{
    certPath = AnsiConsole.Prompt(
        new TextPrompt<string?>("[grey]Path to certificate (leave blank to use system trust):[/]")
            .AllowEmpty()
            .Validate(p => string.IsNullOrEmpty(p) || File.Exists(p)
                ? ValidationResult.Success()
                : ValidationResult.Error("[red]File not found.[/]")));
}

// ── Step 4: Credentials ────────────────────────────────────────────
var username = AnsiConsole.Prompt(new TextPrompt<string>("Username:"));

var password = AnsiConsole.Prompt(
    new TextPrompt<string>("Password:")
        .Secret());          // masks input with *

// ── Step 5: Environment ────────────────────────────────────────────
var env = AnsiConsole.Prompt(
    new SelectionPrompt<string>()
        .Title("Target environment:")
        .AddChoices("dev", "staging", "prod"));

// ── Review ─────────────────────────────────────────────────────────
AnsiConsole.WriteLine();
var review = new Table().RoundedBorder().Expand();
review.AddColumn("Setting");
review.AddColumn("Value");
review.AddRow("Hostname",    hostname);
review.AddRow("Port",        port.ToString());
review.AddRow("TLS",         useTls ? "[green]yes[/]" : "[red]no[/]");
review.AddRow("Certificate", certPath ?? "[grey](system trust)[/]");
review.AddRow("Username",    username);
review.AddRow("Environment", env == "prod" ? "[red bold]prod[/]" : env);
AnsiConsole.Write(review);

if (!AnsiConsole.Confirm("\nSave this configuration?"))
{
    AnsiConsole.MarkupLine("[yellow]Cancelled.[/]");
    return;
}

// ── Save ───────────────────────────────────────────────────────────
var config = new ServerConfig(hostname, port, useTls, certPath, username, env);
var json = System.Text.Json.JsonSerializer.Serialize(config,
    new System.Text.Json.JsonSerializerOptions { WriteIndented = true });

var cfgPath = Path.Combine(AppContext.BaseDirectory, "server.json");
File.WriteAllText(cfgPath, json);
AnsiConsole.MarkupLine($"[green]✓ Saved to[/] [link]{cfgPath}[/]");
```

**Key techniques:**
- `TextPrompt<T>` with `Validate` callback — runs on every submission
- `Secret()` masks password input
- `AllowEmpty()` makes the prompt optional
- `AnsiConsole.Confirm` — yes/no with default
- Branching: standard `if` on a prompt result
- `FigletText` — large ASCII art title

---

## 34b.5 Spectre.Console Survival Reference

### Markup

```csharp
AnsiConsole.MarkupLine("[bold red]Error:[/] something went wrong");
AnsiConsole.MarkupLine("[link=https://example.com]Click me[/]");
// Escape user input before embedding in markup:
var safe = Markup.Escape(userInput);
AnsiConsole.MarkupLine($"You entered: {safe}");
```

### Prompts

```csharp
// Text with default
var name = AnsiConsole.Prompt(new TextPrompt<string>("Name:").DefaultValue("Alice"));

// Validated int
var age = AnsiConsole.Prompt(
    new TextPrompt<int>("Age:").Validate(a => a > 0 && a < 150));

// Secret (password)
var pwd = AnsiConsole.Prompt(new TextPrompt<string>("Password:").Secret());

// Single-select menu
var choice = AnsiConsole.Prompt(
    new SelectionPrompt<string>().Title("Choose:").AddChoices("A", "B", "C"));

// Multi-select checkbox list
var selected = AnsiConsole.Prompt(
    new MultiSelectionPrompt<string>()
        .Title("Select features:")
        .AddChoices("Logging", "Auth", "Caching", "Metrics"));
```

### Progress

```csharp
await AnsiConsole.Progress()
    .StartAsync(async ctx =>
    {
        var task = ctx.AddTask("[green]Downloading[/]", maxValue: 100);
        while (!ctx.IsFinished)
        {
            await Task.Delay(50);
            task.Increment(2);
        }
    });
```

### Status Spinner

```csharp
await AnsiConsole.Status()
    .Spinner(Spinner.Known.Dots)
    .StartAsync("Connecting...", async ctx =>
    {
        await Task.Delay(2000);
        ctx.Status("Authenticating...");
        await Task.Delay(1000);
    });
```

### Tables

```csharp
var table = new Table()
    .Border(TableBorder.Rounded)
    .AddColumn(new TableColumn("Name").LeftAligned())
    .AddColumn(new TableColumn("Score").RightAligned());

table.AddRow("Alice", "[green]98[/]");
table.AddRow("Bob",   "[yellow]74[/]");
AnsiConsole.Write(table);
```

### Tree

```csharp
var root = new Tree("src/");
var core = root.AddNode("[blue]Core[/]");
core.AddNode("Domain/");
core.AddNode("Services/");
root.AddNode("[green]Api[/]");
AnsiConsole.Write(root);
```
