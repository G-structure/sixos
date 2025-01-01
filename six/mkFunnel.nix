{ lib
, pkgs
, six
, timeout-up   ? null # milliseconds
, timeout-down ? null # milliseconds

# you must set exactly one of the following three (run, argv, chpst)
, run   ? null # an executable (string or path)
, argv  ? null # a list-of-(string|path) to be execve()'d
, chpst ? null # an attrset to be passed to six.util.chpst

, finish ? null
, notification-fd ? null
, lock-fd ? null
, timeout-kill ? null
, timeout-finish ? null
, max-death-tally ? null
, down-signal ? null

# spawn supervised process in a new PID namespace
, flag-newpidns ? false

, up    ? null
# down is not allowed -- s6-rc creates its own ./down
, data  ? null # copied verbatim
, env   ? null # copied verbatim
, passthru ? {}
}@args:
assert up!=null   -> lib.isPath up || lib.isDerivation up;
assert data!=null -> lib.isPath data || lib.isDerivation data;
assert env!=null  -> lib.isPath env || lib.isDerivation env || lib.isAttrs env;

assert argv==null && run==null && chpst==null -> throw "you must set one of: run, argv, chpst";
assert argv!=null && run!=null -> throw "you cannot set both run and argv";
assert argv!=null && chpst!=null -> throw "you cannot set both chpst and argv";
assert run!=null && chpst!=null -> throw "you cannot set both chpst and run";

assert flag-newpidns ->
       pkgs.stdenv.hostPlatform.isLinux &&
       lib.versionAtLeast pkgs.s6.version "2.13.1.0";

let
  run' = run;
  argv' =
    if argv!=null
    then argv
    else six.util.chpst ({
      envdir = "./env";
      redirect-stderr-to-stdout = true;

      # TODO: consider these
      #dir ? null,
      #new-session ? false,
      #new-process-group ? new-session,
      #user ? null,
      #group ? null,
      #groups ? [],
      #env-clear ? false,
    } // chpst);
in

let

  run =
    if run'!=null
    then scriptify "run" run'
    else pkgs.writeScript "run" ''
      #!${pkgs.execline}/bin/execlineb
      ${lib.concatStringsSep " " argv'}
    '';

  scriptify = name: script:
    if lib.isList script
    then
      # As a convenience, you can pass an argv (list of strings) and mkFunnel
      # will call writeScript for you.  All elements of the list must be
      # strings, paths, numbers, or derivations.  As a further convenience,
      # `toString` will be applied to each element.
      let argv = map (e:
        if lib.isInt e || lib.isFloat e
        then toString e
        else assert !(lib.isString e || lib.isPath e || lib.isDerivation e)
          -> throw "the list passed as the script argument to mkFunnel must contain only numbers, strings, paths, and derivations";
          e) script;
      in pkgs.writeScript name ''
        #!${pkgs.runtimeShell}
        exec ${lib.escapeShellArgs argv}
      ''
    else
      assert (lib.isString script || lib.isDerivation script);
      script;

  env' =
    if env==null || lib.isPath env || lib.isDerivation env
    then env
    else if !(lib.isAttrs env)
    then throw "env must be null, a path, a derivation, or an attrset of strings"
    else lib.pipe env [
      (lib.mapAttrs
        (key: value:
          let val =
                if lib.isString value
                then value
                else if lib.isInt value
                then toString value
                else throw "when env is an attrset, its values must be strings or integers";
          in ''
            echo ${lib.escapeShellArg val} > $out/${lib.escapeShellArg key}
          ''))
      (lib.mapAttrsToList (_: v: v))
      (lines: pkgs.runCommand "six-env" {} (lib.concatStrings ([''
        mkdir $out
      ''] ++ lines)))
      (drv: drv.outPath)
    ];
in
(six.mkService {
  inherit timeout-up timeout-down up;
  down = null;
  passthru = (args.passthru or {}) // {
    inherit data env;
  };
  type = "longrun";
  extraCommands = "";
}).overrideAttrs(finalAttrs: previousAttrs: {
  buildCommand = (previousAttrs.buildCommand or "") + ''
  '' + lib.optionalString (timeout-kill != null) ''
    echo ${timeout-kill} > $out/timeout-kill
  '' + lib.optionalString (timeout-finish != null) ''
    echo ${timeout-finish} > $out/timeout-finish
  '' + ''
    ln -s ${run} $out/run
  '' + lib.optionalString (finish != null) ''
    ln -s ${scriptify "finish" finish} $out/finish
  '' + lib.optionalString (data != null) ''
    ln -s ${data} $out/data
  '' + lib.optionalString (env' != null) ''
    ln -s ${env'} $out/env
  '' + lib.optionalString (env' == null && chpst != null) ''
    mkdir $out/env
  '' + lib.optionalString flag-newpidns ''
    touch $out/flag-newpidns
  '' + lib.optionalString (notification-fd != null) ''
    echo '${toString notification-fd}' > $out/notification-fd
  '';
})
