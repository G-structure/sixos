{ lib
, pkgs
, six
}:
six.mkFunnel {
  run = pkgs.writeScript "run"
# TO DO: drop privs with `-u`, `-g`, '-U`, `-G`
''
#!${pkgs.runtimeShell}
exec 2>&1
exec ${pkgs.s6}/bin/s6-socklog -t 60 -x /dev/log
'';
}
