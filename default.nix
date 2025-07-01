throw ''
  SixOS is now a pure Nix flake.
  Import it via:
    inputs.sixos.url = "github:g-structure/sixos";

  And consume it in your own flake outputs:
    nixpkgs.overlays = [ sixos.overlays.default ];
    # or
    mySystem = sixos.lib.mkSite { ... };

  The legacy `import ./sixos` interface has been removed.
''
