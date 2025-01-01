{ lib
, pkgs
, six
, hostname ? throw "missing hostname"
}:
six.mkOneshot {
  # FIXME: this can be done using sysctl, and probably mere writes to /sys
  # FIXME: make sure both the hostname and `localhost` are in `/etc/hosts`
  up = pkgs.writeScript "set-hostname-up.sh" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    ${pkgs.inetutils}/bin/hostname "${hostname}"
  '';
}
