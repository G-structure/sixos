{ lib
, pkgs
, six
, targets
, services
, hwclock-fake-file ? "/etc/hwclock-fake"
}@args:

assert
  !(targets?hwclock-fake-updater) ->
   throw "the hwclock-fake and hwclock-fake-updater services must both be used together (you cannot use one without the other)";

six.mkOneshot {

  # Set the system clock from the hwclock-fake-file, if present
  up = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    if [[ -e ${hwclock-fake-file} ]]; then
      ${pkgs.busybox}/bin/busybox date -u -s "@$(cat ${hwclock-fake-file})" > /dev/null
    fi
  '';

  # since remounting the root filesystem read-write depends on this service,
  # during shutdown we will already have switched it back to readonly, so it's
  # too late to update the `hwclock-fake-file`

  passthru = {
    inherit hwclock-fake-file;
    before = [
      targets.global.hwclock
    ];
    # cannot log from anything that mount-root-readwrite depends on
    logger = services.uncaughtLogs;
  };

}
