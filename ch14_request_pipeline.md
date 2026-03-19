# Chapter 14 — ASP.NET Core: Request Pipeline, Middleware, Controllers & Services

## 14.1 The Problem This All Solves

A web server receives a raw TCP packet. Somewhere in your code, a method returns
a typed C# object. Between those two things, a lot has to happen:

```
TCP packet arrives
    ↓
Parse HTTP (headers, method, path, body)
    ↓
Route to the right handler
    ↓
Authenticate (is this a valid token?)
    ↓
Authorize (is this user allowed to do this?)
    ↓
Decode and validate the request body
    ↓
YOUR CODE runs
    ↓
Serialize the response
    ↓
Send HTTP response
```

Without a framework, you write all of that. ASP.NET Core solves it with two
complementary systems:

- **Middleware pipeline** — everything that happens before and after your code
- **Routing + Handlers** — getting the right request to the right code

Understanding both is not optional. They are the skeleton every ASP.NET Core
application runs on.

---

## 14.2 The Request Pipeline — What Actually Happens

The pipeline is a chain of middleware. Each piece either handles the request
completely or passes it to the next piece via `next()`.

```
Request
  │
  ▼
┌─────────────────────────────────────────┐
│  ExceptionHandler middleware            │ ← catches any unhandled exception below
│  ┌───────────────────────────────────┐  │
│  │  HTTPS Redirection                │  │ ← redirects http → https
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Static Files               │  │  │ ← serves .js, .css, images
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │  Routing              │  │  │  │ ← matches URL to handler
│  │  │  │  ┌─────────────────┐  │  │  │  │
│  │  │  │  │  Authentication  │  │  │  │  │ ← reads token, sets User
│  │  │  │  │  ┌───────────┐  │  │  │  │  │
│  │  │  │  │  │Authorization│  │  │  │  │  │ ← checks User has permission
│  │  │  │  │  │  ┌──────┐  │  │  │  │  │  │
│  │  │  │  │  │  │ YOUR │  │  │  │  │  │  │
│  │  │  │  │  │  │HANDLER│  │  │  │  │  │  │
│  │  │  │  │  │  └──────┘  │  │  │  │  │  │
│  │  │  │  │  └────────────┘  │  │  │  │  │
│  │  │  │  └──────────────────┘  │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
  │
  ▼
Response travels back OUT through the same chain in reverse
```

Each middleware wraps everything below it. `ExceptionHandler` wraps the entire
pipeline — if anything below throws, it catches it.

---

## 14.3 Building the Pipeline — `Program.cs`

```csharp
var builder = WebApplication.CreateBuilder(args);

// ── 1. Register services (DI container) ──────────────────────────────
builder.Services.AddControllers();                   // or AddEndpointsApiExplorer()
builder.Services.AddAuthentication().AddJwtBearer();
builder.Services.AddAuthorization();
builder.Services.AddScoped<IOrderService, OrderService>();

var app = builder.Build();

// ── 2. Configure middleware pipeline (ORDER MATTERS) ─────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/error");  // production error handler
    app.UseHsts();                      // HTTP Strict Transport Security
}

app.UseHttpsRedirection();   // redirect HTTP → HTTPS
app.UseStaticFiles();        // serve wwwroot files before routing
app.UseRouting();            // enable route matching
app.UseCors();               // CORS headers (must be after UseRouting)
app.UseAuthentication();     // read token, populate HttpContext.User
app.UseAuthorization();      // check User has permission (must be after Authentication)
app.UseRateLimiter();        // rate limiting (NET 7+)

// ── 3. Map endpoints ─────────────────────────────────────────────────
app.MapControllers();        // or:
app.MapGet("/health", () => Results.Ok("healthy"));

app.Run();
```

**Order is critical.** `UseAuthentication` before `UseAuthorization` — always.
`UseRouting` before `UseCors` — always. Getting this wrong is a silent bug:
everything compiles, the app starts, but auth doesn't work, or CORS headers
are missing, and you spend hours debugging.

---

## 14.4 Writing Middleware

### Why Custom Middleware Exists

There are cross-cutting concerns that should run for every request without
being repeated in every handler: logging, timing, request ID injection,
correlation IDs for distributed tracing, response compression, API versioning headers.

Without middleware, you write it in every handler or forget it in some.

### Inline Middleware (`Use`)

```csharp
// RequestTimingMiddleware — measures and logs every request duration
app.Use(async (context, next) =>
{
    var sw = Stopwatch.StartNew();
    var path = context.Request.Path;

    try
    {
        await next(context);   // call the next middleware in the chain
    }
    finally
    {
        sw.Stop();
        var status = context.Response.StatusCode;
        Console.WriteLine($"{context.Request.Method} {path} {status} {sw.ElapsedMilliseconds}ms");
    }
});
```

### Class-Based Middleware (Recommended for anything reusable)

```csharp
// Middleware/RequestIdMiddleware.cs
// Injects a unique ID into every request for distributed tracing
public class RequestIdMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestIdMiddleware> _log;

    // Note: ILogger injected here via constructor — middleware is a singleton
    public RequestIdMiddleware(RequestDelegate next, ILogger<RequestIdMiddleware> log)
    {
        _next = next;
        _log  = log;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Generate or read existing request ID
        var requestId = context.Request.Headers["X-Request-ID"].FirstOrDefault()
                        ?? Guid.NewGuid().ToString("N")[..8];

        // Add to response so client can correlate
        context.Response.Headers["X-Request-ID"] = requestId;

        // Add to log scope — all log entries within this request include it
        using (_log.BeginScope(new { RequestId = requestId }))
        {
            _log.LogInformation("→ {Method} {Path}", context.Request.Method, context.Request.Path);
            await _next(context);
            _log.LogInformation("← {StatusCode}", context.Response.StatusCode);
        }
    }
}

// Extension method for clean registration
public static class RequestIdMiddlewareExtensions
{
    public static IApplicationBuilder UseRequestId(this IApplicationBuilder app)
        => app.UseMiddleware<RequestIdMiddleware>();
}

// Program.cs
app.UseRequestId();
```

### Middleware vs Filter vs Service — When to Use Which

```
Middleware    → runs for EVERY request, before routing resolves the handler
               use for: logging, timing, compression, request ID, CORS, auth
               can short-circuit the entire pipeline

Filter        → runs for requests that MATCHED a controller/endpoint
               use for: input validation, response shaping, endpoint-level logging
               has access to controller context (action name, route values)

Service       → business logic, called by handlers
               has no knowledge of HTTP at all
               use for: everything your application actually does
```

---

## 14.5 Routing

Routing maps an incoming URL to a handler. ASP.NET Core has two routing systems
that coexist:

### Attribute Routing (Controllers)

```csharp
[ApiController]
[Route("api/v1/orders")]
public class OrdersController : ControllerBase
{
    [HttpGet]                           // GET /api/v1/orders
    [HttpGet("{id:guid}")]              // GET /api/v1/orders/550e8400-...
    [HttpPost]                          // POST /api/v1/orders
    [HttpPut("{id:guid}")]              // PUT /api/v1/orders/550e8400-...
    [HttpDelete("{id:guid}")]           // DELETE /api/v1/orders/550e8400-...

    // Route constraints
    [HttpGet("{id:int:min(1)}")]        // int, must be >= 1
    [HttpGet("{name:alpha:minlength(2)}")] // letters only, min 2 chars
    [HttpGet("{date:datetime}")]        // valid DateTime
}
```

### Minimal API Routing (NET 6+)

```csharp
// Flat — good for small APIs
app.MapGet("/api/orders",         handler);
app.MapGet("/api/orders/{id}",    handler);
app.MapPost("/api/orders",        handler);

// Route groups — good for organizing larger APIs
var orders = app.MapGroup("/api/v1/orders")
    .RequireAuthorization()
    .WithTags("Orders");

orders.MapGet("/",    ListOrders);
orders.MapGet("/{id:guid}", GetOrder);
orders.MapPost("/",   CreateOrder);
orders.MapPut("/{id:guid}", UpdateOrder);
orders.MapDelete("/{id:guid}", DeleteOrder);
```

---

## 14.6 Controllers — The Right Way

### What a Controller Should Do

A controller has exactly one job: **translate HTTP into a method call and translate
the result back into HTTP**. Nothing else.

```csharp
// ❌ Fat controller — business logic in the HTTP layer
[ApiController]
[Route("api/orders")]
public class OrdersController : ControllerBase
{
    private readonly AppDbContext _db;
    public OrdersController(AppDbContext db) => _db = db;

    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderRequest req)
    {
        // ❌ Business logic here
        if (req.Amount > 50_000)
            return BadRequest("Order too large");

        // ❌ Database logic here
        var order = new Order
        {
            CustomerId = req.CustomerId,
            Amount     = req.Amount,
            Status     = "Pending",
            CreatedAt  = DateTime.UtcNow
        };
        _db.Orders.Add(order);
        await _db.SaveChangesAsync();

        // ❌ Response shaping logic here
        return CreatedAtAction(nameof(GetById),
            new { id = order.Id },
            new { order.Id, order.Amount });
    }
}
// Change order size limit → touch controller
// Change DB schema → touch controller
// Change response format → touch controller
// Three reasons to change = three ways to break accidentally
```

```csharp
// ✅ Thin controller — only HTTP translation
[ApiController]
[Route("api/orders")]
public class OrdersController : ControllerBase
{
    private readonly IOrderService _orders;
    public OrdersController(IOrderService orders) => _orders = orders;

    [HttpPost]
    public async Task<IActionResult> Create(
        CreateOrderRequest req, CancellationToken ct)
    {
        var result = await _orders.CreateAsync(req, ct);

        return result.Match<IActionResult>(
            ok:   order => CreatedAtAction(nameof(GetById),
                               new { id = order.Id }, order),
            fail: error => error.Type switch
            {
                ErrorType.Validation => BadRequest(error.Detail),
                ErrorType.NotFound   => NotFound(error.Detail),
                _                    => Problem(error.Detail)
            });
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<OrderDto>> GetById(Guid id, CancellationToken ct)
    {
        var order = await _orders.GetByIdAsync(new OrderId(id), ct);
        return order is null ? NotFound() : Ok(order);
    }
}
```

### Controller Base Classes

```csharp
// ControllerBase — for APIs (no View support)
// Use this for REST APIs
public class OrdersController : ControllerBase { }

// Controller — for MVC apps with Views (Razor)
// Use this only if rendering HTML server-side
public class HomeController : Controller { }

// [ApiController] attribute — adds:
// - automatic model validation (returns 400 if model is invalid)
// - automatic binding inference (reads body as JSON without [FromBody])
// - problem details responses (RFC 7807 format for errors)
[ApiController]
public class OrdersController : ControllerBase { }
```

---

## 14.7 Services — Where the Work Happens

The Service layer is your application logic. It knows nothing about HTTP.
It receives domain objects, does work, returns results.

```csharp
// Abstractions/IOrderService.cs — defined in Application or Core layer
public interface IOrderService
{
    Task<Result<OrderDto, ServiceError>> CreateAsync(
        CreateOrderRequest req, CancellationToken ct);

    Task<OrderDto?>                      GetByIdAsync(
        OrderId id, CancellationToken ct);

    Task<PagedResult<OrderDto>>          ListAsync(
        OrderQuery query, CancellationToken ct);

    Task<Result<Unit, ServiceError>>     CancelAsync(
        OrderId id, string reason, CancellationToken ct);
}

// Services/OrderService.cs — the implementation
public class OrderService : IOrderService
{
    private readonly IOrderRepository   _orders;
    private readonly IInventoryService  _inventory;
    private readonly IEventBus          _events;
    private readonly ILogger<OrderService> _log;

    public OrderService(
        IOrderRepository orders,
        IInventoryService inventory,
        IEventBus events,
        ILogger<OrderService> log)
    {
        _orders    = orders;
        _inventory = inventory;
        _events    = events;
        _log       = log;
    }

    public async Task<Result<OrderDto, ServiceError>> CreateAsync(
        CreateOrderRequest req, CancellationToken ct)
    {
        // Validate domain rules
        if (req.Amount > OrderLimits.MaxOrderValue)
            return ServiceError.Validation($"Amount exceeds maximum of {OrderLimits.MaxOrderValue:C}");

        // Check inventory
        var inStock = await _inventory.IsAvailableAsync(req.Sku, req.Quantity, ct);
        if (!inStock)
            return ServiceError.Conflict($"'{req.Sku}' is out of stock");

        // Create domain entity
        var order = Order.Create(
            customerId: new CustomerId(req.CustomerId),
            sku:        new Sku(req.Sku),
            quantity:   req.Quantity,
            unitPrice:  req.UnitPrice);

        // Persist
        await _orders.SaveAsync(order, ct);

        // Raise domain event
        await _events.PublishAsync(new OrderCreatedEvent(order.Id, order.Total), ct);

        _log.LogInformation("Order {OrderId} created for {Customer}", order.Id, req.CustomerId);
        return OrderDto.From(order);
    }
}
```

Notice what `OrderService` does NOT know:
- What HTTP status code to return
- What `HttpContext` is
- What a route is
- What the request Content-Type was

It only knows orders.

---

## 14.8 Minimal APIs — The Modern Alternative

Minimal APIs skip the `Controller` class entirely. The handler is a function.

```csharp
// Program.cs or split into endpoint files
var orders = app.MapGroup("/api/orders").RequireAuthorization();

// Handler as a lambda
orders.MapGet("/", async (
    [FromQuery] int page,
    [FromQuery] int pageSize,
    IOrderService svc,
    CancellationToken ct) =>
{
    var result = await svc.ListAsync(new OrderQuery(page, pageSize), ct);
    return Results.Ok(result);
});

// Handler as a static method — recommended for non-trivial handlers
orders.MapPost("/", CreateOrder);
orders.MapGet("/{id:guid}", GetOrder);

// Static handler methods — same thin translator principle as controllers
static async Task<IResult> CreateOrder(
    CreateOrderRequest req,
    IOrderService svc,
    CancellationToken ct)
{
    var result = await svc.CreateAsync(req, ct);
    return result.Match(
        ok:   order => Results.Created($"/api/orders/{order.Id}", order),
        fail: error => error.Type switch
        {
            ErrorType.Validation => Results.ValidationProblem(
                new Dictionary<string, string[]> { ["request"] = [error.Detail] }),
            ErrorType.Conflict   => Results.Conflict(error.Detail),
            _                    => Results.Problem(error.Detail)
        });
}

static async Task<IResult> GetOrder(
    Guid id,
    IOrderService svc,
    CancellationToken ct)
{
    var order = await svc.GetByIdAsync(new OrderId(id), ct);
    return order is null ? Results.NotFound() : Results.Ok(order);
}
```

### Organizing Minimal APIs — Endpoint Classes

```csharp
// Endpoints/OrderEndpoints.cs — all order-related endpoints in one place
public static class OrderEndpoints
{
    public static IEndpointRouteBuilder MapOrders(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/orders")
            .RequireAuthorization()
            .WithTags("Orders")
            .WithOpenApi();

        group.MapGet("/",            ListOrders)  .WithName("ListOrders");
        group.MapGet("/{id:guid}",   GetOrder)    .WithName("GetOrder");
        group.MapPost("/",           CreateOrder) .WithName("CreateOrder");
        group.MapPut("/{id:guid}",   UpdateOrder) .WithName("UpdateOrder");
        group.MapDelete("/{id:guid}", CancelOrder).WithName("CancelOrder");

        return app;
    }

    // ... handler methods ...
}

// Program.cs — one line per feature
app.MapOrders();
app.MapUsers();
app.MapProducts();
```

---

## 14.9 Controllers vs Minimal APIs — Choose One

```
Controllers                          Minimal APIs
───────────────────────────────────  ───────────────────────────────────
Exists since ASP.NET MVC (2009)      NET 6+ (2021)
Class-based, more ceremony           Function-based, less ceremony
Built-in model binding attributes    Parameter binding via DI + attributes
Filters (action, result, exception)  Endpoint filters (similar but different)
Better for large teams / conventions Better for small APIs / microservices
Easier to apply global conventions   Easier to see what each endpoint does

When to use Controllers:
  - Large API with many endpoints
  - Team that knows MVC conventions
  - Need action filters extensively
  - Generating SDK clients from OpenAPI

When to use Minimal APIs:
  - New greenfield project
  - Microservice with few endpoints
  - Want explicit over convention
  - Working alone or small team
```

They can coexist. You can have both in one app during migration.

---

## 14.10 Model Binding — How Request Data Arrives

ASP.NET Core reads incoming data from multiple sources. The binding source
is either inferred (with `[ApiController]`) or explicit:

```csharp
// Binding sources — be explicit when it matters
public async Task<IResult> CreateOrder(
    [FromRoute]  Guid     customerId,    // /orders/{customerId}
    [FromQuery]  string?  promoCode,     // ?promoCode=SAVE10
    [FromBody]   CreateOrderRequest req, // JSON body
    [FromHeader] string?  idempotencyKey, // X-Idempotency-Key header
    [FromServices] IOrderService svc)    // injected from DI
{ }

// Minimal API — DI services are auto-detected, no [FromServices] needed
app.MapPost("/orders/{customerId}", async (
    Guid customerId,                // from route (auto)
    string? promoCode,              // from query string (auto if simple type)
    CreateOrderRequest req,         // from body (auto if complex type)
    IOrderService svc,              // from DI (auto)
    CancellationToken ct) => ...);
```

### Request Validation

```csharp
// With [ApiController] — validation runs automatically, returns 400 if fails
public class CreateOrderRequest
{
    [Required]
    public string CustomerId { get; set; } = "";

    [Required, MinLength(3)]
    public string Sku { get; set; } = "";

    [Range(1, 1000)]
    public int Quantity { get; set; }

    [Range(0.01, 100_000)]
    public decimal UnitPrice { get; set; }
}

// With FluentValidation (more powerful, recommended)
public class CreateOrderRequestValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderRequestValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty().MaximumLength(50);
        RuleFor(x => x.Sku).NotEmpty().Matches(@"^[A-Z]{3}-\d{4}$")
            .WithMessage("SKU must be in format ABC-1234");
        RuleFor(x => x.Quantity).InclusiveBetween(1, 1000);
        RuleFor(x => x.UnitPrice).GreaterThan(0).LessThanOrEqualTo(100_000);
    }
}
```

---

## 14.11 Response Types — What to Return

### From Controllers

```csharp
// Specific status codes
return Ok(dto);                              // 200 + JSON body
return Created($"/orders/{id}", dto);        // 201 + Location header + body
return CreatedAtAction(nameof(Get), new { id }, dto); // 201 + route-based Location
return NoContent();                          // 204 — for PUT/DELETE that succeed
return BadRequest("Reason");                 // 400
return BadRequest(new ValidationProblemDetails(ModelState)); // 400 + RFC 7807
return NotFound();                           // 404
return Conflict("Already exists");           // 409
return UnprocessableEntity("Business rule"); // 422
return Problem("Internal error");            // 500 + RFC 7807

// Typed return for OpenAPI schema generation
public async Task<ActionResult<OrderDto>> GetById(Guid id)
{
    var order = await _svc.GetByIdAsync(id);
    return order is null ? NotFound() : Ok(order); // OpenAPI knows both shapes
}
```

### From Minimal APIs

```csharp
Results.Ok(dto)                           // 200
Results.Created($"/orders/{id}", dto)     // 201
Results.NoContent()                       // 204
Results.BadRequest("Reason")              // 400
Results.ValidationProblem(errors)         // 400 + RFC 7807
Results.NotFound()                        // 404
Results.Conflict(detail)                  // 409
Results.Problem(detail)                   // 500 + RFC 7807

// TypedResults — preserves type info for OpenAPI
TypedResults.Ok(dto)
TypedResults.NotFound()
TypedResults.Created($"/orders/{id}", dto)
```

### Problem Details (RFC 7807) — the Standard Error Format

```csharp
// Register globally — all errors return RFC 7807 format
builder.Services.AddProblemDetails();

// Customize
builder.Services.AddProblemDetails(opts =>
{
    opts.CustomizeProblemDetails = ctx =>
    {
        ctx.ProblemDetails.Extensions["requestId"] =
            ctx.HttpContext.TraceIdentifier;
        ctx.ProblemDetails.Extensions["timestamp"] =
            DateTime.UtcNow;
    };
});

// A 404 now returns:
// {
//   "type": "https://tools.ietf.org/html/rfc7231#section-6.5.4",
//   "title": "Not Found",
//   "status": 404,
//   "requestId": "0HMVC1234:00000001",
//   "timestamp": "2025-01-15T10:30:00Z"
// }
```

---

## 14.12 Filters vs Middleware

Both intercept the request — but at different points and with different context.

```
Request
  │
  ▼
[Middleware]   ← runs here, no knowledge of which endpoint matched
  │
  ▼
[Routing resolves handler]
  │
  ▼
[Authorization]
  │
  ▼
[Action Filters]  ← runs here, knows the controller, action, parameters
  │
  ▼
[Action runs]
  │
  ▼
[Result Filters]  ← runs here, knows the result
  │
  ▼
[Response]
```

### Writing an Action Filter

```csharp
// Filters/ValidateModelFilter.cs
// Runs before every action, returns 400 if model is invalid
// (With [ApiController] this is automatic — shown for custom logic)
public class ValidateModelFilter : IActionFilter
{
    public void OnActionExecuting(ActionExecutingContext context)
    {
        if (!context.ModelState.IsValid)
        {
            context.Result = new BadRequestObjectResult(
                new ValidationProblemDetails(context.ModelState));
        }
    }

    public void OnActionExecuted(ActionExecutedContext context) { }
}

// Register globally
builder.Services.AddControllers(opts =>
    opts.Filters.Add<ValidateModelFilter>());

// Or per controller / per action
[TypeFilter(typeof(ValidateModelFilter))]
public class OrdersController : ControllerBase { }
```

### Exception Filter — Consistent Error Responses

```csharp
// Filters/ApiExceptionFilter.cs
// Converts domain exceptions to HTTP responses consistently
public class ApiExceptionFilter : IExceptionFilter
{
    private readonly ILogger<ApiExceptionFilter> _log;
    public ApiExceptionFilter(ILogger<ApiExceptionFilter> log) => _log = log;

    public void OnException(ExceptionContext context)
    {
        var (status, title) = context.Exception switch
        {
            NotFoundException ex  => (404, ex.Message),
            ValidationException ex => (400, ex.Message),
            ConflictException ex  => (409, ex.Message),
            UnauthorizedException  => (401, "Unauthorized"),
            _                      => (500, "An unexpected error occurred")
        };

        if (status == 500)
            _log.LogError(context.Exception, "Unhandled exception");

        context.Result = new ObjectResult(new ProblemDetails
        {
            Status = status,
            Title  = title,
            Extensions = { ["requestId"] = context.HttpContext.TraceIdentifier }
        })
        { StatusCode = status };

        context.ExceptionHandled = true;
    }
}
```

---

## 14.13 The Full Picture — Wiring It Together

```csharp
// Program.cs — a complete, production-ready setup
var builder = WebApplication.CreateBuilder(args);

// ── Services ──────────────────────────────────────────────────────────
builder.Services
    .AddControllers(opts => opts.Filters.Add<ApiExceptionFilter>())
    .AddJsonOptions(opts => opts.JsonSerializerOptions.PropertyNamingPolicy
        = JsonNamingPolicy.CamelCase);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddProblemDetails();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts =>
    {
        opts.Authority = builder.Configuration["Auth:Authority"];
        opts.Audience  = builder.Configuration["Auth:Audience"];
    });

builder.Services.AddAuthorization(opts =>
    opts.AddPolicy("AdminOnly",
        policy => policy.RequireRole("admin")));

builder.Services.AddRateLimiter(opts =>
    opts.AddFixedWindowLimiter("api", o =>
    {
        o.PermitLimit         = 100;
        o.Window              = TimeSpan.FromMinutes(1);
        o.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        o.QueueLimit          = 10;
    }));

// Application services
builder.Services
    .AddData(builder.Configuration)
    .AddApp()
    .AddInfra(builder.Configuration);

var app = builder.Build();

// ── Middleware pipeline ───────────────────────────────────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseExceptionHandler();        // global exception → problem details
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.UseRequestId();               // custom middleware

// ── Endpoints ─────────────────────────────────────────────────────────
app.MapControllers();
app.MapHealthChecks("/healthz");
app.MapSwagger().RequireAuthorization("AdminOnly");

app.Run();
```

---

## 14.14 Seeing the Pipeline in Rider

**Middleware order inspection:**
- Open `Program.cs` → Rider shows the call chain in the Structure panel
- `Alt+F7` on `UseAuthentication` → finds every registration and usage

**Navigate controller → service:**
- `Ctrl+Alt+B` on `IOrderService` in constructor → jumps to `OrderService`
- `Alt+F7` on the interface → shows all injections, all call sites

**HTTP test files:**
- Create `requests.http` → Rider runs requests and shows responses inline
- Test each endpoint without leaving the IDE

> **Rider tip:** *Run → HTTP Client → Create Request in HTTP Client* generates a `.http`
> stub for the endpoint your cursor is on. Saves time writing test requests manually.

> **VS tip:** The *Endpoints Explorer* (`View → Other Windows → Endpoints Explorer`)
> lists every mapped route in the solution with HTTP method, path, and handler.
> Click any endpoint to navigate to its handler.

