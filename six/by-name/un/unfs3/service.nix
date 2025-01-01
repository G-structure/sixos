{ lib
, pkgs
, six
, targets
, nfsd-port         ? 2049  # set to null to use an arbitrary port
, mountd-port       ? nfsd-port
, use-portmapper    ? true
, tcp-only          ? false
, write-cache       ? true
, cluster-extension ? false
, cluster-paths     ? null
, single-user       ? false
, bind-interfaces   ? null   # all if omitted; otherwise specify IP address
, brute-force       ? false  # warning: major performance impact
, debug             ? false
}:

six.mkFunnel {
  passthru.after = with targets; [ global.coldplug ];
  run =
    [ "${pkgs.unfs3}/bin/unfsd" ] ++
    [ "-u" ] ++                        # do not insist on using port 2049
    [ "-n" (toString nfsd-port)   ] ++ # run on specified port
    [ "-m" (toString mountd-port) ] ++ # run on specified port
    (lib.optional  tcp-only "-t") ++
    (lib.optional  (!use-portmapper) "-p") ++
    (lib.optional  (!write-cache) "-w") ++
    (lib.optional  cluster-extension "-c") ++
    (lib.optional  single-user "-s") ++
    (lib.optionals (bind-interfaces != null) [ "-l" "${bind-interfaces}" ]) ++
    (lib.optionals (cluster-paths != null) ([ "-C" ] ++ cluster-paths)) ++
    (lib.optional  debug "-d") ++
    (lib.optional  brute-force "-b");
}
