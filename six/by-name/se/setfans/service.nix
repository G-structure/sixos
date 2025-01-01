{ lib
, pkgs
, six
, targets
, speed ? 180   # a reasonable compromise
}:
six.mkOneshot {
  passthru.after = [ targets.global.coldplug ];
  up = pkgs.writeScript "up" (''
    #!${pkgs.runtimeShell}
    exec 2>&1
    ${pkgs.kmod}/bin/modprobe w83795
    BASE=/sys/devices/pci0000:00/0000:00:14.0/i2c*/*-002f
    for PWM in $BASE/pwm?; do echo -n '${toString speed}' > $PWM; done
  '');
}
