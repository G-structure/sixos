{ lib
, six
, pkgs
, targets
, package ? pkgs.tox-node
, user-name ? "tox"
, group-name ? "tox"
, secret-key-file ? throw "secret-key-file is required"
, listen-address ? throw "listen-address is required"
, listen-port ? 33445
, listen-udp ? true
, listen-tcp ? true
, threads ? 1
}:
let
  motd = "{{start_date}} {{uptime}} Hi from tox-rs on Nixpkgs! I'm up {{uptime}}. TCP: incoming {{tcp_packets_in}}, outgoing {{tcp_packets_out}}, UDP: incoming {{udp_packets_in}}, outgoing {{udp_packets_out}}";
  bootstrap-args =
    lib.pipe (import ./bootstrap-nodes.nix) [
      (lib.mapAttrsToList
        (key: endpoint: [ "--bootstrap-node" key endpoint ]))
      lib.concatLists
    ];
  args = [
    "-u" "${user-name}:${group-name}"
    "-U" "${user-name}:${group-name}"
    "${package}/bin/tox-node"
  ] ++ lib.optionals listen-udp [
    "--udp-address" "${listen-address}:${toString listen-port}"
  ] ++ lib.optionals listen-tcp [
    "--tcp-address" "${listen-address}:${toString listen-port}"
  ] ++ [
    "--threads" (toString threads)
    "--motd" motd
  ] ++ bootstrap-args;

in
six.mkFunnel {
  passthru.after = [
    targets.global.coldplug
  ];

  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1
export TOX_SECRET_KEY=$(${pkgs.busybox}/bin/busybox cat ${secret-key-file})
export RUST_LOG=tox=debug
exec ${pkgs.runit}/bin/chpst ${lib.escapeShellArgs args}
'';
}
