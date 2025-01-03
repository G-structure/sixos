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

}:

let
  root = readTree.fix (self: (readTree {
    args = {
      root = self;
      inherit yants lib infuse sw util readTree;
      inherit (site) tags;
    };
    path = ./.;
  }));

  inherit (root) util;
  
  # attrset mapping each gnu-config canonical name to the outpath
  # which will be used as /run/current-system/sw (what NixOS calls
  # `environment.systemPackages`)
  sw = { };

  # why, oh why, does nix not allow shadowing?
  site' = site { inherit lib util yants infuse sw readTree; };
in let

  site = site' // {
    hosts = util.maybe-invoke-readTree { inherit lib yants infuse sw util; } site'.hosts;
    tags  = util.maybe-invoke-readTree { inherit lib yants infuse sw util; } site'.tags;
  };

  root = readTree.fix (self: (readTree {
    args = {
      root = self;
      inherit yants lib infuse sw util;
      inherit (site) tags;
    };
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
    (util.forall-hosts (final: prev:
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
  ] ++ (import ./boot.nix {
    inherit lib infuse six-initrd util;
  }) ++ [

    # arch stage
    (util.forall-hosts
      (final: prev: infuse prev
        ({
          mips64el-unknown-linux-gnuabi64 =
            import ./arch/mips64 {
              inherit sw final infuse;
              inherit (prev) name;
            };
          powerpc64le-unknown-linux-gnu =
            import ./arch/powerpc64 {
              inherit sw final infuse;
              inherit (prev) name;
            };
          aarch64-unknown-linux-gnu =
            import ./arch/arm64 {
              inherit lib sw final infuse;
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
        (util.forall-hosts
          (final: prev:
            if prev.tags.${tag}      # no `or` here; if attrs are missing it causes infinite recursion
            then overlay final prev
            else prev
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
