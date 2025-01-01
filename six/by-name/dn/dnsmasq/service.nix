{ lib
, six
, pkgs
, targets
, package ? pkgs.dnsmasq
, user-name ? "dnsmasq"
, instance-name ? throw "instance-name is required"
, interface ? throw "interface is required"
, enable-dns ? false
, nameservers ? null   # default is to read /etc/resolv.conf and use those
, ntp-server ? null
, dhcp-range ? null
, gw ? null
, dhcp ? {}
, conf-text ? ""
}:

# FIXME: do a typecheck on `interface`

let
  conf-file =
    builtins.toFile "dnsmasq-${instance-name}.conf" (''
      bind-interfaces   # bind only to the specified interface
      no-hosts          # don't use /etc/hosts to serve DNS
      interface=${interface.ifname}
      dhcp-leasefile=/run/${instance-name}/dnsmasq.leases
    '' + lib.optionalString (gw != null) ''
      dhcp-option-force=option:router,${gw}
    '' + lib.optionalString (ntp-server != null) ''
      dhcp-option-force=option:ntp-server,${ntp-server}
    '' + lib.optionalString (nameservers != null) ''
      no-resolv # do not read /etc/resolv.conf
    '' + lib.optionalString (nameservers != null && nameservers != []) ''
      dhcp-option-force=6,${lib.concatStringsSep "," nameservers}
    '' + lib.optionalString (!enable-dns) ''
      port=0 # completely disables DNS function, leaving only DHCP and/or TFTP
    '' + lib.optionalString (dhcp-range != null) ''
      dhcp-range=${dhcp-range.start},${dhcp-range.end},${dhcp-range.lease-time or "12h"}
    '' +
      (lib.concatStrings
        (lib.mapAttrsToList (k: v: ''
          dhcp-host=${k},${v}
        '') dhcp)) +
    ''
      ${conf-text}
    '');

in six.mkFunnel {
  passthru.after = [
    targets.global.coldplug  # for /dev/urandom
  ];
  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    ${pkgs.busybox}/bin/busybox mkdir -p /run/${instance-name}
    ${pkgs.busybox}/bin/busybox chown ${user-name} /run/${instance-name}
    exec ${pkgs.dnsmasq}/bin/dnsmasq -k --log-facility=- -u ${user-name} -C ${conf-file}
  '';
}
