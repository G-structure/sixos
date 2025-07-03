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
    boot.initrd.contents."early/run".__prepend = [''
      echo initrd: executing /early/run
      mkdir -p /root
      mount -t tmpfs -o size=100m none /root
      mkdir /root/run /root/dev /root/proc /root/sys /root/tmp /root/root /root/etc /root/bin
      mkdir -p /root/nix/var/nix/profiles
      mkdir -p /root/nix/store
      echo 'root:x:0:0:root:/root:/run/current-system/sw/bin/bash' > /root/etc/passwd
      echo 'root:x:0:'  >  /root/etc/group
      echo 'kvm:x:106:' >> /root/etc/group
      echo 'tty:x:107:' >> /root/etc/group
      echo 'uucp:x:108:' >> /root/etc/group
      echo 'disk:x:109:' >> /root/etc/group
      echo 'audio:x:110:' >> /root/etc/group
      echo 'video:x:111:' >> /root/etc/group
      echo 'cdrom:x:112' >> /root/etc/group
      echo 'floppy:x:113' >> /root/etc/group
      echo 'input:x:114' >> /root/etc/group
      modprobe 9p
      modprobe 9pnet_virtio
      modprobe virtio_pci
      mount -t 9p -o trans=virtio,ro,msize=512000,version=9p2000.L nixstore /root/nix/store
    '' ];
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
  boot.kernel.params.__default = [ "console=ttyS0,115200n8" ];
  boot.initrd.image.__input.kernel.__assign = host.boot.kernel.package;
  boot.initrd.image.__input.module-names.__append = [
    "9p" "9pnet" "netfs" "fscache" "9pnet_virtio" "virtio_pci"
    "virtio_ring" "virtio" "virtio_pci_modern_dev" "virtio_pci_legacy_dev"
  ];
  boot.initrd.contents."early/run".__prepend = [''
    echo initrd: executing /early/run
    mkdir -p /root
    mount -t tmpfs -o size=100m none /root
    mkdir /root/run /root/dev /root/proc /root/sys /root/tmp /root/root /root/etc /root/bin
    mkdir -p /root/nix/var/nix/profiles
    mkdir -p /root/nix/store
    echo 'root:x:0:0:root:/root:/run/current-system/sw/bin/bash' > /root/etc/passwd
    echo 'root:x:0:'  >  /root/etc/group
    echo 'kvm:x:106:' >> /root/etc/group
    echo 'tty:x:107:' >> /root/etc/group
    echo 'uucp:x:108:' >> /root/etc/group
    echo 'disk:x:109:' >> /root/etc/group
    echo 'audio:x:110:' >> /root/etc/group
    echo 'video:x:111:' >> /root/etc/group
    echo 'cdrom:x:112' >> /root/etc/group
    echo 'floppy:x:113' >> /root/etc/group
    echo 'input:x:114' >> /root/etc/group
    modprobe 9p
    modprobe 9pnet_virtio
    modprobe virtio_pci
    mount -t 9p -o trans=virtio,ro,msize=512000,version=9p2000.L nixstore /root/nix/store
  '' ];
} 