# Chapter 7 — Collections & LINQ

## 7.1 Array

```csharp
// Declaration
int[] arr = new int[5];                    // zero-initialized: [0,0,0,0,0]
int[] arr2 = new int[] { 1, 2, 3, 4, 5 };
int[] arr3 = [1, 2, 3, 4, 5];             // collection expression (C# 12+)

// 2D array (rectangular)
int[,] matrix = new int[3, 3];
int[,] matrix2 = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 } };
matrix2[1, 1] = 99;

// Jagged array (array of arrays)
int[][] jagged = new int[3][];
jagged[0] = [1, 2];
jagged[1] = [3, 4, 5];
jagged[2] = [6];

// Common operations
int[] sorted = [3, 1, 4, 1, 5, 9];
Array.Sort(sorted);                    // [1,1,3,4,5,9] in-place
Array.Reverse(sorted);                 // [9,5,4,3,1,1]
int idx = Array.BinarySearch(sorted, 4); // binary search (must be sorted)
Array.Fill(sorted, 0);                 // fill with value
int[] copy = sorted.ToArray();         // copy
Array.Copy(sorted, copy, sorted.Length);

// Multidimensional with LINQ
var flat = matrix2.Cast<int>(); // flattens 2D to IEnumerable<int>
```

---

## 7.2 List\<T\>

```csharp
var list = new List<int> { 1, 2, 3 };
var list2 = new List<int>(capacity: 1000); // pre-allocate to avoid resize

list.Add(4);
list.AddRange([5, 6, 7]);
list.Insert(0, 0);          // insert at index
list.Remove(3);             // removes first occurrence of value 3
list.RemoveAt(0);           // removes at index
list.RemoveAll(x => x % 2 == 0); // remove all even numbers

bool has = list.Contains(5);
int pos = list.IndexOf(5);
int count = list.Count;

list.Sort();
list.Sort((a, b) => b.CompareTo(a)); // reverse sort
list.Reverse();

var copy = new List<int>(list);  // copy constructor
var slice = list.GetRange(1, 3); // sublist [1,3) exclusive

// Convert
int[] arr = list.ToArray();
IReadOnlyList<int> ro = list.AsReadOnly();

// Search
int found = list.Find(x => x > 3);
int last   = list.FindLast(x => x > 3);
List<int> all = list.FindAll(x => x > 3);
bool any = list.Exists(x => x > 10);
bool allPos = list.TrueForAll(x => x > 0);

// ForEach
list.ForEach(x => Console.WriteLine(x));
```

---

## 7.3 Dictionary\<TKey, TValue\>

```csharp
var dict = new Dictionary<string, int>
{
    ["Alice"] = 30,
    ["Bob"]   = 25,
};

// Add / update
dict["Charlie"] = 35;           // add or update
dict.Add("Dave", 28);           // throws if key exists
dict.TryAdd("Alice", 99);       // safe add (no throw, returns false if exists)

// Read
int age = dict["Alice"];        // throws KeyNotFoundException if missing
int age2 = dict.GetValueOrDefault("Zzz", 0); // safe read

// TryGetValue — always prefer this for read
if (dict.TryGetValue("Alice", out int found))
    Console.WriteLine(found);

// Remove
dict.Remove("Dave");
dict.Remove("Alice", out int removed); // remove and get value

// Iteration
foreach (var (key, value) in dict)
    Console.WriteLine($"{key}: {value}");

foreach (var kvp in dict)
    Console.WriteLine($"{kvp.Key}: {kvp.Value}");

// Keys/Values
ICollection<string> keys   = dict.Keys;
ICollection<int>    values = dict.Values;

// Merge / update batch
foreach (var (k, v) in updates)
    dict[k] = v;

// Count by frequency
var freq = new Dictionary<char, int>();
foreach (var c in "hello world")
    freq[c] = freq.GetValueOrDefault(c) + 1;
// Or more elegantly:
var freq2 = "hello world".GroupBy(c => c).ToDictionary(g => g.Key, g => g.Count());
```

### Specialized Dictionaries

```csharp
// SortedDictionary<TKey, TValue> — O(log n) ops, ordered by key
var sorted = new SortedDictionary<string, int>(StringComparer.OrdinalIgnoreCase);

// SortedList<TKey, TValue> — array-backed, faster read, slower write
var sortedList = new SortedList<DateTime, string>();

// OrderedDictionary (NET 9+) — preserves insertion order
using System.Collections.Generic;
// Use Dictionary<K,V> — maintains insertion order from NET 5+

// ConcurrentDictionary — thread-safe
var concurrent = new System.Collections.Concurrent.ConcurrentDictionary<string, int>();
concurrent.TryAdd("key", 1);
concurrent.AddOrUpdate("key", 1, (k, old) => old + 1);
int val = concurrent.GetOrAdd("key", k => ComputeDefault(k));
```

---

## 7.4 HashSet\<T\> and SortedSet\<T\>

```csharp
var set = new HashSet<string> { "a", "b", "c" };
set.Add("d");           // returns false if already exists
set.Remove("a");
bool has = set.Contains("b"); // O(1)

// Set operations
var setA = new HashSet<int> { 1, 2, 3, 4 };
var setB = new HashSet<int> { 3, 4, 5, 6 };

var union     = new HashSet<int>(setA); union.UnionWith(setB);        // {1,2,3,4,5,6}
var intersect = new HashSet<int>(setA); intersect.IntersectWith(setB); // {3,4}
var diff      = new HashSet<int>(setA); diff.ExceptWith(setB);         // {1,2}
var symDiff   = new HashSet<int>(setA); symDiff.SymmetricExceptWith(setB); // {1,2,5,6}

bool subset   = setA.IsSubsetOf(union);     // true
bool superset = union.IsSupersetOf(setA);   // true

// Custom equality
var set2 = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
set2.Add("Alice");
set2.Contains("alice"); // true
```

---

## 7.5 Queue, Stack, LinkedList, PriorityQueue

```csharp
// Queue<T> — FIFO
var queue = new Queue<string>();
queue.Enqueue("first");
queue.Enqueue("second");
queue.Enqueue("third");
string front = queue.Peek();    // "first" — don't remove
string taken = queue.Dequeue(); // "first" — remove
bool ok = queue.TryDequeue(out string? item);

// Stack<T> — LIFO
var stack = new Stack<int>();
stack.Push(1);
stack.Push(2);
stack.Push(3);
int top = stack.Peek();    // 3
int popped = stack.Pop();  // 3
bool ok2 = stack.TryPop(out int x);

// LinkedList<T> — O(1) insert/remove at ends and known nodes
var linked = new LinkedList<int>([1, 2, 3]);
linked.AddFirst(0);
linked.AddLast(4);
linked.AddAfter(linked.Find(2)!, 99);
linked.Remove(99);
// Good for: sliding window, LRU cache, frequent insert/remove at arbitrary positions

// PriorityQueue<TElement, TPriority> (NET 6+) — min-heap
var pq = new PriorityQueue<string, int>();
pq.Enqueue("low priority",    100);
pq.Enqueue("high priority",   1);
pq.Enqueue("medium priority", 50);

while (pq.TryDequeue(out var item, out var priority))
    Console.WriteLine($"{priority}: {item}");
// 1: high priority, 50: medium priority, 100: low priority

// Custom priority comparer (max-heap)
var maxPq = new PriorityQueue<string, int>(Comparer<int>.Create((a, b) => b.CompareTo(a)));
```

---

## 7.6 Immutable Collections

```csharp
using System.Collections.Immutable;

// ImmutableList<T>
var list = ImmutableList<int>.Empty;
var list2 = list.Add(1).Add(2).Add(3);  // each returns new list
var list3 = list2.Remove(2);

// ImmutableDictionary<K,V>
var dict = ImmutableDictionary<string, int>.Empty;
var dict2 = dict.Add("a", 1).Add("b", 2);
var dict3 = dict2.SetItem("a", 99); // update

// ImmutableArray<T> — struct, no allocation overhead for empty
var arr = ImmutableArray.Create(1, 2, 3);

// Builders — efficient bulk creation
var builder = ImmutableList.CreateBuilder<int>();
for (int i = 0; i < 1000; i++) builder.Add(i);
ImmutableList<int> result = builder.ToImmutable();
```

---

## 7.7 Concurrent Collections

```csharp
using System.Collections.Concurrent;

// ConcurrentQueue<T> — thread-safe FIFO
var cq = new ConcurrentQueue<string>();
cq.Enqueue("item");
cq.TryDequeue(out string? item);
cq.TryPeek(out string? peeked);

// ConcurrentStack<T> — thread-safe LIFO
var cs = new ConcurrentStack<int>();
cs.Push(1);
cs.TryPop(out int popped);
cs.PushRange([1, 2, 3]);

// ConcurrentBag<T> — unordered, optimized for same-thread add/take
var bag = new ConcurrentBag<int>();
bag.Add(1);
bag.TryTake(out int taken);

// BlockingCollection<T> — producer/consumer with blocking
var bc = new BlockingCollection<int>(boundedCapacity: 100);

// Producer
Task.Run(() => {
    for (int i = 0; i < 10; i++) bc.Add(i);
    bc.CompleteAdding();
});

// Consumer
foreach (var item in bc.GetConsumingEnumerable())
    Console.WriteLine(item);
```

---

## 7.8 Span\<T\> and Memory\<T\>

```csharp
// Span<T> — stack-only, slice over arrays/stack memory without allocation
int[] arr = [1, 2, 3, 4, 5];
Span<int> span = arr.AsSpan();
Span<int> slice = span[1..4];  // [2,3,4] — no allocation

// Modify through span modifies original array
slice[0] = 99;
Console.WriteLine(arr[1]); // 99

// stackalloc
Span<byte> stack = stackalloc byte[256];
stack.Fill(0);

// ReadOnlySpan<T>
ReadOnlySpan<char> text = "hello, world".AsSpan();
ReadOnlySpan<char> word = text[..5]; // "hello" — no allocation

// Memory<T> — heap-safe wrapper, can be stored in fields and passed to async
Memory<byte> mem = new byte[1024];
Memory<byte> slice2 = mem.Slice(0, 512);

// In async context (Span can't be used across await)
async Task ProcessAsync(Memory<byte> data)
{
    await Task.Delay(1);
    data.Span.Fill(0xFF);
}
```

---

## 7.9 LINQ — Complete Operator Reference

### Standard Query Operators

```csharp
var nums = Enumerable.Range(1, 20).ToList();

// ── Filtering ─────────────────────────────────────────────────────────
var evens  = nums.Where(n => n % 2 == 0);
var first  = nums.First(n => n > 10);       // throws if none
var firstN = nums.FirstOrDefault(n => n > 100); // null/0 if none
var last   = nums.Last(n => n % 2 == 0);
var lastN  = nums.LastOrDefault(n => n > 100);
var single = nums.Single(n => n == 10);     // throws if 0 or 2+ matches
var singleN = nums.SingleOrDefault(n => n == 999); // throws if 2+ matches

// ── Projection ────────────────────────────────────────────────────────
var squares  = nums.Select(n => n * n);
var asStrings = nums.Select((n, i) => $"[{i}] {n}"); // index overload
var flat     = new[] { new[]{1,2}, new[]{3,4} }.SelectMany(x => x); // [1,2,3,4]

// ── Ordering ──────────────────────────────────────────────────────────
var asc   = nums.OrderBy(n => n);
var desc  = nums.OrderByDescending(n => n);
var multi = words.OrderBy(w => w.Length).ThenBy(w => w); // stable multi-key sort
var rev   = nums.Reverse();

// ── Grouping ──────────────────────────────────────────────────────────
var groups = nums.GroupBy(n => n % 3);
foreach (var g in groups)
{
    Console.WriteLine($"Key {g.Key}: {string.Join(",", g)}");
}

// Group into dictionary
var byRemainder = nums.GroupBy(n => n % 3)
                      .ToDictionary(g => g.Key, g => g.ToList());

// ── Joining ───────────────────────────────────────────────────────────
var users   = GetUsers();
var orders  = GetOrders();

// Inner join
var joined = users.Join(
    orders,
    u => u.Id,
    o => o.UserId,
    (u, o) => new { u.Name, o.Total });

// Left outer join via GroupJoin + SelectMany
var leftJoin = users.GroupJoin(
    orders,
    u => u.Id,
    o => o.UserId,
    (u, userOrders) => new { User = u, Orders = userOrders })
    .SelectMany(
        x => x.Orders.DefaultIfEmpty(),
        (x, o) => new { x.User.Name, OrderTotal = o?.Total ?? 0 });

// ── Set operations ────────────────────────────────────────────────────
var a = new[] { 1, 2, 3, 4 };
var b = new[] { 3, 4, 5, 6 };
var union     = a.Union(b);          // [1,2,3,4,5,6] — distinct
var intersect = a.Intersect(b);      // [3,4]
var diff      = a.Except(b);         // [1,2]
var distinct  = a.Distinct();
var distinctBy = users.DistinctBy(u => u.Email); // (NET 6+)

// ── Aggregation ───────────────────────────────────────────────────────
int count    = nums.Count();
int countIf  = nums.Count(n => n % 2 == 0);
long lcount  = nums.LongCount();
int sum      = nums.Sum();
double avg   = nums.Average();
int min      = nums.Min();
int max      = nums.Max();
int? minN    = nums.MinOrDefault();  // null if empty (NET 6+)

// Aggregate — custom fold
int product = nums.Aggregate(1, (acc, n) => acc * n);
string joined = nums.Aggregate("", (acc, n) => acc + n + ",");

// ── Quantifiers ───────────────────────────────────────────────────────
bool any    = nums.Any();              // not empty
bool anyIf  = nums.Any(n => n > 15);
bool all    = nums.All(n => n > 0);
bool none   = !nums.Any(n => n < 0);
bool has    = nums.Contains(10);

// ── Element access ────────────────────────────────────────────────────
int elem     = nums.ElementAt(5);
int elemN    = nums.ElementAtOrDefault(999); // 0 if out of range
int elemN2   = nums.ElementAtOrDefault(^1);  // last element (NET 6+)

// ── Partitioning ──────────────────────────────────────────────────────
var skipped  = nums.Skip(5);
var taken    = nums.Take(5);
var page     = nums.Skip(10).Take(10);     // page 2 of 10
var takenRng = nums.Take(3..7);            // range (NET 6+)
var skipLast = nums.SkipLast(3);           // [1..17]
var takeLast = nums.TakeLast(3);           // [18,19,20]
var skipWhile = nums.SkipWhile(n => n < 5); // skip while predicate true
var takeWhile = nums.TakeWhile(n => n < 5); // take while predicate true

// ── Conversion ────────────────────────────────────────────────────────
List<int> toList       = nums.ToList();
int[]     toArr        = nums.ToArray();
HashSet<int> toSet     = nums.ToHashSet();
Dictionary<int, string> toDict = nums.ToDictionary(n => n, n => n.ToString());
ILookup<int, int> lookup = nums.ToLookup(n => n % 3); // like GroupBy but lookup-optimized
```

### Query Syntax (SQL-like)

```csharp
var query = from u in users
            join o in orders on u.Id equals o.UserId
            where u.Age >= 18 && o.Total > 100
            orderby o.Total descending, u.Name
            group new { u, o } by u.Country into g
            select new
            {
                Country = g.Key,
                TotalRevenue = g.Sum(x => x.o.Total),
                UserCount = g.Select(x => x.u.Id).Distinct().Count()
            };
```

### Deferred Execution

```csharp
// LINQ queries are lazy — they don't execute until enumerated
var q = nums.Where(n => n % 2 == 0).Select(n => n * n);
// q is just a query definition — no work done yet

nums.Add(22); // add to source AFTER defining query
var result = q.ToList(); // NOW it executes — includes 22!

// Force immediate evaluation with ToList/ToArray/ToDictionary
var immediate = nums.Where(n => n % 2 == 0).ToList(); // evaluated now
nums.Add(24); // too late — not in result
```

### LINQ Performance Tips

```csharp
// 1. Avoid multiple enumeration
var items = GetExpensiveItems();
// BAD:
if (items.Any()) Console.WriteLine(items.Count()); // enumerates twice
// GOOD:
var list = items.ToList();
if (list.Count > 0) Console.WriteLine(list.Count);

// 2. Use Where before Select
// BAD:
var result1 = items.Select(x => ComputeExpensive(x)).Where(x => x > 0);
// GOOD:
var result2 = items.Where(x => x.IsValid).Select(x => ComputeExpensive(x));

// 3. Short-circuit with Any/First instead of Count/Where+First
// BAD:
bool hasAny = items.Where(x => x.IsActive).Count() > 0;
// GOOD:
bool hasAny2 = items.Any(x => x.IsActive);

// 4. For large sorted datasets, use OrderBy once
var ordered = items.OrderBy(x => x.Name);
var top10 = ordered.Take(10).ToList();
var next10 = ordered.Skip(10).Take(10).ToList();

// 5. Chunk (NET 6+) — batch processing
foreach (var chunk in items.Chunk(100))
{
    await ProcessBatchAsync(chunk); // chunk is int[]
}
```

### Custom LINQ Operators

```csharp
public static class LinqExtensions
{
    // Batch/chunk (before NET 6)
    public static IEnumerable<IReadOnlyList<T>> Batch<T>(this IEnumerable<T> source, int size)
    {
        var batch = new List<T>(size);
        foreach (var item in source)
        {
            batch.Add(item);
            if (batch.Count == size)
            {
                yield return batch.AsReadOnly();
                batch = new List<T>(size);
            }
        }
        if (batch.Count > 0) yield return batch.AsReadOnly();
    }

    // Tap — peek at each element without changing the stream
    public static IEnumerable<T> Tap<T>(this IEnumerable<T> source, Action<T> action)
    {
        foreach (var item in source)
        {
            action(item);
            yield return item;
        }
    }

    // ZipWith — pair two sequences
    public static IEnumerable<(T1, T2)> ZipWith<T1, T2>(
        this IEnumerable<T1> first,
        IEnumerable<T2> second)
        => first.Zip(second);

    // Flatten one level of nesting
    public static IEnumerable<T> Flatten<T>(this IEnumerable<IEnumerable<T>> source)
        => source.SelectMany(x => x);

    // MinBy/MaxBy (NET 6+ built-in, but shown for reference)
    public static T? MinBy<T, TKey>(this IEnumerable<T> source, Func<T, TKey> key)
        where TKey : IComparable<TKey>
    {
        T? min = default;
        TKey? minKey = default;
        bool first = true;
        foreach (var item in source)
        {
            var k = key(item);
            if (first || k.CompareTo(minKey!) < 0) { min = item; minKey = k; first = false; }
        }
        return min;
    }
}
```

### LINQ to XML

```csharp
using System.Xml.Linq;

var xml = XDocument.Load("data.xml");

// Query XML with LINQ
var names = xml.Descendants("user")
               .Where(u => (int)u.Attribute("age")! > 18)
               .Select(u => (string)u.Element("name")!)
               .ToList();

// Build XML
var doc = new XDocument(
    new XElement("users",
        new XElement("user",
            new XAttribute("id", 1),
            new XElement("name", "Alice"),
            new XElement("age", 30))));

doc.Save("output.xml");
```

> **Rider tip:** Rider shows LINQ complexity hints inline — it marks chains that enumerate multiple times with a warning. Use *Code → Optimize Imports and Code Cleanup* to apply LINQ-specific inspections.

> **VS tip:** Install *LINQPad-style* execution via *dotnet-script* or use the *C# Interactive* window (`View → Other Windows → C# Interactive`) to test LINQ queries in real time.

