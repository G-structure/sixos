{ lib
, stdenv
, buildLinux
, ignoreConfigErrors ? true
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

, defconfig ? (if stdenv.hostPlatform.isMips then "cavium_octeon_defconfig" else null)

# TODO: set this to `false` on more platforms
, enableCommonStructuredConfig ? with stdenv.hostPlatform; isx86_64 || isPower64

, patches ? []
}:

let
  commonargs = {
    src = source;
    inherit version;

    # branchVersion needs to be x.y
    extraMeta.branch = lib.versions.majorMinor version;

    kernelPatches = patches;
  };

  kernel =
    if dotconfig!=null
    then linuxKernel.manualConfig.override { inherit stdenv; }
      (commonargs // {
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
      })

    else buildLinux (commonargs // {
      inherit defconfig;
      inherit enableCommonStructuredConfig;
      inherit ignoreConfigErrors;
      structuredExtraConfig =
        with lib.kernel; {

          EXPERT = yes;
          BTRFS_FS = yes;
          ENCRYPTED_KEYS = module;
          USB_OHCI_HCD = module;
          INPUT_EVBUG = no;               # spams the dmesg console
          INPUT_EVDEV = module;
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

    });
in
kernel
  .overrideAttrs(previousAttrs: lib.optionalAttrs stdenv.hostPlatform.isMips {
    NIX_CFLAGS_COMPILE = (previousAttrs.NIX_CFLAGS_COMPILE or "") + " -w ";

    # this runs after `make oldconfig`
    postConfigure = (previousAttrs.postConfigure or "") + lib.optionalString (dotconfig != null) ''
    '';

    postInstall = (previousAttrs.postInstall or "") + ''
      $STRIP $out/vmlinux-${version}
    '';
  })
