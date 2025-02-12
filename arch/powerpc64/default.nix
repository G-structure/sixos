{ final
, name
, infuse
, pkgs ? final.pkgs
, lib ? pkgs.lib
}:

{
  boot.initrd.ttys.hvc0 = _: 115200;
  boot.kernel.console.device = _: "hvc0";
  boot.kernel.payload = _: "${final.boot.kernel.package}/vmlinux";
  boot.loader.update = _: pkgs.writeShellScript "update-syslinux" ''
    cat > /boot/syslinux/syslinux.cfg <<EOF
    DEFAULT sixos-normal

    MENU TITLE ------------------------------------------------------------
    TIMEOUT 50

    LABEL sixos-normal
      MENU LABEL sixos
      LINUX $(readlink -f $1/boot/kernel)
      INITRD $(readlink -f $1/boot/initrd)
      APPEND $(cat $1/boot/kernel-params)

    LABEL sixos-fallback
      MENU LABEL sixos (fallback to last successful boot)
      LINUX $(readlink -f $2/boot/kernel)
      INITRD $(readlink -f $2/boot/initrd)
      APPEND $(cat $2/boot/kernel-params)
    EOF
  '';
}
