{ lib
, pkgs
, six
, targets
, package         ? pkgs.gpsd
, gpsd-socket     ? throw "missing argument: gpsd-socket"
, gps-device      ? throw "missing argument: gps-device"
, debug-level     ? 3
, daemon-port     ? 2947
}:

let
  options = [
    "-b"                        # bluetooth-safe: open data sources read-only
    "-n"                        # don't wait for client connects to poll GPS
    "-N"                        # don't go into background
    "-F" gpsd-socket            # specify control socket location
    "-G"                        # make gpsd listen on INADDR_ANY
    "-D" debug-level            # set debug level
    "-S" (toString daemon-port) # set port for daemon
    gps-device
  ];

  gpsd-user = package.passthru.gpsdUser;
  gpsd-group = package.passthru.gpsdGroup;

  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    ${pkgs.shadow}/bin/useradd \
      --system \
      --shell /run/current-system/sw/bin/nologin \
      --no-create-home \
      --force-badname \
      ${lib.escapeShellArg gpsd-user} \
      < /dev/null 2>/dev/null || true
    chown ${gpsd-user}:${gpsd-group} ${gps-device}
    #rm -rf /var/run/gpsd/
    mkdir -p /var/run/gpsd/
    mkdir -p /run/gpsd/
    chown ${gpsd-user}:${gpsd-group} /var/run/gpsd/
    chown ${gpsd-user}:${gpsd-group} /run/gpsd/
    exec ${package}/bin/gpsd ${lib.escapeShellArgs options}
  '';

in six.mkFunnel {
  passthru = {
    after = with targets; [ global.coldplug ];
    inherit gpsd-socket;
  };
  inherit run;
}
