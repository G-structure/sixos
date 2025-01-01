{ lib
, stdenv
, runtimeShell
, writeScript
, linkFarm

, pkgs
, cpio
, util-linux
, inetutils
, coreutils

, s6-rc
, s6-linux-init

# needed because s6-linux-init-maker expects to be able to create setgid
# directories, which the Nix sandbox forbids
, buildPackages #.fakeroot
, pkgsBuildHost

, default-timezone ? "PST8PDT,M3.2.0,M11.1.0"  # US Pacific Time, with daylight savings

# if non-null, this binary will be executed on the primary kernel console
, early-getty ? null

# initial value for the PATH environment variable in the early-getty process
#, early-getty-path ? initial-path

# log to the console (in addition to the catch-all logger)
, log-to-console ? true

# the value of the PATH environment variable in spawned processes
, initial-path ? ""

, dump-kernel-env-vars-here ? "/run/boot"

# FIXME: write these into basedir/env or pass as `-e` flags
, initial-env-vars ? {}

# amount of time between completion of shutdown and poweroff; null means use the
# s6-linux-init default, which is currently 3000ms.
, final-sleep-time-ms ? null

# if non-null, s6-linux-init will mount devtmpfs here
, devtmpfs-mountpoint ? "/dev"

# This directory must exist and contain the result of `s6-linux-init-maker`
# prior to `s6-linux-init` starting.  Usually this is in `/etc`, but we use
# `/run` instead and have the initramfs populate that directory using a CPIO
# archive.  This is mainly due to the fact that `/nix/store` cannot contain
# fifos.
, basedir ? "/run/init"
}:

let
  busybox = pkgs.pkgsStatic.busybox;

  skeldir = linkFarm "skeldir"
    (lib.mapAttrsToList
      (k: v: { name = k; path = v; }) {
    # Once `s6-svscan` is up and running with the bare minimum set of services
    # (runleveld, shutdownd, and the catch-all logger), a forked child of
    # s6-linux-init (which has by now been reparented to be a child of s6-svscan)
    # will exec() this script.  It can be used for one-time startup procedures
    # that must wait until after s6-svscan is ready to accept commands.
    #
    # FIXME: why doesn't dump-env-vars-here work via miniboot?
    #
    "rc.init" = writeScript "rc.init" (''
      #!${runtimeShell}
      if [ -e "${dump-kernel-env-vars-here}/init" ]; then
        exec $(${pkgs.busybox}/bin/dirname $(${pkgs.busybox}/bin/dirname $(${pkgs.busybox}/bin/cat ${dump-kernel-env-vars-here}/init)))/bin/activate
      fi
      if [ -e "${dump-kernel-env-vars-here}/configuration" ]; then
        ACTIVATE="$(${pkgs.busybox}/bin/cat ${dump-kernel-env-vars-here}/configuration; echo)/bin/activate"
        if [ -x "$ACTIVATE" ]; then
          exec "$ACTIVATE"
        fi
      fi
      echo
      echo 'rc.init: the configuration= environment variable was not set at boot time; dropping to a shell...'
      echo
      export PATH=${pkgs.busybox}/bin
      exec ${runtimeShell}
    '');
    # FIXME: the above should probably to keep retrying s6-rc on failure, or at
    # least log the failure
    # FIXME (from nixos)
    #
    #   mkdir -m 1777 /var/tmp
    #
    #   mkdir -p /var/empty
    #   ${pkgs.e2fsprogs}/bin/chattr -f -i /var/empty || true
    #   find /var/empty -mindepth 1 -delete
    #   chmod 0555 /var/empty
    #   chown root:root /var/empty
    #   ${pkgs.e2fsprogs}/bin/chattr -f +i /var/empty || true
    #
    #   mkdir -p /usr/bin
    #   chmod 0755 /usr/bin
    #   ln -sf ${config.environment.usrbinenv} /usr/bin/.env.tmp
    #   mv /usr/bin/.env.tmp /usr/bin/env # atomically replace /usr/bin/env

    # This is the `run` script for the `runleveld` service -- s6-linux-init
    # generates a `run` script which does a few process-state-setup chores and
    # then exec()s into this.
    runlevel = writeScript "runlevel" ''
      #!${runtimeShell} -e
      exec ${s6-rc}/bin/s6-rc -v2 -up change "$1"
    '';

    # This script is called in order to shut down the machine.
    # FIXME: call s6-linux-init-umountall here
    # FIXME: sigkill-all?
    "rc.shutdown" = writeScript "rc.shutdown" ''
      #!${runtimeShell}
      # Normally logs go to the catch-all logger instead of /dev/console.  Once
      # we've begun shutting down we need those logs on the console, since they won't be
      # caught anymore.
      exec >/dev/console 2>&1
      ${s6-rc}/bin/s6-rc -v2 -bDa change
      ${coreutils}/bin/sync
      ${pkgs.busybox}/bin/reboot -d 3 -f   # FIXME: distinguish between reboot and shutdown!
      sleep 10
      echo "something went wrong"
      '';

    # This script is called after `rc.shutdown` completes.  It isn't usually
    # necessary.  If you're using s6-linux-init in your initramfs, this is where
    # you pivot_root() to the next stage.
    "rc.shutdown.final" = writeScript "rc.shutdown.final" ''
      #!${runtimeShell} -e
      echo goodbye!
    '';
  });

  buildPhaseCommand =
    lib.concatStringsSep " " ([
      "${buildPackages.fakeroot}/bin/fakeroot" "-s" "fakeroot-save-file" "--"
      "${pkgsBuildHost.s6-linux-init}/bin/s6-linux-init-maker"
      "-c" "${basedir}"
    ] ++ lib.optionals (early-getty != null) [
      "-G" (lib.escapeShellArg early-getty)
    ] ++ lib.optionals log-to-console [
      "-1"
    ] ++ [
      "-p" "${initial-path}"
      "-s" dump-kernel-env-vars-here
    ] ++ lib.optionals (final-sleep-time-ms!=null) [
      "-q" final-sleep-time-ms
    ] ++ lib.optionals (devtmpfs-mountpoint!=null) [
      "-d" devtmpfs-mountpoint
    ] ++ [
      "-N"  # assume that a tmpfs is already present on /run
      "-f" skeldir
    ] ++ lib.optionals (default-timezone != null) [
      "-e" "TZ=${default-timezone}"
      #-e LOCALE_ARCHIVE=/usr/local/lib/locale/locale-archive
      #-e LANG=C.UTF-8
    ] ++ [
      "basedir"
    ]);
in
stdenv.mkDerivation {
  pname = "six-s6-linux-init";
  version = "unstable";

  dontUnpack = true;
  buildPhase = ''
    runHook preBuild
    echo ${buildPhaseCommand}
    ${buildPhaseCommand}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    pushd basedir
    find . | ${buildPackages.fakeroot}/bin/fakeroot -i $(pwd)/../fakeroot-save-file -- ${buildPackages.cpio}/bin/cpio -Hnewc --create > $out/s6-linux-init.cpio
    popd
  '' +
  # The first thing s6-linux-init does is to mount /run and recursively copy its
  # template into /run/s6-linux-init.  Unfortunately the "template" contains
  # setgid directories and named pipes, which means it can't be kept in the nix
  # store.  In order to put it there, we wrap it in a cpio archive;
  # unfortunately this means that we must run our own /run-mounting and
  # cpio-unpacking script ahead of s6-linux-init's `init`.  The mount options
  # for /run are the same as those found in s6-linux-init.c.  Statically-linked
  # busybox is used to minimize the size of the closure.
  #
  # six places `init` in $out/boot rather than $out/bin because there is no
  # scenario in which this script should ever be accessible via a user's $PATH.
  ''
    mkdir -p $out/boot
    cat > $out/boot/init <<EOF
    #!${busybox}/bin/sh
    PATH=${busybox}/bin/:\$PATH
    mkdir -m 0000 -p /run
    mount -t tmpfs -o nodev,nosuid,mode=0755 none /run
    mkdir -p ${basedir}
    cd ${basedir}/
    cpio --extract -d < $out/s6-linux-init.cpio
  '' + lib.optionalString (dump-kernel-env-vars-here != null) ''
    mkdir -p ${dump-kernel-env-vars-here}
  '' + ''
    exec ${basedir}/bin/init
    EOF
    chmod +x $out/boot/init

    runHook postInstall
  '';
}
