{ lib
, pkgs
, six
, targets

, where ?
  throw "missing where"

# default device for synthetic filesystem mounts, derived from LSB mountpoint
, what ? {
  "/dev/shm" = "shmfs";
}.${where} or
  (if lib.elem "remount" options
   then ""
   else "none")

# default filesystem types, derived from LSB mountpoint
, fstype ? {
  "/proc" = "proc";
  "/sys"  = "sysfs";
  "/dev/pts" = "devpts";
  "/dev/shm" = "tmpfs";
}.${where} or null

, create-mountpoint ? {
  "/sys" = true;
  "/proc" = true;
  "/tmp" = true;
  "/dev/pts" = true;
  "/dev/shm" = true;
  }.${where} or false

, fstab
  ? if lib.elem "remount" options
    then "/proc/mounts"   # in case /etc/fstab has an incorrect entry
    else null

# if true, mount this filesystem automatically when activating (or booting)
, auto
  ? true

, options ? []
, down ? null
, pre-up ? null
, post-up ? null
, bind ? null
, after ? []
}:

# FIXME: implement reload/restart using remount?
# FIXME: ignore-failure option?

let
  is-remount-rw =
    lib.elem "remount" options &&
    lib.elem "rw" options;
in
six.mkOneshot {
  up = pkgs.writeScript "up" (''
    #!${pkgs.runtimeShell} -e
  '' + lib.optionalString create-mountpoint ''
    ${lib.getBin pkgs.busybox}/bin/busybox mkdir -m 0000 -p ${where}
  '' + lib.optionalString (pre-up != null) ''
    ${pre-up}
  '' + ''
    ${lib.getBin pkgs.busybox}/bin/busybox mount ${
      lib.escapeShellArgs ([
      ] ++ lib.optionals (bind != null) [
        "--bind"
      ] ++ lib.optionals (fstab != null) [
        "-T" fstab
      ] ++ lib.optionals (options != []) [
        "-o" (lib.concatStringsSep "," options)
      ] ++ lib.optionals (fstype != null) [
        "-t" fstype
      ] ++ [
        (if bind==null then what else assert what=="none"; bind)
        where
      ])}
  '' +
  # The kernel needs to know the path to modprobe in order to load modules in
  # response to non-device-hotplug events (mainly: loading filesystems and
  # device-mapper/lvm features).  We ignore errors here in case the kernel
  # was built without CONFIG_MODPROBE_PATH.
  #
  # Putting this here is slightly kludgey.  We want to do this as early as
  # possible -- it needs to happen before any of the following:
  #
  # - attempting to start mdevd (or mdevd-coldplug)
  # - attempting to mount any filesystem other than procfs
  # - attempting to do anything with device-mapper, lvm, or cryptsetup
  #
  # Any of the above may potentially cause the kernel to desire that a module be
  # loaded, which will cause it to launch  /proc/sys/kernel/modprobe.
  #
  # We ignore errors here in case the kernel is built without
  # CONFIG_MODPROBE_PATH; if we stop here things are totally borked and much
  # harder to recover from via manual intervention.
  #
  lib.optionalString (fstype == "proc") ''
    echo -n /run/current-system/boot/modprobe-wrapped > /proc/sys/kernel/modprobe || true
  '' + lib.optionalString (post-up != null) ''
    ${post-up}
  '');

  down =
    if down==false then null
    else if down!=null then down
    else if is-remount-rw
    # FIXME: reconsider ignoring errors here...
    then pkgs.writeScript "down.sh" ''
      #!${pkgs.runtimeShell}
      ${lib.getBin pkgs.busybox}/bin/sync || true
      ${lib.getBin pkgs.busybox}/bin/mount -o remount,ro ${what} ${where} || true
    ''
    # FIXME: stop ignoring exit code here
    else pkgs.writeScript "down.sh" ''
      #!${pkgs.runtimeShell}
      ${lib.getBin pkgs.busybox}/bin/busybox umount ${lib.optionalString (fstab!=null) "-T ${fstab}"} ${where} || true
    '';

  passthru = {
    inherit what where fstype options;
    before = lib.optionals auto [ targets.global.mounts ];
    after = lib.optionals (fstype != "proc" && fstype != "sysfs" && (fstype != "tmpfs" || what == "shmfs")) [
      # Mounting almost any kind of non-synthetic filesystem will require that
      # /proc be mounted beforehand (see comment above regarding
      # /proc/sys/kernel/modprobe)
      targets.mounts.proc

    ] ++ lib.optionals (fstype != "proc" && fstype != "sysfs" && fstype != "tmpfs" && fstype != "devpts") [
      # do our best to set the clock before remounting read-write, in order
      # to avoid erroneous timestamps on files.
      targets.global.hwclock

      # FIXME: I forgot why this is needed...
      targets.mounts.sys

    ] ++ after;
  };
}
