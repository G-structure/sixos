# TODO: send SIGHUP when activating a configuration which changes only the
# configFile and nothing else.

{ lib
, pkgs
, six
, services
, targets

, conf ? throw "you must pass conf with your mdev.conf file"
, firmwarePath ? "/run/current-system/boot/firmware/lib/firmware"
, performColdplug ? false
, kernelBufferSize ?
  500 * 1024  # mdevd-coldplug page says this is the default
  * 10        # use ten times that amount (hit "unable to receive netlink message: no buffer space available")

, sys-mount-target      ? targets.mounts.sys or (throw "missing: target which mounts `-t sysfs`")
, dev-pts-mount-target  ? targets.mounts.dev.pts or (throw "missing: target which mounts `-t devpts` and ensures /dev is mounted")
, devMountPoint         ? "/dev"
, sysMountPoint         ? sys-mount-target.passthru.where

# In order for libudev-zero to react to hotplug events, mdevd must "rebroadcast
# kernel uevents to the 0x4 netlink group of NETLINK_KOBJECT_UEVENT ... because
# libudev-zero can't simply listen to kernel uevents due to potential race
# conditions".  mdevd supports this if you pass `-O 4`.
, rebroadcastEvents ? 4

, verbosity ? 3

}:

assert performColdplug && rebroadcastEvents -> throw
  ''Combining performColdplug (`-C`) and rebroadcastEvents (`-O4`) leaves you
    with no way to change the mdevd configuration (`mdevd.conf`) without
    re-sending all plug events, which will cause services like `seatd` to kill
    the display server.  Please use `services/mdevd-coldplug.nix` instead.'';

let
  notification-fd = 3;

  # mdevd will refuse to start if the `-f` argument is not an *absolute* path
  # FIXME this should come from the `six` argument, not be hardwired
  scandir = "/run/booted-system/six/scandir";  # which is a symlink to /run/service
in

(six.mkFunnel {
  inherit notification-fd;

  data = pkgs.runCommand "mdevd-service-data" {} ''
    mkdir $out
    ln -s ${conf} $out/mdev.conf
  '';
  passthru = {
    inherit kernelBufferSize performColdplug conf devMountPoint rebroadcastEvents verbosity sysMountPoint;
    essential = true;
    after = [ sys-mount-target dev-pts-mount-target ];
    # skarnet recommends that mdevd *not* have a logger, since it needs to
    # start before filesystems are mounted read-write.
    logger = services.uncaughtLogs;
  };
  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1

# to force explicit $PATH, since mdevd is painful to debug
export PATH=

exec \
  ${lib.getBin pkgs.mdevd}/bin/mdevd \
  -f ${scandir}/$1/data/mdev.conf \
  -F ${firmwarePath} \
  -D ${toString notification-fd} \
  -v ${toString verbosity} \
  -b ${toString kernelBufferSize} \
  -s ${sysMountPoint} \
  -d ${devMountPoint} \
  ${lib.optionalString performColdplug " -C "} \
  ${lib.optionalString (rebroadcastEvents!=null) " -O ${toString rebroadcastEvents} "}
'';
})
