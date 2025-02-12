{
  nixpkgs-path
  ? builtins.fetchTarball {
    url = "https://github.com/nixos/nixpkgs/archive/38edd08881ce4dc24056eec173b43587a93c990f.tar.gz";
    sha256 = "049wkiwhw512wz95vxpxx65xisnd1z3ay0x5yzgmkzafcxvx9ckw";
  },

  lib
  ? import "${nixpkgs-path}/lib",

  infuse
  ? ((import (builtins.fetchGit {
    url = "https://codeberg.org/amjoseph/infuse.nix";
    rev = "bb99266d1e65f137a38b7428a16ced77cd587abb";
    shallow = true;
  })) { inherit lib; }).v1.infuse,

  nixpkgs
  ? args:
    (import nixpkgs-path)
      (infuse args {
        overlays.__append = import ./pkgs/overlays.nix { inherit lib infuse; };
      }),

  tvl-fyi
  ? builtins.fetchGit {
    url = "https://github.com/tvl-fyi/depot";
    # feat(nix/readTree): Handle a builtins w/o scopedImport
    rev = "b0547ccfa5e74cf21e813cd18f64ef62f1bf3734";
    shallow = true;
  },

  readTree
  ? import (builtins.fetchurl {
    url = "https://code.tvl.fyi/plain/nix/readTree/default.nix?id=95d6b3754f933c035d1951f25419f797684c147d";
    sha256 = "0f1lm7yfd5rfhiwj04s0fvyjy14ixw91m1n82pgj02p0yvzc7cg6";
  }) {},

  yants
  ? import (builtins.fetchurl {
    url = "https://code.tvl.fyi/plain/nix/yants/default.nix";
    sha256 = "026j3a02gnynv2r95sm9cx0avwhpgcamryyw9rijkmc278lxix8j";
  }) {
    inherit lib;
  },

  six-initrd
  ? import (builtins.fetchGit {
    url = "https://codeberg.org/amjoseph/six-initrd";
    rev = "eeba355b70b7fbc6f7f439c8a76cef9d561e03b5";
    shallow = true;
  }),

  # function which maps gnu-config canonical names to the `pkgs` set which has that 
  pkgsOn ? canonical: nixpkgs {
    hostPlatform = canonical;
  },

  site,

  extra-by-name-dirs ? [],

  extra-auto-args ? {},

}@args:

let

  # readTree invocation on the `site` directory
  site =
    let
      auto-args' = auto-args // extra-auto-args // {
        auto-args = auto-args';
      };
    in
      root.util.maybe-invoke-readTree auto-args' args.site;

  # automatically-provided arguments (e.g. callPackage and readTree)
  auto-args = {
    inherit lib yants infuse readTree;
    inherit (root) types util;
    inherit root;
    inherit auto-args;
    inherit site;
  };

  # readTree invocation on the directory containing this file
  root = readTree.fix (self: (readTree {
    args = auto-args;
    path = ./.;
  }));

  # helpful utility function; turns a fixpoint-on-one-host into a
  # fixpoint-on-the-entire-hosts-set.
  forall-hosts = f:
    (hosts:
      hosts_prev:
      hosts_prev //
      lib.flip lib.mapAttrs hosts_prev
        (name:
          host_prev:
          host_prev // (f hosts.${name} host_prev)));

  overlays = [

    # initial host set: populate attrnames from site.hosts
    (final: prev:
      lib.mapAttrs
        (name: _: prev.${name} or {})
        site.hosts
    )

    # add in the `name`, `pkgs`, `tags`, and (optional) `hostid` attributes
    (final: prev:
      lib.flip lib.mapAttrs prev
        (name: host: host // {
          inherit name;
          pkgs = pkgsOn host.canonical;
          tags = lib.mapAttrsRecursive (_: _: false) site.tags;
        } // lib.optionalAttrs (host?hostid) {
          inherit (host) hostid;
        })
    )

    # build the ifconns and interfaces attributes
    (root.util.forall-hosts (host-name: final: prev:
      let
        ifconns =
          # all the subnets to which it is directly attached.
          lib.pipe site.subnets [
            (
              lib.mapAttrs (subnetName: subnet:
                lib.pipe subnet [
                  # drop the __netmask key, which is not a host
                  (lib.filterAttrs (hostName: _:
                    !(lib.strings.hasPrefix "__" hostName)
                  ))

                  # add ${host}.netmask
                  (lib.mapAttrs
                    (hostName: ifconn: {
                      netmask = subnet.__netmask;
                    } // ifconn))
                ])
            )
            (lib.mapAttrsToList
              (subnetName: subnet:
                if subnet?${prev.name}
                then lib.nameValuePair subnetName subnet.${prev.name}
                else null))
            (lib.filter (v: v!=null))
            lib.listToAttrs
          ];
        interfaces =
          { lo.type = "loopback"; } //
          lib.pipe ifconns [
            (lib.mapAttrsToList
              (subnetName: ifconn:
                if ifconn?ifname
                then lib.nameValuePair ifconn.ifname ({
                  subnet = subnetName;
                } // lib.optionalAttrs (site.subnets.${subnetName}?__type) {
                  type = site.subnets.${subnetName}.__type;
                })
                else null))
            (lib.filter (v: v!=null))
            lib.listToAttrs
          ];
      in prev // { inherit ifconns interfaces; }
    ))

    # boot stage
  ] ++ (import ./initrd.nix { inherit lib infuse six-initrd util; }) ++ [

    # default kernel setup
    (root.util.forall-hosts
      (host-name: final: prev:
        infuse prev {
          boot.kernel.params   = _: [
            "root=LABEL=boot"
            "ro"
          ] ++ lib.optionals (final.boot?kernel.console.device) [
            ("console=${final.boot.kernel.console.device}"
             + lib.optionalString
               (final.boot?ttys.${final.boot.kernel.console.device})
               ",${toString final.boot.ttys.${final.boot.kernel.console.device}}")
          ];
          boot.kernel.modules  = _: "${final.boot.kernel.package}";
          boot.kernel.payload    = _: "${final.boot.kernel.package}/bzImage";
          boot.kernel.package  = _: final.pkgs.callPackage ./kernel.nix { };
        }
      ))

    # arch stage
    (root.util.forall-hosts
      (host-name: final: prev: infuse prev
        ({
          x86_64-unknown-linux-gnu =
            import ./arch/amd64 {
              inherit final infuse;
              inherit (prev) name;
            };
          mips64el-unknown-linux-gnuabi64 =
            import ./arch/mips64 {
              inherit final infuse;
              inherit (prev) name;
            };
          powerpc64le-unknown-linux-gnu =
            import ./arch/powerpc64 {
              inherit final infuse;
              inherit (prev) name;
            };
          aarch64-unknown-linux-gnu =
            import ./arch/arm64 {
              inherit lib final infuse;
              inherit (prev) name;
              inherit (final) tags;
            };
        }.${prev.canonical or ""} or [])
      ))

    (final: prev:
      lib.pipe site.hosts [
        (builtins.mapAttrs
          (name: host:
            host {
              inherit name;
              # FIXME: should fixpoint the whole site, not just site.hosts
              site.hosts = final;
              host = final.${name};
            })
        )
        (infuse prev)
      ])

  ] ++ (lib.pipe site.tags [
    (lib.filterAttrs (n: _: !(lib.hasPrefix "__" n)))
    (lib.mapAttrs
      (tag: overlay:
        (root.util.forall-hosts'
          (name: host-final: host-prev:
            (
              #if site-nofixpoint.host.${name}.tags.${tag}
              #if host-final.tags.${tag}
              if host-prev.tags.${tag}
              then host-prev // overlay host-final host-prev
            else host-prev)
          ))))
    lib.attrValues
  ]) ++ [

    (hosts: prev:
      lib.flip lib.mapAttrs prev
        (_: host:
          host // {
            configuration = import ./configuration.nix {
              inherit yants lib infuse host;
              overlays = host.service-overlays or [];
              six = import ./six {
                inherit lib yants;
                inherit (host) pkgs;
                inherit extra-by-name-dirs;
              };
            };
          })
    )
  ];

in {

  host = lib.pipe overlays [

    # compose the extensions into a single (final: prev: ...)
    (lib.foldr lib.composeExtensions (_: _: {}))

    # tie the fixpoint knot
    (composed: lib.fix (final: composed final {}))

    # typecheck the result
    (lib.mapAttrs (hostName: host: root.types.host host))
  ];

}
