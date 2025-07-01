{
  description = "SixOS – s6-based OS as a flake";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    infuse.url      = "github:g-structure/infuse.nix";
    six-initrd.url  = "github:g-structure/six-initrd";
    # Type validation library used throughout SixOS
    yants.url       = "github:divnix/yants";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # readTree helper library comes from the tvl-fyi/depot repository.
    depot.url       = "github:tvl-fyi/depot";
    depot.flake     = false;
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    let
      # Define the core library functions in a top-level `let` block to avoid
      # circular dependencies on `self` when using it to build other outputs.
      sixos-lib = rec {
        make = {
          system,
          site,
          extra-by-name-dirs ? [],
          extra-auto-args ? {}
        }@args:
          let
            # 1. nixpkgs instance for the requested system
            pkgs = import nixpkgs {
              inherit system;
            };

            # 2. Infuse library compiled against the same `lib` as `pkgs`
            infuse-lib = (import "${inputs.infuse.outPath}/default.nix" {
              lib = pkgs.lib;
            }).v1.infuse;

            # 3. readTree – vendored via the `depot` input (non-flake).
            readTree-lib = import "${inputs.depot.outPath}/nix/readTree/default.nix" {};

            # 4. yants – is now a flake input.
            yants-lib = inputs.yants;

            # 5. six-initrd helper library matching the host system.
            sixInitrd = import "${inputs."six-initrd".outPath}" {
              lib  = pkgs.lib;
              pkgs = pkgs;
            };

            evalArgs = {
              inherit system;
              nixpkgs = pkgs;
              lib = pkgs.lib;
              infuse = infuse-lib;
              readTree = readTree-lib;
              yants = yants-lib;
              six-initrd = sixInitrd;
              inherit site extra-by-name-dirs extra-auto-args;
            } // builtins.removeAttrs args [ "system" "site" "extra-by-name-dirs" "extra-auto-args" ];

          in import ./eval.nix evalArgs;

        # Alias: `mkSite` → `make` for nicer naming
        mkSite = make;
      };
      forAllSystems = f: builtins.listToAttrs (map (s: { name = s; value = f s; }) [ "x86_64-linux" "aarch64-linux" ]);
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, pkgs, system, ... }: {
          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [ s6-rc s6 nixfmt-classic nil ];
            shellHook = ''
              echo "Welcome to the SixOS dev shell for ${system}."
              echo "Helpful commands:";
              echo "  nix fmt          # format the codebase";
              echo "  nix flake check  # run evaluation checks";
            '';
          };

          # `nix fmt` support
          formatter = pkgs.nixfmt-classic;

          # Lightweight evaluation check
          checks = {
            eval-site =
              let
                demoSite = sixos-lib.mkSite {
                  inherit system;
                  site = ./demo-site;
                };
              in
              pkgs.runCommand "eval-site" {} ''
                if [ "${demoSite.hosts.demo.name}" = "demo" ]; then
                  echo "eval-site check passed for host 'demo'" > $out
                else
                  echo "eval-site check failed: could not read host name"
                  exit 1
                fi
              '';
          };

          packages =
            let
              demoSite = sixos-lib.mkSite {
                inherit system;
                site = ./demo-site;
              };
            in {
              debug = pkgs.runCommand "debug-demo-host" {} ''
                echo "Inspecting final.demoSite.hosts.demo attributes"
                echo "${builtins.concatStringsSep "\n" (builtins.attrNames demoSite.hosts.demo)}" > $out
                echo "" >> $out
                echo "Configuration exists: ${if demoSite.hosts.demo ? configuration then "YES" else "NO"}" >> $out
              '';
              demo = demoSite.hosts.demo.configuration;
              default = config.packages.debug;
            };

          apps =
            let
              demoSite = sixos-lib.mkSite {
                inherit system;
                site = ./demo-site;
              };
            in {
              demo-vm = {
                type = "app";
                program = "${demoSite.hosts.demo.configuration.vm}";
              };
              default = config.apps.demo-vm;
            };
      };

      flake = {
        lib = sixos-lib;

        overlays.default = final: prev: {
          sixos = sixos-lib;
        };
      };
    };
}
