{
  # These arguments are expected to be provided by the flake.
  system,
  nixpkgs, # This is the package set, not a path
  lib,
  infuse,
  readTree,
  yants,
  six-initrd,

  # These are user-provided arguments, same as the legacy entrypoint.
  site,
  check-types ? true,
  extra-by-name-dirs ? [],
  extra-auto-args ? {},

  # Capture all arguments for passing to legacy functions.
  ...
}@args:


let yants' = yants; in
let
  # The original `default.nix` had a complex `nixpkgs` argument that was
  # a function for applying overlays. Here, we receive an already-evaluated
  # `pkgs` set from the flake, so we must extend it with our own overlays.
  pkgs = nixpkgs.extend (import ./pkgs/overlays.nix { inherit lib infuse; });

  # this "patches" the version of `lib` that is passed to `yants`, wrapping
  # `tryEval` around invocations of `lib.generators.toPretty`.
  yants = yants' {
    lib = infuse lib {

      generators.toPretty = old-toPretty:
        # The following is copy-pasted from infuse.nix, which uses this routine but
        # does not expose it (since doing so would make it part of the infuse API).
        #
        # This is a `throw`-tolerant version of toPretty, so that error diagnostics in
        # this file will print "<<throw>>" rather than triggering a cascading error.
        args: val:
        let
          try = builtins.tryEval (old-toPretty args val);
        in
          if try.success
          then try.value
          else "<<throw>>";
    };
  };

  # automatically-provided arguments (e.g. callPackage and readTree)
  auto-args = {
    inherit lib yants infuse readTree;
    inherit types;
    inherit (root) util;
    inherit root;
    inherit auto-args;
    inherit site;
    nixpkgs = pkgs; # Use the newly extended pkgs
  };

  # readTree invocation on the directory containing this file
  root = readTree.fix (self: (readTree {
    args = auto-args;
    path = ./.;
  }));

  # readTree invocation on the `site` directory
  site =
    let
      site-unchecked = root.util.maybe-invoke-readTree auto-args' args.site;
      auto-args' = auto-args // extra-auto-args // {
        site = site-unchecked;
        auto-args = auto-args';
      };
    in
      #types.site
        site-unchecked;

  types = root.types { inherit (site) tags; };

  overlays = [

    # initial host set: populate attrnames from site.hosts
    (site-final: site-prev:
      #types.site
        ({
          inherit (site) subnets overlay tags globals;
          # This is a copy of site.hosts built by passing in an attrset full of
          # `throw` values as the fixpoint argument.  This ensures that the
          # `canonical` and `name` fields of `final.hosts.${name}` do not depend
          # on the fixpoint.
          hosts =
            lib.mapAttrs
              (name: host-func:
                let
                  nofixpoint-host' = host-func {
                    inherit name;
                    inherit (nofixpoint-host) canonical tags;
                    host = site-final.hosts.${name};
                    host-prev = {};
                    #site = throw "immutable fields of host must not depend on the site argument";
                    site = site-final;
                    pkgs = throw "immutable fields of host must not depend on the pkgs argument";
                  };
                  q = nofixpoint-host' // {
                    inherit name;
                    tags = types.set-tag-values (nofixpoint-host'.tags or {});
                  };
                  nofixpoint-host = q // {
                    inherit (q) name canonical pkgs tags;
                    service-overlays = q.service-overlays or [];
                  };
                in nofixpoint-host
              )
              site.hosts;
        }))

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

    # default kernel setup
    (root.util.forall-hosts
      (host-name: final: prev:
        let
          mkKernelConsoleBootArg =
            { device
            , baud ? null }:
            "console=${device}"
            + lib.optionalString (baud!=null) ",${toString baud}";
        in infuse prev {
          boot.kernel.params   = _: [
            "root=LABEL=boot"
            "ro"
          ] ++ lib.optionals (final.boot?kernel.console) [
            (mkKernelConsoleBootArg final.boot.kernel.console)
          ];
          boot.kernel.modules  = _: "${final.boot.kernel.package}";
          boot.kernel.payload    = _: "${final.boot.kernel.package}/bzImage";
          boot.kernel.package  = _: final.pkgs.callPackage ./kernel.nix { };
        }
      ))

    # arch stage
    (root.util.forall-hosts
      (name: final: prev: infuse prev
        ({
          x86_64-unknown-linux-gnu =
            import ./arch/amd64 {
              inherit final infuse name;
            };
          mips64el-unknown-linux-gnuabi64 =
            import ./arch/mips64 {
              inherit final infuse name;
            };
          powerpc64le-unknown-linux-gnu =
            import ./arch/powerpc64 {
              inherit final infuse name;
            };
          aarch64-unknown-linux-gnu =
            import ./arch/arm64 {
              inherit lib final infuse name;
              inherit (prev) tags;   # FIXME: use final.tags
            };
          mips-unknown-linux-gnu = {};
          armv7-unknown-linux-gnueabi = {};
          "" = {};
        }."${final.pkgs.system}" or {})))

    # initrd stage
    (root.util.forall-hosts
      (name: final: prev: infuse prev {
        boot.initrd.package = six-initrd.minimal;
        boot.initrd.modules = final.boot.kernel.modules;
      }))

    # configuration.nix stage
    (root.util.forall-hosts
      (name: final: prev:
        let
          eval-config = import ./configuration.nix {
            inherit (final) pkgs;
            inherit lib;
            config = final;
          };
        in
          #types.eval-config
            eval-config
      ))

    # add `configuration` package containing the etc tree
    (root.util.forall-hosts
      (name: final: prev: {
        # This is a bit of a hack around an apparent bug in nix, which manifests
        # when a derivation has a name containing a `.` character when it also
        # has a name override.  The system-generated default name includes a
        # version number like `stage-2-2.0`, and this seems to cause problems.
        # Here we manually compute a name that doesn't include the problematic
        # character.
        configuration = final.pkgs.stdenv.mkDerivation {
          pname = "etc";
          version = "2.0";
          name = "${final.name}-${final.pname}-${final.version}";
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out/etc
            cp -r ${final.build.etc}/* $out/etc
          '';
        };
      }))

    site.overlay or (_: _: {})

  ];
in
  lib.fix (self: lib.foldr lib.pipe self overlays) 