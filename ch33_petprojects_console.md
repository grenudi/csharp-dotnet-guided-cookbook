# Chapter 33 — Pet Projects I: Console Applications

> Each project here is complete, compiles, and runs. Difficulty
> increases through the chapter. Each section names the .NET concepts
> it exercises so you can cross-reference the Bible chapters that
> explain them.

---

## 33.1 Why Start With Console Apps

Console apps have zero ceremony. No framework, no middleware, no config
file, no DI container unless you add one. Every line of code is yours.
That makes them the perfect place to practise C# fundamentals.

```bash
dotnet new console -n MyApp
cd MyApp
dotnet run
```

---

## 33.2 Project 1 — Countdown Timer

**What it does:** Count down from N seconds, print each second, ring a
bell when done.

**Concepts:** `Task.Delay`, `CancellationToken`, `Console.Write`,
string interpolation, top-level statements (Ch 1 §1.5, Ch 8 §8.4)

```csharp
// dotnet new console -n CountdownTimer
// dotnet run -- 10

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

int seconds = args.Length > 0 && int.TryParse(args[0], out var n) ? n : 10;

Console.WriteLine($"Counting down from {seconds}s. Press Ctrl+C to cancel.");

for (int i = seconds; i > 0; i--)
{
    Console.Write($"\r  {i:00}s remaining...  ");
    try   { await Task.Delay(1000, cts.Token); }
    catch (OperationCanceledException) { Console.WriteLine("\nCancelled."); return; }
}

Console.Write("\r  0s — ");
Console.Write("\a");    // BEL character — terminal bell
Console.ForegroundColor = ConsoleColor.Green;
Console.WriteLine("Done! ✓           ");
Console.ResetColor();
```

**Run it:** `dotnet run -- 10`

---

## 33.3 Project 2 — Word and Line Counter

**What it does:** Read a text file (or stdin), count lines, words, and
characters. Accept multiple files. Print a summary table.

**Concepts:** `File.ReadAllLinesAsync`, `IAsyncEnumerable`, LINQ
(Ch 7 §7.9), string splitting, `Console.In`, piped stdin.

```csharp
// dotnet new console -n Wc
// echo "hello world" | dotnet run
// dotnet run -- file1.txt file2.txt

using System.Diagnostics;

var sw     = Stopwatch.StartNew();
var totals = new Counter();

// Accept files from args, or read stdin if no args
var sources = args.Length > 0
    ? args.Select(f => (Name: f, Lines: ReadFileAsync(f)))
    : [(Name: "<stdin>", Lines: ReadStdinAsync())];

Console.WriteLine($"{"Lines",8} {"Words",8} {"Chars",10}  File");
Console.WriteLine(new string('-', 42));

await foreach (var (name, lines) in ProcessSources(sources))
{
    Console.WriteLine($"{lines.LineCount,8} {lines.WordCount,8} {lines.CharCount,10}  {name}");
    totals.Add(lines);
}

if (args.Length > 1)
{
    Console.WriteLine(new string('-', 42));
    Console.WriteLine($"{totals.LineCount,8} {totals.WordCount,8} {totals.CharCount,10}  total");
}

Console.Error.WriteLine($"(Completed in {sw.ElapsedMilliseconds}ms)");

// ── Helpers ──────────────────────────────────────────────────────────────

async IAsyncEnumerable<string> ReadFileAsync(string path)
{
    await foreach (var line in File.ReadLinesAsync(path))
        yield return line;
}

async IAsyncEnumerable<string> ReadStdinAsync()
{
    string? line;
    while ((line = await Console.In.ReadLineAsync()) is not null)
        yield return line;
}

async IAsyncEnumerable<(string Name, Counter Lines)> ProcessSources(
    IEnumerable<(string Name, IAsyncEnumerable<string> Lines)> sources)
{
    foreach (var (name, linesEnum) in sources)
    {
        var counter = new Counter();
        await foreach (var line in linesEnum)
        {
            counter.LineCount++;
            counter.CharCount += line.Length + 1; // +1 for newline
            counter.WordCount += line.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        }
        yield return (name, counter);
    }
}

class Counter
{
    public int LineCount { get; set; }
    public int WordCount { get; set; }
    public int CharCount { get; set; }
    public void Add(Counter other)
    {
        LineCount += other.LineCount;
        WordCount += other.WordCount;
        CharCount += other.CharCount;
    }
}
```

---

## 33.4 Project 3 — Password Generator

**What it does:** Generate cryptographically secure passwords of
configurable length and character set. Print N passwords.

**Concepts:** `RandomNumberGenerator` (Ch 28 §28.8), `ReadOnlySpan<char>`,
const strings, argument parsing via `args`.

```csharp
// dotnet new console -n PassGen
// dotnet run -- --length 20 --count 5 --symbols

using System.Security.Cryptography;
using System.Text;

// ── Parse args ────────────────────────────────────────────────────────────
int    length  = GetArg("--length",  16);
int    count   = GetArg("--count",    5);
bool   symbols = args.Contains("--symbols");
bool   digits  = !args.Contains("--no-digits");
bool   upper   = !args.Contains("--no-upper");
bool   lower   = !args.Contains("--no-lower");

// Build character pool
var pool = new StringBuilder();
if (lower)   pool.Append("abcdefghijkmnopqrstuvwxyz");   // no l (looks like 1)
if (upper)   pool.Append("ABCDEFGHJKLMNPQRSTUVWXYZ");   // no I, O (look like 1, 0)
if (digits)  pool.Append("23456789");                    // no 0, 1
if (symbols) pool.Append("!@#$%^&*-_=+?");

if (pool.Length == 0) { Console.Error.WriteLine("No character set selected."); return 1; }

var chars = pool.ToString().AsSpan();

Console.WriteLine($"Generating {count} passwords ({length} chars each):\n");

for (int i = 0; i < count; i++)
{
    Console.WriteLine(GeneratePassword(chars, length));
}

return 0;

// ── Helpers ───────────────────────────────────────────────────────────────

static string GeneratePassword(ReadOnlySpan<char> pool, int length)
{
    var buf = new char[length];
    // Use cryptographically secure random — not System.Random
    // Bible ref: Ch 28 §28.8 — cryptographic randomness
    for (int i = 0; i < length; i++)
    {
        buf[i] = pool[RandomNumberGenerator.GetInt32(pool.Length)];
    }
    return new string(buf);
}

int GetArg(string name, int @default)
{
    var idx = Array.IndexOf(args, name);
    return idx >= 0 && idx + 1 < args.Length && int.TryParse(args[idx + 1], out var v)
        ? v : @default;
}
```

---

## 33.5 Project 4 — File Duplicate Finder

**What it does:** Walk a directory recursively, hash every file with
SHA256, group files that share a hash, print the duplicate groups.

**Concepts:** `Directory.EnumerateFiles`, `FileStream`, `SHA256`,
`IGrouping`, LINQ `GroupBy` (Ch 7 §7.9, Ch 12 §12.1, Ch 28)

```csharp
// dotnet new console -n FindDups
// dotnet run -- /path/to/scan

using System.Security.Cryptography;

var root = args.FirstOrDefault() ?? ".";
if (!Directory.Exists(root)) { Console.Error.WriteLine($"Not a directory: {root}"); return 1; }

Console.Error.WriteLine($"Scanning {root}…");

// Build hash → paths map
var byHash = new Dictionary<string, List<string>>();
long totalBytes = 0;
int  fileCount  = 0;

foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
{
    try
    {
        var hash = await HashFileAsync(file);
        if (!byHash.TryGetValue(hash, out var list))
        {
            list = new List<string>();
            byHash[hash] = list;
        }
        list.Add(file);
        totalBytes += new FileInfo(file).Length;
        fileCount++;
        Console.Error.Write($"\r  {fileCount} files scanned…   ");
    }
    catch (IOException) { /* skip locked files */ }
}

Console.Error.WriteLine();

// Print groups of duplicates
var dupGroups = byHash.Values.Where(g => g.Count > 1).ToList();

if (dupGroups.Count == 0)
{
    Console.WriteLine("No duplicates found.");
    return 0;
}

long wastedBytes = 0;
foreach (var group in dupGroups.OrderByDescending(g => g.Count))
{
    var size = new FileInfo(group[0]).Length;
    wastedBytes += size * (group.Count - 1);
    Console.WriteLine($"\n── {group.Count} copies ({FormatSize(size)} each) ──");
    foreach (var f in group) Console.WriteLine($"  {f}");
}

Console.WriteLine($"\n{dupGroups.Count} groups, {FormatSize(wastedBytes)} wasted.");
return 0;

static async Task<string> HashFileAsync(string path)
{
    await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read,
        FileShare.Read, bufferSize: 81920, useAsync: true);
    var hash = await SHA256.HashDataAsync(stream);
    return Convert.ToHexString(hash).ToLower();
}

static string FormatSize(long bytes) => bytes switch
{
    >= 1_073_741_824 => $"{bytes / 1_073_741_824.0:F1} GB",
    >= 1_048_576     => $"{bytes / 1_048_576.0:F1} MB",
    >= 1_024         => $"{bytes / 1_024.0:F1} KB",
    _                => $"{bytes} B",
};
```

---

## 33.6 Project 5 — Weather CLI

**What it does:** Hit the free Open-Meteo API, display current weather
and a 3-day forecast for a given city.

**Concepts:** `HttpClient`, `IHttpClientFactory`, `System.Text.Json`,
`JsonSerializerOptions`, record types (Ch 2 §2.6, Ch 13 §13.1)

```csharp
// dotnet new console -n WeatherCli
// dotnet add package Microsoft.Extensions.Http
// dotnet run -- Berlin

using System.Text.Json;
using System.Text.Json.Serialization;

var city = string.Join(" ", args.Length > 0 ? args : ["Berlin"]);

// Step 1: geocode (Open-Meteo geocoding API — free, no key needed)
using var http       = new HttpClient { BaseAddress = new Uri("https://geocoding-api.open-meteo.com") };
using var weatherHttp = new HttpClient { BaseAddress = new Uri("https://api.open-meteo.com") };

Console.WriteLine($"Looking up coordinates for '{city}'…");

var geoResponse = await http.GetFromJsonAsync<GeoResponse>(
    $"/v1/search?name={Uri.EscapeDataString(city)}&count=1&language=en&format=json");

var location = geoResponse?.Results?.FirstOrDefault();
if (location is null) { Console.Error.WriteLine($"City not found: {city}"); return 1; }

Console.WriteLine($"📍 {location.Name}, {location.Country} ({location.Lat:F2}°N, {location.Lon:F2}°E)\n");

// Step 2: get current + daily forecast
var url = $"/v1/forecast" +
    $"?latitude={location.Lat}&longitude={location.Lon}" +
    $"&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code" +
    $"&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code" +
    $"&timezone=auto&forecast_days=4";

var weather = await weatherHttp.GetFromJsonAsync<WeatherResponse>(url);
if (weather is null) { Console.Error.WriteLine("Weather API failed."); return 1; }

// Print current conditions
var c = weather.Current;
Console.WriteLine($"Now:  {WeatherIcon(c.WeatherCode)}  {c.Temperature:F1}°C  💧 {c.Humidity}%  💨 {c.WindSpeed:F1} km/h");
Console.WriteLine();

// Print 3-day forecast
Console.WriteLine("Forecast:");
var d = weather.Daily;
for (int i = 0; i < Math.Min(4, d.Time.Length); i++)
{
    var label = i == 0 ? "Today     " : i == 1 ? "Tomorrow  " : d.Time[i].ToString("dddd").PadRight(10);
    Console.WriteLine($"  {label}  {WeatherIcon(d.WeatherCode[i])}  " +
        $"{d.TempMin[i]:F0}°→{d.TempMax[i]:F0}°C  🌧 {d.Precipitation[i]:F1}mm");
}

return 0;

static string WeatherIcon(int code) => code switch
{
    0           => "☀️",
    1 or 2      => "🌤",
    3           => "☁️",
    45 or 48    => "🌫",
    51 or 53 or 55 or 61 or 63 or 65 or 80 or 81 or 82 => "🌧",
    71 or 73 or 75 or 77 or 85 or 86 => "❄️",
    95 or 96 or 99 => "⛈",
    _           => "🌡",
};

// ── DTOs ──────────────────────────────────────────────────────────────────
record GeoResponse([property: JsonPropertyName("results")] GeoResult[]? Results);
record GeoResult(
    [property: JsonPropertyName("name")]      string Name,
    [property: JsonPropertyName("country")]   string Country,
    [property: JsonPropertyName("latitude")]  double Lat,
    [property: JsonPropertyName("longitude")] double Lon);

record WeatherResponse(
    [property: JsonPropertyName("current")] CurrentWeather Current,
    [property: JsonPropertyName("daily")]   DailyForecast  Daily);

record CurrentWeather(
    [property: JsonPropertyName("temperature_2m")]          double Temperature,
    [property: JsonPropertyName("relative_humidity_2m")]    int    Humidity,
    [property: JsonPropertyName("wind_speed_10m")]          double WindSpeed,
    [property: JsonPropertyName("weather_code")]            int    WeatherCode);

record DailyForecast(
    [property: JsonPropertyName("time")]                 DateTime[] Time,
    [property: JsonPropertyName("temperature_2m_max")]   double[]   TempMax,
    [property: JsonPropertyName("temperature_2m_min")]   double[]   TempMin,
    [property: JsonPropertyName("precipitation_sum")]    double[]   Precipitation,
    [property: JsonPropertyName("weather_code")]         int[]      WeatherCode);
```

---

## 33.7 What to Build Next

These five projects exercised: async/await, LINQ, file I/O, HTTP, records,
span, cryptography, and stdin piping. The next chapter graduates to full
CLI tools with argument parsing, rich terminal output, and interactive menus.
