{ lib
, pkgs
, six
, targets
, bwlimit-mbits-per-second ? null
, remove-source-files ? false
, from
, to
, rsync-args ? []
, ssh-args ? []
, passthru ? {}
}:

six.mkFunnel {
  chpst = {
    argv = [
      "${pkgs.s6-portable-utils}/bin/s6-sleep" "5"
      "${pkgs.rsync}/bin/rsync"
      "-zari"
      "-e" "\"${lib.concatStringsSep " " (["${pkgs.openssh}/bin/ssh"] ++ ssh-args)}\""
      "--progress"
      "--verbose"
      "--partial"
    ] ++ lib.optionals remove-source-files [
      "--remove-source-files"
    ] ++ lib.optionals (bwlimit-mbits-per-second != null) [
      "--bwlimit=${toString (builtins.floor ((bwlimit-mbits-per-second * 1000.0)/ 8.0))}"
    ]
    ++ rsync-args
    ++ lib.toList from
    ++ [
      to
    ];
  };
  inherit passthru;
}
