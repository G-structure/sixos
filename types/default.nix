{ lib
, yants
, root
, ...
}:

# you have to pass the site.tags in, since we derive types from it
{ tags }@args:

with yants;
let

    # (used for site.tags): recursively walks an attrset, turning all non-leaf
    # nodes into instances of `yants.struct` and all leaf nodes into
    # `yants.bool`.
    attrs2yants = name: val:
      if lib.isAttrs val
      then struct name (lib.mapAttrs attrs2yants val  // { tags = option any; })
      else bool;

    # the default tag attrset (i.e. all leaves false) for a host in this site
    default-tag-values =
      lib.mapAttrsRecursive (path: val: false) tags;

    # because `final.host.${hostname}.tags` is a frequent source of infinite
    # recursion, all functions which modify `host.${hostname}.tags` use this
    # function to ensure that its attrnames (in which it is strict) are
    # determined solely by the `site.tags`.
    set-tag-values =
      new-tag-values:
      default-tag-values //
      lib.intersectAttrs default-tag-values new-tag-values;

    # here's the problem
    # - some hosts are on a subnet, but i haven't declared the name of the interface for that subnet yet
    # - the "lo" interface can't have a named subnet, since it doesn't connect to any other machine
    interface = struct "interface" {
      type = option string;
      subnet = option string;
    };
    endpoint = struct "endpoint" {
      ip = string;
      port = int;
    };
    wgpeer = struct "wgpeer" {
      endpoint = option endpoint;
      allowed-ips = list string;
      pubkey = option string;
      keepalive-seconds = option int;
    };
    wg = struct "wg" {
      pubkey = string;
      peers = option (attrs wgpeer);
      fwmark = option int;
    };
    ifconn = struct "ifconn" {
      ifname = option string;
      subnet = option string;
      ip = option string;
      netmask = option int;
      mtu = option int;
      gw = option string;
      wg = option wg;
      edenPort = option int;  # FIXME
    };
    ifname = string;

    # a path in the store (i.e. outpath or a file within an outpath directory)
    storepath =
      either drv
        (restrict "storepath"
          (v: lib.hasPrefix builtins.storeDir v)
          string);

    # A single tty-device, which is a device name and an optional baud rate
    tty-dev = struct "console" {
      device = string;    # the part after "/dev/" -- i.e. just "ttyS0"
      baud = option int;
    };

    # A set of tty-devices: a map from device name to optional baudrate.
    # Using `list tty-dev` would allow duplicates and be ordering-sensitive.
    tty-dev-map = attrs (option yants.int);

    host = struct "host" {
      name = string;
      canonical = string;      # gnu-config triple
      hostid = option string;  # identifier for diskless hosts

      tags = attrs2yants "tags" args.tags;

      interfaces = attrs interface;
      ifconns = attrs ifconn; # attrname is the subnet name; assumes (sensibly) maximum one interface per subnet
      pkgs = any;             # attrsof<pkg>; set to `any` to keep eval times reasonable
      sw = any;               # drv; set to `any` to keep eval times reasonable
      configuration = any;    # drv; set to `any` to keep eval times reasonable
      delete-generations = option string;

      service-overlays = option (list function);

      boot = struct "boot" {
        loader = option (struct "loader" {
          update = either drv string; # command which is run with one or two arguments
        });

        nfsroot = option (struct "boot.tnfsroot" {
          # subnet name from which to boot; there must be an interface assigned to this subnet.
          subnet = string;
        });

        kernel = struct "kernel" {
          payload = storepath;
          params = list string;
          modules = storepath;  # store path containing the built kernel modules
          firmware = either storepath (list storepath);
          package = drv;
          dtb = option storepath;

          # This is the *primary* console which is passed as the *last*
          # `console=` on the kernel command line; this will become /dev/console
          # once the kernel hands off to userspace.
          console = option tty-dev;
        };

        initrd = struct "initrd" {
          image = storepath;

          contents = attrs (either (either string storepath) (list string));  # see six-initrd

          # This indicates the ttys on which login services (getty, seatd, etc)
          # should be run after the kernel starts PID1.  It has no effect on the
          # pre-userspace kernel or the early-userspace initrd.
          ttys  = tty-dev-map;
        };

        spec = option storepath;
      };

    };

    site = struct "site" {
      hosts = attrs host;
      globals = any;  # "junk drawer" for passing things down the hierarchy

      # tag-name -> (list function)
      #
      # if `site.hosts.${name}.tags.${tag-name}==true` then
      # `lib.composeExtensions site.tags.${tag-name}` will be applied to
      # `site.hosts.${name}`
      #
      tags = attrs function;

      # subnet-name -> host-name -> ifconn
      subnets = attrs (attrs ifconn);

      # sitewide hosts-overlay FinalHosts->PrevHosts->NewHosts
      overlay = list function;
    };

in
  {
    inherit interface;
    inherit endpoint;
    inherit wgpeer;
    inherit wg;
    inherit ifconn;
    inherit ifname;
    inherit host;
    inherit site;
    inherit default-tag-values;
    inherit set-tag-values;
  }
