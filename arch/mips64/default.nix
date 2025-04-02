
#
# TODO(amjoseph): a bunch of this is only applicable to Octeons, not to all
# MIPSen.
#
# TODO(amjoseph): attempt to check the "setup requirements" programmatically
# instead of expecting people to read this file.
#

/*

IMPORTANT SETUP REQUIREMENTS!

You must execute the following commands from the uboot prompt (on the serial
console) before attempting to boot sixos on an octeon router.  I recommend:

1. Boot from recovery media (any distro with the `nix` binary)
2. Copy your configuration into the store
3. Run `${configuration}/bin/nextboot`
4. Reboot while pressing "enter" on the serial console to enter the uboot prompt
5. Paste the commands below
   - the (hexadecimal) value `20000000` below should match the `loadaddr-hex` parameter
   - the `numcores` value should be `4` for the ER-4 and ER-6
6. Type `reset`

```
env default -a
setenv bootcmd  'run normal'
setenv bootargs ''
setenv loadaddr 20000000
setenv numcores 4
setenv normal   'fatload mmc 0 $(loadaddr) normal.ubootenv; env import $(loadaddr) $(filesize); fatload mmc 0 $(loadaddr) normal.uImage; env run boot'
setenv fallback 'fatload mmc 0 $(loadaddr) fallback.ubootenv; env import $(loadaddr) $(filesize); fatload mmc 0 $(loadaddr) fallback.uImage; env run boot'
setenv usb      'usb start; fatload usb 0 $(loadaddr) normal.ubootenv; env import $(loadaddr) $(filesize); fatload usb 0 $(loadaddr) normal.uImage; env run boot'
setenv boot     'fdt addr $(loadaddr); fdt get value bootscript /images/script data; run bootscript'
saveenv
reset
```

You'll also need to make sure that `/dev/mmcblk0p1` is a partition of type
`vfat` (the routers ship this way from the manufacturer) with its partition
label set to `boot` (the routers do NOT ship this way).  To set the partition
label, use the `fatlabel` command from `dosfstools`:

```
fatlabel /dev/mmcblk0p1 boot
```

It has to be this exact partition because the uboot `bootcmd` above looks for
the first (zeroth) partition on the (only) mmc device.  Sixos uses volume labels
to find the partition.  You can use a different partition by adjusting the
`setenv bootcmd` above.

In theory it should be possible to set the uboot parameters (which are stored in
mtd flash) programmatically from a booted Linux kernel, rather than having to
use the serial console to do it via uboot.  I never got this working; here's my
unfinished attempt:

```
# I never got this to work properly... (this goes in /etc/fw_env.config)
fw_env = ''
  # MTD device name       Device offset   Env. size       Flash sector size       Number of sectors
  /dev/mtd0               0x7fe000        0x2000          0x1000
'';

set-up-mtd = ''
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 boot0   ${toString (       0 *1024)}      ${toString (3072*1024)}
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 dummy   ${toString (    3072 *1024)}      ${toString (1024*1024)}
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 eeprom  ${toString (    4096 *1024)}      ${toString (  64*1024)}
  ${mtd-utils}/bin/mtdpart add /dev/mtd0 spare   ${toString ((64+4096)*1024)}      ${toString (   0*1024)}
'';
```

*/

{ final
, name
, infuse
, pkgs ? final.pkgs
, lib ? pkgs.lib

, boot-device-label ? "boot"  # filesystem from which uboot will read the kernel and initrd
, root-device-label ? "root"  # root filesystem device (post-boot)

#
# For some utterly strange reason the kernel and initrd must both be
# placed within the 16mbyte window between 0.5gb and 0.5gb+16mbyte.
# Need to figure out why.
#
, preloadaddr-hex      ?   "22000000"  # where the uImage is placed when first loaded from network or disk
, fdtaddr-hex          ?      "80000"  # where the devicetree is located when we jump to the kernel
, loadaddr-hex         ?   "20000000"  # where the kernel is located when we jump to it
, initrd-alignment-hex ?      "10000"  # initrd address will be aligned to multiples of this
, initrd-addr-hex      ?   "20C90000"  # where the initrd is located
, initrd-ceiling-hex   ?   "21000000"  # build will fail if top of initrd is above this address

#
# Although the factory bootloader (u-boot) can be instructed to pass a DTB to
# the kernel, it mangles the DTB in the process (likely trying to helpfully
# autodetect something).  Ubiquiti ships big-endian kernels so maybe their
# bootloader assumes big-endian?  Anyways, if you want to use `vmlinux` kernel
# images instead of a FIT (Flattened Image Tree) archive you'll need to enable
# this.
#
, append-dtb-to-kernel ? false

}:

let

  params = final.boot.kernel.params;

  payload = pkgs.stdenv.mkDerivation {
    pname = "kernel+initrd+dtb";
    inherit (final.boot.kernel.package) version;
    dontUnpack = true;
    nativeBuildInputs = with pkgs.buildPackages; [
      dtc bc
    ];

    # Old buildPhase commands that are no longer needed (but might be useful
    # someday):
    #
    # fdtput    -p -v dtb -t x /chosen linux,initrd-start 0x${initrd-addr-hex}
    # fdtput    -p -v dtb -t x /chosen linux,initrd-end   0x$((echo 10k; wc -c < ${initrd}; echo 16o 16i; echo ${initrd-addr-hex}; echo '+f') | dc)
    # fdtput    -p -v dtb -t s /chosen bootargs           "rd_start=0x${initrd-addr-hex} rd_size=$(wc -c < ${final.boot.initrd.image}) mem=0"
    # fdtput    -p -v dtb -t s /chosen bootargs           ${lib.escapeShellArg (lib.concatStringsSep " " params)}
    #
    buildPhase = lib.optionalString (final.boot.kernel.dtb != null) ''
      cp ${final.boot.kernel.dtb} dtb
      chmod u+w dtb
      dtc -I dtb -O dts dtb -o before.dts

      # not sure this matters
      fdtput    -p -v dtb -t s /chosen stdout-path   "soc/serial@1180000000800"

      dtc -I dtb -O dts dtb -o after.dts
      echo
      diff -u before.dts after.dts || true
      echo

    ''
    #
    # kernel
    #
    + ''
      cp ${final.boot.kernel.package}/vmlinux-* vmlinux
      chmod u+w vmlinux
    '' + lib.optionalString append-dtb-to-kernel ''
      $OBJCOPY --update-section \
        .appended_dtb=dtb \
        vmlinux
    ''
    #
    # initrd
    #
    + ''
      cp ${final.boot.initrd.image} initrd
      chmod u+w initrd
      KERNEL_ADDR=$((0x${loadaddr-hex}))
      KERNEL_TOP=$(( 0x${loadaddr-hex} + $(cat vmlinux | wc -c) ))
      echo KERNEL_TOP is $(echo "10k16o $KERNEL_TOP f" | dc)
      KERNEL_TOP_PADDING=$(( ( 0x${initrd-alignment-hex} - ( $KERNEL_TOP % 0x${initrd-alignment-hex} ) ) 0x${initrd-alignment-hex}  ))
      echo KERNEL_TOP_PADDING is $(echo "10k16o $KERNEL_TOP_PADDING f" | dc)
      INITRD_ADDR=$(( $KERNEL_TOP + $KERNEL_TOP_PADDING ))
      echo INITRD_ADDR is $(echo "10k16o $INITRD_ADDR f" | dc)
      INITRD_TOP=$(( $INITRD_ADDR + $(cat initrd | wc -c) ))
      echo INITRD_TOP is $(echo "10k16o $INITRD_TOP f" | dc)
      if (( $INITRD_TOP > 0x${initrd-ceiling-hex} )); then
        echo kernel and initrd together do not fit beneath 0x${initrd-ceiling-hex}
        exit -1
      fi
    ''
    #
    # devicetree
    #
    + ''
      cat > octeon-dts <<EOF
      /dts-v1/;
      / {
          description = "kernel image with one or more FDT blobs";
          images {
              kernel {
                  description = "kernel";
                  data = /incbin/("vmlinux");
                  type = "kernel_noload";
                  arch = "mips";
                  os = "linux";
                  compression = "none";
                  load = <0x${loadaddr-hex}>;
                  entry = <0>;
                  hash {
                      algo = "sha1";
                  };
              };
              ramdisk {
                  description = "initramfs";
                  data = /incbin/("initrd");
                  type = "ramdisk";
                  arch = "mips";
                  os = "linux";
                  compression = "none";
                  load = <0x${initrd-addr-hex}>;
                  entry = <0>;
                  hash {
                      algo = "sha1";
                  };
              };
    '' + lib.optionalString (final.boot.kernel.dtb != null) ''
              fdt {
                  description = "fdt";
                  data = /incbin/("dtb");
                  type = "flat_dt";
                  arch = "mips";
                  compression = "none";
                  load = <0x${fdtaddr-hex}>;
                  hash {
                      algo = "sha1";
                  };
              };
    '' + ''
              script {
                  description = "script";
                  data = /incbin/("script");
                  type = "script";
                  compression = "none";
                  hash {
                      algo = "sha1";
                  };
              };
          };
          configurations {
              default = "conf";
              conf {
                  kernel = "kernel";
                  fdt = "fdt";
                  ramdisk = "ramdisk";
              };
          };
      };
      EOF
    ''
    #
    # boot script
    #
    + ''
      echo ${lib.escapeShellArg
(lib.concatStringsSep ";" ([
    "fdt move $(fileaddr) 0x${preloadaddr-hex}"
    "fdt addr 0x${preloadaddr-hex}"
    "usb start"
    "fdt header"
    "fdt get addr kernel_addr /images/kernel data"
    "fdt get value rd_start /images/ramdisk load"
    "imxtract 0x${preloadaddr-hex} ramdisk $(rd_start)"
    "fdt get size rd_size /images/ramdisk data"
    "bootm start 0x${preloadaddr-hex}"
    "bootm loados"
    "bootm fdt"
    "bootoctlinux $(kernel_addr) numcores=$(numcores) endbootargs rd_start=$(rd_start) rd_size=$(rd_size) ${lib.concatStringsSep " " params} $(bootargs)"
  ]))} > script
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      ln -s ${final.boot.kernel.package}/{dtbs,lib,config-*,System.map-*} $out/

      ${pkgs.buildPackages.ubootTools}/bin/mkimage \
        -D "-I dts -O dtb -p 4096" \
        -B 1000 \
        -f octeon-dts \
        uImage
      mv uImage $out/uImage

      cp ${final.boot.kernel.package}/vmlinux-* $out/vmlinux
      chmod u+w $out/vmlinux
      cp ${final.boot.initrd.image} $out/initrd

      runHook postInstall
    '';
  };

in
{
  boot.kernel.payload  = _: "${payload}/uImage";

  boot.kernel.dtb = _:
    if final.tags.is-er6
    then "${final.boot.kernel.package}/dtbs/cavium-octeon/cn7130_ubnt_edgerouter_6p.dtb"
    else "${final.boot.kernel.package}/dtbs/cavium-octeon/cn7130_ubnt_edgerouter4.dtb";

  boot.initrd.ttys.ttyS0 = _: 115200;
  boot.kernel.console.device.__assign = "ttyS0";
  boot.kernel.console.baud.__assign   = 115200;

  # The Linux octeon MMC drivers seem to take a very long time to notice that
  # the device exists... like one or two full seconds after the
  # kernel-to-userspace handoff.  So we have to wait for the root device to
  # appear.
  boot.initrd.mount-root.__assign = [''
    while ! (busybox blkid | busybox grep -q 'LABEL="${root-device-label}"'); do
      echo waiting for a device with 'LABEL="${root-device-label}"' to appear
      sleep 1
    done
    mount -o ro LABEL="${root-device-label}" /root || exit -1
  ''];

  # TODO(amjoseph): get rid of `*.ubootenv` (it has serious shell-quoting
  # issues) and instead run `mkimage` from inside the `update-bootloader`
  # script.  We can't hardwire the configuration outpath into the `uImage`
  # because they're built by separate derivations and this would create a
  # reference cycle in `/nix/store`.  This will also clean up the install-media
  # situation.
  boot.loader.update = _:
    pkgs.writeShellScript "update-bootloader" ''
      ${pkgs.busybox}/bin/busybox blkid | ${pkgs.busybox}/bin/busybox grep -q 'LABEL="${root-device-label}"' || \
        (echo -e '\n***\nno device with LABEL=${root-device-label}, refusing to update bootloader (sanity check)\n***\n'; exit -1)
      ${pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint
      ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint 2>/dev/null || true # in case it was mounted
      ${pkgs.busybox}/bin/mount LABEL=${boot-device-label} /run/six/update-bootloader-mountpoint
      ${pkgs.busybox}/bin/cp -L $2/boot/kernel         /run/six/update-bootloader-mountpoint/fallback.uImage
      ${pkgs.busybox}/bin/echo -n bootargs=         >  /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${pkgs.busybox}/bin/cat $2/boot/kernel-params >> /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${pkgs.busybox}/bin/echo                      >> /run/six/update-bootloader-mountpoint/fallback.ubootenv
      ${pkgs.busybox}/bin/cp -L $1/boot/kernel         /run/six/update-bootloader-mountpoint/normal.uImage
      ${pkgs.busybox}/bin/echo -n bootargs=         >  /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${pkgs.busybox}/bin/cat $1/boot/kernel-params >> /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${pkgs.busybox}/bin/echo                      >> /run/six/update-bootloader-mountpoint/normal.ubootenv
      ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint
    '';

  # mips devices have very small disks
  delete-generations = _: "5d";

  # mips devices have really tiny internal mmc devices
  service-overlays.__append = [(final: prev: infuse prev {
    targets.mounts."".__input.options.__append = [ "compress=zstd" ];
  })];

}

/*

Misc Notes:

- If using `bootoctlinux` (which we currently are not using), you must remove
  the factory-shipped `vmlinux.64.md5` from `/dev/mmcblk0p1` -- this is the only
  way to disable md5 checking.

Network boot stuff:

```
setenv tftp_server_ip <REPLACE_ME>
setenv hostname <REPLACE_ME>
setenv netbootcmd 'dhcp; tftp $(loadaddr) $(tftp_server_ip):$(hostname)/uImage; fdt addr $(loadaddr); fdt get value bootscript /images/script data; run bootscript'
```
*/
