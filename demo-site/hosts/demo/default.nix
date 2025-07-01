{ lib, infuse, util, pkgs, system, ... }:
{ name, site, host, host-prev, ... }:

infuse host-prev {
  canonical.__init = util.canonicalize system;
  tags.__assign = {};
  sw.__assign = pkgs.busybox;
  service-overlays.__append = [];
} 