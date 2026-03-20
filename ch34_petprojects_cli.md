# Chapter 34 — Pet Projects II: CLI Tools with System.CommandLine & Spectre.Console

> A proper CLI tool handles subcommands, flags, help text, tab
> completion, and readable output. This chapter shows two libraries
> that make all of that easy.

---

## 34.1 The Two Libraries You Need

**System.CommandLine** — Microsoft's library for argument parsing,
help generation, and tab completion. Handles the plumbing.

**Spectre.Console** — Rich terminal output: colours, tables, trees,
progress bars, spinners, live dashboards, interactive prompts.

```bash
dotnet add package System.CommandLine --prerelease
dotnet add package Spectre.Console
dotnet add package Spectre.Console.Cli   # integrates both
```

---

## 34.2 Project 1 — `todocli`: A Task Manager

**What it does:** A command-line to-do list backed by a JSON file.
Subcommands: `add`, `done`, `list`, `remove`.

**Concepts:** `System.CommandLine`, `Option<T>`, `Argument<T>`,
`RootCommand`, `System.Text.Json`, file I/O, ANSI colours.

```csharp
// dotnet new console -n todocli
// dotnet add package System.CommandLine --prerelease
// dotnet add package Spectre.Console

using System.CommandLine;
using System.Text.Json;
using Spectre.Console;

// ── State file ────────────────────────────────────────────────────────────
var stateFile = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
    ".todocli.json");

List<TodoItem> LoadTodos()
{
    if (!File.Exists(stateFile)) return [];
    return JsonSerializer.Deserialize<List<TodoItem>>(File.ReadAllText(stateFile)) ?? [];
}

void SaveTodos(List<TodoItem> items)
    => File.WriteAllText(stateFile, JsonSerializer.Serialize(items, new JsonSerializerOptions { WriteIndented = true }));

// ── Root command ──────────────────────────────────────────────────────────
var root = new RootCommand("todocli — a minimal task manager");

// ── 'list' subcommand ─────────────────────────────────────────────────────
var listCmd = new Command("list", "Show all tasks")
{
    new Option<bool>("--all",  "-a", description: "Show completed tasks too"),
    new Option<bool>("--done", "-d", description: "Show only completed tasks"),
};
listCmd.SetHandler((all, done) =>
{
    var items = LoadTodos();
    var filtered = items.Where(i =>
        done ? i.Done :
        all  ? true  :
        !i.Done).ToList();

    if (filtered.Count == 0)
    {
        AnsiConsole.MarkupLine("[grey]No tasks.[/]");
        return;
    }

    var table = new Table()
        .Border(TableBorder.Rounded)
        .AddColumn(new TableColumn("ID").RightAligned())
        .AddColumn("Task")
        .AddColumn("Created");

    foreach (var item in filtered)
    {
        var id    = $"[grey]{item.Id}[/]";
        var text  = item.Done ? $"[strikethrough grey]{item.Text}[/]" : $"[white]{item.Text}[/]";
        var check = item.Done ? "[green]✓[/]" : "[yellow]○[/]";
        var date  = item.CreatedAt.ToString("yyyy-MM-dd");
        table.AddRow(id, $"{check} {text}", $"[grey]{date}[/]");
    }

    AnsiConsole.Write(table);
    AnsiConsole.MarkupLine($"[grey]{filtered.Count} task(s)[/]");
},
    listCmd.Options.OfType<Option<bool>>().First(o => o.Name == "all"),
    listCmd.Options.OfType<Option<bool>>().First(o => o.Name == "done"));
root.AddCommand(listCmd);

// ── 'add' subcommand ──────────────────────────────────────────────────────
var textArg = new Argument<string[]>("text", "Task description") { Arity = ArgumentArity.OneOrMore };
var addCmd  = new Command("add", "Add a new task") { textArg };
addCmd.SetHandler(textArr =>
{
    var text  = string.Join(" ", textArr);
    var items = LoadTodos();
    var id    = items.Count > 0 ? items.Max(i => i.Id) + 1 : 1;
    items.Add(new TodoItem(id, text, false, DateTime.UtcNow));
    SaveTodos(items);
    AnsiConsole.MarkupLine($"[green]Added[/] #{id}: {text}");
}, textArg);
root.AddCommand(addCmd);

// ── 'done' subcommand ─────────────────────────────────────────────────────
var idArg   = new Argument<int>("id", "Task ID");
var doneCmd = new Command("done", "Mark a task as completed") { idArg };
doneCmd.SetHandler(id =>
{
    var items = LoadTodos();
    var item  = items.FirstOrDefault(i => i.Id == id);
    if (item is null) { AnsiConsole.MarkupLine($"[red]Task #{id} not found.[/]"); return; }
    items[items.IndexOf(item)] = item with { Done = true };
    SaveTodos(items);
    AnsiConsole.MarkupLine($"[green]✓[/] Marked #{id} done: {item.Text}");
}, idArg);
root.AddCommand(doneCmd);

// ── 'remove' subcommand ───────────────────────────────────────────────────
var rmArg = new Argument<int>("id", "Task ID to remove");
var rmCmd = new Command("remove", "Remove a task") { rmArg };
rmCmd.AddAlias("rm");
rmCmd.SetHandler(id =>
{
    var items = LoadTodos();
    var item  = items.FirstOrDefault(i => i.Id == id);
    if (item is null) { AnsiConsole.MarkupLine($"[red]Not found: #{id}[/]"); return; }
    items.Remove(item);
    SaveTodos(items);
    AnsiConsole.MarkupLine($"[red]Removed[/] #{id}: {item.Text}");
}, rmArg);
root.AddCommand(rmCmd);

return await root.InvokeAsync(args);

record TodoItem(int Id, string Text, bool Done, DateTime CreatedAt);
```

**Usage:**

```bash
todocli add Buy milk
todocli add Write the README
todocli list
todocli done 1
todocli list --all
todocli rm 2
```

---

## 34.3 Project 2 — `sysinfo`: System Information Tool

**What it does:** Print machine information in a rich layout: OS,
CPU, RAM, disk. Show a live CPU usage bar that updates every second.

**Concepts:** `AnsiConsole.Live`, `BarChart`, `Panel`, `Rule`,
`Environment`, `DriveInfo`, background thread, `PeriodicTimer`.

```csharp
// dotnet new console -n sysinfo
// dotnet add package Spectre.Console

using System.Diagnostics;
using System.Runtime.InteropServices;
using Spectre.Console;

// ── Static info panel ─────────────────────────────────────────────────────
var grid = new Grid().AddColumns(2);

grid.AddRow(
    new Panel(new Markup(
        $"[bold]OS[/]\n[grey]{RuntimeInformation.OSDescription}[/]\n\n" +
        $"[bold]Arch[/]\n[grey]{RuntimeInformation.OSArchitecture}[/]\n\n" +
        $"[bold]Runtime[/]\n[grey]{RuntimeInformation.FrameworkDescription}[/]"))
        .Header("[blue]System[/]").Expand(),

    new Panel(new Markup(
        $"[bold]Hostname[/]\n[grey]{Environment.MachineName}[/]\n\n" +
        $"[bold]CPU Cores[/]\n[grey]{Environment.ProcessorCount}[/]\n\n" +
        $"[bold]Working Set[/]\n[grey]{FormatBytes(Environment.WorkingSet)}[/]"))
        .Header("[green]Process[/]").Expand()
);

AnsiConsole.Write(grid);
AnsiConsole.Write(new Rule("[yellow]Drives[/]"));

var driveTable = new Table()
    .Border(TableBorder.Simple)
    .AddColumn("Drive")
    .AddColumn(new TableColumn("Total").RightAligned())
    .AddColumn(new TableColumn("Free").RightAligned())
    .AddColumn(new TableColumn("Used %").RightAligned());

foreach (var drive in DriveInfo.GetDrives().Where(d => d.IsReady))
{
    var pct   = (double)(drive.TotalSize - drive.AvailableFreeSpace) / drive.TotalSize * 100;
    var color = pct > 90 ? "red" : pct > 70 ? "yellow" : "green";
    driveTable.AddRow(
        drive.Name, FormatBytes(drive.TotalSize),
        FormatBytes(drive.AvailableFreeSpace),
        $"[{color}]{pct:F0}%[/]");
}

AnsiConsole.Write(driveTable);
AnsiConsole.Write(new Rule("[yellow]Live CPU Usage[/]"));
AnsiConsole.MarkupLine("[grey](Press any key to stop)[/]\n");

// ── Live CPU bar ──────────────────────────────────────────────────────────
using var cts = new CancellationTokenSource();
_ = Task.Run(() => { Console.ReadKey(intercept: true); cts.Cancel(); });

var cpuCounter = OperatingSystem.IsWindows()
    ? new PerformanceCounter("Processor", "% Processor Time", "_Total")
    : null;

await AnsiConsole.Live(new BarChart().Width(60).Label("[grey]CPU %[/]"))
    .AutoClear(false)
    .StartAsync(async ctx =>
    {
        var history = new Queue<double>(maxCapacity: 20);
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));

        while (!cts.IsCancellationRequested && await timer.WaitForNextTickAsync(cts.Token).ConfigureAwait(false))
        {
            double cpu = GetCpuPercent(cpuCounter);
            history.Enqueue(cpu);
            if (history.Count > 20) history.Dequeue();

            var chart = new BarChart().Width(60).Label($"[grey]CPU % — last {history.Count}s[/]");
            int i = 1;
            foreach (var val in history)
            {
                var color = val > 80 ? "red" : val > 50 ? "yellow" : "green";
                chart.AddItem($"[grey]{i++,2}[/]", val, Color.FromConsoleColor(
                    val > 80 ? ConsoleColor.Red : val > 50 ? ConsoleColor.Yellow : ConsoleColor.Green));
            }
            ctx.UpdateTarget(chart);
        }
    });

AnsiConsole.MarkupLine("[grey]Done.[/]");

static double GetCpuPercent(PerformanceCounter? counter)
{
    if (counter is not null) return counter.NextValue();
    // Linux: parse /proc/stat (simplified)
    if (!File.Exists("/proc/stat")) return 0;
    var line = File.ReadLines("/proc/stat").FirstOrDefault(l => l.StartsWith("cpu "));
    if (line is null) return 0;
    var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
    if (parts.Length < 5) return 0;
    double user = double.Parse(parts[1]), nice = double.Parse(parts[2]),
           sys  = double.Parse(parts[3]), idle = double.Parse(parts[4]);
    double total = user + nice + sys + idle;
    return total == 0 ? 0 : (total - idle) / total * 100;
}

static string FormatBytes(long b) => b switch
{
    >= 1_073_741_824 => $"{b / 1_073_741_824.0:F1} GB",
    >= 1_048_576     => $"{b / 1_048_576.0:F1} MB",
    _ => $"{b / 1_024.0:F1} KB",
};
```

---

## 34.4 Project 3 — `difftool`: Compare Two Directories

**What it does:** Walk two directories, compare them, print a
diff-style summary: files only in left, only in right, modified in
both (by size+date).

**Concepts:** `IAsyncEnumerable`, `HashSet<T>`, `Dictionary<K,V>`,
`Spectre.Console` tree rendering.

```csharp
// dotnet new console -n difftool
// dotnet add package Spectre.Console

using Spectre.Console;

if (args.Length < 2)
{
    AnsiConsole.MarkupLine("[red]Usage: difftool <left-dir> <right-dir>[/]");
    return 1;
}

var (leftDir, rightDir) = (args[0], args[1]);

var left  = ScanDirectory(leftDir);
var right = ScanDirectory(rightDir);

var allPaths = left.Keys.Union(right.Keys).OrderBy(k => k);

var onlyLeft  = new List<string>();
var onlyRight = new List<string>();
var different = new List<string>();

foreach (var path in allPaths)
{
    bool inLeft  = left.TryGetValue(path,  out var lInfo);
    bool inRight = right.TryGetValue(path, out var rInfo);

    if (inLeft && !inRight)        onlyLeft.Add(path);
    else if (!inLeft && inRight)   onlyRight.Add(path);
    else if (lInfo!.Size != rInfo!.Size || Math.Abs((lInfo.Modified - rInfo.Modified).TotalSeconds) > 2)
                                   different.Add(path);
}

AnsiConsole.Write(new Rule($"[blue]{leftDir}[/]  vs  [blue]{rightDir}[/]"));

if (onlyLeft.Count == 0 && onlyRight.Count == 0 && different.Count == 0)
{
    AnsiConsole.MarkupLine("[green]✓ Directories are identical.[/]");
    return 0;
}

if (onlyLeft.Count > 0)
{
    AnsiConsole.MarkupLine($"\n[red]Only in LEFT ({onlyLeft.Count}):[/]");
    foreach (var p in onlyLeft) AnsiConsole.MarkupLine($"  [red]-[/] {p}");
}
if (onlyRight.Count > 0)
{
    AnsiConsole.MarkupLine($"\n[green]Only in RIGHT ({onlyRight.Count}):[/]");
    foreach (var p in onlyRight) AnsiConsole.MarkupLine($"  [green]+[/] {p}");
}
if (different.Count > 0)
{
    AnsiConsole.MarkupLine($"\n[yellow]Different ({different.Count}):[/]");
    foreach (var p in different) AnsiConsole.MarkupLine($"  [yellow]~[/] {p}");
}

AnsiConsole.MarkupLine($"\n[grey]Left: {left.Count} files · Right: {right.Count} files[/]");
return onlyLeft.Count + onlyRight.Count + different.Count;

static Dictionary<string, (long Size, DateTime Modified)> ScanDirectory(string dir)
{
    if (!Directory.Exists(dir)) { AnsiConsole.MarkupLine($"[red]Not found: {dir}[/]"); return []; }
    return Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories)
        .ToDictionary(
            f => Path.GetRelativePath(dir, f).Replace('\\', '/'),
            f => { var i = new FileInfo(f); return (i.Length, i.LastWriteTimeUtc); });
}
```

---

## 34.5 Spectre.Console Quick Reference

```csharp
// ── Markup language ───────────────────────────────────────────────────────
AnsiConsole.MarkupLine("[bold red]Error:[/] Something went wrong.");
AnsiConsole.MarkupLine("[blue underline]https://example.com[/]");
AnsiConsole.MarkupLine("[on green]background colour[/]");
AnsiConsole.MarkupLine("[grey50]dim text[/]");
// Escape square brackets:
AnsiConsole.MarkupLine(Markup.Escape("[not markup]"));

// ── Prompts ───────────────────────────────────────────────────────────────
var name = AnsiConsole.Ask<string>("What is your [green]name[/]?");
var age  = AnsiConsole.Ask<int>("Your age?");
var ok   = AnsiConsole.Confirm("Continue?");
var fruit = AnsiConsole.Prompt(
    new SelectionPrompt<string>()
        .Title("Choose a fruit")
        .AddChoices(["Apple", "Banana", "Cherry"]));
var fruits = AnsiConsole.Prompt(
    new MultiSelectionPrompt<string>()
        .Title("Choose fruits")
        .AddChoices(["Apple", "Banana", "Cherry"]));
var secret = AnsiConsole.Prompt(new TextPrompt<string>("Password:").Secret());

// ── Progress bars ─────────────────────────────────────────────────────────
await AnsiConsole.Progress()
    .StartAsync(async ctx =>
    {
        var task = ctx.AddTask("[green]Uploading[/]", maxValue: 100);
        while (!ctx.IsFinished)
        {
            await Task.Delay(50);
            task.Increment(2);
        }
    });

// ── Spinner ───────────────────────────────────────────────────────────────
await AnsiConsole.Status()
    .Spinner(Spinner.Known.Dots)
    .StartAsync("Working…", async ctx =>
    {
        ctx.Status("Step 1…");
        await Task.Delay(1000);
        ctx.Status("Step 2…");
        await Task.Delay(1000);
    });

// ── Table ─────────────────────────────────────────────────────────────────
var table = new Table()
    .Border(TableBorder.Rounded)
    .AddColumn(new TableColumn("Name").LeftAligned())
    .AddColumn(new TableColumn("Score").RightAligned());
table.AddRow("Alice", "98");
table.AddRow("[bold]Bob[/]", "[red]42[/]");
AnsiConsole.Write(table);

// ── Tree ──────────────────────────────────────────────────────────────────
var tree = new Tree("/home/user");
var docs = tree.AddNode("[blue]Documents[/]");
docs.AddNode("report.pdf");
docs.AddNode("notes.md");
AnsiConsole.Write(tree);

// ── Panel ─────────────────────────────────────────────────────────────────
AnsiConsole.Write(new Panel("[bold]Hello[/]\nWorld")
    .Header("[green]My Panel[/]")
    .BorderColor(Color.Blue)
    .Expand());
```
