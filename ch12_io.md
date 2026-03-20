# Chapter 12 — IO: Streams, Pipelines & the File System

> Every useful program reads or writes something: files, network sockets,
> database connections, standard input/output. In .NET, all of these are
> expressed through a single abstraction: the Stream. Understanding
> streams is understanding how all I/O in .NET works. This chapter
> builds from the concept of a stream up through file operations,
> pipelines, and file watching.

*Building on:* Ch 2 (types, value vs reference, IDisposable), Ch 3
(`using` statements), Ch 8 (async/await — all I/O should be async)

---

## 12.1 What a Stream Is and Why It Exists

A stream is an abstraction over a sequence of bytes. The sequence might
come from a file on disk, from a network socket, from a database blob,
from memory, or from any other byte source. The key design insight is
that the consumer does not need to know the source — they just read
bytes, and the stream provides them.

This abstraction enables composition: you can wrap one stream in another.
A `GZipStream` wrapping a `FileStream` reads from a file and decompresses
on the fly. A `CryptoStream` wrapping a `NetworkStream` encrypts bytes as
they are sent over the network. Neither wrapper knows about the other's
source.

```
Your code
    ↓ reads/writes bytes
[CryptoStream]        ← encrypts/decrypts
    ↓ reads/writes bytes
[GZipStream]          ← compresses/decompresses
    ↓ reads/writes bytes
[BufferedStream]      ← buffers to reduce syscall count
    ↓ reads/writes bytes
[FileStream]          ← reads/writes the actual file on disk
```

```csharp
// The base class all streams extend
public abstract class Stream : IDisposable, IAsyncDisposable
{
    // Read bytes into a buffer
    public abstract int Read(byte[] buffer, int offset, int count);
    public abstract ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct);

    // Write bytes from a buffer
    public abstract void Write(byte[] buffer, int offset, int count);
    public abstract Task WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken ct);

    // Seek (if the stream supports random access)
    public abstract long Seek(long offset, SeekOrigin origin);
    public abstract long Position { get; set; }
    public abstract long Length   { get; }
    public abstract bool CanSeek  { get; }   // false for network streams
    public abstract bool CanRead  { get; }
    public abstract bool CanWrite { get; }
}
```

Not all streams are seekable. A `NetworkStream` is a fire-hose — bytes
arrive in order and cannot be re-read. A `FileStream` supports seeking
to any position. Always check `CanSeek` before calling `Seek`.

Always close streams (use `using` or `await using`) — they hold OS
file handles, network connections, or system resources that cannot be
garbage-collected.

---

## 12.2 FileStream — Reading and Writing Files

`FileStream` is the lowest-level way to work with files. For text,
`StreamReader` and `StreamWriter` wrap it and handle encoding. For
high-level file operations, `File` provides convenient static methods.

```csharp
// Reading a file — choose the right abstraction for your use case

// For small text files: simplest, loads entire file into memory
string text = await File.ReadAllTextAsync("config.json", ct);

// For large text files: line by line, no memory spike
await foreach (var line in File.ReadLinesAsync("large.log", ct))
    Process(line);    // each line processed immediately, not buffered

// For binary data: raw bytes
byte[] data = await File.ReadAllBytesAsync("image.png", ct);

// For streaming binary: process as data arrives, no full load
await using var fs = new FileStream("large.bin", FileMode.Open, FileAccess.Read,
    FileShare.Read, bufferSize: 4096, useAsync: true);
var buffer = new byte[4096];
int bytesRead;
while ((bytesRead = await fs.ReadAsync(buffer, ct)) > 0)
    await ProcessChunkAsync(buffer[..bytesRead], ct);
```

```csharp
// Writing files

// Simple text or binary
await File.WriteAllTextAsync("output.txt", content, ct);
await File.WriteAllBytesAsync("output.bin", data, ct);

// Streaming write — for large output that should not all be in memory at once
await using var output = new StreamWriter("output.txt", append: false, Encoding.UTF8);
await foreach (var record in GetRecordsAsync(ct))
    await output.WriteLineAsync(record.ToCsv());
// File is flushed and closed when StreamWriter is disposed

// Append to existing file
await using var log = File.AppendText("events.log");
await log.WriteLineAsync($"{DateTime.UtcNow:O} {message}");
```

### File Operations — `File`, `Directory`, `Path`

```csharp
// File existence and metadata
bool exists = File.Exists("myfile.txt");
var info    = new FileInfo("myfile.txt");
Console.WriteLine($"Size: {info.Length}, Modified: {info.LastWriteTime}");

// Copy, move, delete
File.Copy("source.txt", "dest.txt", overwrite: true);
File.Move("old.txt", "new.txt", overwrite: false);
File.Delete("temp.txt");

// Directory operations
Directory.CreateDirectory("output/reports");   // creates all intermediate dirs
var files = Directory.EnumerateFiles("logs", "*.log", SearchOption.AllDirectories);
Directory.Delete("old-output", recursive: true);

// Path manipulation — always use Path, never string concatenation
string full    = Path.Combine("/home/user", "docs", "report.pdf");
string dir     = Path.GetDirectoryName(full)!;   // /home/user/docs
string name    = Path.GetFileName(full);          // report.pdf
string noExt   = Path.GetFileNameWithoutExtension(full); // report
string ext     = Path.GetExtension(full);         // .pdf
string temp    = Path.GetTempPath();              // OS temp directory
string tmpFile = Path.GetTempFileName();          // creates a temp file, returns path
```

---

## 12.3 `StreamReader` and `StreamWriter` — Text Streams

File systems store bytes. Text has encoding. `StreamReader`/`StreamWriter`
bridge the gap — they decode bytes to characters using a specified
encoding (UTF-8 by default):

```csharp
// Read CSV with explicit encoding
await using var reader = new StreamReader("data.csv", Encoding.UTF8);
string? line;
while ((line = await reader.ReadLineAsync(ct)) is not null)
{
    var columns = line.Split(',');
    // ...
}

// Write JSON with BOM (some legacy systems require it)
await using var writer = new StreamWriter("output.json",
    new FileStreamOptions { Mode = FileMode.Create, Access = FileAccess.Write },
    new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));  // UTF-8 with BOM
await writer.WriteAsync(jsonContent);
```

---

## 12.4 `System.IO.Pipelines` — High-Throughput IO

`System.IO.Pipelines` (introduced in .NET Core 2.1) is designed for
writing high-throughput network servers and parsers. The BCL's `Stream`
API has an ergonomic friction: you must provide a buffer, read into it,
then parse it. Tracking positions, handling partial reads, and managing
buffer reuse is complex and error-prone.

Pipelines solve this with two abstractions:
- `PipeWriter` — the producer writes data into the pipe
- `PipeReader` — the consumer reads data from the pipe in chunks, telling
  the pipe which bytes it has consumed

The system manages buffer allocation and reuse automatically:

```csharp
// Parse a line-delimited text stream efficiently
static async Task ParseLinesAsync(PipeReader reader, CancellationToken ct)
{
    while (true)
    {
        ReadResult result = await reader.ReadAsync(ct);
        ReadOnlySequence<byte> buffer = result.Buffer;

        while (TryReadLine(ref buffer, out ReadOnlySequence<byte> line))
        {
            ProcessLine(line);   // work with the line without copying
        }

        // Tell the pipe we consumed everything up to here
        reader.AdvanceTo(buffer.Start, buffer.End);

        if (result.IsCompleted) break;  // no more data
    }
    await reader.CompleteAsync();
}

static bool TryReadLine(ref ReadOnlySequence<byte> buffer, out ReadOnlySequence<byte> line)
{
    var position = buffer.PositionOf((byte)'\n');
    if (position == null)
    {
        line = default;
        return false;
    }
    line = buffer.Slice(0, position.Value);
    buffer = buffer.Slice(buffer.GetPosition(1, position.Value));
    return true;
}
```

Pipelines are used internally by ASP.NET Core's Kestrel server to parse
HTTP requests at very high throughput. You rarely write pipeline code
directly in application code, but understanding it explains why Kestrel
is fast.

---

## 12.5 `FileSystemWatcher` — Reacting to File System Changes

Rather than polling a directory for changes, `FileSystemWatcher` uses the
OS's notification mechanism (inotify on Linux, ReadDirectoryChangesW on
Windows, FSEvents on macOS) to get notified immediately when a file is
created, modified, deleted, or renamed.

```csharp
// Watch a directory for changes
using var watcher = new FileSystemWatcher("/var/data/uploads")
{
    Filter                = "*.csv",               // only CSV files
    IncludeSubdirectories = false,
    NotifyFilter          = NotifyFilters.FileName
                          | NotifyFilters.LastWrite
                          | NotifyFilters.Size,
    EnableRaisingEvents   = true
};

// Events fire on a background thread — must be thread-safe
watcher.Created += async (_, e) =>
{
    // New file appeared — wait briefly for the write to complete
    await Task.Delay(500);   // debounce
    await ProcessFileAsync(e.FullPath, CancellationToken.None);
};

watcher.Changed += (_, e) =>
    Console.WriteLine($"Modified: {e.FullPath}");

watcher.Error += (_, e) =>
    Console.WriteLine($"Watch error: {e.GetException().Message}");

// Keep the program alive
await Task.Delay(Timeout.Infinite);
```

### Debouncing — The Essential Pattern

File editors typically save a file in multiple write operations. Without
debouncing, you receive multiple `Changed` events for a single logical
save. The standard fix is to delay processing until changes have settled:

```csharp
// Debounce: only process after 500ms of no new events for the same file
private readonly Dictionary<string, CancellationTokenSource> _pending = new();

void OnChanged(string path)
{
    if (_pending.TryGetValue(path, out var existingCts))
        existingCts.Cancel();  // cancel any pending process for this file

    var cts = new CancellationTokenSource();
    _pending[path] = cts;

    _ = Task.Delay(500, cts.Token)
            .ContinueWith(t =>
            {
                if (!t.IsCanceled)
                    ProcessFile(path);
            });
}
```

Chapter 35 (Pet Projects III — Daemons) builds a complete file watcher
daemon using this pattern with `Channel<T>` to decouple detection from
processing.

---

## 12.6 Serialisation — Turning Objects into Bytes and Back

Serialisation is the process of converting an object to a byte sequence
(for storage or transmission) and deserialisation is the reverse. .NET
provides two main serialisers: `System.Text.Json` (built-in, fast,
AOT-compatible) and Newtonsoft.Json (third-party, more flexible).

### `System.Text.Json` — The Modern Standard

```csharp
// Serialise to JSON
var order = new Order { Id = 1, Customer = "Alice", Total = 99.99m };
string json = JsonSerializer.Serialize(order, new JsonSerializerOptions
{
    WriteIndented        = true,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase  // { "id": 1, "customer": "Alice" }
});

// Deserialise from JSON
Order? restored = JsonSerializer.Deserialize<Order>(json);

// Stream-based — avoids loading entire JSON string into memory
await using var stream = File.OpenRead("data.json");
var items = await JsonSerializer.DeserializeAsync<List<Order>>(stream, ct: ct);

// Source generation — faster startup, AOT-compatible
[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(List<Order>))]
public partial class OrderJsonContext : JsonSerializerContext { }

// Use with the source-generated context
var json2 = JsonSerializer.Serialize(order, OrderJsonContext.Default.Order);
```

### Custom Converters

For types that do not serialise naturally (enums as strings, custom date
formats, domain primitives):

```csharp
public class MoneyJsonConverter : JsonConverter<Money>
{
    public override Money Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions opts)
    {
        var text = reader.GetString()!;  // "9.99 EUR"
        var parts = text.Split(' ');
        return new Money(decimal.Parse(parts[0]), parts[1]);
    }

    public override void Write(Utf8JsonWriter writer, Money value, JsonSerializerOptions opts) =>
        writer.WriteStringValue($"{value.Amount:F2} {value.Currency}");
}

// Register
var opts = new JsonSerializerOptions();
opts.Converters.Add(new MoneyJsonConverter());
```

---

## 12.7 Connecting IO to the Rest of the Book

- **Ch 8 (Async)** — All file and stream operations have async variants.
  Always use `ReadAsync`/`WriteAsync` rather than blocking `Read`/`Write`
  in async code. `IAsyncEnumerable<T>` from `File.ReadLinesAsync` pairs
  with `await foreach` for lazy file processing.
- **Ch 13 (Networking)** — `HttpClient` response bodies are `Stream`
  objects. You can read them with `StreamReader`, pass them to a
  `JsonSerializer`, or pipe them to a file.
- **Ch 15 (EF Core)** — BLOB columns in databases are often read via
  `Stream`. EF Core supports streaming large binary data.
- **Ch 26 (Memory)** — `Span<T>`, `Memory<T>`, and `ArrayPool<T>` are
  the tools for zero-copy buffer management in IO-heavy code.
- **Ch 35 (Pet Projects — Daemons)** — a complete FileSystemWatcher
  daemon with debounce, Channel<T> pipeline, and JSONL logging.
