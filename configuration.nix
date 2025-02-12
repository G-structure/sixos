{ lib
, yants
, infuse
, host
, overlays ? []
, nixpkgs-version ? "unknown-nixpkgs-version"
}:

let
  six = import ./six {
    inherit lib yants;
    inherit (host) pkgs;
  };

  netifs = final: {
    targets.net.iface = _: lib.pipe host.interfaces [
      (lib.mapAttrsToList
        (ifname: interface:
          if interface.type or null == "loopback"
          then lib.nameValuePair ifname (final.services.netif {
            inherit ifname;
            inherit (interface) type;
            address = "127.0.0.1";
            netmask = 8;
          }) else if interface?subnet
            then lib.nameValuePair ifname (
              let ifconn = host.ifconns.${interface.subnet};
              in if ifconn?wg
                 then final.services.wireguard ((builtins.removeAttrs ifconn ["ip" "edenPort" "wg"]) // {
                   inherit ifname;
                   inherit (ifconn) mtu netmask;
                   inherit (ifconn.wg) fwmark peers;
                   private-key-filename = "/etc/wireguard/privatekey";
                   address = host.ifconns.${interface.subnet}.ip;
                   listen-port = 201;
                 })
                 else final.services.netif ((builtins.removeAttrs ifconn ["ip" "edenPort"]) // {
                   inherit ifname;
                 } // lib.optionalAttrs (host.ifconns.${interface.subnet}?ip) {
                   address = host.ifconns.${interface.subnet}.ip;
                 }))
             else null
        ))
      (lib.filter (v: v!=null))
      (map (lib.flip infuse ({
        value.__output.passthru.before.__append = [ final.targets.default ];
      })))
      lib.listToAttrs
    ];
  };

  base = final: prev: infuse prev [
    ({
      targets.default = _: final.six.mkBundle { };
      targets.global.mounts = _: final.six.mkBundle { passthru.before = [ final.targets.default ]; };
      targets.global.coldplug = _: final.six.mkBundle { };
      targets.global.set-hostname = _: final.six.mkBundle { };
      targets.global.hwclock = _: final.six.mkBundle { };
    })
    (netifs final)
    ({
      # TODO: use --onlyonce mounting option?
      targets.mounts = _: {
        proc = final.services.mount { where = "/proc"; };
        sys = final.services.mount { where = "/sys"; };
        dev.pts = final.services.mount { where = "/dev/pts"; };
        tmp = final.services.mount {
          where = "/tmp";
          fstype = "tmpfs";
          options = [ "nodev" "nosuid" "nr_inodes=0" "mode=1777" "size=1g" ];
        };
        dev.shm = final.services.mount {
          where = "/dev/shm";
          options = [ "size=50%" "nosuid" "nodev" "mode=1777" ];
        };
        "" = final.services.mount {
          where = "/";
          options = [ "remount" "rw" ];

          # FIXME: this still isn't good enough; mdevd needs /etc/passwd and
          # /etc/group, and it starts before root remounts read-write
          post-up = ''
            set +e  # best-effort
            if [ "$(${host.pkgs.busybox}/bin/readlink /bin/sh)" != "/run/current-system/sw/bin/sh" ]; then
              ${host.pkgs.busybox}/bin/mkdir -m 0555 -p /bin
              ${host.pkgs.busybox}/bin/ln -sfT /run/current-system/sw/bin/sh /bin/sh
            fi
            if [ "$(${host.pkgs.busybox}/bin/readlink /usr/bin/sh)" != "/run/current-system/sw/bin/env" ]; then
              ${host.pkgs.busybox}/bin/mkdir -m 0555 -p /usr/bin
              ${host.pkgs.busybox}/bin/ln -sfT /run/current-system/sw/bin/env /usr/bin/env
            fi
            if [ ! -e /etc/passwd ]; then
              ${host.pkgs.busybox}/bin/mkdir -m 0555 -p /etc
              echo 'root:x:0:0:root:/root:/run/current-system/sw/bin/sh' > /etc/passwd
              echo 'sshd:x:1:1::/run/sshd:/run/current-system/sw/bin/false' >> /etc/passwd
            fi
            if [ ! -e /etc/group ]; then
              ${host.pkgs.busybox}/bin/mkdir -m 0555 -p /etc
              echo 'root:x:0:'     >  /etc/group
              echo 'tty:x:900:'    >> /etc/group
              echo 'disk:x:901:'   >> /etc/group
              echo 'uucp:x:902:'   >> /etc/group
              echo 'floppy:x:903:' >> /etc/group
              echo 'cdrom:x:904:'  >> /etc/group
              echo 'kvm:x:905:'    >> /etc/group
              echo 'audio:x:906:'  >> /etc/group
              echo 'video:x:907:'  >> /etc/group
              echo 'input:x:908:'  >> /etc/group
            fi
          '';
        };
      };
    })
    {
      targets = {
        mdevd = _: final.services.mdevd {
          conf = host.pkgs.callPackage ./mdev-conf.nix { inherit host; };
        };
        mdevd-coldplug     = _: final.services.mdevd-coldplug { };
        dnscache           = _: final.services.dnscache {
          # FIXME: wait for wireguard?  or at least the firewall?
          forward-queries-to = [
            "8.8.8.8" # REDACTED (was: westernsemico internal)
          ];
        };
        nix-daemon         = _: final.services.nix-daemon {};
        sshd               = _: final.services.sshd {}; # FIXME: logging sshd means it won't start if the root filesystem can't be remounted read-write
        syslog             = _: final.services.syslog {};
        set-hostname       = _: final.services.set-hostname { hostname = host.name; };
        openntpd           = _: final.services.openntpd { };
      };
    }
  ];
  #{ targets = lib.mapAttrs (k: v: if k=="target" then v else util.appendToListAttr "before" [ final.targets.default ] v); }
  # FIXME: need to add after=target-mounts to almost everything
  # above... right now I'm getting away with it only because of logging
in
    six.mkConfiguration {
      inherit (host) boot;
      delete-generations = host.delete-generations or null;
      sw = host.sw or null;
      inherit nixpkgs-version;
      hostname = host.name;
      console.device = host.boot.kernel.console.device;
      console.baud   = host.boot.kernel.console.baud or host.boot.ttys.${host.boot.kernel.console.device};
      verbosity = 3;
      overlays = [
        (final: prev: {
          defaultLogger =
            spath: service:
            let sname = lib.concatStringsSep "." spath; in
            final.six.mkLogger {
              run = let logDir = "/var/log/${sname}/";
                    in host.pkgs.writeShellScript "eden-logger-${sname}" ''
                      ${host.pkgs.busybox}/bin/rm -f "${logDir}" 2>/dev/null # in case a file exists there
                      ${host.pkgs.busybox}/bin/mkdir -p "${logDir}"
                      exec ${host.pkgs.s6}/bin/s6-log s1000000 n20 t "${logDir}"
                    '';
              passthru.after = [
                final.targets.set-hostname
                final.targets.mounts.""  # cannot start logging until filesystem is read/write
              ];
            };
        })
        base
      ] ++ overlays ++ [
        (final: prev:
          infuse prev ({
            targets.default.__output.passthru.after.__append =
              map (name: final.targets.${name})
                # FIXME: hacky
                (lib.attrNames (builtins.removeAttrs prev.targets [ "net" "default" "global" "mounts" ]))
            ;
            targets.mdevd-coldplug.__output.passthru.before.__append = [ final.targets.global.coldplug ];
            targets.set-hostname.__output.passthru.before.__append = [ final.targets.global.set-hostname ];
          }))

        # It is very important that this is the *last* overlay that adds to
        # boot.kernel.params, since `console=` parameters are order-sensitive.  We
        # need the `boot.console.device` to be the *last* `console=` parameter;
        # this makes it the "primary" console which becomes /dev/console after the
        # handoff to userspace.
        (final: prev:
          infuse prev ({
            boot.kernel.params.__append = [
              "console=${final.boot.kernel.console.device or "ttyS0"},${toString final.boot.kernel.console.baud}n8"
            ];
          }))

      ];
    }
