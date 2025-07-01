{
  # This block of arguments with fetch* calls is intentionally kept for
  # backward compatibility with non-flake users. It ensures that projects
  # importing this file directly continue to work as before.
  nixpkgs-path
  ? builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/38edd08881ce4dc24056eec173b43587a93c990f.tar.gz";
    sha256 = "049wkiwhw512wz95vxpxx65xisnd1z3ay0x5yzgmkzafcxvx9ckw";
  },

  lib
  ? import "${nixpkgs-path}/lib",

  infuse
  ? ((import (builtins.fetchGit {
    url = "https://codeberg.org/amjoseph/infuse.nix";
    rev = "bb99266d1e65f137a38b7428a16ced77cd587abb";
    shallow = true;
  })) { inherit lib; }).v1.infuse,

  readTree
  ? import (builtins.fetchurl {
    url = "https://codeberg.org/amjoseph/depot/raw/commit/874181181145c7004be6164baea912bde78f43f6/nix/readTree/default.nix";
    sha256 = "1hfidfd92j2pkpznplnkx75ngw14kkb2la8kg763px03b4vz23zf";
  }) {},

  yants
  ? import (builtins.fetchurl {
    url = "https://code.tvl.fyi/plain/nix/yants/default.nix";
    sha256 = "026j3a02gnynv2r95sm9cx0avwhpgcamryyw9rijkmc278lxix8j";
  }),

  six-initrd
  ? import (builtins.fetchGit {
    url = "https://codeberg.org/amjoseph/six-initrd";
    rev = "eeba355b70b7fbc6f7f439c8a76cef9d561e03b5";
    shallow = true;
  }),

  check-types ? true,

  site,

  extra-by-name-dirs ? [],

  extra-auto-args ? {},

}@args:

let
  # The core logic has been moved to eval.nix.
  # This file is now a compatibility wrapper.
  eval = import ./eval.nix;

  # Determine the system for nixpkgs. This remains impure for the legacy entrypoint.
  system = args.system or builtins.currentSystem;

  # Instantiate nixpkgs for the target system.
  nixpkgs = import nixpkgs-path { inherit system; };

  # Prepare the arguments for the new evaluation function.
  evalArgs = {
    inherit system nixpkgs lib infuse readTree yants;
    six-initrd = six-initrd { inherit lib; pkgs = nixpkgs; };
  } // args;

in
  # Call the new evaluator with the prepared arguments.
  eval evalArgs
