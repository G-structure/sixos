{ lib, infuse, util, pkgs, system, ... }:
{ name, site, host, host-prev, ... }:

let
  dummy = builtins.traceSeq (infuse host-prev {
    canonical.__init = util.canonicalize system;
    tags.__assign = {};
    sw.__assign = pkgs.busybox;
    tags.dont-mount-root.__assign = true;
    service-overlays.__append = [];
    boot.kernel.console.device.__init = "ttyS0";
    boot.kernel.console.baud.__init = 115200;
    boot.initrd.ttys.ttyS0.__init = 115200;
    boot.kernel.params.__append = [ "console=ttyS0,115200n8" ];
    boot.initrd.image.__input.kernel.__assign = host.boot.kernel.package;
    boot.initrd.image.__input.module-names.__append = [
      "9p" "9pnet" "netfs" "fscache" "9pnet_virtio" "virtio_pci"
      "virtio_ring" "virtio" "virtio_pci_modern_dev" "virtio_pci_legacy_dev"
    ];
  }) (builtins.trace "evaluating demo host" null);
in
infuse host-prev {
  canonical.__init = util.canonicalize system;
  tags.__assign = {};
  sw.__assign = pkgs.busybox;
  tags.dont-mount-root.__assign = true;
  service-overlays.__append = [];
  boot.kernel.console.device.__init = "ttyS0";
  boot.kernel.console.baud.__init = 115200;
  boot.initrd.ttys.ttyS0.__init = 115200;
  boot.kernel.params.__append = [ "console=ttyS0,115200n8" ];
  boot.initrd.image.__input.kernel.__assign = host.boot.kernel.package;
  boot.initrd.image.__input.module-names.__append = [
    "9p" "9pnet" "netfs" "fscache" "9pnet_virtio" "virtio_pci"
    "virtio_ring" "virtio" "virtio_pci_modern_dev" "virtio_pci_legacy_dev"
  ];
} 