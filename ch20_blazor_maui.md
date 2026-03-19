# Chapter 20 — Blazor & MAUI

## 20.1 Blazor Fundamentals

Blazor lets you build interactive web UIs with C# instead of JavaScript. Three modes:
- **Blazor Server** — components on server, SignalR for UI updates
- **Blazor WebAssembly** — C# compiled to WASM, runs in browser
- **Blazor United (NET 8+)** — single app supports all modes per-component

### Project Structure (Blazor Web App)

```
MyBlazor/
├── MyBlazor.csproj
├── Program.cs
├── App.razor
├── Routes.razor
├── Components/
│   ├── Layout/
│   │   ├── MainLayout.razor
│   │   └── NavMenu.razor
│   └── Pages/
│       ├── Home.razor
│       ├── Counter.razor
│       └── Users.razor
├── Services/
│   └── UserService.cs
└── wwwroot/
    ├── app.css
    └── favicon.ico
```

### Component Anatomy

```razor
@* Components/Pages/Counter.razor *@
@page "/counter"
@rendermode InteractiveServer

<PageTitle>Counter</PageTitle>

<h1>Counter</h1>
<p role="status">Current count: @_count</p>

<button class="btn btn-primary" @onclick="Increment">Click me</button>
<button class="btn btn-danger"  @onclick="Reset">Reset</button>

@code {
    private int _count = 0;

    private void Increment() => _count++;
    private void Reset() => _count = 0;
}
```

---

## 20.2 Blazor Directives — Complete Reference

```razor
@* File-level directives *@
@page "/users/{Id:int}"          @* Route with typed parameter *@
@page "/users/new"               @* Multiple routes on same component *@
@layout AdminLayout              @* Use specific layout *@
@rendermode InteractiveServer    @* Render mode (NET 8+) *@
@rendermode InteractiveWebAssembly
@rendermode InteractiveAuto      @* Server first, then WASM *@
@attribute [Authorize]           @* Apply attribute *@
@using MyApp.Services            @* Add using *@
@inject IUserService Users       @* DI injection *@
@inject NavigationManager Nav    @* DI injection *@
@implements IDisposable          @* Interface implementation *@
@inherits ComponentBase          @* Base class *@
@typeparam TItem                 @* Generic type parameter *@
```

---

## 20.3 Data Binding

```razor
@* Two-way binding with @bind *@
<input @bind="_name" />
<input @bind="_name" @bind:event="oninput" />   @* live update on each keystroke *@
<input @bind="_date" @bind:format="yyyy-MM-dd" />

@* Bind to component parameter *@
<MyInput @bind-Value="_searchText" />

@* Select *@
<select @bind="_selectedCountry">
    @foreach (var country in _countries)
    {
        <option value="@country.Code">@country.Name</option>
    }
</select>

@* Checkbox *@
<input type="checkbox" @bind="_isChecked" />

@* Numeric input *@
<input type="number" @bind="_count" />

@code {
    private string _name = "";
    private DateTime _date = DateTime.Today;
    private string _searchText = "";
    private string _selectedCountry = "DE";
    private bool _isChecked = false;
    private int _count = 0;
    private List<Country> _countries = [];
}
```

---

## 20.4 Component Parameters and Cascading Values

```razor
@* Parent passes parameters to child *@

@* ChildComponent.razor *@
<div class="card @CssClass">
    <h3>@Title</h3>
    @ChildContent
    @if (OnDelete.HasDelegate)
    {
        <button @onclick="() => OnDelete.InvokeAsync(Id)">Delete</button>
    }
</div>

@code {
    [Parameter] public int Id { get; set; }
    [Parameter] public required string Title { get; set; }
    [Parameter] public string CssClass { get; set; } = "";
    [Parameter] public RenderFragment? ChildContent { get; set; }
    [Parameter] public EventCallback<int> OnDelete { get; set; }

    // Two-way binding parameter
    [Parameter] public string Value { get; set; } = "";
    [Parameter] public EventCallback<string> ValueChanged { get; set; }

    private async Task OnInput(ChangeEventArgs e)
        => await ValueChanged.InvokeAsync(e.Value?.ToString() ?? "");
}

@* Parent usage *@
<ChildComponent Id="42" Title="My Card" CssClass="featured"
    OnDelete="HandleDelete">
    <p>This is the content</p>
</ChildComponent>

@* Cascading values — pass data through component tree without prop drilling *@
@* App.razor *@
<CascadingValue Value="_theme">
    <Router .../>
</CascadingValue>

@* Deep child *@
@code {
    [CascadingParameter] private AppTheme Theme { get; set; } = default!;
}
```

---

## 20.5 Lifecycle

```csharp
// Full lifecycle in code-behind or @code block
public class UserListBase : ComponentBase, IDisposable
{
    [Inject] private IUserService UserService { get; set; } = null!;
    [Inject] private ILogger<UserListBase> Logger { get; set; } = null!;

    protected List<User> Users { get; set; } = new();
    protected bool IsLoading { get; set; } = true;
    protected string? ErrorMessage { get; set; }

    // Called when parameters are set (and on re-renders)
    protected override void OnParametersSet() { }

    // Initial data loading
    protected override async Task OnInitializedAsync()
    {
        try
        {
            Users = await UserService.GetAllAsync();
        }
        catch (Exception ex)
        {
            ErrorMessage = "Failed to load users.";
            Logger.LogError(ex, "Error loading users");
        }
        finally
        {
            IsLoading = false;
        }
    }

    // After first render (can interact with JS here)
    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (firstRender)
        {
            await JsRuntime.InvokeVoidAsync("initTooltips");
        }
    }

    // Manual re-render trigger
    protected void ForceUpdate() => StateHasChanged();

    public void Dispose()
    {
        // Unsubscribe from events, cancel operations
    }
}
```

---

## 20.6 Forms and Validation

```razor
@page "/users/edit/{Id:int}"
@inject IUserService UserService
@inject NavigationManager Nav

<EditForm Model="_model" OnValidSubmit="HandleSubmit">
    <DataAnnotationsValidator />
    <ValidationSummary />

    <div class="mb-3">
        <label>Name</label>
        <InputText class="form-control" @bind-Value="_model.Name" />
        <ValidationMessage For="() => _model.Name" />
    </div>

    <div class="mb-3">
        <label>Email</label>
        <InputText class="form-control" @bind-Value="_model.Email" />
        <ValidationMessage For="() => _model.Email" />
    </div>

    <div class="mb-3">
        <label>Age</label>
        <InputNumber class="form-control" @bind-Value="_model.Age" />
        <ValidationMessage For="() => _model.Age" />
    </div>

    <button type="submit" class="btn btn-primary" disabled="@_saving">
        @(_saving ? "Saving..." : "Save")
    </button>
</EditForm>

@code {
    [Parameter] public int Id { get; set; }
    private EditUserModel _model = new();
    private bool _saving;

    protected override async Task OnInitializedAsync()
    {
        var user = await UserService.GetByIdAsync(Id);
        if (user is null) { Nav.NavigateTo("/not-found"); return; }
        _model = new EditUserModel { Name = user.Name, Email = user.Email, Age = user.Age };
    }

    private async Task HandleSubmit()
    {
        _saving = true;
        try
        {
            await UserService.UpdateAsync(Id, _model);
            Nav.NavigateTo("/users");
        }
        finally
        {
            _saving = false;
        }
    }
}

@code {
    public class EditUserModel
    {
        [Required, MaxLength(100)]
        public string Name { get; set; } = "";

        [Required, EmailAddress]
        public string Email { get; set; } = "";

        [Range(0, 150)]
        public int Age { get; set; }
    }
}
```

---

## 20.7 JavaScript Interop

```csharp
// Inject IJSRuntime
@inject IJSRuntime JS

// Call JS from C#
await JS.InvokeVoidAsync("alert", "Hello from C#!");
string result = await JS.InvokeAsync<string>("prompt", "Enter your name:");
await JS.InvokeVoidAsync("navigator.clipboard.writeText", textToCopy);

// Call module (ES module)
await using var module = await JS.InvokeAsync<IJSObjectReference>(
    "import", "./js/myModule.js");
await module.InvokeVoidAsync("doSomething", arg1, arg2);
var data = await module.InvokeAsync<string>("getData");

// C# method called from JS
// In JS: await DotNet.invokeMethodAsync("MyAssembly", "HandleEvent", data);
[JSInvokable]
public static Task HandleEvent(string data) => Task.CompletedTask;

// Instance method via DotNetObjectReference
var ref = DotNetObjectReference.Create(this);
await JS.InvokeVoidAsync("setupCallback", ref);
// JS: dotNetObj.invokeMethodAsync("OnCallback", data);

[JSInvokable]
public void OnCallback(string data) { /* called from JS */ }
```

---

## 20.8 .NET MAUI

MAUI (Multi-platform App UI) builds native apps for Android, iOS, macOS, and Windows from a single codebase.

### Project Structure

```
MyMauiApp/
├── MyMauiApp.csproj
├── MauiProgram.cs
├── App.xaml
├── App.xaml.cs
├── AppShell.xaml
├── AppShell.xaml.cs
├── Platforms/
│   ├── Android/
│   │   ├── AndroidManifest.xml
│   │   ├── MainActivity.cs
│   │   └── MainApplication.cs
│   ├── iOS/
│   │   ├── Info.plist
│   │   └── AppDelegate.cs
│   ├── MacCatalyst/
│   └── Windows/
├── Pages/
│   ├── MainPage.xaml
│   ├── MainPage.xaml.cs
│   └── DetailPage.xaml
├── ViewModels/
│   ├── MainViewModel.cs
│   └── DetailViewModel.cs
├── Services/
│   └── ApiService.cs
└── Resources/
    ├── Fonts/
    ├── Images/
    └── Styles/
```

### `.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net9.0-android;net9.0-ios;net9.0-maccatalyst;net9.0-windows10.0.19041.0</TargetFrameworks>
    <OutputType>Exe</OutputType>
    <UseMaui>true</UseMaui>
    <SingleProject>true</SingleProject>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <!-- App Info -->
    <ApplicationId>com.acme.myapp</ApplicationId>
    <ApplicationTitle>My App</ApplicationTitle>
    <ApplicationVersion>1</ApplicationVersion>
    <ApplicationDisplayVersion>1.0.0</ApplicationDisplayVersion>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Maui.Controls" Version="$(MauiVersion)" />
    <PackageReference Include="CommunityToolkit.Maui" Version="9.0.3" />
    <PackageReference Include="CommunityToolkit.Mvvm" Version="8.3.2" />
  </ItemGroup>
</Project>
```

### MauiProgram.cs

```csharp
public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder
            .UseMauiApp<App>()
            .UseMauiCommunityToolkit()
            .ConfigureFonts(fonts =>
            {
                fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
                fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
            });

        // Services
        builder.Services.AddSingleton<IApiService, ApiService>();
        builder.Services.AddSingleton<IPreferences>(_ => Preferences.Default);
        builder.Services.AddHttpClient<IApiService, ApiService>(client =>
        {
            client.BaseAddress = new Uri("https://api.example.com/");
        });

        // Pages and ViewModels
        builder.Services.AddTransientWithShellRoute<MainPage, MainViewModel>("//main");
        builder.Services.AddTransientWithShellRoute<DetailPage, DetailViewModel>("detail");

#if DEBUG
        builder.Logging.AddDebug();
#endif

        return builder.Build();
    }
}
```

### ViewModel with CommunityToolkit.Mvvm

```csharp
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

public partial class MainViewModel : ObservableObject
{
    private readonly IApiService _api;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(LoadCommand))]
    private bool _isLoading;

    [ObservableProperty]
    private string _errorMessage = "";

    [ObservableProperty]
    private ObservableCollection<UserDto> _users = new();

    [ObservableProperty]
    private string _searchText = "";

    public MainViewModel(IApiService api) => _api = api;

    [RelayCommand(CanExecute = nameof(CanLoad))]
    private async Task LoadAsync()
    {
        IsLoading = true;
        ErrorMessage = "";
        try
        {
            var items = await _api.GetUsersAsync();
            Users = new ObservableCollection<UserDto>(items);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private bool CanLoad() => !IsLoading;

    [RelayCommand]
    private async Task NavigateToDetailAsync(UserDto user)
    {
        await Shell.Current.GoToAsync("detail", new Dictionary<string, object>
        {
            ["User"] = user
        });
    }
}
```

### Android Foreground Service

```csharp
// Platforms/Android/SyncForegroundService.cs
[Service(ForegroundServiceType = Android.Content.PM.ForegroundService.TypeDataSync)]
public class SyncForegroundService : Service
{
    private const int NotificationId = 1001;
    private CancellationTokenSource? _cts;

    public override IBinder? OnBind(Intent? intent) => null;

    public override StartCommandResult OnStartCommand(Intent? intent, StartCommandFlags flags, int startId)
    {
        StartForeground(NotificationId, BuildNotification("SyncDot running…"));
        _cts = new CancellationTokenSource();
        Task.Run(() => RunSyncLoopAsync(_cts.Token));
        return StartCommandResult.Sticky;
    }

    private async Task RunSyncLoopAsync(CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(5));
        while (await timer.WaitForNextTickAsync(ct))
        {
            try
            {
                // ... sync logic ...
                UpdateNotification("Last sync: " + DateTime.Now.ToShortTimeString());
            }
            catch (Exception ex) { /* log */ }
        }
    }

    private Notification BuildNotification(string text)
    {
        var channel = new NotificationChannel("syncdot", "SyncDot", NotificationImportance.Low);
        var nm = (NotificationManager)GetSystemService(NotificationService)!;
        nm.CreateNotificationChannel(channel);

        return new Notification.Builder(this, "syncdot")
            .SetContentTitle("SyncDot")
            .SetContentText(text)
            .SetSmallIcon(Resource.Drawable.ic_sync)
            .Build();
    }

    private void UpdateNotification(string text)
    {
        var nm = (NotificationManager)GetSystemService(NotificationService)!;
        nm.Notify(NotificationId, BuildNotification(text));
    }

    public override void OnDestroy()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        base.OnDestroy();
    }
}
```

---

## 20.9 Photino.Blazor — Desktop App

Photino uses the OS WebView to host Blazor as a native desktop app:

```xml
<PackageReference Include="Photino.Blazor" Version="3.1.0" />
```

```csharp
// Program.cs
var app = PhotinoBlazorAppBuilder.CreateDefault(args);
app.Services.AddLogging();
app.RootComponents.Add<App>("#app");
app.Services.AddSingleton<IMyService, MyService>();

app.MainWindow
    .SetTitle("MyApp Desktop")
    .SetSize(1200, 800)
    .Center()
    .SetResizable(true);

AppDomain.CurrentDomain.UnhandledException += (sender, error) =>
    app.MainWindow.ShowMessage("Fatal error", error.ExceptionObject.ToString());

app.Run();
```

> **Rider tip:** For MAUI development in Rider, install the *MAUI* plugin from Rider's plugin marketplace. Rider supports the XAML designer and can deploy to connected Android/iOS devices via *Run Configurations*.

> **VS tip:** Visual Studio 2022 has first-class MAUI support including the *MAUI Preview* pane for XAML design-time rendering. *Hot Reload* works for both XAML and C# — change code while the app is running on a device.

