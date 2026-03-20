#!/usr/bin/env bash

# 1. Environment Paths
export DOTNET_CLI_HOME="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_CLI_HOME/tools"
export DOTNET_ROOT=$(dirname $(which dotnet))

# 2. Stupid Simple Workload Check
# By setting DOTNET_CLI_HOME above, this forces the workload to install 
# into your home directory, avoiding NixOS read-only errors.
if ! dotnet workload list | grep -q "maui-android"; then
    echo "📦 Missing Android Workload. Installing to $DOTNET_CLI_HOME..."
    dotnet workload install maui-android --skip-manifest-check
fi

# 3. Check for Entity Framework (SQLite)
if ! command -v dotnet-ef &> /dev/null; then
    echo "📦 Installing SQLite/EF tools..."
    dotnet tool install --global dotnet-ef
fi

# 4. Launch Rider
echo "🚀 Launching Rider for MeshFlow..."
rider . > /dev/null 2>&1 &