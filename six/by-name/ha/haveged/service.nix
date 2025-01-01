{ lib
, pkgs
, mkFunnel
}:
mkFunnel {
  run = pkgs.writeScript "run"
''
#!${pkgs.runtimeShell}
exec 2>&1
# -F run in foreground
# -w sets low entropy watermark (in bits)
exec ${pkgs.haveged}/bin/haveged -F -w 1024
'';
}
