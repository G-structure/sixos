{ lib, infuse, util, pkgs, system, ... }:
{ name, site, host, host-prev, ... }:

let
  dummy = builtins.traceSeq (infuse host-prev {
    canonical.__init = util.canonicalize system;
    tags.__assign = {};
    sw.__assign = pkgs.busybox;
    service-overlays.__append = [];
  }) (builtins.trace "evaluating demo host" null);
in
infuse host-prev {
  canonical.__init = util.canonicalize system;
  tags.__assign = {};
  sw.__assign = pkgs.busybox;
  service-overlays.__append = [];
} 