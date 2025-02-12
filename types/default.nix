{ lib
, yants
, root
, ...
}:

# you have to pass the site.tags in, since we derive types from it
{ tags }@args:

with yants;
let
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

    host = struct "host" {
      name = string;
      canonical = string;      # gnu-config triple
      hostid = option string;  # identifier for diskless hosts

      tags =
        let
          attrs2yants = val:
            if lib.isAttrs val
            then struct "tag-type" (lib.mapAttrs (_: attrs2yants) val)
            else bool;
        in
          attrs2yants args.tags;

      interfaces = attrs interface;
      ifconns = attrs ifconn; # attrname is the subnet name; assumes (sensibly) maximum one interface per subnet
      pkgs = any;             # attrsof<pkg>
      sw = any;               # drv
      configuration = any;    # drv
      delete-generations = option string;

      service-overlays = option (list any);

      # these are declared "any" in order to prevent typechecking from forcing
      # the entire kernel derivation
      boot = struct "boot" {
        loader = option (struct "loader" {
          update = any; # string: a command which is run with one or two arguments
        });

        nfsroot = option (struct "boot.tnfsroot" {
          # subnet name from which to boot; there must be an interface assigned to this subnet.
          subnet = string;
        });

        kernel = struct "kernel" {
          payload = any;  #string or path;
          params = any;   #list string;
          modules = any;  #string;
          firmware = either storepath (list storepath);
          package = any;
          dtb = any;

          # This is the *primary* console which is passed as the *last*
          # `console=` on the kernel command line; this will become /dev/console
          # once the kernel hands off to userspace.
          console = option (struct "console" {
            device = string;
            baud = option int;
          });
        };

        # This indicates the ttys on which login services (getty, seatd, etc)
        # should be run after the kernel starts PID1.  It has no effect on the
        # pre-userspace kernel or the early-userspace initrd.
        ttys = any;    # attrsof< null | int >

        spec = any;    #string;
        initrd = any;  #string;
      };

    };

    hosts = attrs host;

    site = struct "site" {
      #host = attrs host;
      host = any;
      hosts = any;
      site = any;
      globals = any;  # "junk drawer" for passing things down the hierarchy

      # tag-name -> overlay-that-is-applied-if-tag-is-present
      tags = attrs function;

      # subnet-name -> host-name -> ifconn
      subnets = attrs (attrs ifconn);

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
    inherit hosts;
    inherit site;
  }
