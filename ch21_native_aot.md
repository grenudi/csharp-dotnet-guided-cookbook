# Chapter 21 — Native AOT, P/Invoke & Performance

## 21.1 Native AOT Overview

Native AOT compiles your entire application — IL + BCL + runtime — into a **single native binary**. No JIT, no CLR shipped to the target. Result: near-instant startup, lower memory, deployable without .NET installed.

```
Traditional:
  app.dll + dotnet runtime (150–250 MB) → JIT compilation at startup

Native AOT:
  app (single native binary, 5–30 MB) → no JIT, no runtime needed
```

### Enable Native AOT

```xml
<!-- In .csproj -->
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <!-- Required: must target specific RID -->
  <RuntimeIdentifier>linux-x64</RuntimeIdentifier>
  <!-- Optional: reduce binary size -->
  <StripSymbols>true</StripSymbols>
  <InvariantGlobalization>true</InvariantGlobalization> <!-- smaller binary, no locale data -->
</PropertyGroup>
```

```bash
# Publish
dotnet publish -c Release -r linux-x64
dotnet publish -c Release -r win-x64
dotnet publish -c Release -r osx-arm64

# Result: a few-megabyte native binary
ls -lh ./publish/MyApp  # e.g., 12MB for a simple web API
```

---

## 21.2 AOT Restrictions and Workarounds

### What's NOT Allowed

```csharp
// 1. Arbitrary reflection (dynamic type creation)
var type = Type.GetType(typeName);  // ⚠ may fail — type may be trimmed
Activator.CreateInstance(type);      // ⚠ same

// 2. Dynamic code generation
var asm = AssemblyBuilder.DefineDynamicAssembly(...); // ⚠ not supported

// 3. Non-source-generated JSON serialization
JsonSerializer.Serialize(obj); // ⚠ with default options, reflection-based

// 4. Dynamic Linq / runtime-compiled expressions
// Expression.Compile() with non-trivial trees may fail
```

### AOT-Compatible JSON (Source Generation)

```csharp
// Define source generator context
[JsonSerializable(typeof(User))]
[JsonSerializable(typeof(List<User>))]
[JsonSerializable(typeof(Order))]
[JsonSerializable(typeof(ApiResponse<User>))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    WriteIndented = false)]
internal partial class AppJsonContext : JsonSerializerContext { }

// Register in DI
builder.Services.ConfigureHttpJsonOptions(opts =>
    opts.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default));

// Use explicitly
string json = JsonSerializer.Serialize(user, AppJsonContext.Default.User);
User? user = JsonSerializer.Deserialize(json, AppJsonContext.Default.User);
```

### AOT-Compatible gRPC

```xml
<PackageReference Include="Grpc.AspNetCore" Version="2.65.0" />
<!-- Protobuf is source-generated, already AOT-compatible -->
```

### Trimming Annotations

```csharp
using System.Diagnostics.CodeAnalysis;

// Preserve a type from trimming
[DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.All)]
public class MyPlugin { /* ... */ }

// Tell trimmer this method uses reflection on its type parameter
public void CreateInstance<[DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicConstructors)] T>()
    where T : class
    => Activator.CreateInstance<T>();

// Suppress trim warning (you know it's safe)
[RequiresUnreferencedCode("Uses reflection — only call from known contexts")]
public void UseReflection(string typeName) { /* ... */ }
```

---

## 21.3 AOT-Compatible Minimal API

```csharp
// Program.cs — fully AOT-compatible web API
var builder = WebApplication.CreateSlimBuilder(args); // slim builder for AOT
builder.Services.ConfigureHttpJsonOptions(opts =>
    opts.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default));

builder.Services.AddSingleton<IUserRepository, InMemoryUserRepository>();

var app = builder.Build();

app.MapGet("/users", async (IUserRepository repo) =>
    Results.Ok(await repo.GetAllAsync()));

app.MapGet("/users/{id:int}", async (int id, IUserRepository repo) =>
{
    var user = await repo.GetByIdAsync(id);
    return user is null ? Results.NotFound() : Results.Ok(user);
});

app.MapPost("/users", async (User user, IUserRepository repo) =>
{
    var id = await repo.AddAsync(user);
    return Results.Created($"/users/{id}", user with { Id = id });
});

app.Run();

// Source-generated JSON context
[JsonSerializable(typeof(User))]
[JsonSerializable(typeof(List<User>))]
internal partial class AppJsonContext : JsonSerializerContext { }
```

---

## 21.4 P/Invoke — Calling Native Code

### Classic P/Invoke

```csharp
using System.Runtime.InteropServices;

// Import from a native library
public static class NativeLib
{
    [DllImport("libsodium", CallingConvention = CallingConvention.Cdecl)]
    public static extern int crypto_hash_sha256(
        [Out] byte[] hash,
        [In] byte[] input,
        ulong inputLen);

    [DllImport("libc", EntryPoint = "getpid")]
    public static extern int GetPid();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int MessageBox(IntPtr hWnd, string text, string caption, int type);
}
```

### LibraryImport (C# 11+ / .NET 7+) — AOT-Compatible

```csharp
// Source-generated P/Invoke — preferred for AOT
public static partial class NativeLib
{
    // Simple case
    [LibraryImport("libc")]
    public static partial int getpid();

    // String marshaling
    [LibraryImport("libc", StringMarshalling = StringMarshalling.Utf8)]
    public static partial int open(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        int flags);

    // Custom struct marshaling
    [LibraryImport("libsodium", EntryPoint = "crypto_hash_sha256")]
    public static partial int CryptoHashSha256(
        ref byte hash,
        ref byte input,
        ulong inputLen);
}

// Usage
int pid = NativeLib.getpid();
Console.WriteLine($"PID: {pid}");
```

### Safe Handle Pattern

```csharp
// Wrap native handle for safe resource management
public sealed class NativeFileHandle : SafeHandle
{
    public NativeFileHandle() : base(IntPtr.Zero, ownsHandle: true) { }

    public override bool IsInvalid => handle == IntPtr.Zero || handle == new IntPtr(-1);

    protected override bool ReleaseHandle()
    {
        return NativeLib.CloseHandle(handle) != 0;
    }
}

public static partial class NativeLib
{
    [LibraryImport("kernel32.dll", EntryPoint = "CreateFileW",
        StringMarshalling = StringMarshalling.Utf16)]
    public static partial NativeFileHandle CreateFile(
        string fileName, uint access, uint share, IntPtr security,
        uint creationDisposition, uint flags, IntPtr template);

    [LibraryImport("kernel32.dll")]
    public static partial int CloseHandle(IntPtr handle);
}
```

---

## 21.5 Unsafe Code and Pointers

```csharp
// Enable in .csproj:
// <AllowUnsafeBlocks>true</AllowUnsafeBlocks>

public static unsafe class FastOps
{
    // Direct pointer manipulation
    public static void Fill(byte* ptr, int length, byte value)
    {
        for (int i = 0; i < length; i++)
            ptr[i] = value;
    }

    // stackalloc with pointer
    public static int SumStack(int[] arr)
    {
        int* scratch = stackalloc int[arr.Length];
        int total = 0;
        for (int i = 0; i < arr.Length; i++)
        {
            scratch[i] = arr[i] * 2;
            total += scratch[i];
        }
        return total;
    }

    // fixed — pin managed array for pointer access
    public static void XorBuffer(byte[] data, byte key)
    {
        fixed (byte* ptr = data)
        {
            for (int i = 0; i < data.Length; i++)
                ptr[i] ^= key;
        }
    }

    // Reinterpret cast (very dangerous — use only when you know the layout)
    public static unsafe float AsFloat(int bits)
    {
        return *(float*)&bits;
    }
}
```

---

## 21.6 Performance — SIMD and Hardware Intrinsics

```csharp
using System.Runtime.Intrinsics;
using System.Runtime.Intrinsics.X86;

// Vector<T> — portable SIMD (auto-vectorized by JIT)
public static float DotProduct(float[] a, float[] b)
{
    var sum = Vector<float>.Zero;
    int i = 0;
    int simdLen = Vector<float>.Count; // 8 on AVX2

    for (; i <= a.Length - simdLen; i += simdLen)
    {
        var va = new Vector<float>(a, i);
        var vb = new Vector<float>(b, i);
        sum += va * vb;
    }

    float total = Vector.Dot(sum, Vector<float>.One);
    for (; i < a.Length; i++) total += a[i] * b[i]; // remainder
    return total;
}

// Hardware intrinsics — AVX2 explicit (x86 only)
public static unsafe void AddArraysAvx2(float[] a, float[] b, float[] result)
{
    if (!Avx2.IsSupported) { /* fallback */ return; }

    fixed (float* pA = a, pB = b, pR = result)
    {
        int i = 0;
        for (; i <= a.Length - 8; i += 8)
        {
            var va = Avx.LoadVector256(pA + i);
            var vb = Avx.LoadVector256(pB + i);
            Avx.Store(pR + i, Avx.Add(va, vb));
        }
        for (; i < a.Length; i++) pR[i] = pA[i] + pB[i];
    }
}

// SearchValues<T> — zero-allocation string searching (NET 8+)
private static readonly SearchValues<char> SpecialChars =
    SearchValues.Create("<>&\"'");

public static bool ContainsSpecial(string text)
    => text.AsSpan().IndexOfAny(SpecialChars) >= 0;
```

---

## 21.7 Benchmarking with BenchmarkDotNet

```csharp
// Install: BenchmarkDotNet
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Running;

[MemoryDiagnoser]
[SimpleJob(RuntimeMoniker.Net90)]
public class StringBenchmarks
{
    private const string TestString = "Hello, World! This is a test string.";

    [Benchmark(Baseline = true)]
    public string Concat() => TestString + " suffix";

    [Benchmark]
    public string Interpolation() => $"{TestString} suffix";

    [Benchmark]
    public string StringBuilder()
    {
        var sb = new System.Text.StringBuilder(TestString);
        sb.Append(" suffix");
        return sb.ToString();
    }

    [Benchmark]
    public string StringCreate()
        => string.Create(TestString.Length + 7, TestString, (span, s) =>
        {
            s.AsSpan().CopyTo(span);
            " suffix".AsSpan().CopyTo(span[s.Length..]);
        });
}

// Run:
// BenchmarkRunner.Run<StringBenchmarks>();
// dotnet run -c Release
```

> **Rider tip:** *Run → Profile* opens JetBrains dotTrace/dotMemory integration directly from Rider. You can attach the profiler to any running process, record a performance snapshot, and analyze flame graphs and allocation traces without leaving the IDE.

> **VS tip:** *Debug → Performance Profiler* (`Alt+F2`) offers CPU Usage, Memory Usage, .NET Object Allocation, and GPU Usage profilers. The PerfView tool (separate download from Microsoft) provides deeper ETW-based analysis for startup and GC.

