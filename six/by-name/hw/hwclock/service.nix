{ lib
, pkgs
, six
, targets
}@args:

six.mkOneshot {

  # ignore hwclock's exit code, since booting with the clock wrong is better
  # than refusing to boot.  --noadjfile prevents writing /etc/adjtime, which
  # won't work if the root filesystem is still readonly
  up = pkgs.writeScript "hwclock-hctosys" ''
    #!${pkgs.runtimeShell}
    ${pkgs.util-linux}/bin/hwclock --hctosys --noadjfile --utc || true
  '';

  # likewise for shutdown
  down = pkgs.writeScript "hwclock-systohc" ''
    #!${pkgs.runtimeShell}
    ${pkgs.util-linux}/bin/hwclock --systohc --noadjfile --utc || true
  '';

  passthru.after = [
    # we need /dev/rtc0 to exist
    targets.global.coldplug
  ];

  passthru.before = [
    targets.global.hwclock
  ];

}
