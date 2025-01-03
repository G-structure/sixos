{ lib
, forall-hosts
, infuse
, six-initrd
}:

# TODO: rename this file to initrd.nix

[(forall-hosts

  # TODO: move this into arch/
  (final: prev:
    let
      inherit (final) name pkgs;

      make-linux-fast-again = lib.optionals (with pkgs.stdenv.hostPlatform; isx86 || isAarch64) [
        "noibrs"
        "noibpb"
        "nopti"
        "nospectre_v2"
        "nospectre_v1"
        "l1tf=off"
        "nospec_store_bypass_disable"
        "no_stf_barrier"
        "mds=off"
        "tsx=on"
        "tsx_async_abort=off"
        "mitigations=off"
      ];
    in infuse prev {
      boot.kernel.params   = _: [
        "root=LABEL=boot"
        "ro"
      ] ++ make-linux-fast-again ++ lib.optionals (final.boot?kernel.console.device) [
        ("console=${final.boot.kernel.console.device}"
          + lib.optionalString
            (final.boot?ttys.${final.boot.kernel.console.device})
            ",${toString final.boot.ttys.${final.boot.kernel.console.device}}")
      ];
      boot.kernel.modules  = _: "${final.boot.kernel.package}";
      boot.kernel.payload    = _: "${final.boot.kernel.package}/bzImage";
      boot.kernel.firmware = _: pkgs.buildEnv {
        name = "firmware";
        paths = [
          pkgs.linux-firmware
          pkgs.alsa-firmware
        ];
      };
      boot.kernel.package  = _: final.pkgs.callPackage ./kernel.nix { };
    }
  ))

 # basic minimal initrd
 (forall-hosts
   (final: prev: infuse prev {
     boot.initrd = _:
       (six-initrd {
         inherit lib;
         inherit (final) pkgs;
       })
         .minimal;
  }))

 # abduco-enabled initrd
 (forall-hosts
  (final: prev: infuse prev ({
    boot.initrd.__input.contents = _:
      (six-initrd {
        inherit lib;
        inherit (final) pkgs;
      }).abduco {
        inherit (final.boot) ttys;
      };
  })))

 # minimum necessary contents
 (forall-hosts
  (final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.__input.compress = _: "gzip";
    boot.initrd.__input.contents = ({
      "early/run".__append = [''
        modprobe btrfs || true # not sure why this is necessary
        modprobe ext4 || true  # sterling has rootfs as ext4
      ''] ++ lib.optionals final.tags.is-kgpe [''
        modprobe ehci_hcd
        modprobe ehci_pci
        modprobe sd_mod
        modprobe uas
        modprobe ahci
      ''] ++ [''
        sleep 5  # yuck
      ''];
      "early/fail".__append = [''
        exec /bin/sh

      ''];
    } // lib.optionalAttrs (!final.pkgs.stdenv.hostPlatform.isMips64) {
      "lib/modules"     = _: "${final.boot.kernel.modules}/lib/modules/";
    } // lib.optionalAttrs final.tags.is-gru-kevin {
      # FIXME: need this in the rootfs as well
      # TODO: want to hold the chip in reset too
      "etc/modprobe.conf" = _: builtins.toFile "modprobe.conf" ''
        blacklist mwifiex_pcie
        blacklist mwifiex
      '';
    } // lib.optionalAttrs final.tags.is-kgpe {
      # FIXME: need this in the rootfs as well
      "etc/modprobe.conf" = _: builtins.toFile "modprobe.conf" ''
        blacklist ehci_hcd
        blacklist ehci_pci
        blacklist snd_pcsp
      '';
    });
  })))

 (forall-hosts
  (final: prev: let inherit (final) pkgs; in infuse prev ( {
    boot.initrd.__input.contents =
      let
        boot-ifconn = final.ifconns.${final.boot.nfsroot.subnet};
      in
        (lib.optionalAttrs final.tags.is-nfsroot {
      # TODO: identify "scratch drives" using the partition table uuid:
      #   grep -lxF eui.002538db11418915 /sys/block/* /wwid
      #   sfdisk --disk-id /dev/nvme0n1 33333333-3333-3333-3333-333333333333
      #
      # FIXME: this is totally unauthenticated
      "early/run".__append = lib.optionals final.tags.is-kgpe [ ''
        # the ownerboot kernel is probably missing features that s6-linux-init expects :(
        modprobe e1000e
      ''] ++ lib.optionals final.tags.is-rockpi4 [''
        modprobe dwmac_rk
      ''] ++ [''
        ifconfig ${boot-ifconn.ifname} ${boot-ifconn.ip} up netmask 255.255.255.0
        mount -t tmpfs none -osize=8g /root
        mkdir -p /root/nix/store /root/nix/var/nix/profiles/by-hostname /root/initrd /root/dev /root/proc /root/sys

        mkdir -m 0555 -p /root/bin
        ln -sfT /run/current-system/sw/bin/sh /root/bin/sh
        mkdir -m 0555 -p /root/usr/bin
        ln -sfT /run/current-system/sw/bin/env /root/usr/bin/env
        mkdir -m 0555 -p /root/etc
        echo 'root:x:0:0:root:/root:/run/current-system/sw/bin/sh' > /root/etc/passwd
        echo 'sshd:x:1:1::/run/sshd:/run/current-system/sw/bin/false' >> /root/etc/passwd
        echo 'root:x:0:' >  /root/etc/group
        echo -e 'tty:x:900:\ndisk:x:901:\nuucp:x:902:\nfloppy:x:903:\ncdrom:x:904:\nkvm:x:905:\naudio:x:906:\nvideo:x:907:\ninput:x:908' >> /root/etc/group

        mkdir -p /root/root
        mkdir -p -m 0700 /root/root/.ssh
        cat >> /root/root/.ssh/authorized_keys <<EOF
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+81mtu7it+5hAOnbstiNrsaDz93YdDZ5EGxO6Iu2It user@ostraka
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAsvi2+bDOMayZe61HfseRWCuy7MFTUg2iBLirjvcLtF user@snowden
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILDWcYWBJkezqr6zQl/kSjCOHb1Lcl+rM8ZEQ+vEKgs0 user@conway
        EOF

        touch /init  # stupid busybox switch_root sanity-check
        mount -t nfs -ov3,nolock,port=2049,mountport=2049,ro 192.168.22.6:/nix/var/nix/profiles/by-hostname /root/nix/var/nix/profiles/by-hostname
        mount -t nfs -ov3,nolock,port=2049,mountport=2049,ro 192.168.22.6:/nix/store /root/nix/store
        mkdir -p /root/nix/var/nix/profiles
        ln -s by-hostname/${final.name}/nextboot /root/nix/var/nix/profiles/nextboot
      ''];
    });
  })))

 # cryptsetup-enabled initrd
 (forall-hosts
  (final: prev: let inherit (final) pkgs; in infuse prev ({
    boot.initrd.__input.contents = lib.optionalAttrs (!final.tags.is-nfsroot) {
      "early/run".__append = [''
        for DEV in $(blkid | grep 'TYPE="crypto_LUKS"' | sed 's_^\([^\:]*\):.*$_\1_;t;d'); do
            # we're relying here on the fact that the keyfile passed by the
            # pre-kexec initrd will only work on one of the volumes...
            if cryptsetup luksDump $DEV | grep -q '^Label:\W*\(boot\|rescue\)$'; then
                cryptsetup luksOpen --key-file /miniboot-cryptsetup-keyfile $DEV miniboot-root
            fi
        done
      ''];
      "sbin/cryptsetup" = _: let
        cryptsetup =
          infuse pkgs.pkgsStatic.cryptsetup ({
            __input.lvm2 = _: pkgs.pkgsStatic.lvm2;
            __input.withInternalArgon2 = _: true;
            __output.configureFlags.__append = [
              "--disable-external-tokens"
              "--disable-ssh-token"
              "--disable-luks2-reencryption"
              "--disable-veritysetup"
              "--disable-integritysetup"
              "--disable-selinux"
              "--disable-udev"
              "--enable-internal-sse-argon2"
              "--with-crypto_backend=kernel"    # huge reduction: 4.4M to under 1M
            ];
          });
        in "${lib.getBin cryptsetup}/bin/cryptsetup";
    };
  })))

 # lvm-enabled initrd
 (forall-hosts
  (final: prev: let inherit (final) pkgs; in infuse prev ( {
    boot.initrd.__input.contents = lib.optionalAttrs (!final.tags.is-nfsroot && !final.tags.dont-mount-root) {
      "early/run".__append = [''
        # lvm lvchange --addtag @boot vg/lv
        /sbin/lvm lvchange -a ay @boot
        mkdir -p /root
        mount -o ro LABEL=boot /root || exit 1
      ''];
      "sbin/dmsetup"    = _: "${lib.getBin pkgs.pkgsStatic.lvm2}/bin/dmsetup.static";
      "sbin/lvm"        = _: "${lib.getBin pkgs.pkgsStatic.lvm2}/bin/lvm";
    };
  })))

 # switch_root into the chosen profile
 (forall-hosts
  (final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.__input.contents."early/finish".__init = [''
      CONFIGURATION=/nix/var/nix/profiles/nextboot
      set -- $(cat /proc/cmdline)
      for x in "$@"; do
          case "$x" in
              configuration=*)
              CONFIGURATION="''${x#configuration=}"
              ;;
          esac
      done
      echo
      echo initrd: will now switch_root to configuration $CONFIGURATION
      echo
      # sanity check: make sure that $CONFIGURATION exists
      (test -e /root$CONFIGURATION || test -L /root/$CONFIGURATION) \
        && exec switch_root /root $CONFIGURATION/boot/init
      exec /bin/sh
    ''];
  })))

]
