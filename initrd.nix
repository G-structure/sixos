{ lib
, infuse
, six-initrd
, util
}:

[

 # basic minimal initrd
 (util.forall-hosts
   (host-name: final: prev: infuse prev {
     boot.initrd.image.__assign =
       (six-initrd {
         inherit lib;
         inherit (final) pkgs;
       })
         .minimal;
  }))

 (util.forall-hosts
   (host-name: final: prev: infuse prev {
     boot.initrd.image.__input.contents.__init =
       final.boot.initrd.contents;
   }))

 # abduco-enabled initrd
 (util.forall-hosts
  (host-name: final: prev: infuse prev ({
    boot.initrd.contents =
      lib.mapAttrs
        (_: val: { __default = val; })
        ((six-initrd {
          inherit lib;
          inherit (final) pkgs;
        }).abduco {
          ttys = final.boot.initrd.ttys;
        });
  })))

 # minimum necessary contents
 (util.forall-hosts
  (host-name: final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.image.__input.compress = _: "gzip";
    boot.initrd.image.__input.contents = ({
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

 (util.forall-hosts
  (host-name: final: prev: let inherit (final) pkgs; in infuse prev ( {
    boot.initrd.image.__input.contents =
      lib.optionalAttrs final.tags.is-nfsroot {
      # TODO: identify "scratch drives" using the partition table uuid:
      #   grep -lxF eui.002538db11418915 /sys/block/* /wwid
      #   sfdisk --disk-id /dev/nvme0n1 33333333-3333-3333-3333-333333333333
      "early/run".__append = lib.optionals final.tags.is-kgpe [ ''
        # the ownerboot kernel is probably missing features that s6-linux-init expects :(
        modprobe e1000e
      ''] ++ lib.optionals final.tags.is-rockpi4 [''
        modprobe dwmac_rk
      ''];
    };
  })))

 # cryptsetup-enabled initrd
 (util.forall-hosts
  (host-name: final: prev: let inherit (final) pkgs; in infuse prev ({
    boot.initrd.image.__input.contents = lib.optionalAttrs (!final.tags.is-nfsroot) {
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
 (util.forall-hosts
  (host-name: final: prev: let inherit (final) pkgs; in infuse prev ( {
    boot.initrd.image.__input.contents = lib.optionalAttrs (!final.tags.is-nfsroot && !final.tags.dont-mount-root) {
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
 (util.forall-hosts
  (host-name: final: prev: let
    inherit (final) pkgs;
  in infuse prev ({
    boot.initrd.contents."early/finish".__append = [''
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
