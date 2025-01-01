{ lib
, pkgs
, six
, targets
}:

let
  env = {
    PCSCLITE_HP_DROPDIR = "${pkgs.ccid}/pcsc/drivers";
  };

  run = pkgs.writeScript "run" ''
    #!${pkgs.runtimeShell}
    exec ${lib.escapeShellArgs
      (six.util.chpst {
        envdir = "./env";
        argv = [
          "${pkgs.pcsclite}/bin/pcscd"
          "-f"  # foreground
          # bug causes mass-scanning of /etc if no configuration file
          # is provided; see https://github.com/NixOS/nixpkgs/issues/121088
          "-c" "/dev/null"
          #"--debug"
          "-a"  # log APDU commands+results
        ];
      })}
  '';

in six.mkFunnel {
  inherit env run;
  passthru.after = with targets; [ global.coldplug ];
}
