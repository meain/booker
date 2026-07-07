{
  description = "booker — native macOS spotlight-style bookmark picker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Dev tooling. Everything comes from nix: the Swift compiler + SwiftPM
        # and the matching Apple SDK (whose setup hook exports SDKROOT /
        # DEVELOPER_DIR), plus the linter CI uses (Apple swift-format, reads
        # .swift-format). Build with `swift build` / `./build-app.sh`.
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.swift
            pkgs.swiftpm
            pkgs.swift-format
          ];
          shellHook = ''
            echo "booker devshell · swift $(swift --version 2>/dev/null | head -1 || echo '?')"
            echo "  lint:   swift-format lint --strict --recursive --configuration .swift-format Sources"
            echo "  format: swift-format --in-place --recursive --configuration .swift-format Sources"
            echo "  build:  swift build   ·   app: ./build-app.sh"
          '';
        };
      }
    );
}
