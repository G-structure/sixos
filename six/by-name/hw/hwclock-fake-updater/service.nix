{ lib
, pkgs
, six
, targets
, services

# default is five minutes; this is a compromise between backward clock jump on
# power-loss reboot vs. wearing out cheap eMMC devices.  TODO(amjoseph): store
# this in /dev/mtd0 if available, which has much higher durability.
, interval-seconds ? 3 * 60

}@args:

assert
  !(targets?hwclock-fake) ->
   throw "the hwclock-fake and hwclock-fake-updater services must both be used together (you cannot use one without the other)";

let
  inherit (targets.hwclock-fake.passthru)
    hwclock-fake-file;

  execline-update-hwclock-fake = ''
    ${pkgs.execline}/bin/if
      { ${pkgs.execline}/bin/redirfd -w 1 ${hwclock-fake-file}- ${pkgs.busybox}/bin/busybox date -u +%s }
      ${pkgs.busybox}/bin/busybox mv ${hwclock-fake-file}- ${hwclock-fake-file}
  '';

in six.mkFunnel {

  # continuously copy from the system clock to the hwclock-fake file
  run = pkgs.writeScript "run" ''
    #!${pkgs.execline}/bin/execlineb -P
    ${pkgs.execline}/bin/loopwhilex
      ${pkgs.execline}/bin/if
        { ${execline-update-hwclock-fake} }
        sleep ${toString interval-seconds}
  '';

  # at shutdown, update the hwclock-fake file one last time, but don't obstruct
  # the shutdown process if we're unable to update it.
  finish = pkgs.writeScript "finish" ''
    #!${pkgs.execline}/bin/execlineb -P
    ${pkgs.execline}/bin/foreground
      { ${execline-update-hwclock-fake} }
      ${pkgs.execline}/bin/exit 0
  '';


  passthru.after = [
    # Don't start this until hwclock-fake has copied from the disk to the system
    # clock -- or at least attempted to do so.
    targets.global.hwclock

    # must have root filesystem mounted read-write
    targets.mounts.""
  ];

}
