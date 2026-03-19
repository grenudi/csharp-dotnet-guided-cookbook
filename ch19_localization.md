# Chapter 19 — Localization & Internationalization

## 19.1 Why Bake It In From Day One

Retrofitting localization onto an existing app means touching every string in every
file. If you start with one language but structure it correctly from day one, adding
a second language later costs almost nothing.

The rule: **never put a user-facing string directly in code**.

```csharp
// ❌ Hard-coded — impossible to localize later without touching every file
Console.WriteLine("Order placed successfully.");
return Results.BadRequest("Email address is invalid.");
throw new Exception("User not found.");

// ✅ Resource key — one change point, swap language by config
Console.WriteLine(_loc["Order.PlacedSuccessfully"]);
return Results.BadRequest(_loc["Validation.Email.Invalid"]);
throw new NotFoundException(_loc["User.NotFound"]);
```

Even if you ship only English for five years, the structure costs nothing extra and
the payoff when you need language two is enormous.

---

## 19.2 Core Concepts

```
Culture         = language + region: "en-US", "de-DE", "fr-FR", "zh-Hans"
                  Language: what words to use
                  Region:   date format, number format, currency symbol

Invariant culture = no culture (used for serialization, logging — never user-facing)

Resource file (.resx) = XML key-value pairs for one culture
IStringLocalizer<T>   = .NET's built-in typed interface to resource files
ILocalizer            = abstraction you define for easier testing and swapping
```

### Culture vs UICulture

```csharp
// Thread.CurrentThread has two culture properties:
Thread.CurrentThread.CurrentCulture   // formatting: dates, numbers, currency
Thread.CurrentThread.CurrentUICulture // string resources: which .resx to load

// In ASP.NET Core middleware sets both from:
// 1. Accept-Language HTTP header
// 2. Query string: ?culture=de-DE
// 3. Cookie
// 4. Route segment: /de/orders
```

---

## 19.3 .resx Resource Files — The Standard Approach

### Project Structure

```
MyApp/
├── Resources/
│   ├── SharedResources.resx          ← default (English or neutral)
│   ├── SharedResources.de.resx       ← German
│   ├── SharedResources.fr.resx       ← French
│   └── SharedResources.zh-Hans.resx  ← Simplified Chinese
└── Program.cs
```

### Resource File Content

```xml
<!-- Resources/SharedResources.resx (English — the fallback) -->
<?xml version="1.0" encoding="utf-8"?>
<root>
  <data name="Order.PlacedSuccessfully" xml:space="preserve">
    <value>Order placed successfully.</value>
  </data>
  <data name="Order.NotFound" xml:space="preserve">
    <value>Order '{0}' was not found.</value>
  </data>
  <data name="Validation.Email.Invalid" xml:space="preserve">
    <value>'{0}' is not a valid email address.</value>
  </data>
  <data name="Validation.Required" xml:space="preserve">
    <value>'{0}' is required.</value>
  </data>
</root>
```

```xml
<!-- Resources/SharedResources.de.resx (German) -->
<root>
  <data name="Order.PlacedSuccessfully" xml:space="preserve">
    <value>Bestellung erfolgreich aufgegeben.</value>
  </data>
  <data name="Order.NotFound" xml:space="preserve">
    <value>Bestellung '{0}' wurde nicht gefunden.</value>
  </data>
  <data name="Validation.Email.Invalid" xml:space="preserve">
    <value>'{0}' ist keine gültige E-Mail-Adresse.</value>
  </data>
  <data name="Validation.Required" xml:space="preserve">
    <value>'{0}' ist erforderlich.</value>
  </data>
</root>
```

### Setup in ASP.NET Core

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// 1. Register localization services
builder.Services.AddLocalization(opts =>
    opts.ResourcesPath = "Resources");

// 2. Register request localization options
var supportedCultures = new[] { "en", "de", "fr", "zh-Hans" };
builder.Services.Configure<RequestLocalizationOptions>(opts =>
{
    opts.SetDefaultCulture("en");
    opts.AddSupportedCultures(supportedCultures);
    opts.AddSupportedUICultures(supportedCultures);

    // Order matters — first match wins
    opts.RequestCultureProviders = new List<IRequestCultureProvider>
    {
        new QueryStringRequestCultureProvider(),   // ?culture=de
        new CookieRequestCultureProvider(),        // cookie
        new AcceptLanguageHeaderRequestCultureProvider() // browser header
    };
});

var app = builder.Build();

// 3. Add middleware BEFORE routing
app.UseRequestLocalization();

app.MapGet("/orders/{id}", async (
    string id,
    IStringLocalizer<SharedResources> loc) =>
{
    // loc["Key"] — looks up in the .resx for the current culture
    // loc["Key", arg1] — with format arguments
    return Results.NotFound(loc["Order.NotFound", id].Value);
});

app.Run();

// Marker class for the generic type parameter
public class SharedResources { }
```

---

## 19.4 Using IStringLocalizer

```csharp
// Inject IStringLocalizer<T> where T is your marker class
public class OrderService
{
    private readonly IStringLocalizer<SharedResources> _loc;

    public OrderService(IStringLocalizer<SharedResources> loc) => _loc = loc;

    public string GetConfirmationMessage(string orderId)
        => _loc["Order.PlacedSuccessfully"];

    public string GetNotFoundMessage(string orderId)
        => _loc["Order.NotFound", orderId]; // {0} replaced with orderId

    // Check if a translation exists
    public bool HasTranslation(string key)
        => !_loc[key].ResourceNotFound;
}
```

### IStringLocalizer — Key Members

```csharp
// loc["Key"]                 → LocalizedString (never null, falls back to key if missing)
// loc["Key", arg1, arg2]    → formatted with string.Format
// loc["Key"].Value           → the string itself
// loc["Key"].ResourceNotFound → true if key not in .resx (useful for debugging)
// loc.GetAllStrings()        → all strings for the current culture
```

---

## 19.5 Data Annotations Localization

Error messages from `[Required]`, `[MaxLength]`, etc. can also be localized:

```csharp
// Register in Program.cs
builder.Services.AddControllers()
    .AddDataAnnotationsLocalization();

// Or for Minimal APIs with validation:
builder.Services.AddLocalization(o => o.ResourcesPath = "Resources");

// In your model:
public class CreateOrderRequest
{
    [Required(ErrorMessage = "Validation.Required")]
    [MaxLength(100, ErrorMessage = "Validation.MaxLength")]
    public string CustomerId { get; set; } = "";

    [Range(0.01, 100_000, ErrorMessage = "Validation.Amount.Range")]
    public decimal Amount { get; set; }
}
```

```xml
<!-- SharedResources.resx -->
<data name="Validation.Required">
  <value>'{0}' is required.</value>
</data>
<data name="Validation.MaxLength">
  <value>'{0}' cannot exceed {1} characters.</value>
</data>
<data name="Validation.Amount.Range">
  <value>Amount must be between {1} and {2}.</value>
</data>
```

---

## 19.6 Number, Date & Currency Formatting

These use `CurrentCulture` (not `CurrentUICulture`) and work automatically:

```csharp
// No extra code needed — formatting adapts to current culture
decimal price = 1234.56m;
DateTime date  = DateTime.UtcNow;

// en-US: 1,234.56  de-DE: 1.234,56  fr-FR: 1 234,56
Console.WriteLine(price.ToString("N2"));

// en-US: $1,234.56  de-DE: 1.234,56 €  fr-FR: 1 234,56 €
Console.WriteLine(price.ToString("C"));

// en-US: 1/15/2025  de-DE: 15.01.2025  fr-FR: 15/01/2025
Console.WriteLine(date.ToString("d"));

// Always use invariant culture for storage/serialization:
string stored = price.ToString(CultureInfo.InvariantCulture); // "1234.56" always
decimal parsed = decimal.Parse(stored, CultureInfo.InvariantCulture);
```

---

## 19.7 Route-Based Culture (URL Contains Language)

```
https://example.com/en/orders
https://example.com/de/orders
https://example.com/fr/orders
```

```csharp
// Program.cs
builder.Services.Configure<RequestLocalizationOptions>(opts =>
{
    opts.SetDefaultCulture("en");
    opts.AddSupportedCultures("en", "de", "fr");
    opts.AddSupportedUICultures("en", "de", "fr");

    // Add route data provider FIRST — highest priority
    opts.RequestCultureProviders.Insert(0, new RouteDataRequestCultureProvider());
});

app.UseRequestLocalization();

// Route template must include {culture}
app.MapGet("/{culture}/orders", (string culture, IStringLocalizer<SharedResources> loc) =>
    Results.Ok(new { message = loc["Order.PlacedSuccessfully"].Value }));
```

---

## 19.8 Blazor Localization

```csharp
// Program.cs (Blazor Server)
builder.Services.AddLocalization(o => o.ResourcesPath = "Resources");
builder.Services.AddControllers()
    .AddViewLocalization()
    .AddDataAnnotationsLocalization();
```

```razor
@* Components/Pages/OrderPage.razor *@
@inject IStringLocalizer<SharedResources> Loc

<h1>@Loc["Orders.Title"]</h1>
<p>@Loc["Orders.Description"]</p>

<button @onclick="PlaceOrder">@Loc["Order.PlaceButton"]</button>
```

### Language Switcher Component

```razor
@* Components/LanguageSwitcher.razor *@
@inject NavigationManager Nav
@inject IHttpContextAccessor HttpCtx

<select @onchange="OnCultureChanged" value="@_currentCulture">
    <option value="en">English</option>
    <option value="de">Deutsch</option>
    <option value="fr">Français</option>
</select>

@code {
    private string _currentCulture = "en";

    protected override void OnInitialized()
    {
        _currentCulture = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
    }

    private void OnCultureChanged(ChangeEventArgs e)
    {
        var culture = e.Value?.ToString() ?? "en";
        var uri     = new Uri(Nav.Uri).GetComponents(UriComponents.PathAndQuery, UriFormat.Unescaped);
        var query   = $"?culture={Uri.EscapeDataString(culture)}&redirectUri={Uri.EscapeDataString(uri)}";
        Nav.NavigateTo("/Culture/Set" + query, forceLoad: true);
    }
}
```

---

## 19.9 MAUI Localization

```csharp
// MauiProgram.cs
builder.Services.AddLocalization();

// In your AppShell or startup, set culture from device or user preference:
var savedCulture = Preferences.Get("app_culture", "en");
CultureInfo.DefaultThreadCurrentCulture   = new CultureInfo(savedCulture);
CultureInfo.DefaultThreadCurrentUICulture = new CultureInfo(savedCulture);
```

```csharp
// Resources/AppResources.resx        ← default
// Resources/AppResources.de.resx     ← German
// Resources/AppResources.fr.resx     ← French

// Access in ViewModels:
public class OrderViewModel
{
    private readonly IStringLocalizer<AppResources> _loc;
    public OrderViewModel(IStringLocalizer<AppResources> loc) => _loc = loc;

    public string Title => _loc["Orders.Title"];
}
```

---

## 19.10 Extracting Strings — Practical Workflow

When working solo or on a small team, this workflow lets you write English first
and extract to resources later without losing anything:

```bash
# 1. Install the Roslyn localizer tool
dotnet tool install --global Roslynator.Localization

# 2. Grep for hard-coded strings to extract (rough audit)
grep -rn '"[A-Z][a-z]' src/ --include="*.cs" \
    | grep -v "// " \
    | grep -v ".csproj" \
    | grep -v "nameof("

# 3. In Rider: right-click a string literal → Refactor → Extract to Resource
#    Rider generates the .resx entry and replaces the string with loc["Key"]
```

### Rider: Extract to Resource

> *Right-click any string literal → Refactor → Move to Resource*
> Rider prompts for the resource file, the key name, and replaces the literal
> with `_localizer["Key"]` automatically. Works across the whole solution.

---

## 19.11 Testing Localization

```csharp
// Test that all keys exist in all supported cultures
public class LocalizationTests
{
    private static readonly string[] SupportedCultures = ["en", "de", "fr"];

    [Theory]
    [InlineData("Order.PlacedSuccessfully")]
    [InlineData("Order.NotFound")]
    [InlineData("Validation.Email.Invalid")]
    public void Key_ExistsInAllCultures(string key)
    {
        foreach (var culture in SupportedCultures)
        {
            var resx = ResourceManager.GetString(key,
                new CultureInfo(culture));
            Assert.False(string.IsNullOrEmpty(resx),
                $"Key '{key}' missing in culture '{culture}'");
        }
    }
}
```

---

## 19.12 The Architecture Rule

Localization belongs in the **Presentation layer only**. Domain and Application layers
use domain language in exceptions and domain events (English, always English in code).
Only the surface that the user sees gets translated.

```
Domain exceptions   → English, always: throw new DomainException("Order is already shipped.")
Application results → English keys only: Result.Fail("Order.AlreadyShipped")
Presentation layer  → translates keys to display language: loc["Order.AlreadyShipped"]
```

This keeps the domain clean and testable in English, while the UI is fully multilingual.

