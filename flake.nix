{
  description = "SixOS – s6-based OS as a flake";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    infuse.url      = "github:g-structure/infuse.nix";
    six-initrd.url  = "github:g-structure/six-initrd";
    six-demo.url    = "path:../six-demo";
    six-demo.flake  = false;
    # Type validation library used throughout SixOS
    yants.url       = "github:divnix/yants";
    yants.flake     = false;
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, six-demo, ... }:
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

            # 4. yants – imported from the dedicated input (non-flake).
            yants-lib = import "${inputs.yants.outPath}/default.nix" { lib = pkgs.lib; };

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
                  site = ../six-demo/site;
                };
              in
              pkgs.runCommand "eval-site" {} ''
                [ -d "${demoSite.hosts.demo.configuration}" ]
                echo ok > $out
              '';
          };
      };

      flake = {
        packages = forAllSystems (system:
          let
            demoSite = sixos-lib.mkSite {
              inherit system;
              site = ../six-demo/site;
            };
          in {
            demo = demoSite.hosts.demo.configuration;
            default = demoSite.hosts.demo.configuration;
          });

        apps = forAllSystems (system:
          let
            demoSite = sixos-lib.mkSite {
              inherit system;
              site = ../six-demo/site;
            };
          in {
            demo-vm = {
              type = "app";
              program = "${demoSite.hosts.demo.configuration.vm}/bin/vm-demo.sh";
            };
            default = self.apps.${system}.demo-vm;
          });

        lib = sixos-lib;

        overlays.default = final: prev: {
          sixos = sixos-lib;
        };
      };
    };
}
