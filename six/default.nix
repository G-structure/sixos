{ lib
, yants
, pkgs
}:
let

  util = import ./util {
    inherit lib pkgs;
  };

  mkConfiguration = pkgs.callPackage ./mkConfiguration.nix {
    inherit util yants;
    s6-linux-init   = pkgs.callPackage ./s6-linux-init.nix { };
    services =
      let inherit (lib) pipe mapAttrs attrValues mergeAttrsList stringLength filterAttrs substring;
      in pipe (builtins.readDir ./by-name) [

        # keep only two-letter directories in ./by-name
        (filterAttrs
          (name: type:
            type == "directory" &&
            stringLength name == 2))

        # read each stem directory
        (mapAttrs (stem: _:
          builtins.readDir (./. + "/by-name/${stem}")))

        (mapAttrs (stem: stemdir:
          pipe stemdir [
            # filter out anything in a stem directory that isn't a subdirectory
            # whose first two characters match the stem
            (filterAttrs
              (fulldirname: fulldirtype:
                fulldirtype == "directory" &&
                substring 0 2 fulldirname == stem))
            # look in any remaining subdirectories for a `service.nix` file
            (mapAttrs
              (fulldirname: _:
                import (./. + "/by-name/${stem}/${fulldirname}/service.nix")))
          ]))

        builtins.attrValues
        lib.attrsets.mergeAttrsList
      ];
  };

in {
  inherit mkConfiguration;
  inherit util;
}
