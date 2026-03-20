#./flake.nix
{
  description = "MeshFlow: .NET 10 + Android APK Development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system; 
        config = { 
          allowUnfree = true; 
          android_sdk.accept_license = true; 
        }; 
      };

      androidComposition = pkgs.androidenv.composeAndroidPackages {
        buildToolsVersions = [ "34.0.0" "35.0.0" ];
        platformVersions = [ "34" "35" ];
        abiVersions = [ "x86_64" "arm64-v8a" ]; # arm64 is required for real phones
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          (with pkgs.dotnetCorePackages; combinePackages [
            sdk_10_0
            aspnetcore_10_0
          ])
          androidComposition.androidsdk
          pkgs.jdk21
          
          # FIX: Explicitly request WebKitGTK 4.1 and its required UI dependencies
          pkgs.webkitgtk_4_1 
          pkgs.gtk3
          pkgs.glib
        ];

        shellHook = ''
          export DOTNET_ROOT=${pkgs.dotnetCorePackages.sdk_10_0}
          export JAVA_HOME=${pkgs.jdk21}/lib/openjdk
          export ANDROID_HOME=${androidComposition.androidsdk}/libexec/android-sdk
          export ANDROID_SDK_ROOT=$ANDROID_HOME
          export DOTNET_CLI_HOME=$HOME/.dotnet
          export PATH="$PATH:$HOME/.dotnet/tools"
          
          echo "🤖 MeshFlow Android & Desktop Environment Ready"
        '';
      };
    };
}