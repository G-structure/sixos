{ lib
, six
, pkgs
, targets

# attrnames are paths below `/sys/module/zswap/parameters`; attrvalues will be
# written to the corresponding file.
, parameters ? {}
}:
six.mkOneshot {
  # FIXME: use execlineb/list-of-strings
  up = pkgs.writeScript "zswap-up.sh" (''
    #!${pkgs.runtimeShell}
    exec 2>&1
    echo -n 1 > /sys/module/zswap/parameters/enabled
    ${lib.concatStrings (lib.mapAttrsToList (k: v: ''
    echo -n ${lib.escapeShellArg v} > /sys/module/zswap/parameters/${k}
    ''))}
  '';

  passthru.after = [
    targets.mounts.proc
    targets.mounts.sys
  ];
}
