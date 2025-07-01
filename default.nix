{
  # Mandatory inputs – callers *must* provide these explicitly.  The thin
  # wrapper flake (see `flake.nix`) takes care of wiring them up so that
  # users of the flake interface do **not** have to think about it.  Legacy
  # import-based consumers now need to supply the arguments themselves.

  # Target system triplet we are evaluating for (e.g. "x86_64-linux").
  system,

  # Pre-evaluated nixpkgs (attribute set) **path** that matches the system
  # above.  We keep the historic name to avoid churn in downstream code.
  nixpkgs-path,

  # Core libraries and helper inputs – all *pre-evaluated*.
  lib,
  infuse,
  readTree,
  yants,

  # six-initrd helper function (expects `{ lib, pkgs; }`).
  six-initrd,

  # Behavioural flags / user supplied knobs – unchanged compared to the
  # legacy interface.
  check-types ? true,
  site,
  extra-by-name-dirs ? [],
  extra-auto-args ? {},

  # Catch-all for forward compatibility.
  ...
}@args:

let
  # The core logic has been moved to eval.nix.
  # This file is now a compatibility wrapper.
  eval = import ./eval.nix;

  # Instantiate nixpkgs for the requested system.  We **never** fall back to
  # `builtins.currentSystem` any more – the caller must supply `system`.
  nixpkgs = import nixpkgs-path { inherit system; };

  # Arguments forwarded to the main evaluator (`eval.nix`).  We pass through
  # *all* user-provided keys so that future additions propagate automatically.
  evalArgs = {
    inherit system nixpkgs lib infuse readTree yants;

    # six-initrd wants the *package set* for the same system – construct it
    # lazily to avoid repeating evaluation work when callers share pkgs.
    six-initrd = six-initrd {
      inherit lib;
      pkgs = nixpkgs;
    };

    # legacy knobs
    inherit site check-types extra-by-name-dirs extra-auto-args;
  } // args;

in
  # Delegate the heavy lifting to `eval.nix`.
  eval evalArgs
