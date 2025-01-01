{ lib
, pkgs
, six
, package ? pkgs.nixVersions.nix_2_3
}:
let
  inherit (pkgs) stdenv;
  options = {
    substitute           = "true";
    substituters         = "http://moore.eden:8080";
    trusted-substituters = "http://moore.eden:8080";
    trusted-public-keys  = "nix@moore-1:CDup8eQ4rnabqJVV56yJ3coNEzoHHxFhOF+Ly/wEFLs=";
    sandbox              = "true";
    sandbox-fallback     = "true";
    #extra-experimental-features = [ "ca-derivations" "impure-derivations" ];
    trusted-users        = [ "nix" "user" "root" ];
  } // lib.optionalAttrs stdenv.hostPlatform.isAarch64 {
    cores = "4";
    max-jobs = "4";
  } // lib.optionalAttrs stdenv.hostPlatform.isx86_64 {
    cores = "16";
    max-jobs = "16";
    system-features      = [ "gccarch-bdver1" "big-parallel" ];
  } // lib.optionalAttrs stdenv.hostPlatform.isMips64 {
    cores = "4";
    max-jobs = "4";
  } // lib.optionalAttrs stdenv.hostPlatform.isPower64 {
    cores = "32";
    max-jobs = "32";
  };
  optionValueToString = val:
    if lib.isList val
    then lib.concatStringsSep " " (map optionValueToString val)
    else if lib.isBool val
    then toString val
    else if lib.isInt val
    then toString val
    else if lib.isString val
    then val
    else throw "unexpected optionValue type: ${toString val}";
  optionsString = lib.pipe options [
    (lib.mapAttrsToList (k: v: [
      "--option"
      k
      (optionValueToString v)
    ]))
    lib.concatLists
    lib.escapeShellArgs
  ];
in
#
# FIXME all the conditionals below can be resolved at build time
#
six.mkFunnel {
  run = pkgs.writeScript "run" (''
    #!${pkgs.runtimeShell}
    exec 2>&1
  ''
  # nix-daemon allocates memory in fairly large chunks; we need
  # to have at least one of those free at all times, so start
  # swapping as soon as we have less than 1/4th of a GB free
  # (=1/16th of physical RAM).  I added this in response to:
  #
  # nix-daemon: page allocation failure: order:5,
  #   mode:0x40dc0(GFP_KERNEL|__GFP_COMP|__GFP_ZERO)
  # ...
  # proc_sys_read+0x14/0x20
  # ...
  # Node 0 DMA free:88704kB min:32236kB low:40292kB high:48348kB
  #   reserved_highatomic:0KB active_anon:135764kB inactive_anon:525360kB
  #   active_file:18556kB inactive_file:14840kB unevictable:0kB
  #   writepending:4980kB present:1046528kB managed:956812kB mlocked:0kB
  #   pagetables:10552kB bounce:0kB free_pcp:884kB local_pcp:248kB
  #   free_cma:0kB
  #
  + lib.optionalString stdenv.hostPlatform.isAarch64 ''
    echo $((2*128*1024)) > /proc/sys/vm/min_free_kbytes
  '' + ''
    if [ -e /nix/tmp ]; then
      umount /nix/tmp || true
      mount /nix/tmp
      export TMPDIR=/nix/tmp
    fi
    # nuke the nix binarycache-cache so we can use `sv restart` to clear it
    rm -rf /root/.cache/nix/
    ulimit -n 500000  # open files limit
    ulimit -u 215504  # number of user processes
    exec ${package}/bin/nix-daemon ${optionsString}
  '');
}
