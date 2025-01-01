{ lib
, pkgs
, six
, targets

, debug ? false

, ifname  ? throw "missing ifname"
, address ? null
, netmask ? if address==null then null else throw "missing netmask"
, gw ? if dhcp then true else null    # set to `true` to use the device itself (with no gateway) as the default route
, mtu ? null

# FIXME instead of each of these being a string, they should be a list of
# exec()-able paths

, type ? null      # if non-null, `ip link add` will be called
, pre-add ? null   # executed at the very start of the `up` script
, pre-up ? null    # executed immediately before `ip link set ${ifname} up`
, post-up ? null   # executed at the very end of the `up` script, or after *each* dhcp lease issuance/renewal
, pre-down ? null  # executed immediately before `ip link set ${ifname} down` (FIXME: what about dhcp?)
, post-down ? null # executed at the very end of the `down` script (FIXME: what about dhcp?)

, dhcp ? false     # FIXME: need to deal with DNS/resolvconf

, metric ? null    # if non-null, this metric will be used for any routes added by this service.nix
, table ? null     # if non-null, any routes added will be added to this table

, passthru ? {}
}:

# FIXME: readiness signaling to supervisor

# FIXME: change addresses gracefully, without bringing the interface up/down
# FIXME: use `-e` in scripts?

assert dhcp -> (gw==null || gw==true);

let passthru' = passthru; in
let
  passthru = passthru' // {
    after = (passthru'.after or []) ++ (with targets.global; [
      coldplug      # note: udhcpc expects /dev/random
      set-hostname
    ]);
  };

  up = lib.optionalString (pre-add != null) ''
    ${pre-add}
  '' + lib.optionalString (type != null) ''
    ${pkgs.iproute2}/bin/ip link del ${ifname} &>/dev/null || true
    ${pkgs.iproute2}/bin/ip link add ${ifname} type ${type}
  '' + lib.optionalString (mtu != null) ''
    ${pkgs.iproute2}/bin/ip link set ${ifname} mtu ${builtins.toString mtu}
  '' + lib.optionalString (pre-up != null) ''
    ${pre-up}
  '' + ''
    ${pkgs.iproute2}/bin/ip link set ${ifname} up
  '';

  down = pkgs.writeScript "down.sh" (''
    #!${pkgs.runtimeShell} ${lib.optionalString debug "-x"}
    exec 2>&1
  '' + lib.optionalString (pre-down != null) ''
    ${pre-down}
  '' + ''
    ${pkgs.iproute2}/bin/ip link set ${ifname} down
    ${pkgs.iproute2}/bin/ip addr flush dev ${ifname}
  '' + lib.optionalString (type != null && type != "loopback") ''
    ${pkgs.iproute2}/bin/ip link del ${ifname} type ${type}
  '' + lib.optionalString (post-down != null) ''
    ${post-down}
  '');

  # https://udhcp.busybox.net/README.udhcpc
  # SIGUSR1 will force a renew state
  # SIGUSR2 will force a release of the current lease, and cause udhcpc to
  # go into an inactive state (until it is killed, or receives a SIGUSR1).
  dhcp-script = pkgs.writeScript "dhcp-script.sh" (''
    #!${pkgs.runtimeShell} -x
    router=$serverid
    case $1 in
      bound|renew)
        ${pkgs.iproute2}/bin/ip addr replace $ip/$subnet dev ${ifname}

  '' + lib.optionalString (gw == true) ''
        ${pkgs.iproute2}/bin/ip route replace default via $router dev $interface ${
          lib.optionalString (metric!=null) " metric ${metric}"
        } ${
          lib.optionalString (table!=null) " table ${table}"
        }

  '' + lib.optionalString (post-up != null) ''
        ${post-up}
        ;;

      # note: busybox executes this *on startup* as well as after a lease is
      # lost.  it is expected to leave the interface *up* but with no address.
      deconfig)
        ${pkgs.iproute2}/bin/ip addr flush ${ifname} || true
        ${pkgs.iproute2}/bin/ip link set up ${ifname}
        ;;

      leasefail | nak)
        echo "configuration failed: $1: $message"
        ;;

      *)
        echo "$0: Unknown udhcpc command: $1" >&2
        exit 1
        ;;
    esac
  '');

  udhcpc-args = [
    "-C"  # do not send MAC address as client identifier
    "-f"  # run in the foreground
    "-n"  # exit if lease not obtained (supervisor will restart us)
    "-R"  # release IP on exit
    #"--request=ip" # request a specicfic IP
    #"-V" "udhcp VERSION"   # vendor identifier
    #"-F" NAME   # ask server to update DNS mapping for NAME (??)
    #"-x opt:val"
    #"--clientid="  # clientid
    #"--hostname="  # hostname
    "-S" # log to syslog in addition to /dev/stderr
    "-i" "${ifname}"
    "-s" "${dhcp-script}"
  ];

in if dhcp
   then six.mkFunnel {
     inherit passthru;
     run = pkgs.writeScript "run-dhcp-${ifname}" (''
       #!${pkgs.runtimeShell}
       exec 2>&1
       ${up}
       exec ${pkgs.busybox}/bin/busybox udhcpc ${lib.escapeShellArgs udhcpc-args}
     '');
     finish = down;
   }
   else six.mkOneshot {
     up = pkgs.writeScript "up-${ifname}" (''
       #!${pkgs.runtimeShell}
       exec 2>&1
       ${up}
     '' + lib.optionalString (address != null) ''
       ${pkgs.iproute2}/bin/ip addr change ${address}/${builtins.toString netmask} dev ${ifname}
     '' + lib.optionalString (gw == true) ''
       ${pkgs.iproute2}/bin/ip route replace default           dev ${ifname}
     '' + lib.optionalString (gw != true && gw != null) ''
       ${pkgs.iproute2}/bin/ip route replace default via ${gw} dev ${ifname}
     '' + lib.optionalString (post-up != null) ''
       ${post-up}
     '');
     inherit down passthru;
   }
