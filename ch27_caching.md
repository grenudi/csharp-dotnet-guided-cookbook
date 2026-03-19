# Chapter 27 — Caching

## 27.1 Why Caching Exists

A cache stores expensive results so you don't recompute or re-fetch them on the next request.
The same pattern, the same tradeoffs, every time:

```
Without cache:   Request → Database (50ms) → Response
With cache:      Request → Cache hit (0.1ms) → Response
                           or
                           Cache miss → Database (50ms) → Store in cache → Response
```

The cost: you trade **memory** for **speed**, and you accept that cached data may be
**stale**. Every caching decision is really a decision about how much staleness is acceptable.

---

## 27.2 IMemoryCache — In-Process Cache

Lives in the same process. Fastest possible access. Lost on restart. Not shared between instances.

```csharp
// Register
builder.Services.AddMemoryCache();

// Inject
public class ProductService
{
    private readonly IMemoryCache _cache;
    private readonly IProductRepository _repo;

    public ProductService(IMemoryCache cache, IProductRepository repo)
    { _cache = cache; _repo = repo; }

    public async Task<Product?> GetByIdAsync(int id, CancellationToken ct)
    {
        var cacheKey = $"product:{id}";

        // TryGetValue — synchronous, no async version needed (cache is in-memory)
        if (_cache.TryGetValue(cacheKey, out Product? cached))
            return cached;

        // Cache miss — fetch from DB
        var product = await _repo.GetByIdAsync(id, ct);

        if (product is not null)
        {
            _cache.Set(cacheKey, product, new MemoryCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5),
                SlidingExpiration               = TimeSpan.FromMinutes(2),
                Size                            = 1,  // relative size unit (requires SizeLimit)
                Priority                        = CacheItemPriority.Normal,
            });
        }

        return product;
    }

    public void Invalidate(int id) => _cache.Remove($"product:{id}");
}
```

### GetOrCreateAsync — Cleaner Pattern

```csharp
var product = await _cache.GetOrCreateAsync($"product:{id}", async entry =>
{
    entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
    entry.SlidingExpiration               = TimeSpan.FromMinutes(2);
    return await _repo.GetByIdAsync(id, ct);
});
```

### Memory Limits (Critical — without this, cache can grow unbounded)

```csharp
// Register with size limit
builder.Services.AddMemoryCache(opts =>
{
    opts.SizeLimit = 1024;  // max 1024 "units" (you define what a unit is)
    opts.CompactionPercentage = 0.25;  // remove 25% of entries when limit hit
});

// Each entry must declare its size
_cache.Set(key, value, new MemoryCacheEntryOptions
{
    Size = 1,  // this entry costs 1 unit
    AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10)
});
```

---

## 27.3 IDistributedCache — Shared Cache

Shared across multiple instances. Survives restarts (depending on backend).
Required for horizontally scaled applications.

```csharp
// Register with Redis (most common)
builder.Services.AddStackExchangeRedisCache(opts =>
{
    opts.Configuration = builder.Configuration.GetConnectionString("Redis");
    opts.InstanceName  = "MyApp:";  // key prefix — isolates this app's keys
});

// Or in-memory for dev/testing (same API, no Redis needed)
builder.Services.AddDistributedMemoryCache();

// Use
public class SessionService
{
    private readonly IDistributedCache _cache;

    public SessionService(IDistributedCache cache) => _cache = cache;

    public async Task SetSessionAsync(string token, UserSession session, CancellationToken ct)
    {
        var json    = JsonSerializer.SerializeToUtf8Bytes(session);
        var options = new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1),
            SlidingExpiration               = TimeSpan.FromMinutes(20),
        };
        await _cache.SetAsync(token, json, options, ct);
    }

    public async Task<UserSession?> GetSessionAsync(string token, CancellationToken ct)
    {
        var bytes = await _cache.GetAsync(token, ct);
        return bytes is null ? null : JsonSerializer.Deserialize<UserSession>(bytes);
    }

    public async Task RemoveSessionAsync(string token, CancellationToken ct)
        => await _cache.RemoveAsync(token, ct);
}
```

### Typed Cache Wrapper Pattern

```csharp
// Avoid spreading cache key strings and serialization across the codebase
public class ProductCache
{
    private readonly IDistributedCache _cache;
    private static readonly JsonSerializerOptions _opts = new(JsonSerializerDefaults.Web);

    private static string Key(int id) => $"product:v1:{id}";

    public ProductCache(IDistributedCache cache) => _cache = cache;

    public async Task<Product?> GetAsync(int id, CancellationToken ct)
    {
        var bytes = await _cache.GetAsync(Key(id), ct);
        return bytes is null ? null : JsonSerializer.Deserialize<Product>(bytes, _opts);
    }

    public async Task SetAsync(Product product, CancellationToken ct)
    {
        var bytes   = JsonSerializer.SerializeToUtf8Bytes(product, _opts);
        var options = new DistributedCacheEntryOptions
            { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10) };
        await _cache.SetAsync(Key(product.Id), bytes, options, ct);
    }

    public async Task InvalidateAsync(int id, CancellationToken ct)
        => await _cache.RemoveAsync(Key(id), ct);
}
```

---

## 27.4 Output Caching (NET 7+)

Caches complete HTTP responses at the middleware level — no code needed in handlers.

```csharp
// Register
builder.Services.AddOutputCache(opts =>
{
    // Default policy
    opts.AddBasePolicy(policy => policy.Expire(TimeSpan.FromSeconds(30)));

    // Named policies
    opts.AddPolicy("Products", policy => policy
        .Expire(TimeSpan.FromMinutes(5))
        .SetVaryByQuery("page", "pageSize")
        .SetVaryByHeader("Accept-Language")
        .Tag("products"));  // tag for targeted invalidation
});

// Middleware
app.UseOutputCache();

// Apply to endpoints
app.MapGet("/api/products", GetProducts)
    .CacheOutput("Products");

// Or on controller actions
[OutputCache(PolicyName = "Products")]
[HttpGet]
public async Task<IActionResult> GetProducts() { /* ... */ }

// No policy = use base policy
[OutputCache(Duration = 60)]
[HttpGet("{id}")]
public async Task<IActionResult> GetProduct(int id) { /* ... */ }

// Invalidate by tag (when product data changes)
public class ProductWriteService
{
    private readonly IOutputCacheStore _cache;

    public ProductWriteService(IOutputCacheStore cache) => _cache = cache;

    public async Task UpdateProductAsync(Product product, CancellationToken ct)
    {
        await _repo.UpdateAsync(product, ct);
        await _cache.EvictByTagAsync("products", ct);  // invalidate all product cache
    }
}
```

---

## 27.5 Cache-Aside Pattern — The Standard Approach

```
Check cache
    ↓ miss
Fetch from source
    ↓
Store in cache with TTL
    ↓
Return data
    ↓
When data changes: invalidate cache key
```

```csharp
// Generic cache-aside implementation
public class CacheAside<TKey, TValue>
    where TKey  : notnull
    where TValue : class
{
    private readonly IMemoryCache _cache;
    private readonly TimeSpan     _ttl;
    private readonly Func<TKey, string> _keyFn;

    public CacheAside(IMemoryCache cache, TimeSpan ttl, Func<TKey, string> keyFn)
    { _cache = cache; _ttl = ttl; _keyFn = keyFn; }

    public async Task<TValue?> GetOrLoadAsync(TKey key, Func<TKey, Task<TValue?>> load)
    {
        var cacheKey = _keyFn(key);
        if (_cache.TryGetValue(cacheKey, out TValue? cached)) return cached;

        var value = await load(key);
        if (value is not null)
            _cache.Set(cacheKey, value, _ttl);

        return value;
    }

    public void Invalidate(TKey key) => _cache.Remove(_keyFn(key));
}
```

---

## 27.6 Stampede Prevention

When a popular cache entry expires, many requests may simultaneously hit the database.
This is called a **cache stampede** or **thundering herd**.

```csharp
// SemaphoreSlim prevents stampede — only one request fetches, others wait
public class StampedeProtectedCache<T> where T : class
{
    private readonly IMemoryCache _cache;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public StampedeProtectedCache(IMemoryCache cache) => _cache = cache;

    public async Task<T?> GetOrLoadAsync(
        string key,
        Func<Task<T?>> load,
        TimeSpan ttl,
        CancellationToken ct)
    {
        // Fast path — no lock needed
        if (_cache.TryGetValue(key, out T? cached)) return cached;

        // Slow path — acquire lock, check again, then fetch
        await _lock.WaitAsync(ct);
        try
        {
            // Double-check after acquiring lock (another request may have loaded it)
            if (_cache.TryGetValue(key, out cached)) return cached;

            var value = await load();
            if (value is not null)
                _cache.Set(key, value, ttl);

            return value;
        }
        finally
        {
            _lock.Release();
        }
    }
}
```

---

## 27.7 When Not to Cache

```
Never cache:
  - Per-user financial data (show user A's balance to user B)
  - Anything that must be real-time accurate
  - Write operations (POST/PUT/DELETE responses)
  - Data that changes faster than your TTL (you'll always serve stale data)

Be careful caching:
  - Search results (vary by many query params — combinatorial explosion)
  - Personalized content (vary by user — kills cache hit rate)
  - Large objects (chews through memory limit quickly)

Cache confidently:
  - Reference data (countries, categories, config — changes rarely)
  - Expensive aggregations (reports, dashboards)
  - Public API responses (product listings, documentation)
  - Auth tokens (verify once, cache result briefly)
```

> **Rider tip:** Search for `GetByIdAsync` usages (`Alt+F7`) to find all the places
> that hit the database — these are your caching candidates. Rider's call stack in
> the profiler shows which DB calls are on the hot path.

> **VS tip:** *Application Insights → Performance → Dependencies* (Azure) shows
> which queries are called most frequently. High call count + low complexity = cache it.
