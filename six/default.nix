{ lib
, yants
, pkgs
, extra-by-name-dirs ? []
}:
let

  util = import ./util {
    inherit lib pkgs;
  };

  mkConfiguration = pkgs.callPackage ./mkConfiguration.nix {
    inherit util yants;
    s6-linux-init   = pkgs.callPackage ./s6-linux-init.nix { };
    services =
      let
        inherit (lib) pipe mapAttrs attrValues mergeAttrsList stringLength filterAttrs substring;
        services =
        lib.pipe ([./by-name] ++ extra-by-name-dirs) [
          (map (dir: pipe dir [

            builtins.readDir

            # keep only two-letter directories in ./by-name
            (filterAttrs
              (name: type:
                type == "directory" &&
                stringLength name == 2))

            # read each stem directory
            (mapAttrs (stem: _:
              builtins.readDir (dir + "/${stem}")))

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
                    import (dir + "/${stem}/${fulldirname}/service.nix")))
              ]))

            builtins.attrValues
            lib.attrsets.mergeAttrsList
            lib.attrsToList
          ]))

          lib.concatLists
          lib.listToAttrs
        ];
      in
        services;
  };

in {
  inherit mkConfiguration;
  inherit util;
}
