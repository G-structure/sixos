{ lib
, pkgs
, six
, targets
, flush-old-ruleset ? true
, ruleset ? throw "you must provide a string as argument `ruleset` to the firewall service"
}:

let
  ruleset-file = builtins.toFile "nftables-ruleset"
    (lib.optionalString flush-old-ruleset ''
      flush ruleset
     '' + ruleset);
in
six.mkOneshot {
  up = pkgs.writeScript "firewall-up" ''
    #!${pkgs.runtimeShell} -e

    # incredibly gross hack FIXME FIXME FIXME
    ${pkgs.kmod}/bin/modprobe --all $(${pkgs.busybox}/bin/find /run/booted-system/kernel-modules/lib/modules/*/kernel/net/ -name nf\*.ko) || true

    ${pkgs.nftables}/bin/nft -f ${ruleset-file} || exit -1
    # it is extremely important that the following line is not executed unless
    # the previous line succeeds!
    ${pkgs.busybox}/bin/echo -n 1 > /proc/sys/net/ipv4/ip_forward
  '';

  down = pkgs.writeScript "firewall-down" ''
    #!${pkgs.runtimeShell}
    ${pkgs.busybox}/bin/echo -n 0 > /proc/sys/net/ipv4/ip_forward
    # s6 does not have much support for recovering from a oneshot "down" script
    # which fails.  Therefore we do as little as possible here.
  '';

  passthru = {
    after = with targets; [
      mounts.proc
    ];
  };
}
