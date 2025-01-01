{ lib
, stdenv
, buildLinux
, overrideWithDistCC ? throw "missing"
, version ? "6.6.41"
, source ? fetchurl {
  url = "mirror://kernel/linux/kernel/v${lib.versions.major version}.x/linux-${version}.tar.xz";
  hash = "sha256-nsmcV4FYq4XZmzd5GnZkPS6kw/cuy+97XrbWDz3gMu8=";
}
, fetchurl
, fetchpatch
, dotconfig ? null
, linuxKernel
, enableDistCC ? false
, runCommand
}:

let stdenv' = stdenv; in
let stdenv  = if enableDistCC then overrideWithDistCC stdenv' else stdenv'; in

let
  # TODO: set this to `false` on more platforms
  enableCommonStructuredConfig =
    with stdenv.hostPlatform; isx86_64 || isPower64;

in ((if dotconfig==null then buildLinux else linuxKernel.manualConfig.override { inherit stdenv; }) ({
  src = source;
  inherit version;

  # branchVersion needs to be x.y
  extraMeta.branch = lib.versions.majorMinor version;

} // lib.optionalAttrs (dotconfig != null) {
  configfile =
    if !enableDistCC
    then dotconfig
    else runCommand "config-without-plugins" {} ''
      cat ${dotconfig} | grep -v ^CONFIG_GCC_PLUGIN > $out
      echo 'CONFIG_HAVE_GCC_PLUGINS=n' >> $out
      echo 'CONFIG_GCC_PLUGINS=n' >> $out
    '';
  config = {
    CONFIG_MODULES = "y";
    CONFIG_FW_LOADER = "m";
    #CONFIG_RUST = if withRust then "y" else "n";
  };

} // lib.optionalAttrs stdenv.hostPlatform.isMips {
  defconfig = "cavium_octeon_defconfig";

} // {

  kernelPatches = lib.optionals stdenv.hostPlatform.isAarch64 (map (p: { name = "patch"; patch = p; }) [
    ../../../../boot/patches/kevin/0009-drm-bridge-analogix_dp-Don-t-return-EBUSY-when-msg-s.patch
    #../../../../boot/patches/kevin/0008-bridge-analogix-Don-t-wait-for-panel-ACK-on-PSR-exit.patch
    ../../../../boot/patches/kevin/0010-make-panfrost-not-spam-the-dmesg-log-from-https-gitl.patch
    ../../../../boot/patches/kevin/0012-map-search-key-as-capslock-like-all-other-PC-style-k.patch
    ../../../../boot/patches/kevin/0013-LOCAL-rk3399-DTSI-remove-serial2-115200n8-assignment.patch
    ../../../../boot/patches/kevin/0014-LOCAL-panfrost-tolerate-missing-regulator-control-v5.patch
    ../../../../boot/patches/kevin/0001-cros_ec_keybp-disable-SW_TABLET_MODE.patch
  ]) ++ [
    {
      name = "btrfs-metadata";
      patch = fetchpatch {
        url = "https://github.com/kakra/linux/compare/2eaf5c0d81911ba05bace3a722cbcd708fdbbcba..76e1b3eeb9a99149bf171453f2f7ced1040e3c41.patch";
        hash = "sha256-MzZsNy8p5AYT++ErWFIWSod4h+Th4Vms5q/kMseHAPk=";
      };
    }

    {
      # commit 16ef02bad239f11f322df8425d302be62f0443ce imposes
      # unrealistically-restrictive assumptions about the USB endpoint
      # numbering; these assumptions fail for ath9271 chips that do not have
      # an ath7010 sitting between them an the usb bus (i.e. 2.4ghz-only
      # chips)
      name = "revert-ath9k-breakage";
      patch = fetchpatch {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/?id=16ef02bad239f11f322df8425d302be62f0443ce";
        hash = "sha256-1Qz1IFTT3GP0cs4Q4sigSCQV6TKF0MQtyO2mkDq67is=";
        revert = true;
      };
    }

  ] ++ lib.optionals stdenv.hostPlatform.isMips [
    rec {
      name = "110-er200-ethernet_probe_order.patch";
      patch = fetchpatch {
        inherit name;
        url = "https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob_plain;"+
              "f=target/linux/octeon/patches-5.4/110-er200-ethernet_probe_order.patch;"+
              "hb=02e2723ef317c65b6ddfc70144b10f9936cfc2af";
        sha256 = "sha256-oumgFtZnuFL2MXWtUd5RipF+qDHuze+wG/ogjtcd5XQ=";
      };
    }

    # this patch is needed in order to get predictable interface names; it is from openwrt but no longer applies cleanly
    # https://git.openwrt.org/?p=openwrt/openwrt.git;a=blob_plain;f=target/linux/octeon/patches-5.4/700-allocate_interface_by_label.patch
    { name = "700-allocate_interface_by_label.patch"  ; patch = ./patches/700-allocate_interface_by_label.patch; }
/*
    # support for Ubiquiti E100 boards (Cavium CN5020), Edgerouter Lite
    # support for Ubiquiti E120 boards (Cavium CN5020), Unifi Security Gateway 3 (USG-3)
    { name = "ubnt_e100-e120.patch"           ; patch = ./patches/ubnt_e100-e120.patch; }

    # support for Ubiquiti E200 board (Cavium CN6120), Edgerouter 8 Pro; SFP cages do not work in Linux
    # support for Ubiquiti E220 board (Cavium CN6120), Unifi Security Gateway Pro-4 (USGPro-4); SFP cages do not work in Linux
    { name = "edgerouter-8pro.patch"          ; patch = ./patches/edgerouter-8pro.patch; }
*/
    # support for Ubiquiti E300 board (Cavium CN7130) Edgerouter-4; SFP cages *do* work in Linux
    { name = "edgerouter-4.patch"             ; patch = ./patches/edgerouter-4.patch; }

    # support for Ubiquiti E300 board (Cavium CN7130) Edgerouter-6; SFP cages *do* work in Linux
    # support for Ubiquiti E300 board (Cavium CN7130) Edgerouter-12; SFP cages *do* work in Linux, internal switch behaves strangely
    { name = "edgerouter-6,12.patch"          ; patch = ./patches/edgerouter-6-12.patch; }
/*
    # The vendor-supplied bootloader (a u-boot fork) shipped with all
    # Octeon devices communicates the initrd's memory location only
    # via a nonstandard `rd_name=` kernel parameter, which upstream
    # kernel declines to support.
    #
    # Note: this doesn't actually work; the kernel still doesn't notice the initrd
    #
    #  usb start
    #  dhcp
    #  freeprint
    #  # pick the first "Block address", round up to end with 0x0000, and use it as the second value below:
    #  setenv initrd_addr 0x4e000000
    #  namedalloc my_initrd 0xb00000 $(initrd_addr)
    #  tftpboot $(initrd_addr) 192.168.22.6:cedar/kernel/initrd
    #  tftpboot $(loadaddr) 192.168.22.6:cedar/kernel/vmlinux
    #  bootoctlinux $(loadaddr) numcores=$(numcores) endbootargs mem=0 rd_name=my_initrd
    #
    {
      name = "octeon-rd_name.patch";
      patch = fetchpatch {
        # rebase of original here: https://lore.kernel.org/all/1418666603-15159-10-git-send-email-aleksey.makarov@auriga.com/
        url = "https://raw.githubusercontent.com/alpinelinux/aports/6f0349a849b733d788fd02788c0516d689ddc6a2/main/linux-octeon/octeon-rd_name.patch";
        hash = "sha256-4W9kStw1ZHLYu/axUbkutJAgMFQzWquRChO3fFtkaTA=";
      };
    }

    {
      name = "fix-initrd-address.patch";
      patch = fetchpatch {
        url = "https://lore.kernel.org/all/20230619102133.809736219@linuxfoundation.org/raw";
        hash = "sha256-53sJSN2koaGOIwrJumlRmdy22ueG3e39VUIQVG3IKYs=";
      };
    }
*/
  ];

  #extraMakeFlags = [ "V=1" ];

} // lib.optionalAttrs (dotconfig == null) {
  inherit enableCommonStructuredConfig;
  ignoreConfigErrors = true;
  structuredExtraConfig =
    if dotconfig != null then {} else with lib.kernel; {

    EXPERT = yes;
    BTRFS_FS = yes;
    ENCRYPTED_KEYS = module;
    USB_OHCI_HCD = module;
    INPUT_EVBUG = no;               # spams the dmesg console
    INPUT_EVDEV = module;
    #INPUT_UNIPUT = module;    # for keycaster
    ZSWAP = yes;

    RD_XZ = lib.mkForce (option yes);
    KERNEL_XZ = lib.mkForce (option yes);
    MODULE_COMPRESS_XZ = lib.mkForce (option yes);
    KERNEL_ZSTD = lib.mkForce (option no);

    KEXEC = lib.mkForce yes;
    #KEXEC_FILE = yes;

    #CFG80211_DEBUGFS = yes;
    #CFG80211_WEXT = yes;

    #CPU_FREQ_GOV_POWERSAVE = yes;
    #CPU_FREQ_STAT = yes;

    #EFI = no;

    #FW_LOADER_COMPRESS = yes;
    #FW_LOADER_USER_HELPER = yes;

    #HIBERNATION = no;    # never got this working

    #HWMON = yes;

    #HYPERVISOR_GUEST = lib.mkForce no;   # paranoia

    #IKCONFIG = yes;    # /proc/config.gz
    #IKHEADERS = yes;   # /sys/kernel/kheaders.tar.xz

    #KVM = yes;
    #MAC80211_DEBUGFS = yes;
    #MEMORY_FAILURE = yes;  # recover from ECC events?
    #MTD = yes;
    #MTD_CMDLINE_PARTS = yes;
    #PCCARD = no;
    #PERF_EVENTS_AMD_POWER = yes; # AMD power reporting
    #SENSORS_W83795 = module;
    #UEVENT_HELPER = lib.mkForce yes;
    #USERFAULTFD = yes;
    #USER_NS = lib.mkForce no;       # ??
    #WIREGUARD = yes;

    # TODO:
    # DEFAULT_HOSTNAME
    # DEFAULT_INIT
    # AUDIT = n maybe? kills SELINUX tho
    # PREEMPT = y on laptop?
    # BOOT_CONFIG -- see Documentation/admin-guide/bootconfig.rst; lets you append a command line to the initramfs
    # SPECULATION_MITIGATIONS = n
    # MODPROBE_PATH  <- path to /sbin/modprobe

    #MICROCODE_OLD_INTERFACE=yes;
    BPF_UNPRIV_DEFAULT_OFF = lib.mkForce (option no);   # I think the nixpkgs version bounds are wrong here

    BLK_DEV_NVME = yes;           # for boot
    NVME_CORE = lib.mkForce (option yes);

    RUNTIME_TESTING_MENU = no;   # some kind of vulnerability involving serial consoles

    INET_MPTCP_DIAG = lib.mkForce (option module);

    IPV6 = lib.mkForce (option no);

  } // lib.optionalAttrs (!stdenv.hostPlatform.isMips) {
    DEBUG_INFO_BTF = lib.mkForce (option no);           # otherwise we get crashes with too-new binutils and pahole
    FW_LOADER_COMPRESS_XZ = lib.mkForce (option yes);

  } // lib.optionalAttrs (!stdenv.hostPlatform.isPower64) {
    TEE = no;                 # tee.o, trusted execution environment

  } // lib.optionalAttrs (with stdenv.hostPlatform; isx86_64 || isPower64) {
    DRM_AMDGPU = module;

    NUMA_BALANCING = yes;
    NUMA_BALANCING_DEFAULT_ENABLED = yes;

  } // lib.optionalAttrs stdenv.hostPlatform.isPower64 {
    CRYPTO_AES_GCM_P10 = lib.mkForce (option no);
    CRYPTO_CHACHA20_P10 = lib.mkForce (option no);
    CRYPTO_POLY1305_P10 = lib.mkForce (option no);

  } // lib.optionalAttrs stdenv.hostPlatform.isx86 {
    GART_IOMMU = yes;
    NUMA_EMU=yes;
    #INTEL_IDLE = yes;

  } // lib.optionalAttrs stdenv.hostPlatform.isx86_64 {
    MK8 = yes;                   # CPU type
    SENSORS_K10TEMP = module;
    SENSORS_W83795 = module;
    SENSORS_W83795_FANCTRL = yes;
    W83627HF_WDT = option module; # the "good watchdog"
    SP5100_TCO   = no;            # does not work and messes up iommu
    X86_X32_ABI=yes;
    E1000E = module;
    SENSORS_FAM15H_POWER = module;

    #X86_AMD_PSTATE = yes;
    #X86_AMD_PSTATE_UT = module;
    #X86_BOOTPARAM_MEMORY_CORRUPTION_CHECK = yes;
    #X86_CPUID = no;
    #X86_INTEL_MEMORY_PROTECTION_KEYS = no;
    #X86_MCELOG_LEGACY = yes;     # /dev/mcelog
    #X86_MSR = no;
    #X86_PCC_CPUFREQ = yes;

  } // lib.optionalAttrs (enableCommonStructuredConfig) {
    NF_TABLES = lib.mkForce module;

  } // lib.optionalAttrs (!enableCommonStructuredConfig) {
    # needed for wireguard
    NET_UDP_TUNNEL = module;
    NETFILTER = yes;
    NETFILTER_ADVANCED = yes;

    WIREGUARD = module;

    USB_ACM = module;    # useful for controlling serial consoles of other machines
    USB_SERIAL = lib.mkForce module;    # useful for controlling serial consoles of other machines
    USB_SERIAL_FTDI_SIO = module;
    USB_SERIAL_PL2303 = module;
    USB_SERIAL_CP210X = module;

  } // lib.optionalAttrs (!enableCommonStructuredConfig && !stdenv.hostPlatform.isPower64) {
    # needed to mount /nix/store on several of my machines
    USB_UAS = lib.mkForce yes;

  } // lib.optionalAttrs stdenv.hostPlatform.isMips {
    CAVIUM_OCTEON_CVMSEG_SIZE = freeform "0";
    CPU_BIG_ENDIAN = no;
    CPU_LITTLE_ENDIAN = yes;
    PCIEPORTBUS = yes;
    PCIEAER = yes;
    MTD_SPI_NOR = yes;
    MTD_SPI_NOR_USE_4K_SECTORS = yes;
    #PHYLINK = module;
    #SFP = module;
    #MDIO_I2C = module;

    # needed for /dev/mtd{1..} to show up
    MTD_CMDLINE_PARTS = lib.mkForce yes;

    # allow use of the .appended_dtb section
    MIPS_ELF_APPENDED_DTB = lib.mkForce yes;

    # Didn't get the following to work:
    #
    # Ensures that the DTB chosen/bootparams are extended by, rather than
    # overwritten by, the bootloader's boot arguments.  This lets us put the
    # initrd start/size in the DTB.
    USE_OF = lib.mkForce yes;

    MIPS_CMDLINE_FROM_BOOTLOADER = lib.mkForce no;
    MIPS_CMDLINE_DTB_EXTEND = lib.mkForce yes;

    STRIP_ASM_SYMS = lib.mkForce yes;

    # for vlans on simpson
    VLAN_8021Q = lib.mkForce module;

    # FIXME: never figured out how to make the nft_*.ko modules auto-load
    NF_TABLES = lib.mkForce module;
    NFT_NUMGEN = lib.mkForce module;
    NFT_CT = lib.mkForce module;
    NFT_CONNLIMIT = lib.mkForce module;
    NFT_LOG = lib.mkForce module;
    NFT_LIMIT = lib.mkForce module;
    NFT_MASQ = lib.mkForce module;
    NFT_REDIR = lib.mkForce module;
    NFT_NAT = lib.mkForce module;
    NFT_TUNNEL = lib.mkForce module;
    NFT_QUOTA = lib.mkForce module;
    NFT_REJECT = lib.mkForce module;
    NFT_HASH = lib.mkForce module;
    NFT_SOCKET = lib.mkForce module;
    NFT_OSF = lib.mkForce module;
    NFT_TPROXY = lib.mkForce module;
    NFT_REJECT_IPV4 = lib.mkForce module;
    NF_CONNTRACK = lib.mkForce module;
    NF_LOG_SYSLOG = lib.mkForce module;
    NF_CONNTRACK_MARK = lib.mkForce yes;
    NF_CONNTRACK_ZONES = lib.mkForce yes;
    # NF_CONNTRACK_PROCFS is not set
    NF_CONNTRACK_EVENTS = lib.mkForce yes;
    NF_CONNTRACK_TIMEOUT = lib.mkForce yes;
    NF_CONNTRACK_TIMESTAMP = lib.mkForce yes;
    NF_CONNTRACK_LABELS = lib.mkForce yes;
    NF_CT_PROTO_DCCP = lib.mkForce yes;
    NF_CT_PROTO_GRE = lib.mkForce yes;
    NF_CT_PROTO_SCTP = lib.mkForce yes;
    NF_CT_PROTO_UDPLITE = lib.mkForce yes;
    NF_CONNTRACK_AMANDA = lib.mkForce module;
    NF_CONNTRACK_FTP = lib.mkForce module;
    NF_CONNTRACK_H323 = lib.mkForce module;
    NF_CONNTRACK_IRC = lib.mkForce module;
    NF_CONNTRACK_BROADCAST = lib.mkForce module;
    NF_CONNTRACK_NETBIOS_NS = lib.mkForce module;
    NF_CONNTRACK_SNMP = lib.mkForce module;
    NF_CONNTRACK_PPTP = lib.mkForce module;
    NF_CONNTRACK_SANE = lib.mkForce module;
    NF_CONNTRACK_SIP = lib.mkForce module;
    NF_CONNTRACK_TFTP = lib.mkForce module;
    NF_CT_NETLINK = lib.mkForce module;
    NF_CT_NETLINK_TIMEOUT = lib.mkForce module;
    NF_NAT = lib.mkForce module;
    NF_NAT_AMANDA = lib.mkForce module;
    NF_NAT_FTP = lib.mkForce module;
    NF_NAT_IRC = lib.mkForce module;
    NF_NAT_SIP = lib.mkForce module;
    NF_NAT_TFTP = lib.mkForce module;
    NF_NAT_REDIRECT = lib.mkForce yes;
    NF_NAT_MASQUERADE = lib.mkForce yes;
    NF_TABLES_NETDEV = lib.mkForce yes;
    NF_DUP_NETDEV = lib.mkForce module;
    NF_FLOW_TABLE_INET = lib.mkForce module;
    NF_FLOW_TABLE = lib.mkForce module;
    # NF_FLOW_TABLE_PROCFS is not set
    NF_DEFRAG_IPV4 = lib.mkForce module;
    NF_SOCKET_IPV4 = lib.mkForce module;
    NF_TPROXY_IPV4 = lib.mkForce module;
    NF_TABLES_IPV4 = lib.mkForce yes;
    NF_TABLES_INET= lib.mkForce yes;
    NF_TABLES_ARP = lib.mkForce yes;
    NF_DUP_IPV4 = lib.mkForce module;
    NF_LOG_ARP = lib.mkForce module;
    NF_LOG_IPV4 = lib.mkForce module;
    NF_REJECT_IPV4 = lib.mkForce module;
    NF_NAT_SNMP_BASIC = lib.mkForce module;
    NF_NAT_PPTP = lib.mkForce module;
    NF_NAT_H323 = lib.mkForce module;
    NF_CONNTRACK_BRIDGE = lib.mkForce module;

    #      PHYLIB = module;
    #      NET_DSA_VITESSE_VSC73XX = module;
    #      VITESSE_PHY = yes;

    PPP = lib.mkForce module;
    PPP_BSDCOMP = lib.mkForce module;
    PPP_DEFLATE = lib.mkForce module;
    PPP_FILTER= lib.mkForce yes;
    #PPP_MPPE = lib.mkForce module;
    #PPP_MULTILINK=y
    PPPOE = lib.mkForce module;
    PPP_ASYNC = lib.mkForce module;
    PPP_SYNC_TTY = lib.mkForce module;
    #HDLC_PPP = lib.mkForce module;

  };

}))
  .overrideAttrs(previousAttrs: lib.optionalAttrs stdenv.hostPlatform.isMips {
    NIX_CFLAGS_COMPILE = (previousAttrs.NIX_CFLAGS_COMPILE or "") + " -w ";

    # this runs after `make oldconfig`
    postConfigure = (previousAttrs.postConfigure or "") + lib.optionalString (dotconfig != null) ''
    '';

    postInstall = (previousAttrs.postInstall or "") + ''
      $STRIP $out/vmlinux-${version}
    '';
  })
