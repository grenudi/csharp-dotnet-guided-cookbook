# Chapter 12 — IO: Streams, Pipelines & File System

## 12.1 File and Directory Operations

```csharp
// File — static convenience methods (for small files)
string   text = File.ReadAllText("data.txt");
string[] lines = File.ReadAllLines("data.txt");
byte[]   bytes = File.ReadAllBytes("image.png");

File.WriteAllText("out.txt", "Hello, World!");
File.WriteAllLines("out.txt", new[] { "line 1", "line 2", "line 3" });
File.WriteAllBytes("out.bin", buffer);

// Append
File.AppendAllText("log.txt", $"[{DateTime.Now}] Event happened\n");

// Copy / Move / Delete
File.Copy("src.txt", "dst.txt", overwrite: true);
File.Move("old.txt", "new.txt", overwrite: true);
File.Delete("unwanted.txt");

// Existence
bool exists = File.Exists("data.txt");

// Metadata
DateTime created  = File.GetCreationTimeUtc("data.txt");
DateTime modified = File.GetLastWriteTimeUtc("data.txt");
long size = new FileInfo("data.txt").Length;

// Directory
Directory.CreateDirectory("path/to/dir");  // creates all intermediate dirs
Directory.Delete("path/to/dir", recursive: true);
bool dirExists = Directory.Exists("path");

// Enumerate (lazy — better for large dirs)
foreach (var file in Directory.EnumerateFiles("src", "*.cs", SearchOption.AllDirectories))
    Console.WriteLine(file);

foreach (var dir in Directory.EnumerateDirectories("src", "*", SearchOption.TopDirectoryOnly))
    Console.WriteLine(dir);

// Path manipulation
string full   = Path.GetFullPath("../file.txt");
string dir2   = Path.GetDirectoryName("/a/b/c.txt")!; // "/a/b"
string name   = Path.GetFileName("/a/b/c.txt");        // "c.txt"
string noExt  = Path.GetFileNameWithoutExtension("/a/b/c.txt"); // "c"
string ext    = Path.GetExtension("/a/b/c.txt");       // ".txt"
string joined = Path.Combine("a", "b", "c.txt");       // "a/b/c.txt" (OS-aware)
string temp   = Path.GetTempFileName();                 // creates temp file
string tempDir = Path.GetTempPath();

// OS-independent path separator
char sep = Path.DirectorySeparatorChar; // '\' on Windows, '/' on Linux
```

---

## 12.2 Streams

The `Stream` class is the base for all streaming I/O.

### FileStream — Low-Level File Access

```csharp
// Read file in chunks — for large files
await using var fs = new FileStream("large.bin",
    FileMode.Open,
    FileAccess.Read,
    FileShare.Read,
    bufferSize: 65536,          // 64KB buffer
    useAsync: true);            // use IOCP (async I/O)

var buffer = new byte[65536];
int bytesRead;
while ((bytesRead = await fs.ReadAsync(buffer, 0, buffer.Length)) > 0)
{
    ProcessChunk(buffer.AsSpan(0, bytesRead));
}

// Modern Memory<byte> overload
while ((bytesRead = await fs.ReadAsync(buffer.AsMemory())) > 0)
{
    Process(buffer.AsSpan(0, bytesRead));
}

// Write file
await using var writer = new FileStream("out.bin", FileMode.Create, FileAccess.Write,
    FileShare.None, 65536, true);
await writer.WriteAsync(data.AsMemory());
await writer.FlushAsync();
```

### StreamReader / StreamWriter — Text

```csharp
// Read text file
await using var reader = new StreamReader("data.txt", Encoding.UTF8,
    detectEncodingFromByteOrderMarks: true);

// Line by line
string? line;
while ((line = await reader.ReadLineAsync()) is not null)
{
    ProcessLine(line);
}

// Or (C# 13+) — ReadLinesAsync
await foreach (var l in File.ReadLinesAsync("data.txt"))
    ProcessLine(l);

// All text
string all = await reader.ReadToEndAsync();

// Write text
await using var sw = new StreamWriter("out.txt", append: false, Encoding.UTF8);
await sw.WriteLineAsync("First line");
await sw.WriteAsync("No newline");
await sw.FlushAsync();
```

### MemoryStream

```csharp
// In-memory stream — good for testing and buffering
using var ms = new MemoryStream();
using var sw = new StreamWriter(ms, Encoding.UTF8, leaveOpen: true);
await sw.WriteLineAsync("Hello");
await sw.FlushAsync();

ms.Seek(0, SeekOrigin.Begin); // rewind
using var sr = new StreamReader(ms, Encoding.UTF8);
string text = await sr.ReadToEndAsync(); // "Hello\n"

// Get underlying array
byte[] bytes = ms.ToArray();
ReadOnlyMemory<byte> mem = ms.GetBuffer().AsMemory(0, (int)ms.Length);
```

### BinaryReader / BinaryWriter — Typed Primitives

```csharp
// Write binary data
await using var fs = new FileStream("data.bin", FileMode.Create);
using var bw = new BinaryWriter(fs, Encoding.UTF8, leaveOpen: true);
bw.Write(42);           // int (4 bytes)
bw.Write(3.14f);        // float (4 bytes)
bw.Write("hello");      // length-prefixed string
bw.Write(true);         // bool (1 byte)

// Read binary data
fs.Seek(0, SeekOrigin.Begin);
using var br = new BinaryReader(fs, Encoding.UTF8, leaveOpen: true);
int n    = br.ReadInt32();
float f  = br.ReadSingle();
string s = br.ReadString();
bool b   = br.ReadBoolean();
```

### Compression

```csharp
using System.IO.Compression;

// GZip compress
await using var fs = new FileStream("out.gz", FileMode.Create);
await using var gz = new GZipStream(fs, CompressionLevel.Optimal);
await using var sw = new StreamWriter(gz);
await sw.WriteAsync(largeText);

// GZip decompress
await using var fs2 = new FileStream("out.gz", FileMode.Open);
await using var gz2 = new GZipStream(fs2, CompressionMode.Decompress);
await using var sr  = new StreamReader(gz2);
string decompressed = await sr.ReadToEndAsync();

// In-memory compression
using var compressed = new MemoryStream();
using (var gz3 = new GZipStream(compressed, CompressionLevel.Fastest, leaveOpen: true))
    await gz3.WriteAsync(sourceBytes);
byte[] result = compressed.ToArray();

// ZipArchive — work with ZIP files
using var archive = ZipFile.OpenRead("archive.zip");
foreach (var entry in archive.Entries)
{
    using var entryStream = entry.Open();
    // process entryStream
}

// Create ZIP
using var newZip = ZipFile.Open("new.zip", ZipArchiveMode.Create);
newZip.CreateEntryFromFile("file.txt", "file.txt", CompressionLevel.Optimal);
```

---

## 12.3 System.IO.Pipelines

Pipelines provide high-performance, low-allocation I/O. Used internally by ASP.NET Core, Kestrel, gRPC.

```csharp
using System.IO.Pipelines;

// Basic pipe
var pipe = new Pipe();

// Writer side
async Task ProduceAsync(PipeWriter writer)
{
    for (int i = 0; i < 100; i++)
    {
        var buffer = writer.GetMemory(256);  // request buffer
        int written = Encode(i, buffer.Span); // write into buffer
        writer.Advance(written);             // tell writer how much we wrote

        var flush = await writer.FlushAsync();
        if (flush.IsCompleted) break;
    }
    await writer.CompleteAsync();
}

// Reader side
async Task ConsumeAsync(PipeReader reader)
{
    while (true)
    {
        var result = await reader.ReadAsync();
        var buffer = result.Buffer;

        while (TryReadLine(ref buffer, out ReadOnlySequence<byte> line))
        {
            ProcessLine(line);
        }

        reader.AdvanceTo(buffer.Start, buffer.End);

        if (result.IsCompleted) break;
    }
    await reader.CompleteAsync();
}

bool TryReadLine(ref ReadOnlySequence<byte> buffer, out ReadOnlySequence<byte> line)
{
    var position = buffer.PositionOf((byte)'\n');
    if (position == null) { line = default; return false; }
    line = buffer.Slice(0, position.Value);
    buffer = buffer.Slice(buffer.GetPosition(1, position.Value));
    return true;
}

// Wire up
var producer = ProduceAsync(pipe.Writer);
var consumer = ConsumeAsync(pipe.Reader);
await Task.WhenAll(producer, consumer);

// Stream to PipeReader adapter
PipeReader fromStream = PipeReader.Create(networkStream, new StreamPipeReaderOptions(
    bufferSize: 65536,
    minimumReadSize: 4096,
    leaveOpen: false));
```

---

## 12.4 FileSystemWatcher

```csharp
using var watcher = new FileSystemWatcher("./sync-root")
{
    NotifyFilter = NotifyFilters.FileName
                 | NotifyFilters.DirectoryName
                 | NotifyFilters.LastWrite
                 | NotifyFilters.Size,
    Filter = "*",                    // all files
    IncludeSubdirectories = true,
    EnableRaisingEvents = true,      // must be true to start watching
    InternalBufferSize = 65536,      // increase to reduce missed events (default 8192)
};

watcher.Created += (sender, e) =>
    Console.WriteLine($"Created: {e.FullPath}");

watcher.Changed += (sender, e) =>
    Console.WriteLine($"Changed: {e.FullPath}");

watcher.Deleted += (sender, e) =>
    Console.WriteLine($"Deleted: {e.FullPath}");

watcher.Renamed += (sender, e) =>
    Console.WriteLine($"Renamed: {e.OldFullPath} → {e.FullPath}");

watcher.Error += (sender, e) =>
{
    var ex = e.GetException();
    Console.Error.WriteLine($"Watcher error: {ex.Message}");
    // InternalBufferOverflowException means events were dropped — rescan!
    if (ex is InternalBufferOverflowException)
        TriggerFullRescan();
};
```

### Debounced File Watcher

```csharp
// Debounce rapid-fire events (e.g., save triggers 5 events for same file)
public class DebouncedWatcher : IDisposable
{
    private readonly FileSystemWatcher _watcher;
    private readonly ConcurrentDictionary<string, Timer> _timers = new();
    private readonly TimeSpan _delay;
    private readonly Action<string> _onChange;

    public DebouncedWatcher(string path, TimeSpan delay, Action<string> onChange)
    {
        _delay = delay;
        _onChange = onChange;
        _watcher = new FileSystemWatcher(path)
        {
            IncludeSubdirectories = true,
            EnableRaisingEvents = true,
            InternalBufferSize = 65536,
        };
        _watcher.Changed += OnChange;
        _watcher.Created += OnChange;
    }

    private void OnChange(object sender, FileSystemEventArgs e)
    {
        var timer = _timers.AddOrUpdate(e.FullPath,
            _ => new Timer(Callback, e.FullPath, _delay, Timeout.InfiniteTimeSpan),
            (_, t) => { t.Change(_delay, Timeout.InfiniteTimeSpan); return t; });
    }

    private void Callback(object? state)
    {
        var path = (string)state!;
        _timers.TryRemove(path, out var t);
        t?.Dispose();
        _onChange(path);
    }

    public void Dispose()
    {
        _watcher.Dispose();
        foreach (var t in _timers.Values) t.Dispose();
    }
}
```

---

## 12.5 Path Utilities and Cross-Platform Paths

```csharp
// Never hardcode path separators
// BAD:
string path = "data" + "/" + "file.txt"; // fails on Windows with backslash mismatch
// GOOD:
string path2 = Path.Combine("data", "file.txt"); // uses OS separator

// Special folders
string home     = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
string appData  = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
string desktop  = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
string docDir   = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
string tempDir2 = Path.GetTempPath(); // /tmp on Linux, %TEMP% on Windows

// Relative to executable
string exeDir = AppContext.BaseDirectory;
string config = Path.Combine(AppContext.BaseDirectory, "appsettings.json");

// Glob patterns — use Microsoft.Extensions.FileSystemGlobbing
using Microsoft.Extensions.FileSystemGlobbing;
var matcher = new Matcher();
matcher.AddInclude("**/*.cs");
matcher.AddExclude("**/obj/**");
matcher.AddExclude("**/bin/**");

var results = matcher.GetResultsInFullPath("./src");
foreach (var file in results) Console.WriteLine(file);
```

---

## 12.6 Serialization

### System.Text.Json (Built-in, Fast)

```csharp
using System.Text.Json;
using System.Text.Json.Serialization;

// Serialize
var user = new User { Name = "Alice", Age = 30 };
string json = JsonSerializer.Serialize(user);
// {"name":"Alice","age":30}

string prettyJson = JsonSerializer.Serialize(user, new JsonSerializerOptions
{
    WriteIndented = true,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
});

// Deserialize
User? user2 = JsonSerializer.Deserialize<User>(json);
var userFromJson = JsonSerializer.Deserialize<User>("{\"name\":\"Bob\",\"age\":25}");

// From stream (efficient — no string intermediate)
await using var fs = new FileStream("data.json", FileMode.Open);
User? fromFile = await JsonSerializer.DeserializeAsync<User>(fs);

// Source generation (NET 7+ — AOT-friendly, faster)
[JsonSerializable(typeof(User))]
[JsonSerializable(typeof(List<User>))]
internal partial class UserJsonContext : JsonSerializerContext { }

string json2 = JsonSerializer.Serialize(user, UserJsonContext.Default.User);
User? u = JsonSerializer.Deserialize(json2, UserJsonContext.Default.User);

// Custom converter
public class DateOnlyJsonConverter : JsonConverter<DateOnly>
{
    public override DateOnly Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions opts)
        => DateOnly.Parse(reader.GetString()!);

    public override void Write(Utf8JsonWriter writer, DateOnly value, JsonSerializerOptions opts)
        => writer.WriteStringValue(value.ToString("yyyy-MM-dd"));
}

// Register
var opts = new JsonSerializerOptions();
opts.Converters.Add(new DateOnlyJsonConverter());
```

### JsonSerializerOptions — Recommended Configuration

```csharp
// App-wide shared options (create once, reuse)
public static class JsonOptions
{
    public static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web)
    {
        // JsonSerializerDefaults.Web:
        // - CamelCase property names
        // - case-insensitive deserialization
        // - number tolerant (accepts string "42" as int)
    };

    public static readonly JsonSerializerOptions Strict = new()
    {
        PropertyNamingPolicy        = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        WriteIndented               = false,
        DefaultIgnoreCondition      = JsonIgnoreCondition.WhenWritingNull,
        Converters =
        {
            new JsonStringEnumConverter(JsonNamingPolicy.CamelCase),
            new DateOnlyJsonConverter(),
        }
    };
}
```

> **Rider tip:** *Tools → Postfix Templates* → type `.toJson` after an object to get a snippet that calls `JsonSerializer.Serialize()`. Also, *Rider → HTTP Client* (`Tools → HTTP Client`) lets you send requests and inspect JSON responses without leaving the IDE.

> **VS tip:** *Edit → Paste Special → Paste JSON as Classes* automatically generates C# record/class definitions from JSON. Very useful when integrating with external APIs.

