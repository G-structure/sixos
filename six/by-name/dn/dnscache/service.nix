{ lib
, six
, pkgs
, targets
, package ? pkgs.djbdns
, user-name ? "nobody"
, group-name ? "nogroup"
, cache-size ? 10000
, listen-ip ? "127.0.0.1"
, outbound-ip ? "0.0.0.0"   # 0.0.0.0 means let the kernel decide

# if non-null: act as a stub resolver, and forward queries to specified servers
# if null: act as a recursive resolver
, forward-queries-to ? null
, root-servers ? null
}:

# TODO: block queries to .in-addr.arpa. except for *.127.in-addr.arpa

# Useful: "If there are addresses listed in servers/moon.af.mil, for
# example, then dnscache will send queries for anything.moon.af.mil to
# those addresses, and will not cache records for anything.moon.af.mil
# from outside servers such as the root servers."

# Notes:
# - dnscache handles localhost internally, giving it an A record of 127.0.0.1.
# - dnscache handles 1.0.0.127.in-addr.arpa internally, giving it a PTR record of localhost.
# - dnscache handles dotted-decimal domain names internally, giving (e.g.) the domain name 192.48.96.2 an A record of 192.48.96.2.

let

  error-message =
    "exactly one of root-servers or forward-queries-to must be non-null";
  servers =
    if root-servers != null
    then
      assert !(forward-queries-to==null)
              -> throw "you cannot specify both of forward-queries-to and root-servers";
      root-servers
    else if forward-queries-to != null
    then forward-queries-to
    else throw "you cannot leave both forward-queries-to and root-servers unspecified";

  env = {
    FORWARDONLY = if forward-queries-to == null then "0" else "1";
    UID = user-name;
    GID = group-name;
    CACHESIZE = toString cache-size;
    ROOT = dnscache-root;
    IP = listen-ip;
    IPSEND = outbound-ip;
  };

  command = lib.escapeShellArgs ([
    "${pkgs.busybox}/bin/busybox"
    "env"
  ] ++ (lib.mapAttrsToList (k: v: "${k}=${v}") env) ++ [
    "${package}/bin/dnscache"
  ]);

  dnscache-root = "/run/dnscache/root";
in

six.mkFunnel {
  passthru.after = [ targets.global.coldplug ]; # for /dev/urandom
  run = pkgs.writeScript "run"
(''
#!${pkgs.runtimeShell}
exec 2>&1
${pkgs.busybox}/bin/busybox rm -rf ${dnscache-root}
${pkgs.busybox}/bin/busybox mkdir -p ${dnscache-root}
'' +
# FIXME apparently this is a non-disableable filtering mechanism for client IPs,
# but it can only be configured at 8-bit-netmask-chunk granularity?
''
${pkgs.busybox}/bin/busybox mkdir -p ${dnscache-root}/ip
${pkgs.busybox}/bin/busybox touch ${dnscache-root}/ip/127.0.0.1
'' +
''
${pkgs.busybox}/bin/busybox rm -rf ${dnscache-root}/servers
${pkgs.busybox}/bin/busybox mkdir -p ${dnscache-root}/servers
${# TODO: validate that these are numerical ipv4 addresses at eval-time
  lib.concatStrings (map (ip: ''
    echo ${lib.escapeShellArg ip} >> ${dnscache-root}/servers/@
  '') servers)
}

${pkgs.busybox}/bin/busybox chown -R ${user-name}:${group-name} ${dnscache-root}

'' +
# FIXME: move this somewhere else
''
${pkgs.busybox}/bin/busybox chattr -i /etc/resolv.conf || true &>/dev/null
echo 'nameserver 127.0.0.1' > /etc/resolv.conf
${pkgs.busybox}/bin/busybox chattr +i /etc/resolv.conf
'' +
''
exec ${command} < /dev/urandom
'');
}
