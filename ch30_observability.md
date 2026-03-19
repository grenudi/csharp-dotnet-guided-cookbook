# Chapter 30 — Observability: OpenTelemetry, Metrics & Distributed Tracing

## 30.1 Why Observability Matters

Logging tells you what happened. Observability tells you why.

In a distributed system — even a simple one with an API and a background worker —
a user-facing error may have been caused by a slow database query three service calls
deep, triggered by a memory spike, five minutes ago. Logs alone cannot answer that.

The three pillars:

```
Logs     — discrete events: "order 42 failed with NullReferenceException"
Metrics  — aggregated measurements: "99th percentile latency is 450ms"
Traces   — causal chain across services: request A called B called C, here's the timeline
```

OpenTelemetry (OTel) is the vendor-neutral standard for all three. Write it once,
send to any backend: Jaeger, Zipkin, Prometheus, Grafana, Datadog, Azure Monitor.

---

## 30.2 OpenTelemetry Setup

```bash
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Instrumentation.Http
dotnet add package OpenTelemetry.Instrumentation.EntityFrameworkCore
dotnet add package OpenTelemetry.Exporter.Console          # dev
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol  # prod (OTLP)
dotnet add package OpenTelemetry.Exporter.Prometheus.AspNetCore  # metrics
```

```csharp
// Program.cs
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService(
        serviceName:    "MyApp.Api",
        serviceVersion: "1.0.0",
        serviceInstanceId: Environment.MachineName))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(opts =>
        {
            opts.RecordException = true;
            opts.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/healthz");
        })
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation(opts =>
            opts.SetDbStatementForText = true)  // include SQL in spans
        .AddSource("MyApp.*")                   // include custom activity sources
        .AddConsoleExporter()                   // dev
        .AddOtlpExporter(opts =>               // prod → Jaeger/Grafana/etc
            opts.Endpoint = new Uri("http://collector:4317")))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()            // GC, thread pool, etc.
        .AddProcessInstrumentation()
        .AddMeter("MyApp.*")                   // custom meters
        .AddPrometheusExporter()               // scrape endpoint for Prometheus
        .AddOtlpExporter());

// Add Prometheus scrape endpoint
app.MapPrometheusScrapingEndpoint("/metrics");
// Protect it in production:
// app.MapPrometheusScrapingEndpoint("/metrics").RequireAuthorization("AdminOnly");
```

---

## 30.3 Distributed Tracing — Custom Spans

```csharp
using System.Diagnostics;

// Define your ActivitySource once — this is the tracer
public static class Telemetry
{
    public static readonly ActivitySource Source = new("MyApp.OrderService");
}

// Register it
builder.Services.AddOpenTelemetry()
    .WithTracing(t => t.AddSource("MyApp.OrderService"));

public class OrderService : IOrderService
{
    public async Task<OrderDto> CreateOrderAsync(CreateOrderRequest req, CancellationToken ct)
    {
        // Start a span — child of the current incoming request span
        using var activity = Telemetry.Source.StartActivity("CreateOrder");

        // Add attributes to the span
        activity?.SetTag("order.customerId", req.CustomerId);
        activity?.SetTag("order.sku",        req.Sku);
        activity?.SetTag("order.quantity",   req.Quantity);

        try
        {
            // Child span for the DB operation
            using var dbSpan = Telemetry.Source.StartActivity("SaveOrder");
            var order = await _repo.SaveAsync(req.ToOrder(), ct);
            dbSpan?.SetTag("db.order_id", order.Id.ToString());

            // Child span for event publishing
            using var eventSpan = Telemetry.Source.StartActivity("PublishOrderCreated");
            await _events.PublishAsync(new OrderCreatedEvent(order.Id), ct);

            activity?.SetTag("order.id",     order.Id.ToString());
            activity?.SetStatus(ActivityStatusCode.Ok);

            return OrderDto.From(order);
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.RecordException(ex);
            throw;
        }
    }
}
```

### Trace Propagation — Across Services

```csharp
// Outgoing HTTP calls automatically propagate trace context via W3C headers:
// traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01

// When HttpClient is instrumented, this is automatic
// For manual propagation (e.g., message queues):
var propagator = Propagators.DefaultTextMapPropagator;

// Inject into outgoing message
var carrier    = new Dictionary<string, string>();
propagator.Inject(new PropagationContext(Activity.Current?.Context ?? default, Baggage.Current),
    carrier, (c, key, value) => c[key] = value);

// message.Headers = carrier  → send with the message

// Extract from incoming message
var context = propagator.Extract(default, messageHeaders,
    (headers, key) => headers.TryGetValue(key, out var v) ? new[] { v } : Array.Empty<string>());

using var activity = Telemetry.Source.StartActivity("ProcessMessage",
    ActivityKind.Consumer, context.ActivityContext);
```

---

## 30.4 Metrics — Custom Measurements

```csharp
using System.Diagnostics.Metrics;

// Define meters and instruments once
public static class AppMetrics
{
    private static readonly Meter _meter = new("MyApp.Api", "1.0.0");

    // Counter — only goes up
    public static readonly Counter<long> OrdersCreated =
        _meter.CreateCounter<long>("orders.created", unit: "{orders}",
            description: "Number of orders created");

    // Histogram — distribution of values (for latency, sizes)
    public static readonly Histogram<double> OrderProcessingDuration =
        _meter.CreateHistogram<double>("order.processing.duration", unit: "ms",
            description: "Order processing time in milliseconds");

    // Gauge — current value (via ObservableGauge)
    public static readonly ObservableGauge<int> ActiveOrders =
        _meter.CreateObservableGauge<int>("orders.active",
            () => OrderTracker.ActiveCount,
            description: "Currently active orders");

    // UpDownCounter — can go up and down
    public static readonly UpDownCounter<int> QueueDepth =
        _meter.CreateUpDownCounter<int>("queue.depth", description: "Messages in queue");
}

// Use in code
public async Task<OrderDto> CreateOrderAsync(CreateOrderRequest req, CancellationToken ct)
{
    var sw = Stopwatch.StartNew();
    try
    {
        var order = await ProcessOrderAsync(req, ct);

        // Record with dimensions (tags)
        AppMetrics.OrdersCreated.Add(1,
            new TagList
            {
                { "order.status",   "success" },
                { "order.currency", req.Currency },
                { "customer.tier",  req.CustomerTier }
            });

        return order;
    }
    catch
    {
        AppMetrics.OrdersCreated.Add(1,
            new TagList { { "order.status", "failed" } });
        throw;
    }
    finally
    {
        AppMetrics.OrderProcessingDuration.Record(sw.Elapsed.TotalMilliseconds,
            new TagList { { "order.type", req.Type } });
    }
}
```

---

## 30.5 Structured Logging Integration

With OpenTelemetry, logs are automatically correlated to traces. The `TraceId`
and `SpanId` from the current activity are injected into log entries.

```csharp
// Serilog + OpenTelemetry correlation
Log.Logger = new LoggerConfiguration()
    .Enrich.WithProperty("ServiceName", "MyApp.Api")
    .Enrich.FromLogContext()
    .WriteTo.OpenTelemetry(opts =>           // send logs via OTLP
    {
        opts.Endpoint = "http://collector:4317";
        opts.ResourceAttributes = new Dictionary<string, object>
        {
            ["service.name"]    = "MyApp.Api",
            ["service.version"] = "1.0.0",
        };
    })
    .WriteTo.Console()
    .CreateLogger();

// In the log output, every line will include:
// TraceId: 4bf92f3577b34da6a3ce929d0e0e4736
// SpanId:  00f067aa0ba902b7
// These correlate to the distributed trace in Jaeger/Grafana
```

---

## 30.6 .NET Aspire — Cloud-Native Orchestration (NET 9+)

.NET Aspire is Microsoft's answer to the complexity of local multi-service development.
It wires up services, databases, and dependencies for local development with
OpenTelemetry built in.

```bash
dotnet new aspire-starter -n MyApp
```

```csharp
// AppHost/Program.cs — declare your distributed application
var builder = DistributedApplication.CreateBuilder(args);

var postgres = builder.AddPostgres("db")
    .WithDataVolume()
    .AddDatabase("myapp");

var redis = builder.AddRedis("cache");

var api = builder.AddProject<Projects.MyApp_Api>("api")
    .WithReference(postgres)
    .WithReference(redis)
    .WithEnvironment("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317");

builder.AddProject<Projects.MyApp_Worker>("worker")
    .WithReference(api)
    .WithReference(postgres);

builder.Build().Run();
// Starts everything, wires service discovery, injects connection strings,
// opens the Aspire Dashboard with traces/metrics/logs built in
```

> **Rider tip:** The *OpenTelemetry* plugin for Rider shows trace spans inline in
> the editor alongside the code that generated them (experimental, 2024+).
> The standard approach is to open Jaeger/Grafana in a browser alongside Rider.

> **VS tip:** .NET Aspire Dashboard opens automatically when you run an Aspire
> project from VS 2022. It shows distributed traces, metrics, and structured logs
> with full correlation, no external tools needed for local dev.
