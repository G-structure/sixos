{
  lib,
  yants,
  readTree,
  infuse,
  ...
}:

let
  # copied from unmerged https://github.com/NixOS/nixpkgs/pull/235230
  canonicalize = let
    tripleFromSystem = { cpu, vendor, kernel, abi, ... } @ sys:
      let
        kernel' = lib.systems.parse.kernelName kernel;
        optAbi = lib.optionalString (abi.name != "") "-${abi.name}";
        optVendor = lib.optionalString (vendor.name != "") "-${vendor.name}";
        optKernel = lib.optionalString (kernel' != "") "-${kernel'}";
      in
        # gnu-config considers "mingw32" and "cygwin" to be kernels.
        # This is obviously bogus, which is why nixpkgs has historically
        # parsed them differently.  However for regression testing
        # reasons (see lib/tests/triples.nix) we need to replicate this
        # quirk when unparsing in order to round-trip correctly.
        if      abi == "cygnus"     then "${cpu.name}${optVendor}-cygwin"
        else if kernel == "windows" then "${cpu.name}${optVendor}-mingw32"
        else "${cpu.name}${optVendor}${optKernel}${optAbi}";
  in
    lib.flip lib.pipe [
      lib.systems.parse.mkSystemFromString
      tripleFromSystem
    ];

  #
  # To avoid the site repository needing to fetchGit readTree and
  # yants, we optionally allow the hosts and tags attrsets to be
  # passed as directories and invoke readTree on them.
  #
  maybe-invoke-readTree = args: arg:
    if lib.isPath arg
    then
      lib.filterAttrsRecursive
        (name: value: !(lib.hasPrefix "__readTree" name))
        (readTree.fix (self: (readTree {
          args = { root = self; } // args;
          path = arg;
        })))
    else arg;

  #
  # Nix attrsets are strict in their attrnames.  Applying this function to a
  # `host` attrset ensures that the result's attrnames are statically
  # determined.  Doing this within a fixpoint avoids a lot of very hard-to-debug
  # infinite recursions.
  #
  make-host-attrnames-deterministic =
    host:
    let
      defaults = {
        name = throw "missing name";
        canonical = "missing canonical";
        tags = {};
        interfaces = {};
        ifconns = {};
        pkgs = throw "missing pkgs";
        sw = throw "missing sw";
        configuration = throw "missing configuration";
        delete-generations = null;
        service-overlays = [];
        boot = {};
      };
    in
      builtins.intersectAttrs
        (defaults // { hostid = throw "bogus"; })
        (builtins.mapAttrs
          (k: v: host.${k} or v)
          defaults);

  #
  # Turns an overlay-on-hosts into an overlay-on-a-site
  #
  apply-to-hosts =
    hosts-overlay:
    site-final: site-prev:
    site-prev // {
      hosts = site-prev.hosts // hosts-overlay site-final.hosts site-prev.hosts;
    };

  #
  # Turns an overlay-on-one-host into an overlay-on-the-set-of-hosts; also
  # does two additional things to avoid hard-to-debug infinite recursions:
  #
  #   1. applies `make-host-attrnames-deterministic` after each overlay
  #   2. prevents overlays from changing `host.${name}.tags`
  #
  forall-hosts =
    overlay:
    apply-to-hosts
      (hosts-final: hosts-prev:
        let
          traced-hosts-prev = builtins.trace "forall-hosts processing hosts: ${builtins.toString (builtins.attrNames hosts-prev)}" hosts-prev;
        in
        lib.mapAttrs
          (name: host-prev:
            (host-prev // (overlay name hosts-final.${name} host-prev))
          )
          traced-hosts-prev
      );

in {
  inherit
    canonicalize
    maybe-invoke-readTree
    forall-hosts
    apply-to-hosts
    make-host-attrnames-deterministic
    ;
}
