{ lib
, six
, pkgs
, targets
, package ? pkgs.tor
, conf-file ? throw "conf-file is required"
, user-name ? throw "user-name is required"
, group-name ? throw "group-name is required"
}:

let
args = [
    "-U" "${user-name}:${group-name}"
    "-u" "${user-name}:${group-name}"
    "${package}/bin/tor"
    "-f" "${conf-file}"
];
in
six.mkFunnel {
  passthru.after = [
    targets.global.coldplug
  ];
  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1
export HOME=/var/lib/tor
exec ${pkgs.runit}/bin/chpst ${lib.escapeShellArgs args}
'';
}
