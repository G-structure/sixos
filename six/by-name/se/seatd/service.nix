{ lib
, pkgs
, six
, targets
, user ? throw "missing user"
, group ? throw "missing group"
}:
let
  notification-fd = 3;
in
six.mkFunnel {
  inherit notification-fd;
  passthru.after = [ targets.global.coldplug ];
  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    exec ${pkgs.seatd}/bin/seatd -u ${user} -g ${group} -l info -n ${toString notification-fd}
  '';
}
