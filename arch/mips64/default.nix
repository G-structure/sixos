{ final
, name
, infuse
, sw
, pkgs ? final.pkgs
, lib ? pkgs.lib
, boot-device-label ? "boot"  # filesystem from which uboot will read the kernel and initrd
, root-device-label ? "root"  # root filesystem device (post-boot)
}:

/*
  # I never got this to work properly... (this goes in /etc/fw_env.config)
  fw_env = ''
    # MTD device name       Device offset   Env. size       Flash sector size       Number of sectors
    /dev/mtd0               0x7fe000        0x2000          0x1000
  '';
*/
  /*
  set-up-mtd = ''
    ${mtd-utils}/bin/mtdpart add /dev/mtd0 boot0   ${toString (       0 *1024)}      ${toString (3072*1024)}
    ${mtd-utils}/bin/mtdpart add /dev/mtd0 dummy   ${toString (    3072 *1024)}      ${toString (1024*1024)}
    ${mtd-utils}/bin/mtdpart add /dev/mtd0 eeprom  ${toString (    4096 *1024)}      ${toString (  64*1024)}
    ${mtd-utils}/bin/mtdpart add /dev/mtd0 spare   ${toString ((64+4096)*1024)}      ${toString (   0*1024)}
  '';
  */

let
  payload = pkgs.p.kernel.octeon.payload.override {
    kernel = final.boot.kernel.package;
    initrd = final.boot.initrd;
    params = final.boot.kernel.params;
    dtb    = final.boot.kernel.dtb;
  };
in
{
  boot.kernel.firmware = _: null;
  boot.kernel.package  = _: pkgs.p.kernel.simple;
  boot.kernel.payload  = _: "${payload}/uImage";

  boot.kernel.dtb = _:
    if final.tags.is-er6
    then "${final.boot.kernel.package}/dtbs/cavium-octeon/cn7130_ubnt_edgerouter_6p.dtb"
    else "${final.boot.kernel.package}/dtbs/cavium-octeon/cn7130_ubnt_edgerouter4.dtb";

  boot.ttys.ttyS0 = _: 115200;
  boot.kernel.console.device = _: "ttyS0";

  boot.initrd.__input.contents."early/run" =
    _: pkgs.writeScript "stage3.sh" (''
      #!/bin/sh
      while ! (busybox blkid | busybox grep -q 'LABEL="${root-device-label}"'); do
        echo waiting for a device with 'LABEL="${root-device-label}"' to appear
        sleep 1
      done
      mount -o rw LABEL="${root-device-label}" /root
    '');

  boot.loader.update = _:
    let
    in pkgs.writeShellScript "update-bootloader" ''
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

  sw = _: "${sw.mips}";

  # mips devices have very small disks
  delete-generations = _: "5d";

  # mips devices have really tiny internal mmc devices
  service-overlays.__append = [(final: prev: infuse prev {
    targets.mounts."".__input.options.__append = [ "compress=zstd" ];
  })];

}
