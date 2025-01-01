{ lib
, pkgs
, six
, targets
, package         ? pkgs.chrony
, chrony-username ? "_chrony"

, conf-file       ? null

# the following options cannot be used with conf-file
, conf-text       ? null
, gpsd-socket     ? null
, log-dir         ? null
, logging         ? []
}:

assert !(conf-file != null -> conf-text == null)
  -> throw "you cannot specify both conf-file and conf-text";

assert !((gpsd-socket!=null) -> (conf-file==null))
  -> throw "the gpsd-socket paramter is not available when the conf-file parameter is used";
assert !((log-dir!=null) -> (conf-file==null))
  -> throw "the log-dir paramter is not available when the conf-file parameter is used";
assert !((logging!=[]) -> (conf-file==null))
  -> throw "the logging paramter is not available when the conf-file parameter is used";

let
  conf =
    if conf-file != null
    then conf-file
    else builtins.toFile "chrony.conf" (''
      logdir ${log-dir}
    '' + lib.optionalString (logging != []) ''
      log ${lib.concatStringsSep " " logging}
    '' + lib.optionalString (gpsd-socket!=null) ''
      refclock SOCK ${gpsd-socket}
    ''
    + lib.optionalString (conf-text!=null) conf-text)
  ;
  options = [
    "-4"                 # Use IPv4 addresses only
    "-n"                 # Don't run as daemon
    "-d"                 # Don't run as daemon and log to stderr
    #"-6"                # Use IPv6 addresses only
    "-f" conf            # Specify configuration file (/etc/chrony.conf)
    "-u" chrony-username # Specify user (root)
  /*
  "-l" FILE            # Log to file
  "-L" LEVEL           # Set logging threshold (0)
  "-p"                 # Print configuration and exit
  "-q"                 # Set clock and exit
  "-Q"                 # Log offset and exit
  "-r"                 # Reload dump files
  "-R"                 # Adapt configuration for restart
  "-s"                 # Set clock from RTC
  "-t" SECONDS         # Exit after elapsed time
  "-U"                 # Don't check for root
  "-F" LEVEL           # Set system call filter level (0)
  "-P" PRIORITY        # Set process priority (0)
  "-m"                 # Lock memory
  "-x"                 # Don't control clock
  */
  ];

  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    # FIXME: ugly
    ${pkgs.shadow}/bin/useradd \
      --system \
      --shell /run/current-system/sw/bin/nologin \
      --no-create-home \
      --force-badname \
      ${lib.escapeShellArg chrony-username} \
      < /dev/null 2>/dev/null || true
    #mkdir -p /var/run/gpsd/
    #mkdir -p /var/log/chrony/
    #chown ${chrony-username} /var/log/chrony
    #touch /var/log/chrony/tracking.log
    #chown ${chrony-username} /var/log/chrony/tracking.log
    exec ${package}/bin/chronyd ${lib.escapeShellArgs options}
  '';

in six.mkFunnel {
  passthru.after = with targets; [ global.coldplug ];
  inherit run;
}
