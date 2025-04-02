{ lib
, six
, pkgs
, targets
, package ? pkgs.ppp
, chap-secrets ? null
, pap-secrets ? null
, add-default-route ? true
, user ? null
, pppoe-nic ? null
, debug ? false
, plugins ? lib.optionals (pppoe-nic != null) [ "pppoe" ]
, conf-dir ? "/run/ppp/etc"
, conf-text ? ""
}:

/* options to implement:
       defaultroute-metric
              Define the metric of the defaultroute and only add it if
              there is no other default route with the same metric.  With
              the default value of -1, the route is only added if there
              is no default route at all.

       replacedefaultroute
              This option is a flag to the defaultroute option. If
              defaultroute is set and this flag is also set, pppd
              replaces an existing default route with the new default
              route.  This option is privileged.

*/

let package' = package; in
let
  package = package'.overrideAttrs(previousAttrs: {
    configureFlags = (previousAttrs.configureFlags or []) ++ [
      "--with-runtime-dir=${runtime-dir}"
      "--sysconfdir=${sysconfdir}"
    ];
  });

  sysconfdir = "/run/ppp";
  runtime-dir = "/run/ppp";

  conf-file = builtins.toFile "ppp-options" (
    # `defaultroute` does not seem to work properly, so we emulate it in `ip-up`
  ''
    nodefaultroute
  '' + ''
    ${lib.concatStringsSep "\n" (map (plugin: "plugin ${plugin}.so") plugins)}
  '' + lib.optionals (pppoe-nic != null) ''
    nic-${pppoe-nic}
  '' + lib.optionals debug ''
    debug
  '' + lib.optionals (user != null) ''
    user ${user}
  '' + ''
    -detach
    ${conf-text}
  '');

  ip-up = pkgs.writeScript "ip-up.sh" (''
    #!${pkgs.runtimeShell}
    # interface-name tty-device speed local-IP-address remote-IP-address ipparam
    INTERFACE_NAME="$1"
  '' + lib.optionalString (add-default-route != false) ''
    ${pkgs.iproute2}/bin/ip route replace default dev "$1"${
      lib.optionalString (lib.isString add-default-route)
        " table ${lib.escapeShellArg add-default-route}"}
  '');

in six.mkFunnel {
  passthru.after = [
    targets.global.coldplug
    # FIXME: the interface?
  ];
  run = pkgs.writeScript "run" (''
    #!${pkgs.runtimeShell}
    exec 2>&1
  '' + lib.optionals (pppoe-nic != null) ''
    /run/current-system/boot/modprobe-wrapped pppoe
  '' + ''
    # cannot be set independently
    ${pkgs.busybox}/bin/busybox mkdir ${runtime-dir}
    ${pkgs.busybox}/bin/busybox mkdir ${conf-dir}
    ${pkgs.busybox}/bin/busybox ln -sfT ${conf-dir} ${sysconfdir}/ppp
    ${pkgs.busybox}/bin/ln -s ${ip-up} ${conf-dir}/ip-up
  '' + lib.optionals (chap-secrets != null) ''
    ${pkgs.busybox}/bin/ln -s ${chap-secrets} ${conf-dir}/chap-secrets
  '' + lib.optionals (pap-secrets != null) ''
    ${pkgs.busybox}/bin/ln -s ${pap-secrets} ${conf-dir}/pap-secrets
  '' + ''
    exec ${lib.getBin package}/bin/pppd file ${conf-file}
  '');
}
