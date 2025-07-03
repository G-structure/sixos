# Nix Overlays - Overrides

https://wiki.nixos.org/wiki/Overlays
https://nixos.org/manual/nixpkgs/stable/#chap-overlays 
https://flyingcircus.io/en/about-us/blog-news/details-view/nixos-the-dos-and-donts-of-nixpkgs-overlays


## Nixpkgs Documentation: Overlays and Overrides

### Table of Contents

- [Installing overlays](#installing-overlays)
- [Defining overlays](#defining-overlays)
- [Using overlays to configure alternatives](#using-overlays-to-configure-alternatives)
- [Overriding](#overriding)

## Overlays

This chapter describes how to extend and change Nixpkgs using overlays. Overlays are used to add layers in the fixed-point used by Nixpkgs to compose the set of all packages.

Nixpkgs can be configured with a list of overlays, which are applied in order. This means that the order of the overlays can be significant if multiple layers override the same package.

### Installing overlays

#### Set overlays in NixOS or Nix expressions
#### Install overlays via configuration lookup

The list of overlays can be set either explicitly in a Nix expression, or through `<nixpkgs-overlays>` or user configuration files.

#### Set overlays in NixOS or Nix expressions

On a NixOS system the value of the `nixpkgs.overlays` option, if present, is passed to the system Nixpkgs directly as an argument. Note that this does not affect the overlays for non-NixOS operations (e.g. `nix-env`), which are looked up independently.

The list of overlays can be passed explicitly when importing nixpkgs, for example:

```nix
import <nixpkgs> { overlays = [ overlay1 overlay2 ]; }
```

> **NOTE:** DO NOT USE THIS in nixpkgs. Further overlays can be added by calling the `pkgs.extend` or `pkgs.appendOverlays`, although it is often preferable to avoid these functions, because they recompute the Nixpkgs fixpoint, which is somewhat expensive to do.

#### Install overlays via configuration lookup

The list of overlays is determined as follows:

1. First, if an `overlays` argument to the Nixpkgs function itself is given, then that is used and no path lookup will be performed.

2. Otherwise, if the Nix path entry `<nixpkgs-overlays>` exists, we look for overlays at that path, as described below.

   See the section on `NIX_PATH` in the Nix manual for more details on how to set a value for `<nixpkgs-overlays>`.

3. If one of `~/.config/nixpkgs/overlays.nix` and `~/.config/nixpkgs/overlays/` exists, then we look for overlays at that path, as described below. It is an error if both exist.

If we are looking for overlays at a path, then there are two cases:

- If the path is a file, then the file is imported as a Nix expression and used as the list of overlays.

- If the path is a directory, then we take the content of the directory, order it lexicographically, and attempt to interpret each as an overlay by:
  - Importing the file, if it is a `.nix` file.
  - Importing a top-level `default.nix` file, if it is a directory.

Because overlays that are set in NixOS configuration do not affect non-NixOS operations such as `nix-env`, the `overlays.nix` option provides a convenient way to use the same overlays for a NixOS system configuration and user configuration: the same file can be used as `overlays.nix` and imported as the value of `nixpkgs.overlays`.

### Defining overlays

Overlays are Nix functions which accept two arguments, conventionally called `self` and `super`, and return a set of packages. For example, the following is a valid overlay:

```nix
self: super:

{
  boost = super.boost.override {
    python = self.python3;
  };
  rr = super.callPackage ./pkgs/rr {
    stdenv = self.stdenv_32bit;
  };
}
```

The first argument (`self`) corresponds to the final package set. You should use this set for the dependencies of all packages specified in your overlay. For example, all the dependencies of `rr` in the example above come from `self`, as well as the overridden dependencies used in the `boost` override.

The second argument (`super`) corresponds to the result of the evaluation of the previous stages of Nixpkgs. It does not contain any of the packages added by the current overlay, nor any of the following overlays. This set should be used either to refer to packages you wish to override, or to access functions defined in Nixpkgs. For example, the original recipe of `boost` in the above example, comes from `super`, as well as the `callPackage` function.

The value returned by this function should be a set similar to `pkgs/top-level/all-packages.nix`, containing overridden and/or new packages.

Overlays are similar to other methods for customizing Nixpkgs, in particular the `packageOverrides` attribute described in the section called "Modify packages via packageOverrides". Indeed, `packageOverrides` acts as an overlay with only the `super` argument. It is therefore appropriate for basic use, but overlays are more powerful and easier to distribute.

### Using overlays to configure alternatives

#### BLAS/LAPACK
#### Switching the MPI implementation

Certain software packages have different implementations of the same interface. Other distributions have functionality to switch between these. For example, Debian provides DebianAlternatives. Nixpkgs has what we call alternatives, which are configured through overlays.

#### BLAS/LAPACK

In Nixpkgs, we have multiple implementations of the BLAS/LAPACK numerical linear algebra interfaces. They are:

**OpenBLAS**

The Nixpkgs attribute is `openblas` for ILP64 (integer width = 64 bits) and `openblasCompat` for LP64 (integer width = 32 bits). `openblasCompat` is the default.

**LAPACK reference (also provides BLAS and CBLAS)**

The Nixpkgs attribute is `lapack-reference`.

**Intel MKL (only works on the x86_64 architecture, unfree)**

The Nixpkgs attribute is `mkl`.

**BLIS**

BLIS, available through the attribute `blis`, is a framework for linear algebra kernels. In addition, it implements the BLAS interface.

**AMD BLIS/LIBFLAME (optimized for modern AMD x86_64 CPUs)**

The AMD fork of the BLIS library, with attribute `amd-blis`, extends BLIS with optimizations for modern AMD CPUs. The changes are usually submitted to the upstream BLIS project after some time. However, AMD BLIS typically provides some performance improvements on AMD Zen CPUs. The complementary AMD LIBFLAME library, with attribute `amd-libflame`, provides a LAPACK implementation.

Introduced in PR #83888, we are able to override the `blas` and `lapack` packages to use different implementations, through the `blasProvider` and `lapackProvider` argument. This can be used to select a different provider. BLAS providers will have symlinks in `$out/lib/libblas.so.3` and `$out/lib/libcblas.so.3` to their respective BLAS libraries. Likewise, LAPACK providers will have symlinks in `$out/lib/liblapack.so.3` and `$out/lib/liblapacke.so.3` to their respective LAPACK libraries. For example, Intel MKL is both a BLAS and LAPACK provider. An overlay can be created to use Intel MKL that looks like:

```nix
self: super:

{
  blas = super.blas.override {
    blasProvider = self.mkl;
  };

  lapack = super.lapack.override {
    lapackProvider = self.mkl;
  };
}
```

This overlay uses Intel's MKL library for both BLAS and LAPACK interfaces. Note that the same can be accomplished at runtime using `LD_LIBRARY_PATH` of `libblas.so.3` and `liblapack.so.3`. For instance:

```bash
LD_LIBRARY_PATH=$(nix-build -A mkl)/lib${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH nix-shell -p octave --run octave
```

Intel MKL requires an openmp implementation when running with multiple processors. By default, `mkl` will use Intel's `iomp` implementation if no other is specified, but this is a runtime-only dependency and binary compatible with the LLVM implementation. To use that one instead, Intel recommends users set it with `LD_PRELOAD`. Note that `mkl` is only available on `x86_64-linux` and `x86_64-darwin`. Moreover, Hydra is not building and distributing pre-compiled binaries using it.

To override `blas` and `lapack` with its reference implementations (i.e. for development purposes), one can use the following overlay:

```nix
self: super:

{
  blas = super.blas.override {
    blasProvider = self.lapack-reference;
  };

  lapack = super.lapack.override {
    lapackProvider = self.lapack-reference;
  };
}
```

For BLAS/LAPACK switching to work correctly, all packages must depend on `blas` or `lapack`. This ensures that only one BLAS/LAPACK library is used at one time. There are two versions of BLAS/LAPACK currently in the wild, LP64 (integer size = 32 bits) and ILP64 (integer size = 64 bits). The attributes `blas` and `lapack` are LP64 by default. Their ILP64 version are provided through the attributes `blas-ilp64` and `lapack-ilp64`. Some software needs special flags or patches to work with ILP64. You can check if ILP64 is used in Nixpkgs with `blas.isILP64` and `lapack.isILP64`. Some software does NOT work with ILP64, and derivations need to specify an assertion to prevent this. You can prevent ILP64 from being used with the following:

```nix
{
  stdenv,
  blas,
  lapack,
  ...
}:

assert (!blas.isILP64) && (!lapack.isILP64);

stdenv.mkDerivation {
  # ...
}
```

#### Switching the MPI implementation

All programs that are built with MPI support use the generic attribute `mpi` as an input. At the moment Nixpkgs natively provides two different MPI implementations:

- **Open MPI (default)**, attribute name `openmpi`
- **MPICH**, attribute name `mpich`
- **MVAPICH**, attribute name `mvapich`

To provide MPI enabled applications that use MPICH, instead of the default Open MPI, use the following overlay:

```nix
self: super:

{
  mpi = self.mpich;
}
```

## Overriding

### Table of Contents

- [`<pkg>.override`](#pkg-override)
- [`<pkg>.overrideAttrs`](#pkg-overrideattrs)
- [`<pkg>.overrideDerivation`](#pkg-overridederivation)
- [`lib.makeOverridable`](#lib-makeoverridable)

Sometimes one wants to override parts of nixpkgs, e.g. derivation attributes, the results of derivations.

These functions are used to make changes to packages, returning only single packages. Overlays, on the other hand, can be used to combine the overridden packages across the entire package set of Nixpkgs.

### `<pkg>.override`

The function `override` is usually available for all the derivations in the nixpkgs expression (`pkgs`).

It is used to override the arguments passed to a function.

Example usages:

```nix
pkgs.foo.override {
  arg1 = val1;
  arg2 = val2; # ...
}
```

It's also possible to access the previous arguments:

```nix
pkgs.foo.override (previous: {
  arg1 = previous.arg1; # ...
})
```

```nix
import pkgs.path {
  overlays = [
    (self: super: {
      foo = super.foo.override { barSupport = true; };
    })
  ];
}
```

```nix
{
  mypkg = pkgs.callPackage ./mypkg.nix {
    mydep = pkgs.mydep.override {
      # ...
    };
  };
}
```

In the first example, `pkgs.foo` is the result of a function call with some default arguments, usually a derivation. Using `pkgs.foo.override` will call the same function with the given new arguments.

Many packages, like the `foo` example above, provide package options with default values in their arguments, to facilitate overriding. Because it's not usually feasible to test that packages build with all combinations of options, you might find that a package doesn't build if you override options to non-default values.

Package maintainers are not expected to fix arbitrary combinations of options. If you find that something doesn't work, please submit a fix, ideally with a regression test. If you want to ensure that things keep working, consider becoming a maintainer for the package.

### `<pkg>.overrideAttrs`

The function `overrideAttrs` allows overriding the attribute set passed to a `stdenv.mkDerivation` call, producing a new derivation based on the original one. This function is available on all derivations produced by the `stdenv.mkDerivation` function, which is most packages in the nixpkgs expression `pkgs`.

Example usages:

```nix
{
  helloBar = pkgs.hello.overrideAttrs (
    finalAttrs: previousAttrs: {
      pname = previousAttrs.pname + "-bar";
    }
  );
}
```

In the above example, "-bar" is appended to the `pname` attribute, while all other attributes will be retained from the original `hello` package.

The argument `previousAttrs` is conventionally used to refer to the attr set originally passed to `stdenv.mkDerivation`.

The argument `finalAttrs` refers to the final attributes passed to `mkDerivation`, plus the `finalPackage` attribute which is equal to the result of `mkDerivation` or subsequent `overrideAttrs` calls.

If only a one-argument function is written, the argument has the meaning of `previousAttrs`.

Function arguments can be omitted entirely if there is no need to access `previousAttrs` or `finalAttrs`:

```nix
{
  helloWithDebug = pkgs.hello.overrideAttrs {
    separateDebugInfo = true;
  };
}
```

In the above example, the `separateDebugInfo` attribute is overridden to be `true`, thus building debug info for `helloWithDebug`.

> **Note:** `separateDebugInfo` is processed only by the `stdenv.mkDerivation` function, not the generated, raw Nix derivation. Thus, using `overrideDerivation` will not work in this case, as it overrides only the attributes of the final derivation. It is for this reason that `overrideAttrs` should be preferred in (almost) all cases to `overrideDerivation`, i.e. to allow using `stdenv.mkDerivation` to process input arguments, as well as the fact that it is easier to use (you can use the same attribute names you see in your Nix code, instead of the ones generated (e.g. `buildInputs` vs `nativeBuildInputs`), and it involves less typing).

### `<pkg>.overrideDerivation`

> **Warning:** You should prefer `overrideAttrs` in almost all cases, see its documentation for the reasons why. `overrideDerivation` is not deprecated and will continue to work, but is less nice to use and does not have as many abilities as `overrideAttrs`.

> **Warning:** Do not use this function in Nixpkgs as it evaluates a derivation before modifying it, which breaks package abstraction. In addition, this evaluation-per-function application incurs a performance penalty, which can become a problem if many overrides are used. It is only intended for ad-hoc customisation, such as in `~/.config/nixpkgs/config.nix`.

The function `overrideDerivation` creates a new derivation based on an existing one by overriding the original's attributes with the attribute set produced by the specified function. This function is available on all derivations defined using the `makeOverridable` function. Most standard derivation-producing functions, such as `stdenv.mkDerivation`, are defined using this function, which means most packages in the nixpkgs expression, `pkgs`, have this function.

Example usage:

```nix
{
  mySed = pkgs.gnused.overrideDerivation (oldAttrs: {
    name = "sed-4.2.2-pre";
    src = fetchurl {
      url = "ftp://alpha.gnu.org/gnu/sed/sed-4.2.2-pre.tar.bz2";
      hash = "sha256-MxBJRcM2rYzQYwJ5XKxhXTQByvSg5jZc5cSHEZoB2IY=";
    };
    patches = [ ];
  });
}
```

In the above example, the `name`, `src`, and `patches` of the derivation will be overridden, while all other attributes will be retained from the original derivation.

The argument `oldAttrs` is used to refer to the attribute set of the original derivation.

> **Note:** A package's attributes are evaluated before being modified by the `overrideDerivation` function. For example, the `name` attribute reference in `url = "mirror://gnu/hello/${name}.tar.gz";` is filled-in before the `overrideDerivation` function modifies the attribute set. This means that overriding the `name` attribute, in this example, will not change the value of the `url` attribute. Instead, we need to override both the `name` and `url` attributes.

### `lib.makeOverridable`

The function `lib.makeOverridable` is used to make the result of a function easily customizable. This utility only makes sense for functions that accept an argument set and return an attribute set.

Example usage:

```nix
{
  f =
    { a, b }:
    {
      result = a + b;
    };
  c = lib.makeOverridable f {
    a = 1;
    b = 2;
  };
}
```

The variable `c` is the value of the `f` function applied with some default arguments. Hence the value of `c.result` is 3, in this example.

The variable `c` however also has some additional functions, like `c.override` which can be used to override the default arguments. In this example the value of `(c.override { a = 4; }).result` is 6.