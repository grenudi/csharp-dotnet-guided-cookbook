# Chapter 22 — NixOS: Reproducible .NET Development with Nix

## 22.1 Why Nix for .NET?

| Problem | Nix Solution |
|---------|-------------|
| "Works on my machine" | Exact, reproducible dependency graph |
| SDK version conflicts | Isolated per-project via `global.json` + `nix develop` |
| Global tool pollution | Tools in shell env, not global install |
| CI/dev parity | Same `flake.nix` on developer laptop and CI |
| Dotnet runtime updates | `nixpkgs` pins exact version, no surprise upgrades |

---

## 22.2 Basic `flake.nix` for .NET Development

```nix
# flake.nix
{
  description = "SyncDot — P2P File Sync Daemon";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Pin .NET SDK version
        dotnet = pkgs.dotnet-sdk_9;

        # All dev tools
        devTools = with pkgs; [
          dotnet                   # .NET 9 SDK + runtime
          omnisharp-roslyn         # C# language server (for Neovim/VS Code)
          netcoredbg               # .NET debugger
          dotnet-ef                # EF Core migrations CLI
          protobuf                 # protoc compiler
          grpc-tools               # gRPC tools
          sqlite                   # SQLite CLI
          postgresql_16            # psql client
          redis                    # redis-cli (if using Redis)
          jq                       # JSON processing in scripts
          httpie                   # HTTP client for testing APIs
          git
          gnumake
        ];

      in {
        # Development shell
        devShells.default = pkgs.mkShell {
          packages = devTools;

          # Environment variables
          DOTNET_ROOT    = "${dotnet}";
          DOTNET_CLI_HOME = "/tmp/.dotnet-cli-home";
          NUGET_PACKAGES = "${builtins.getEnv "HOME"}/.nuget/packages";

          # Disable telemetry
          DOTNET_CLI_TELEMETRY_OPTOUT = "1";
          DOTNET_NOLOGO               = "1";

          # Fix SSL certificates on NixOS
          NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

          shellHook = ''
            echo "🚀 SyncDot dev shell loaded"
            echo "   .NET: $(dotnet --version)"
            echo "   EF:   $(dotnet ef --version 2>/dev/null || echo 'not available')"

            # Create required directories
            mkdir -p /tmp/.dotnet-cli-home
            mkdir -p ./run
          '';
        };

        # Nix package build (see section 18.5)
        packages.default = self.packages.${system}.syncdot;
        packages.syncdot = pkgs.buildDotnetApplication {
          pname = "syncdot";
          version = "0.1.0";
          src = ./.;
          dotnet-sdk     = dotnet;
          dotnet-runtime = pkgs.dotnet-runtime_9;
          projectFile    = "src/SyncDot.Daemon/SyncDot.Daemon.csproj";
          nugetDeps      = ./nix/nuget-deps.nix;
          selfContainedBuild = false;
          executables    = ["SyncDot.Daemon"];
        };

        # Checks (run with `nix flake check`)
        checks = {
          tests = pkgs.runCommand "dotnet-tests" {
            buildInputs = devTools;
            DOTNET_CLI_TELEMETRY_OPTOUT = "1";
          } ''
            cd ${self}
            dotnet test --no-build -c Release
            touch $out
          '';
        };
      }
    );
}
```

---

## 22.3 `direnv` Integration

`direnv` automatically loads/unloads the Nix shell when you `cd` into the project.

### Setup

```bash
# Install direnv (once, in NixOS configuration.nix)
# programs.direnv.enable = true;
# programs.direnv.nix-direnv.enable = true;

# Per-project: create .envrc
echo "use flake" > .envrc
direnv allow

# Now: cd into project → shell loads automatically
# cd out → shell unloads
```

### `.envrc` Options

```bash
# Basic
use flake

# With specific output
use flake .#devShells.x86_64-linux.default

# Load additional env from file (secrets)
dotenv_if_exists .env.local

# Set custom variables
export APP_ENV=development
export DATABASE_URL="Data Source=./dev.db"
export SMTP_HOST=localhost

# Load shell file
source_if_exists scripts/dev-env.sh
```

### `.env.local` (not committed)

```bash
# .env.local — git-ignored, local secrets
SMTP_PASSWORD=super-secret-password
STRIPE_SECRET_KEY=sk_test_...
JWT_SECRET=dev-only-jwt-secret-change-in-production
```

---

## 22.4 NixOS System Configuration for Development

```nix
# /etc/nixos/configuration.nix (relevant parts)
{ config, pkgs, ... }:
{
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Developer tools (system-wide)
  environment.systemPackages = with pkgs; [
    git
    direnv
    nix-direnv
    htop
    curl
    wget
  ];

  # direnv shell hook
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;   # or enableBashIntegration
  };

  # Rider / VS Code (install JetBrains Toolbox or VS Code via nix)
  # Note: Rider requires nixpkgs.config.allowUnfree = true
  programs.java.enable = true; # required for Rider JVM
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    jetbrains.rider    # or: jetbrains-toolbox (installs Rider + others)
    vscode             # VS Code
    vscode-extensions.ms-dotnettools.csdevkit
  ];

  # For FUSE (needed by SyncDot on Linux)
  environment.systemPackages = with pkgs; [ fuse3 libfuse ];

  # systemd service for SyncDot daemon
  systemd.services.syncdot = {
    description = "SyncDot P2P File Sync Daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.syncdot}/bin/SyncDot.Daemon";
      Restart = "on-failure";
      User = "syncdot";
      Group = "syncdot";
      WorkingDirectory = "/var/lib/syncdot";
      StateDirectory = "syncdot";
      RuntimeDirectory = "syncdot";
      NoNewPrivileges = true;
    };
  };
  users.users.syncdot = {
    isSystemUser = true;
    group = "syncdot";
    home = "/var/lib/syncdot";
    createHome = true;
  };
  users.groups.syncdot = {};
}
```

---

## 22.5 Building a .NET App with Nix

### Generate `nuget-deps.nix`

Nix needs a static list of all NuGet packages for sandboxed builds:

```bash
# Install the helper tool
nix-shell -p dotnet-sdk_9 nuget-to-nix

# Restore packages first
dotnet restore

# Generate the lock file
nuget-to-nix ./packages.lock.json > nix/nuget-deps.nix
```

### Complete `flake.nix` Build Example

```nix
# More detailed build configuration
packages.syncdot = pkgs.buildDotnetApplication rec {
  pname = "syncdot";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ./.;

  dotnet-sdk = pkgs.dotnet-sdk_9;
  dotnet-runtime = pkgs.dotnet-runtime_9;

  projectFile = "src/SyncDot.Daemon/SyncDot.Daemon.csproj";
  nugetDeps = ./nix/nuget-deps.nix;

  # Build as native AOT
  dotnetFlags = [
    "-r" "linux-x64"
    "/p:PublishAot=true"
    "/p:StripSymbols=true"
  ];

  # Post-install
  postInstall = ''
    install -Dm644 nix/syncdot.service $out/lib/systemd/system/syncdot.service
    install -Dm644 README.md $out/share/doc/syncdot/README.md
  '';

  meta = with pkgs.lib; {
    description = "P2P masterless file sync daemon";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "SyncDot.Daemon";
  };
};
```

### Build and Run

```bash
# Build the Nix package
nix build .#syncdot
./result/bin/SyncDot.Daemon

# Build and run in one step
nix run .#syncdot

# Install to user profile
nix profile install .#syncdot

# Build for specific system
nix build .#packages.x86_64-linux.syncdot
```

---

## 22.6 CI/CD with Nix

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v27
        with:
          nix_path: nixpkgs=channel:nixos-unstable
          extra_nix_config: |
            experimental-features = nix-command flakes

      - name: Setup Cachix (optional — cache Nix artifacts)
        uses: cachix/cachix-action@v14
        with:
          name: my-cache
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'

      - name: Check flake
        run: nix flake check

      - name: Run tests
        run: nix develop --command dotnet test -c Release

      - name: Build
        run: nix build .#syncdot

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: syncdot-linux-x64
          path: result/bin/SyncDot.Daemon
```

---

## 22.7 Useful Nix Commands

```bash
# Development
nix develop              # enter dev shell
nix develop --command dotnet run  # run command in shell without entering
direnv allow             # trust .envrc

# Flake management
nix flake update         # update all inputs to latest
nix flake update nixpkgs # update only nixpkgs
nix flake lock           # regenerate flake.lock
nix flake show           # show all outputs (packages, devShells, etc.)
nix flake metadata       # show metadata and inputs

# Build
nix build .              # build default package
nix build .#syncdot      # build specific package
nix build --dry-run      # show what would be built
nix build --print-build-logs # show build output

# Run
nix run .                # run default package
nix run nixpkgs#cowsay -- "hello" # run package from nixpkgs directly

# Garbage collection
nix store gc             # collect unreferenced store paths
nix-collect-garbage -d   # delete old generations + gc

# Inspect
nix why-depends .#syncdot nixpkgs#openssl  # why is openssl a dep?
nix path-info -r .#syncdot  # full closure (all deps)
```

---

## 22.8 Home Manager for Developer Config

```nix
# ~/.config/home-manager/home.nix
{ config, pkgs, ... }:
{
  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.11";

  # Developer packages
  home.packages = with pkgs; [
    dotnet-sdk_9
    jetbrains.rider
    vscode
    git
    direnv
    nix-direnv
    gh              # GitHub CLI
    lazygit         # terminal git UI
    ripgrep         # fast grep
    fd              # fast find
    bat             # better cat
    eza             # better ls
    delta           # better git diff
  ];

  # Git config
  programs.git = {
    enable = true;
    userName  = "Alice Smith";
    userEmail = "alice@example.com";
    extraConfig = {
      core.editor = "hx";  # helix editor
      pull.rebase = true;
      init.defaultBranch = "main";
    };
  };

  # direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Shell aliases
  programs.zsh.shellAliases = {
    dr  = "dotnet run";
    db  = "dotnet build";
    dt  = "dotnet test";
    def = "dotnet ef";
    dp  = "dotnet publish -c Release";
  };
}
```

> **Rider on NixOS tip:** Use `nix develop` inside Rider's terminal to get the correct SDK. In *Settings → Build, Execution, Deployment → Toolset and Build → Use SDK for solution* — point to `/nix/store/.../dotnet-sdk-9.x.x/`.

> **VS Code on NixOS tip:** Use the `nix-direnv` extension for VS Code + `direnv` integration to automatically pick up the correct .NET SDK per project.

