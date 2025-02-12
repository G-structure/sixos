# from six
{ lib
, yants
, pkgs
, s6-linux-init
, services
, util
}:

# local args
{ overlays
, s6-fdholder-daemon-username ? null   # -h
, verbosity                   ? null   # -v
, default-runlevel            ? "default"

# This directory can only be changed by doing a reboot or pivot_root(), since it
# is passed to s6-supervise (which is forked only at boot or pivot_root() time).
# Any references to it should be via `/run/booted-system/six/scandir`, and never
# via `/run/current-system`. (why?  I can't remember...)
, scandir                     ? "/run/service"

# This mainly protects against recursive invocations of s6-rc tools.  Recursive
# invocations are a bug, which should fail rather than deadlock.
, fail-on-lock-contention     ? true   # -b

, console ? throw "the console argument is required"
, early-getty ? "${pkgs.busybox}/bin/getty -nl ${pkgs.busybox}/bin/sh ${toString console.baud} ${console.device}"

, hostname
, nixpkgs-version ? "unknown-nixpkgs-version"
, boot  ? {}
, sw    ? null
, delete-generations
}:

let

  add-spath =
    spath: v:
    v.overrideAttrs (previousAttrs: {
      passthru = previousAttrs.passthru // {
        inherit spath;
      }; });

  mapDerivations' =
    path: f: val:
    if path == [ "pkgs" ] then val else  # FIXME HACK
    if path == [ "lib" ] then val else  # FIXME HACK
    if lib.isDerivation val
    then f path val
    else if !(lib.isAttrs val)
    then val
    else lib.mapAttrs
      (k: v: mapDerivations' (path ++ [k]) f v)
      val;

  mapDerivations = mapDerivations' [];

  flatten' =
    path: val:
    if path == [ "pkgs" ] then [] else  # FIXME HACK
    if path == [ "lib" ] then [] else  # FIXME HACK
    if path == [ "yants" ] then [] else  # FIXME HACK
    if path == [ "services" ] then [] else  # FIXME HACK
  if !(lib.isAttrs val) || lib.isDerivation val
    then [(lib.nameValuePair (lib.concatStringsSep "." path) val)]
    else lib.concatLists
      (lib.mapAttrsToList
        (k: v: flatten' (path ++ [k]) v)
        val);

  flatten = attrs:
    lib.pipe attrs [
      (lib.mapAttrsToList (k: v: flatten' [k] v))
      lib.concatLists
      lib.listToAttrs
    ];

  init = final: prev: {

    inherit lib yants pkgs;

    # consider automatically allowing arguments `before` and `after` which, if
    # present, become `overrideAttrs` applied to `passthru`
    callService = path: final.callPackage path;

    six = {
      mkService       = final.callPackage ./mkService.nix;
      mkBundle        = final.callPackage ./mkBundle.nix;
      mkOneshot       = final.callPackage ./mkOneshot.nix;
      mkFunnel        = final.callPackage ./mkFunnel.nix;
      mkLogger        = final.callPackage ./mkLogger.nix;
      inherit util;
    };

    # A service is a Nix function which can be applied to various arguments,
    # like a callPackage in nixpkgs.  Each `src/by-name/??/${name}/service.nix`
    # defines one service.  See also `targets` below, which include service
    # *derivations*.
    services =
      (lib.flip builtins.mapAttrs services
        (name: service:
          final.callService service))
      // {

        # A logger which simply uses `cat` to send its stdin to the supervisor's
        # stdout, which is the same as the scanner's stdout.
        #
        # Unfortunately we need to create one of these (i.e. a separate s6-cat
        # process, plus a s6-supervise process for it) due to s6 restrictions:
        # every longrun either sends its stdout to some other longrun, or else
        # sends it to the catch-all logger (i.e. the console) -- and you cannot
        # change one type to the other without restarting the service.  In the
        # case of mdevd this is catastrophic: restarting mdevd will freqently
        # nuke the entire wayland/gui/x11 session.
        uncaughtLogs =
          spath: service:
          final.six.mkLogger {
            run = "${pkgs.s6-portable-utils}/bin/s6-cat";
          };

        defaultLogger = final.uncaughtLogs;
      };

    # A target is something that can be depended upon, started, or stopped.
    # Targets include:
    #
    # - Bundles (possibly empty) of other targets.
    # - Service derivations, which are specific instantiations of services.
    #   Each service expression, applied to a complete set of arguments, yields
    #   a service derivation.
    #
    # Each target has a `tname` which is the unique attrpath below `targets`
    # through which it is reachable.  The `tname` is used to identify the target
    # when issuing commands like `six start` and `six stop`.
    #
    targets = {
    };
  };

  # After and before references must always be made via `final.${spath}`
  # references to services which are part of the top-level service set.  Because
  # there can be cyclic references (a.after = b, b.before = a) we can't test
  # them for equality.  Therefore, we identify each service by its attrname in
  # the top-level service set.  This is fundamentally what makes it possible for
  # six to (unlike NixOS) have multiple copies of the ssh daemon running, and to
  # reference that daemon without getting confused about which "sshd" the user
  # means.
  add-spaths =
    final: prev: prev // {
      targets = mapDerivations (path: v:
        if !(lib.isDerivation v)
        then v
        else if v?overrideAttrs
        then add-spath path v
        else throw "derivation does not have an .override method: ${lib.concatStringsSep "." path}")
        (prev.targets or {});
    };

  # This needs to be nearly-the-last overlay: any overlays after it must not add
  # additional services to the top-level service set.  We deliberately use
  # `final` instead of `prev` to cause an infinite recursion if any attrsets
  # after this one add new services.
  convert-before-to-after = final: prev:
    let
      flattened = lib.filter (x: x!=null) (builtins.attrValues (flatten prev.targets));
      beforeFunc =
        after-spath:
        lib.pipe flattened [
          (lib.filter
            (target:
              let target-before-spaths = map (x: x.passthru.spath) target.passthru.before;
              in lib.elem after-spath target-before-spaths))
          (map
            (target: (lib.attrByPath target.passthru.spath (throw "missing") final.targets)))
        ];
    in {
      targets = lib.flip mapDerivations prev.targets
        (_: target:
          target.overrideAttrs
            (previousAttrs: {
              passthru = previousAttrs.passthru or {} // {
                after = previousAttrs.passthru.after or [] ++
                        beforeFunc target.passthru.spath;
              };
            })
        );
    };

  add-loggers =
    let make-logger-spath = path:
          (lib.take ((lib.length path) - 1) path) ++ [ "${lib.last path}-log" ];
    in final: prev: {
      targets =
        lib.flip mapDerivations prev.targets
          (path: v:
            if false
               || v.passthru.stype or null != "longrun"
               || (v.passthru.logger or null) == false
            then v
            else let
              logger-spath = make-logger-spath path;
              logger-sname = lib.concatStringsSep "." logger-spath;
              #logger-sname = "${lib.concatStringsSep "." path}-log";
            in v.overrideAttrs (finalAttrs: previousAttrs: {
                 buildCommand = (previousAttrs.buildCommand or "") + ''
                   echo '${logger-sname}' > $out/producer-for
                 '';
                 passthru = (previousAttrs.passthru or {}) // {
                   logger = lib.getAttrByPath path (throw "missing ${lib.concatStringsSep "." path}") final.targets.loggers;
                 };
               })
          ) // {
      loggers =
        lib.flip mapDerivations prev.targets
          (path: v:
            if false
               || v.passthru.stype or null != "longrun"
               || (v.passthru.logger or null) == false
            then null
            else let
              logger-spath = make-logger-spath path;
              loggerfunc = if v.passthru.logger or null == null
                           then prev.defaultLogger
                           else v.passthru.logger;
              logger = add-spath logger-spath (loggerfunc path v);
            in logger
          );
          };
    };

  sorted-collected-services = lib.pipe
    # note: add-spaths must be the last extension before
    # "convert-before-to-after", to be sure that it is able to "see" any
    # additional services added by earlier overlays
    (lib.composeManyExtensions ([
      init
    ] ++ overlays ++ [
      add-spaths
      add-loggers
      convert-before-to-after
    ]))
    [
      (lib.makeScope lib.callPackageWith (self: { })).overrideScope
      flatten
      (lib.filterAttrs (k: v: k!="spath" && v?passthru.spath))
      (lib.mapAttrsToList (_: v: v))
      (map (s: lib.nameValuePair (lib.concatStringsSep "." s.spath) s))
      lib.listToAttrs
      lib.attrValues
      (lib.sort (a: b: (lib.concatStringsSep "." a.passthru.spath) < (lib.concatStringsSep "." b.passthru.spath)))
    ];

  source = pkgs.runCommand "s6-rc-source" { preferLocalBuild = true; } (''
    mkdir -p $out
    ${lib.concatMapStrings (target: ''
      mkdir -p                  $out/${lib.concatStringsSep "." target.passthru.spath}
      ln -s ${target.outPath}/* -t $out/${lib.concatStringsSep "." target.passthru.spath}/
      '')
      sorted-collected-services}
    ${lib.concatMapStrings (target:
      # s6-rc requires that consumers reference their producers and vice-versa;
      # when mapping services to derivations this would create cyclic
      # derivations, which are disallowed.  Therefore, the per-service
      # derivations include only the `producer-for` entry.  Links in the reverse
      # direction (i.e. `consumer-for`) are created just before invoking
      # s6-rc-compile.
      ''
      if [ -e "${target.outPath}/producer-for" ]; then
        echo ${lib.concatStringsSep "." target.passthru.spath} >> $out/$(cat ${target.outPath}/producer-for)/consumer-for
      fi
      '')
      sorted-collected-services}
  '');

  compiled = pkgs.runCommand "s6-rc-compiled" { preferLocalBuild = true; } (''
    mkdir -p $out/six/s6-rc
    ln -s ${source} $out/six/s6-rc/source
    ${pkgs.pkgsBuildTarget.s6-rc}/bin/s6-rc-compile ${lib.escapeShellArgs
      (lib.optionals (verbosity!=null) [
        "-v" (toString verbosity)
      ] ++ lib.optionals (s6-fdholder-daemon-username != null) [
        "-h" s6-fdholder-daemon-username
      ])} $out/six/s6-rc/db ${source}
  '');

  s6-linux-init-cpio = s6-linux-init.override {
    inherit early-getty;
    initial-path = "/run/current-system/sw/bin";
  };

  # We need to provide the kernel (via /proc/sys/kernel/modprobe) the path to a
  # single executable that it can spawn, *without additional arguments* in
  # order to load modules.  Since we (a) want to respect the user's blacklists
  # and (b) keep modules in a non-FHS location we need to pass a flag to
  # modprobe to tell it where the modules are.  We don't want the wrapped
  # version of modprobe to "occlude" the ordinary one in the user's $PATH, so
  # we put it in /boot and give it a different name (the user can link it into
  # their $PATH with the name modprobe if desired).
  #
  # Note that this command is invoked via the /run/current-system link, but
  # searches for modules in /run/booted-system.  Activating a new configuration
  # will use the new configuration's modprobe binary, but it will still take
  # kernel modules from whatever configuration was booted.
  #
  # Busybox is used here because kmod randomly decides to ignore module
  # blacklisting, and I'm sick of debugging it.  Busybox modprobe just works
  # properly the first time.
  #
  modprobe-wrapped = pkgs.writeScriptBin "modprobe-wrapped" ''
    #!${pkgs.busybox}/bin/sh
    ${pkgs.busybox}/bin/modprobe -b -d /run/booted-system/kernel-modules "$@"
  '';

  mkBootDir =
    # systems these days need so much firmware that most machines are likely to
    # fail to boot if the firmware directory is missing.  if you really really
    # want a no-firmware boot, pass the empty directory.
    let
      firmware =
        if lib.isList boot.kernel.firmware
        then pkgs.buildEnv {
          name = "firmware";
          paths = boot.kernel.firmware;
        }
        else boot.kernel.firmware;
    in
   ''
     mkdir $out/boot
     ln -sT ${boot.kernel.payload} $out/boot/kernel
   '' + lib.optionalString (boot.kernel.modules != null) ''
     ln -sT ${boot.kernel.modules} $out/boot/kernel-modules
     # path has to match NixOS in order to use the nixpkgs depmod/insmod/modprobe tools :(
     ln -sT boot/kernel-modules $out/kernel-modules
   '' + lib.optionalString (boot?initrd.image) ''
     ln -sT ${boot.initrd.image} $out/boot/initrd
   '' + lib.optionalString (boot?spec) ''
     ln -sT ${boot.spec} $out/boot/boot.json
   '' +
   # six places `init` in $out/boot rather than $out/bin because there is no
   # scenario in which this script should ever be accessible via a user's $PATH.
   ''
     ln -sT ${s6-linux-init-cpio}/boot/init $out/boot/init
     echo ${lib.concatStringsSep " "
       (map lib.escapeShellArg boot.kernel.params ++ [
         "init=$out/boot/init"
         "configuration=$out"
       ])} > $out/boot/kernel-params
   '' +
   # somewhat-similarly for modprobe-wrapped; we need to be able to reference
   # it, and so does the kernel, but the user might not want this in their $PATH
   ''
     cp -a ${modprobe-wrapped}/bin/modprobe-wrapped $out/boot/modprobe-wrapped
   '' + lib.optionalString (firmware == null) ''
     mkdir $out/boot/firmware
   '' + lib.optionalString (firmware != null) ''
     ln -sT ${firmware} $out/boot/firmware
   '' + ''
     ln -sT boot/firmware $out/firmware    # to match NixOS path burned-in to nixpkgs
   '';

  configuration = (pkgs.runCommand "six-system-${hostname}-${nixpkgs-version}" { preferLocalBuild = true; } (''
    mkdir -p $out
    ${pkgs.gnu-config}/config.sub "${pkgs.hostPlatform.config}" > $out/system-canonical-gnu-triple
    mkdir -p $out/six/s6-rc
    ln -s ${source}                $out/six/s6-rc/source
    ln -s ${compiled}/six/s6-rc/db $out/six/s6-rc/db
    ln -s ${scandir}               $out/six/scandir

    mkdir -p $out/bin

    cat > $out/bin/activate<<\EOF
    #!${pkgs.runtimeShell} -e
    if [[ -d /run/s6-rc ]]; then
      # s6-svscan is already up and running; switch to the new configuration
      ${pkgs.s6-rc}/bin/s6-rc-update -v 8 $@ ${compiled}/six/s6-rc/db

      # s6-ln is used because POSIX ln is defined such that it cannot be atomic.
      ${pkgs.s6-portable-utils}/bin/s6-ln -sfn ${builtins.placeholder "out"} /run/current-system
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/activated --set ${builtins.placeholder "out"}
    else
      # first activation after a new bootup
      ${pkgs.busybox}/bin/ln -sfn ${builtins.placeholder "out"} /run/booted-system
      ${pkgs.busybox}/bin/ln -sfn ${builtins.placeholder "out"} /run/current-system

      # ectool (and other things) expect /run/lock (formerly /var/lock) to exist
      ${pkgs.busybox}/bin/mkdir /run/lock
      # FIXME: root filesystem is still read-only at this point
      #${pkgs.busybox}/bin/mkdir -m 0555 -p /bin
      #${pkgs.busybox}/bin/ln -sfT /run/current-system/sw/bin/sh /bin/sh
      #${pkgs.busybox}/bin/mkdir -m 0555 -p /usr/bin
      #${pkgs.busybox}/bin/ln -sfT /run/current-system/sw/bin/env /usr/bin/env
      ${pkgs.busybox}/bin/mkdir -p ${scandir}
      ${pkgs.s6-rc}/bin/s6-rc-init -d -c /run/current-system/six/s6-rc/db $@ ${scandir}
      # Presumably / is still read-only at this point, so we don't try to
      # `nix-env --set` the `activated` profile.  The `nextboot` profile was
      # updated prior to reboot, so you can reconstruct the full activation
      # history by interleaving it with `activated`.
      exec ${pkgs.s6-rc}/bin/s6-rc -v2 -up change ${default-runlevel}
    fi
    EOF

    cat > $out/bin/dry-activate<<\EOF
    #!${pkgs.runtimeShell} -ex
    exec ${pkgs.s6-rc}/bin/s6-rc-update -n $@ -v 8 ${builtins.placeholder "out"}/six/s6-rc/db
    EOF

    cat > $out/bin/kexec <<\EOF
    #!${pkgs.runtimeShell} -ex
    mkdir -p /run/kexec
    chmod 0700 /run/kexec
    ${pkgs.busybox}/bin/zcat ${boot.initrd.image} > /run/kexec/initrd

    ${pkgs.busybox}/bin/gzip /run/kexec/initrd
    ${pkgs.kexec-tools}/bin/kexec ${lib.escapeShellArgs ([
      "--load"
    ] ++ lib.optionals (boot?initrd.image) [
      "--initrd=/run/kexec/initrd.gz"
    ] ++ lib.optionals (boot?kernel.dtb) [
      "--dtb=${boot.kernel.dtb}"
    ])} --command-line=${
      lib.pipe (
        boot.kernel.params ++ [
          "configuration=${builtins.placeholder "out"}"
        ]) [
          (lib.concatStringsSep " ")
          lib.escapeShellArg
        ]
    } ${boot.kernel.payload}
    rm -f /run/kexec/initrd

    ${pkgs.busybox}/bin/sync
    ${pkgs.busybox}/bin/sleep 1
    ${pkgs.kexec-tools}/bin/kexec -e
    EOF

  ''
    # need WAY more sanity checks at the time nextboot is executed, especially
    # when installing for the first time using a chroot:
    # - mkdir -m 0000 -p /mnt/tmp/{run,dev,proc,sys}
    # - all mountpoints must exist, since root is read-only initially
    # might be worth checking for this stuff at kexec-time
  + ''
    cat > $out/bin/nextboot <<\EOF
    #!${pkgs.runtimeShell} -ex
    # This ensures that these links always exist, particularly at boot time when
    # /nix might not yet be read-write.  s6-ln is used because POSIX ln is
    # defined such that it cannot be atomic.
    ${pkgs.s6-portable-utils}/bin/s6-ln -sfn /run/current-system /nix/var/nix/gcroots/current-system
    ${pkgs.s6-portable-utils}/bin/s6-ln -sfn /run/booted-system  /nix/var/nix/gcroots/booted-system
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/nextboot --set ${builtins.placeholder "out"}
  '' + lib.optionalString (delete-generations != null) ''
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/nextboot --delete-generations ${lib.escapeShellArg delete-generations} || true
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/activated --delete-generations ${lib.escapeShellArg delete-generations} || true
  '' +
  # The fallbackboot profile is a "safe fallback" boot option.
  #
  # The fallbackboot profile provides the following guarantee: if fallbackboot exists,
  # it points to a profile that (a) booted and (b) worked well enough to
  # successfully run the bin/nextboot of some (possibly other) profile.
  #
  # After updating the nextboot profile, we set the fallbackboot profile to
  # /run/booted-system.  Note that we don't use /run/current-system here,
  # because the only thing we know /run/current-system is that it *activated*
  # successfully -- but its kernel or initrd might have fatal flaws.  This
  # means that in order to fully garbage collect the profile that booted your
  # system, you must run bin/nextboot on some other profile, reboot to that
  # profile (which updates the /run/booted-system gcroot), run bin/nextboot a
  # second time, and then `nix profile wipe-history` both nextboot and
  # fallbackboot.
  ''
    if [ -e $(${pkgs.busybox}/bin/realpath /run/booted-system) ]; then
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/fallbackboot --set /run/booted-system
  '' + lib.optionalString (delete-generations != null) ''
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/fallbackboot --delete-generations ${lib.escapeShellArg delete-generations}
  '' + ''
    fi
  '' + lib.optionalString (boot?loader.update) ''
    if [ -e /nix/var/nix/profiles/fallbackboot ]; then
      ${boot.loader.update} /nix/var/nix/profiles/nextboot /nix/var/nix/profiles/fallbackboot
    else
      ${boot.loader.update} /nix/var/nix/profiles/nextboot /nix/var/nix/profiles/nextboot
    fi
  '' + lib.optionalString (delete-generations != null) ''
      echo
      ${pkgs.nix}/bin/nix-store --gc
  '' + ''
      echo
      ${pkgs.nix}/bin/nix-store --gc --print-roots | ${pkgs.busybox}/bin/grep -v ^/proc
      echo
  ''
  # busybox df does not search for the enclosing mountpoint, so we use coreutils
  + ''
      ${pkgs.coreutils}/bin/df -h /nix/store
      echo
    EOF

    chmod +x $out/bin/*

    ${mkBootDir}
   '' + lib.optionalString (sw != null) ''
     ln -s ${sw} $out/sw
   '' + lib.optionalString (sw == null) ''
     mkdir -p $out/sw
     ln -s ${pkgs.busybox}/bin $out/sw/bin
   '' +
   # sanity-check that bin/{sh,env} exist: without them things will fail quite badly.
   ''
     test -e $out/sw/bin/sh || (echo profiles must have a sw/bin/sh; exit -1)
     test -e $out/sw/bin/env || (echo profiles must have a sw/bin/env; exit -1)
   ''
  )).overrideAttrs (previousAttrs: {
      meta = (previousAttrs.meta or {}) // { mainProgram = "activate"; };
      passthru = (previousAttrs.passthru or {}) // {
        inherit source boot;
        vm = lib.makeOverridable
          ({ storeDir
           , memSize-mbytes
           }:
             let
               args = [
                 "-m" (toString memSize-mbytes)
                 "-nographic"
                 "-no-reboot" # shutdown means exit
                 "-virtfs" "local,path=${storeDir},security_model=none,readonly=on,mount_tag=nixstore,id=nixstore_dev"
                 "-device" "virtio-9p-pci,fsdev=nixstore_dev,mount_tag=nixstore"
                 "-net" "none"
                 "-vga" "none"
                 "-kernel" (toString configuration.boot.kernel.payload)
                 "-initrd" (toString configuration.boot.initrd.image)
               ];
             in pkgs.writeShellScriptBin "vm-${configuration.name}.sh" ''
               exec ${pkgs.vmTools.qemu-common.qemuBinary pkgs.qemu} \
                 ${lib.escapeShellArgs args} \
                 -append "$(cat ${configuration}/boot/kernel-params)"
             '')
        { storeDir = builtins.storeDir;
          memSize-mbytes  = 512; };
      };
    });
in
  configuration
