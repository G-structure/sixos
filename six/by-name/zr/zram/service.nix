{ lib
, six
, pkgs
, targets
, algorithm ? "zstd"
, size-percent ? 10
, device ? "/dev/zram0"
, modprobe-command ? "/run/current-system/boot/modprobe-wrapped"
}:

six.mkOneshot {

  # FIXME: use execlineb/list-of-strings
  up = pkgs.writeScript "zram-up.sh" (''
    #!${pkgs.runtimeShell} -e
    exec 2>&1
    ${modprobe-command} zram
    ${pkgs.util-linux}/bin/zramctl \
      ${device} \
      --algorithm ${algorithm} \
      --size "$(($(${pkgs.gnugrep}/bin/grep -Po 'MemTotal:\s*\K\d+' /proc/meminfo)*${toString size-percent}/100))KiB"
    ${pkgs.util-linux}/bin/mkswap ${device}
    ${pkgs.util-linux}/bin/swapon \
      --discard \
      --priority 100 \
      ${device}
  '');

  down = pkgs.writeScript "zram-down.sh" (''
    #!${pkgs.runtimeShell}
    exec 2>&1
    ${pkgs.util-linux}/bin/swapoff ${device}
    ${pkgs.util-linux}/bin/zramctl -r ${device}
    ${modprobe-command} -r zram
  '');

  passthru.after = [
    targets.mounts.proc
    targets.mounts.sys
  ];
}
