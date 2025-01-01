{ lib
, six
, pkgs
, sockdir ? "/run/lpd/sockdir" # localhost lpr-to-lpd socket will be created here
, spooldir ? "/var/spool/lpd"  # print queue will be kept here
, lockdir ? "/run/lpd/lock"    # lpd lockfiles will be this string suffixed with "." and the port number
, user ? "_lprng"              # username under which lpd will run
, group ? "_lprng"             # groupid under which lpd will run
, printer ? {
  ip = throw "you must provide printer.ip";
  port = throw "you must provide printer.port";
}
, filter ? throw "you must provide a print filter (use pkgs.writeScript)"
, package ? pkgs.p.lprng
}:
let
  opts = [
    "-P" "${sockdir}/socket"
    "-F"                     # foreground
    "-p" "off"               # do not listen for TCP connections
  ];

  printcap = pkgs.writeText "printcap" ''
    lp|double-sided brother laser:\
        :lp=${toString printer.port}@${printer.ip}:\
        :if=${filter}:\
        :sd=${spooldir}/lp:\
        :pl#66:\
        :pw#80:\
        :pc#150:\
        :mx#0:\
        :sh:
  '';

  lpd_conf_options =
    { default_printer = "lp"

    ; default_tmp_dir = "/tmp"                # default temp directory for temp files
    ; server_tmp_dir = "/tmp"                 # server temporary file directory

    ; unix_socket_path = "${sockdir}/socket"  # path for UNIX socket for localhost connections

    ; lockfile = "${lockdir}/lockfile"        # lpd lock file

    ; sd = "${spooldir} /%P"                  # spool directory (only ONE printer per directory!)

    ; lpd_printcap_path = printcap            # lpd printcap path
    ; printcap_path = printcap                # /etc/printcap files

    ; lpd_listen_port = "off"                 # lpd server listen port, "off" does not open remote port, usual port is 515.

    ; sendmail = "${pkgs.busybox}/bin/false"  # sendmail program
    ; sendmail_to_user = false                # allow mail to user using the sendmail program

    # other possibly-interesting options
    #; "direct@"="on"                           # allow LPR to make direct socket connection to printer
    #; done_jobs= 1  (INTEGER)                # do not print zero length jobs
    #; done_jobs_max_age= 0  (INTEGER)        # keep done jobs for at most max age seconds
    #; exit_linger_timeout=600  (INTEGER)     # exit linger timeout to wait for socket to close
    #; force_localhost  (FLAG on)             # force clients to send all requests to localhost
    #; group=${group}  (STRING)               # group to run SUID ROOT programs
    #; half_close  (FLAG on)                  # do a 'half close' on socket when sending job to remote printer
    #; ipv6@ (FLAG off)                       # Running IPV6
    #; keepalive  (FLAG on)                   # TCP keepalive enabled
    #; lpd_path=  (EMPTY STRING)              # lpd pathname for server use
    #; lpd_port=5155                          # lpd port
    #; lpr=""                                 # Additional options for LPR
    #; lpr_send_try=3                         # numbers of times for lpr to try sending job - 0 is infinite
    #; network_connect_grace=0  (INTEGER)     # connection control for remote network printers
    #; originate_port=512 1023  (STRING)      # orginate connections from these ports
    #; require_configfiles  (FLAG on)         # client requires lpd.conf, printcap
    #; require_explicit_q@ (FLAG off)         # require default queue to be explicitly set
    #; retry_econnrefused  (FLAG on)          # retry on ECONNREFUSED error
    #; reuse_addr@ (FLAG off)                 # set SO_REUSEADDR on outgoing ports
    #; rg=  (EMPTY STRING)                    # restrict queue use to members of specified user groups
    #; send_try=3  (INTEGER)                  # numbers of times for server to try sending job - 0 is infinite
    #; sf  (FLAG on)                          # no form feed separator between job files
    #; sh@ (FLAG off)                         # suppress headers and/or banner page
    #; shell=/bin/sh  (STRING)                # SHELL enviornment variable value for filters
    #; socket_linger=10  (INTEGER)            # set the SO_LINGER socket option
    #; spool_dir_perms=000700  (INTEGER)      # spool directory permissions
    #; spool_file_perms=000600  (INTEGER)     # spool file permissions
    #; stalled_time=120  (INTEGER)            # stalled job timeout
    #; syslog_device=/dev/console  (STRING)   # name of syslog device
    #; user_printcap=.printcap  (STRING)      # allow users to use local ''${HOME}/.printcap
    ;};

  lpd_conf =
    pkgs.writeText "lpd.conf"
      (lib.concatStrings
        (lib.mapAttrsToList (k: v: "${k}=${toString v}\n")
          lpd_conf_options));

in
six.mkFunnel {
  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec 2>&1
    mkdir -p ${sockdir}
    chown -R ${user}:${group} ${sockdir}
    chmod g+w ${sockdir}

    mkdir -p ${spooldir}
    chown ${user}:${group} ${spooldir}

    mkdir -p ${lockdir}
    chown ${user}:${group} ${lockdir}

    mkdir -p /run/etc/
    ln -sfT ${lpd_conf} /run/etc/lpd.conf
    touch /run/etc/lpd.conf.local

    exec ${pkgs.runit}/bin/chpst \
      -u ${user}:${group} \
      -U ${user}:${group} \
      -- \
      ${package}/bin/lpd ${lib.concatStringsSep " " (map (o: "'${o}'") opts)}
  '';
}
