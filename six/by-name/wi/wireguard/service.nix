{ lib
, yants
, pkgs
, services
, targets
, peers ? throw "missing peers"
, ifname ? throw "missing ifname"
, address ? throw "missing address"
, netmask ? throw "missing netmask"
, gw ? null
, mtu ? null
, fwmark ? null
, private-key-filename ? throw "missing private key file"
, pre-shared-key-filename ? null
, listen-port ? throw "listen-port is required"
, modprobe-command ? "/run/current-system/boot/modprobe-wrapped"
, pre-add ? ""     # executed at the very start of the `up` script
, pre-up ? ""      # executed immediately before `ip link set ${ifname} up`
, post-up ? ""     # executed at the very end of the `up` script
, pre-down ? null  # executed immediately before `ip link set ${ifname} down`
, post-down ? null # executed at the very end of the `down` script
, passthru ? {}
}:

let
  wg = "${pkgs.wireguard-tools}/bin/wg";

  # this matches the definitions in types.nix
  types = with yants; rec {
    endpoint = struct "endpoint" {
      ip = string;
      port = int;
    };
    peer = struct "peer" {
      endpoint = option endpoint;
      allowed-ips = list string;
      pubkey = option string;
      keepalive-seconds = option int;
    };
    peers = attrs peer;
  };
in
services.netif {
  type = "wireguard";
  inherit address netmask mtu ifname gw;
  inherit pre-down;
  inherit post-down;
  passthru = passthru // {
    # since we need to do a `modprobe wireguard`, we have to wait for the
    # coldplug to finish first
    after = (passthru.after or []) ++ [ targets.global.coldplug ];
  };
  pre-add = pre-add + ''
    ${modprobe-command} wireguard
  '';
  pre-up = pre-up + lib.optionalString (fwmark != null) ''
    ${wg} set ${ifname} fwmark ${toString fwmark}
  '';
  post-up = ''
    ${wg} set ${ifname} private-key ${private-key-filename}
    ${wg} set ${ifname} listen-port ${toString listen-port}
  '' +
  (lib.concatStringsSep " "
    (lib.mapAttrsToList
      (peerName: peer:
        (lib.concatStringsSep " " ([
          wg
          "set" ifname
          "peer" peer.pubkey
          "allowed-ips" (lib.concatStringsSep "," peer.allowed-ips)
        ] ++ lib.optionals (peer.endpoint or null != null) [
          "endpoint ${peer.endpoint.ip}:${toString peer.endpoint.port}"
        ] ++ lib.optionals (lib.isInt (peer.keepalive-seconds or null)) [
          "persistent-keepalive" (toString peer.keepalive-seconds)
        ] ++ lib.optionals (pre-shared-key-filename != null) [
          "preshared-key" pre-shared-key-filename
        ] ++ [
          "# ${peerName}"   # extremely useful for troubleshooting
        ]))+"\n"
      )
      (types.peers peers)
    )
  )
  + post-up;
}
