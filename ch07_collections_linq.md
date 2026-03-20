# Chapter 7 — Collections & LINQ

> Data structures are the first design decision in any algorithm: the
> wrong container makes simple problems expensive. LINQ is the uniform
> query language that works over all of them. Together they form the
> vocabulary for expressing what you want from data. This chapter
> explains the mental model behind each collection type, when to reach
> for it, and how LINQ turns querying into a composable pipeline.

*Building on:* Ch 2 (generics — all collections are generic types),
Ch 3 (pattern matching, `foreach`), Ch 4 (lambdas — every LINQ operator
takes a `Func<T,…>` argument)

---

## 7.1 The Mental Model: Choosing a Container

The question is not "what does this collection do" but "what invariant
does it maintain for me". Each collection trades memory or CPU for a
guarantee:

| Container | Guarantee | Typical use |
|---|---|---|
| `T[]` | Fixed size, O(1) random access | Raw performance, fixed-size buffers |
| `List<T>` | Dynamic size, O(1) amortised append | General-purpose ordered sequence |
| `Dictionary<K,V>` | O(1) lookup by key | Index, cache, group-by results |
| `HashSet<T>` | O(1) membership test, no duplicates | Deduplication, set operations |
| `SortedDictionary<K,V>` | O(log n) lookup, keys always sorted | Sorted index |
| `Queue<T>` | FIFO ordering | Work queues, BFS |
| `Stack<T>` | LIFO ordering | Undo stacks, DFS, call simulation |
| `PriorityQueue<T,P>` | O(log n) dequeue of minimum priority | Task scheduling, Dijkstra's |
| `LinkedList<T>` | O(1) insert/delete at known position | Splice-heavy ordered sequences |
| `ImmutableList<T>` | Any read, any thread, no mutation | Shared read-only state |
| `ConcurrentDictionary<K,V>` | Thread-safe read/write | Shared caches, counters |

---

## 7.2 Arrays — The Primitive Foundation

An array (`T[]`) is the most primitive collection. It is a contiguous
block of memory with a fixed length. All other .NET collections are
built on top of arrays (or use arrays internally). Its advantages:
O(1) indexed access, minimal overhead, stack-allocatable for small
sizes, directly mappable to hardware memory layouts.

Its limitation: the length is fixed at creation. If you need to grow
the collection, you allocate a new array and copy.

```csharp
// Fixed-length: set at creation and cannot change
int[] scores = new int[5];            // [0, 0, 0, 0, 0]
int[] primes = [2, 3, 5, 7, 11];     // collection expression (C# 12+)

// O(1) indexed access
int third = primes[2];                // 5
primes[0] = 1;                        // mutation

// Bounds: Array.Length, Indices (^), Ranges (..)
Console.WriteLine(primes.Length);     // 5
Console.WriteLine(primes[^1]);        // 11 (last element, ^ = from end)
int[] middle = primes[1..4];          // [3, 5, 7] (range, exclusive end)

// Sorting, searching (mutates in place)
int[] data = [5, 2, 8, 1, 9];
Array.Sort(data);                     // [1, 2, 5, 8, 9]
int idx = Array.BinarySearch(data, 5); // 2 — O(log n) on sorted array

// 2D rectangular array — one block of memory, row×col layout
int[,] matrix = new int[3, 3];
matrix[0, 1] = 42;

// Jagged array — array of arrays, rows can differ in length
int[][] jagged = [[1, 2], [3, 4, 5], [6]];
```

Use arrays when: the size is known upfront, performance is critical,
or you're interoperating with native code or low-level APIs.

---

## 7.3 `List<T>` — Dynamic Arrays

`List<T>` wraps an array and grows it automatically. Internally it
doubles the array's capacity when it runs out of space — an O(n) copy
that is amortised to O(1) per append. Random access by index is O(1).
Inserting or removing from the middle is O(n) because elements shift.

`List<T>` is the go-to default collection when you need a sequence of
unknown size. The vast majority of sequence work in .NET applications
uses `List<T>` or `IEnumerable<T>` (the read-only view of it).

```csharp
var items = new List<string> { "apple", "banana" };
var sized = new List<string>(capacity: 1000);  // pre-allocate; avoids resizes for known size

// O(1) amortised
items.Add("cherry");
items.AddRange(["date", "elderberry"]);

// O(n) — avoid in hot paths
items.Insert(0, "avocado");     // shifts all elements right
items.Remove("banana");         // linear scan then shift
items.RemoveAt(1);              // shift
items.RemoveAll(s => s.Length > 5); // filter in-place

// O(1)
bool has = items.Contains("cherry");   // linear scan (O(n)) — use HashSet for O(1) membership
int idx  = items.IndexOf("cherry");    // linear scan
string   first = items[0];             // O(1) index

// Sorting: delegates the comparison to you
items.Sort();                           // natural order (IComparable<T>)
items.Sort((a, b) => b.Length.CompareTo(a.Length)); // sort by length descending

// Conversion
string[] arr   = items.ToArray();   // copy to array
var      fixed = items.AsReadOnly(); // read-only wrapper, no copy
```

When you expose a list from a method, return `IReadOnlyList<T>` or
`IEnumerable<T>` — this prevents callers from accidentally mutating the
internal list through the returned reference.

---

## 7.4 `Dictionary<TKey, TValue>` — Hash-Table Lookup

A `Dictionary<K,V>` maps keys to values with O(1) average lookup, insert,
and delete. It works by hashing the key to a bucket index — finding an
entry is usually one hash computation and one memory access, regardless
of how many entries the dictionary has.

This O(1) guarantee is what makes `Dictionary` the tool for any lookup
problem: caching computed results, building an index over a list, grouping
items by category, or deduplicating with associated values.

```csharp
// Creation
var ages = new Dictionary<string, int>
{
    ["Alice"] = 30,
    ["Bob"]   = 25,
};
var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
// StringComparer.OrdinalIgnoreCase: "key" and "KEY" are the same key

// Safe lookup patterns
if (ages.TryGetValue("Alice", out int age))  // preferred — no double-lookup
    Console.WriteLine(age);

int val = ages.GetValueOrDefault("Eve", -1); // returns -1 if missing

// Insert / update
ages["Charlie"] = 28;                        // add or overwrite
ages.TryAdd("Alice", 99);                    // adds only if key is absent; returns false if present

// Convenient conditional increment
var wordCount = new Dictionary<string, int>();
foreach (var word in words)
    wordCount[word] = wordCount.GetValueOrDefault(word) + 1;

// Iteration
foreach (var (name, a) in ages)             // deconstruct KeyValuePair
    Console.WriteLine($"{name}: {a}");

// Keys and Values as collections
IEnumerable<string> names  = ages.Keys;
IEnumerable<int>    values = ages.Values;
```

The hash function and equality comparer determine performance and
correctness. Mutable objects as keys are dangerous — if the object's
`GetHashCode()` result changes after insertion, the entry becomes
unreachable. Prefer immutable types (strings, ints, records) as keys.

---

## 7.5 `HashSet<T>` — Membership and Set Operations

A `HashSet<T>` stores unique elements and answers "is X in this set?" in
O(1). It has no order and no associated values — it is a `Dictionary<T,
unit>`. Use it whenever you care about membership without caring about
position or associated data.

```csharp
var visited = new HashSet<string>();
visited.Add("page-1");
visited.Add("page-1");     // duplicate — silently ignored
Console.WriteLine(visited.Count);  // 1

// O(1) membership — far faster than List.Contains for large sets
bool seen = visited.Contains("page-1");  // true
bool notSeen = visited.Contains("page-99");  // false

// Mathematical set operations
var a = new HashSet<int> { 1, 2, 3, 4 };
var b = new HashSet<int> { 3, 4, 5, 6 };

// These MODIFY 'a' in place:
a.UnionWith(b);        // a = {1,2,3,4,5,6}
a.IntersectWith(b);    // a = {3,4,5,6}
a.ExceptWith(b);       // a = {1,2} (elements in a but not b)

// Non-destructive (LINQ):
var union     = a.Union(b);
var intersect = a.Intersect(b);
var except    = a.Except(b);
```

A common pattern: deduplicate a list while preserving only unique elements.

```csharp
var deduped = new HashSet<string>(rawList).ToList();
// or with LINQ:
var deduped2 = rawList.Distinct().ToList();
```

---

## 7.6 `Queue<T>`, `Stack<T>`, `PriorityQueue<T,P>`

These are data structures with specific ordering invariants. They are
less common than `List` or `Dictionary` but indispensable when the
ordering itself is part of your algorithm.

**`Queue<T>` — First In, First Out (FIFO).** Items are dequeued in the
order they were enqueued. Use for: work queues where order matters,
breadth-first graph traversal, event buffers.

```csharp
var queue = new Queue<string>();
queue.Enqueue("task-1");
queue.Enqueue("task-2");
queue.Enqueue("task-3");

string next = queue.Dequeue();   // "task-1" — the oldest item
string peek = queue.Peek();      // "task-2" — look without removing
Console.WriteLine(queue.Count);  // 2
```

**`Stack<T>` — Last In, First Out (LIFO).** The most recently added item
is the first to be removed. Use for: undo history, depth-first traversal,
expression evaluation, call simulation.

```csharp
var history = new Stack<string>();
history.Push("action-1");
history.Push("action-2");
history.Push("action-3");

string last = history.Pop();     // "action-3" — most recent
string peek = history.Peek();    // "action-2" — look without removing
```

**`PriorityQueue<TElement, TPriority>` — Minimum Priority First.**
Dequeues the element with the lowest priority value first. Implemented
as a binary min-heap: O(log n) enqueue and dequeue, O(1) peek.

```csharp
// Task scheduler: lower number = higher priority
var scheduler = new PriorityQueue<string, int>();
scheduler.Enqueue("send-email",   priority: 3);
scheduler.Enqueue("process-payment", priority: 1);
scheduler.Enqueue("generate-report", priority: 2);

while (scheduler.TryDequeue(out var task, out var priority))
    Console.WriteLine($"[{priority}] {task}");
// Output:
// [1] process-payment
// [2] generate-report
// [3] send-email
```

---

## 7.7 Immutable and Concurrent Collections

### Immutable Collections — Safe to Share

The `System.Collections.Immutable` package provides collections that
cannot be modified after creation. Any "modification" returns a new
collection sharing structure with the original (persistent data structure).
They are safe to share across threads without locks because nothing ever
changes.

```csharp
using System.Collections.Immutable;

var list = ImmutableList.Create(1, 2, 3);
var list2 = list.Add(4);     // NEW list [1,2,3,4] — list is still [1,2,3]
var list3 = list.Remove(2);  // NEW list [1,3]

// ImmutableDictionary: safe to share as a read-only snapshot
var config = ImmutableDictionary.Create<string, string>()
    .Add("host", "localhost")
    .Add("port", "5432");
```

Use immutable collections when a data structure is shared across threads
for reading, and updates are infrequent (each update builds a new snapshot).

### Concurrent Collections — Thread-Safe Mutation

When multiple threads need to read and write the same collection without
external locks, use `System.Collections.Concurrent`:

```csharp
// ConcurrentDictionary: lock-free reads, fine-grained locking for writes
var cache = new ConcurrentDictionary<string, User>();
cache.TryAdd("user-1", new User("Alice"));
var user = cache.GetOrAdd("user-2", id => LoadFromDatabase(id));

// Atomic compare-and-update
cache.AddOrUpdate("counter",
    addValue:       "1",
    updateValueFactory: (key, old) => (int.Parse(old) + 1).ToString());

// ConcurrentQueue: lock-free enqueue/dequeue
var events = new ConcurrentQueue<string>();
events.Enqueue("event-1");
if (events.TryDequeue(out var evt)) Process(evt);
```

Chapter 38 covers thread safety and race conditions in depth.

---

## 7.8 `Span<T>` and `Memory<T>` — Zero-Copy Slices

`Span<T>` is a stack-only, ref-like type that provides a view over a
contiguous region of memory without copying it. It can view an array
slice, a stack allocation, or a block of native memory. It is the tool
for high-performance code that needs to parse or process data without
allocating new buffers.

```csharp
// Slice an array without copying
int[] data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
Span<int> middle = data.AsSpan(2, 5);  // elements [3, 4, 5, 6, 7] — no copy
middle[0] = 99;                         // mutates the original array: data[2] = 99

// Stack allocation: for small buffers, avoid heap allocation entirely
Span<byte> buffer = stackalloc byte[256];
int written = Encoding.UTF8.GetBytes("Hello World", buffer);
// buffer[..written] contains the UTF-8 bytes — no heap allocation

// Parsing without allocating substrings
ReadOnlySpan<char> text = "2024-01-15".AsSpan();
int year  = int.Parse(text[..4]);   // "2024" — no string allocation
int month = int.Parse(text[5..7]);  // "01"
int day   = int.Parse(text[8..]);   // "15"
```

`Memory<T>` is the heap-compatible sibling — it can be stored in fields
and used in async methods (where `Span<T>` is restricted to synchronous
code because it cannot cross an `await`).

Chapter 26 covers the memory management picture in detail; Spans are a
key part of reducing GC pressure in high-throughput code.

---

## 7.9 LINQ — Querying Any Sequence

LINQ (Language Integrated Query) is a set of extension methods on
`IEnumerable<T>` (and `IQueryable<T>`) that lets you express data
transformations as composable method chains. It was inspired by
functional languages and SQL. It is one of the features that makes C#
distinctively expressive compared to most other languages.

### The Mental Model: Lazy Pipelines

LINQ operators do not execute immediately. They build a pipeline description.
The pipeline runs when you *materialize* it with a terminal operator
(`ToList()`, `ToArray()`, `First()`, `Count()`, `Sum()`, etc.). Until
then, no work is done.

```
source.Where(pred).Select(proj).OrderBy(key).Take(10)
                                                      ↑
                               Nothing runs yet.      │
                                                      │
.ToList()  ← materialise here. NOW it reads the source, filters, projects, sorts, takes.
```

This laziness is what allows LINQ to compose with infinite sequences,
database queries (EF Core), and any custom source — the operators just
describe *what* to do, not *when*.

### The Core Operators

**Filtering:**
```csharp
var adults = people.Where(p => p.Age >= 18);
var first  = people.First(p => p.Name == "Alice");   // throws if not found
var maybe  = people.FirstOrDefault(p => p.Name == "Bob"); // null if not found
bool any   = people.Any(p => p.IsAdmin);
bool all   = people.All(p => p.Age > 0);
int count  = people.Count(p => p.IsActive);
```

**Projection (transformation):**
```csharp
var names    = people.Select(p => p.Name);
var fullInfo = people.Select(p => new { p.Name, p.Age, IsAdult = p.Age >= 18 });

// SelectMany: flatten a sequence of sequences
var allTags  = posts.SelectMany(p => p.Tags);  // each post has many tags
```

**Ordering:**
```csharp
var sorted    = people.OrderBy(p => p.LastName).ThenBy(p => p.FirstName);
var youngest  = people.OrderBy(p => p.Age).First();
var oldest    = people.MaxBy(p => p.Age);  // .NET 6+ — no materialise needed
```

**Grouping:**
```csharp
// Group people by country; result is IGrouping<string, Person>
var byCountry = people.GroupBy(p => p.Country);
foreach (var group in byCountry)
{
    Console.WriteLine($"{group.Key}: {group.Count()} people");
    foreach (var person in group)
        Console.WriteLine($"  {person.Name}");
}

// Group and project in one step
var summary = people
    .GroupBy(p => p.Department)
    .Select(g => new
    {
        Department  = g.Key,
        Count       = g.Count(),
        AverageSalary = g.Average(p => p.Salary),
    });
```

**Aggregation:**
```csharp
decimal total  = orders.Sum(o => o.Total);
decimal avg    = orders.Average(o => o.Total);
decimal max    = orders.Max(o => o.Total);
decimal min    = orders.Min(o => o.Total);

// Aggregate: custom accumulator (like fold/reduce)
string sentence = words.Aggregate("", (acc, word) => acc == "" ? word : acc + " " + word);
```

**Set operations:**
```csharp
var union     = listA.Union(listB);           // distinct union
var intersect = listA.Intersect(listB);       // common elements
var except    = listA.Except(listB);          // in A but not B
var distinct  = list.Distinct();              // remove duplicates
```

**Joining:**
```csharp
// Join on a key — like SQL INNER JOIN
var joined = orders.Join(
    customers,
    order    => order.CustomerId,
    customer => customer.Id,
    (order, customer) => new { order.Id, customer.Name, order.Total });

// GroupJoin — like SQL LEFT JOIN
var withOrders = customers.GroupJoin(
    orders,
    customer => customer.Id,
    order    => order.CustomerId,
    (customer, customerOrders) => new
    {
        customer.Name,
        OrderCount = customerOrders.Count(),
        TotalSpent  = customerOrders.Sum(o => o.Total),
    });
```

**Paging:**
```csharp
int pageSize   = 20;
int pageNumber = 3;
var page = items
    .Skip(pageNumber * pageSize)  // skip first N pages
    .Take(pageSize)               // take one page
    .ToList();
```

**Materialisation (terminal operators):**
```csharp
List<T>        toList    = query.ToList();
T[]            toArray   = query.ToArray();
HashSet<T>     toHashSet = query.ToHashSet();
Dictionary<K,V> toDict   = query.ToDictionary(x => x.Key, x => x.Value);
```

### Query Syntax vs. Method Syntax

LINQ has two syntaxes. The compiler translates query syntax into method
syntax — they produce identical IL. Method syntax is more commonly used
in C# (as opposed to VB.NET), but query syntax is clearer for complex joins:

```csharp
// Query syntax (SQL-like)
var result =
    from order in orders
    where order.Total > 100
    join customer in customers on order.CustomerId equals customer.Id
    orderby order.Total descending
    select new { customer.Name, order.Total };

// Equivalent method syntax
var result2 = orders
    .Where(o => o.Total > 100)
    .Join(customers, o => o.CustomerId, c => c.Id,
          (o, c) => new { c.Name, o.Total })
    .OrderByDescending(x => x.Total);
```

---

## 7.10 `IEnumerable<T>` vs `IQueryable<T>` — Where Execution Happens

This distinction is one of the most important things to understand when
working with databases (Chapter 15):

- `IEnumerable<T>` executes in your process. Every LINQ operator runs in
  C#, over data already in memory.

- `IQueryable<T>` builds an expression tree (Ch 4 §4.7). A provider
  (EF Core, for example) translates it to SQL and executes it in the
  database. Only the result rows arrive in memory.

```csharp
// IEnumerable: loads ALL orders then filters in .NET — expensive!
var pending = db.Orders.ToList()  // materialise entire table
    .Where(o => o.Status == "pending"); // filter in C#

// IQueryable: SQL is "SELECT * FROM orders WHERE status = 'pending'" — efficient
var pending2 = db.Orders           // IQueryable
    .Where(o => o.Status == "pending")  // added to expression tree
    .ToList();                          // NOW executes: sends SQL to DB, gets only matching rows
```

The detailed treatment of this distinction is in Chapter 15 §15.12.

---

## 7.11 Connecting Collections and LINQ to the Rest of the Book

- **Ch 8 (Async)** — `IAsyncEnumerable<T>` extends the sequence model
  to async sources. `await foreach` is `foreach` for async streams.
- **Ch 14 (ASP.NET Core)** — Pagination, filtering, and sorting in API
  endpoints all use LINQ operators over `IQueryable<T>`.
- **Ch 15 (EF Core)** — EF Core implements `IQueryable<T>`. Every LINQ
  chain you write against `DbSet<T>` becomes SQL.
- **Ch 26 (Memory)** — `Span<T>`, `Memory<T>`, and `ArrayPool<T>` are
  the tools for avoiding collections allocations on hot paths.
- **Ch 38 (Multithreading)** — `ConcurrentDictionary`, `ConcurrentQueue`,
  and `ImmutableDictionary` from this chapter are the thread-safe
  collection tools explored in the concurrency projects.
