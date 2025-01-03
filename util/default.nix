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

  # To avoid the site repository needing to fetchGit readTree and
  # yants, we optionally allow the hosts and tags attrsets to be
  # passed as directories and invoke readTree on them.
  maybe-invoke-readTree = args: arg:
    if lib.isPath arg
    then
      lib.filterAttrsRecursive
        (name: value: !(lib.hasPrefix "__readTree" name))
        (readTree.fix (self: (readTree {
          args = { root = self; } // args;
          path = arg;
          rootDir = false;
        })))
    else arg;

  # helpful utility function; turns a fixpoint-on-one-host into a
  # fixpoint-on-the-entire-hosts-set.
  forall-hosts = f:
    (hosts:
      hosts_prev:
      hosts_prev //
      lib.flip lib.mapAttrs hosts_prev
        (name:
          host_prev:
          host_prev // (f hosts.${name} host_prev)));

in {
  inherit canonicalize maybe-invoke-readTree forall-hosts;
}
