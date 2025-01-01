{ final
, name
, infuse
, sw
, tags
, pkgs ? final.pkgs
, lib /*? pkgs.lib*/          # no default in order to prevent infinite recursion
, boot-device-label ? "boot"  # filesystem from which uboot will read the kernel and initrd
, root-device-label ? "root"  # root filesystem device (post-boot)
}:

{
  sw = _: "${sw.arm}";

} // lib.optionalAttrs tags.is-nfsroot {
  boot.kernel.firmware = _: null;
  boot.kernel.package  = _: pkgs.p.kernel.simple;
  boot.kernel.payload  = _: pkgs.callPackage ./payload.nix {
    kernel = "${final.boot.kernel.package}/Image";
    initrd = final.boot.initrd;
    params = final.boot.kernel.params;
    dtb    = final.boot.kernel.dtb;
  };
/*
  # FIXME this is all wrong
  boot.loader.update = _:
    let
    in pkgs.writeShellScript "update-bootloader" ''
      ${pkgs.busybox}/bin/busybox blkid | ${pkgs.busybox}/bin/busybox grep -q 'LABEL="${root-device-label}"' || \
        (echo -e '\n***\nno device with LABEL=${root-device-label}, refusing to update bootloader (sanity check)\n***\n'; exit -1)
      ${pkgs.busybox}/bin/mkdir -p /run/six/update-bootloader-mountpoint
      ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint 2>/dev/null || true # in case it was mounted
      ${pkgs.busybox}/bin/mount LABEL=${boot-device-label} /run/six/update-bootloader-mountpoint
      ${pkgs.busybox}/bin/cp -L $2/boot/kernel /run/six/update-bootloader-mountpoint/fallback.uImage
      ${pkgs.busybox}/bin/cp -L $1/boot/kernel /run/six/update-bootloader-mountpoint/normal.uImage
      ${pkgs.busybox}/bin/umount /run/six/update-bootloader-mountpoint
    '';
*/
}
