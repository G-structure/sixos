{ lib, infuse, util, pkgs, system, ... }:
{ name, site, host, host-prev, ... }:

# Minimal overlay that turns the skeleton `host-prev` into a bootable smoke-test host.

infuse host-prev {
  # Ensure a deterministic canonical triple so cross-evaluation works.
  canonical.__init = util.canonicalize system;

  # Trim feature surface – no tags for the demo build.
  tags.__assign = {};

  # Provide something small but real for the system path.
  sw.__assign = pkgs.busybox;

  # Nothing to overlay yet – placeholder to keep type happy.
  service-overlays.__append = [];
} 