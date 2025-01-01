{ lib
, pkgs
}:

let
  chpst = pkgs.callPackage ./chpst {};
in {
  inherit chpst;
}
