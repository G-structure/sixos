{ lib
, six
, pkgs
, targets
, public-ip ? throw "you must provide the public-ip parameter"
, tinydns-root ? throw "you must provide tinydns-root, which is where the tinydns database root is kept"
, package ? pkgs.djbdns
}:

let
  env = [
    "ROOT=${tinydns-root}"
    "IP=${public-ip}"

    # these are passed to tinydns, which uses them to call setuid.
    "GID=nogroup"
    "UID=nobody"
  ];

  # I was using this previously, and it worked, but I don't know if it should be relied upon
  #PUBLIC_IP=$(ip route get 8.8.8.8 | head -n 1 | sed 's_.*src \([0-9\.]*\).*_\1_')
in
six.mkFunnel {
  passthru.after = [
    targets.global.coldplug  # for /dev/urandom
  ];
  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1
exec ${pkgs.busybox}/bin/env ${lib.escapeShellArgs env} ${package}/bin/tinydns
'';
}
