{
  description = "SixOS – s6-based OS as a flake";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    infuse.url      = "github:g-structure/infuse.nix";
    six-initrd.url  = "github:g-structure/six-initrd";
    depot.url       = "github:tvl-fyi/depot";
    depot.flake     = false;
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, pkgs, system, ... }: {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ s6-rc s6 nixfmt nil ];
        };
      };

      # Top-level (system-agnostic) outputs contributed by this flake
      flake = {
        # Thin-wrapper helper that re-uses the historic `sixos/default.nix` API
        # but sources its dependencies from the flake inputs instead of
        # `builtins.fetch*` calls scattered in the file.  The implementation
        # goal is *zero functional change* – existing site directories can be
        # evaluated verbatim.
        lib = rec {
          make = {
            system ? (builtins.currentSystem or "x86_64-linux"),
            site,
            extra-by-name-dirs ? [],
            extra-auto-args ? {}
          }@args:
            let
              # 1. nixpkgs instance for the requested system
              pkgs = import nixpkgs {
                inherit system;
              };

              # 2. Infuse library compiled against the same `lib` as `pkgs` to
              #    avoid cross-system surprises (Infuse in its own flake is
              #    evaluated only for x86_64-linux by default).
              infuse-lib = (import "${inputs.infuse.outPath}/default.nix" {
                lib = pkgs.lib;
              }).v1.infuse;

              # 3. six-initrd helper library matching the host system.  Its
              #    default.nix expects `{ lib, pkgs }`.
              sixInitrd = import "${inputs."six-initrd".outPath}" {
                lib  = pkgs.lib;
                pkgs = pkgs;
              };

              # 4. Invoke the legacy entrypoint whilst overriding the fetch*-based
              #    defaults with the flake inputs prepared above.
              six = import ./. ({
                nixpkgs-path = nixpkgs.outPath;
                lib          = pkgs.lib;
                infuse       = infuse-lib;
                six-initrd   = sixInitrd;
                # Forward user-supplied arguments such as `site`, keeping the
                # historical parameter names.
                inherit site extra-by-name-dirs extra-auto-args;
              } // builtins.removeAttrs args [ "system" "site" "extra-by-name-dirs" "extra-auto-args" ]);

            in six;

          # Alias: `mkSite` → `make` for nicer naming
          mkSite = make;
        };

        # Overlay exposing the mkSite helper through the package set so that
        # consumers can conveniently write `pkgs.sixos.mkSite { … }` inside an
        # overlay chain.
        overlays.default = final: prev: {
          sixos = self.lib.mkSite;
        };
      };
    };
}
