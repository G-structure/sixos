{ lib
, pkgs
, six
, targets
, listen-ip                ? 0    # means listen everywhere
, listen-port              ? 69
, path-to-serve            ? throw "you must provide the path to serve"
, allow-upload             ? false
, allow-file-creation      ? false
, simultaneous-connections ? null
, lookup-peer-hostname     ? false
, setup-environment        ? false
, verbose                  ? false
, user                     ? null
, group                    ? null
, local-hostname           ? null  # reverse lookup will be used if null
}:

assert allow-file-creation -> allow-upload;
assert (user==null) -> (group==null);

six.mkFunnel {
  passthru.after = with targets; [ global.coldplug ];

  # TODO: factor out a six.mkUdpsvd?
  run =
    [ "${pkgs.busybox}/bin/udpsvd" ] ++
    (lib.optional lookup-peer-hostname "-h") ++
    (lib.optional verbose "-v") ++
    (lib.optional (!setup-environment) "-E") ++
    (lib.optionals (user != null) [ "-u" "${user}${lib.optionalString (group != null) ":${group}"}" ]) ++
    (lib.optionals (simultaneous-connections != null) [ "-c" (toString simultaneous-connections) ]) ++
    (lib.optionals (local-hostname != null) [ "-l" local-hostname ]) ++
    [ listen-ip (toString listen-port) ] ++

    [ "${pkgs.busybox}/bin/busybox" "tftpd" ] ++
    (lib.optional allow-file-creation "-c") ++
    (lib.optional (!allow-upload) "-r") ++
    [ "-l" ] ++ # Log to syslog (inetd mode requires this)
    [ path-to-serve ]
  ;
}
