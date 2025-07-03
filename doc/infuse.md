# Infuse – Deep Attribute Surgery for Nix

Infuse is a tiny, **self-contained** Nix library by Adam M. Joseph (`amjoseph`) that lets you _deeply_ modify attrsets, lists, and even functions while preserving the algebraic laws they obey.  It replaces most hand-written `//` merges, `lib.pipe` chains, and the noisy combination of `.override` + `.overrideAttrs`.

> TL;DR Think of it as a lightweight, untyped alternative to the NixOS module system that you can drop anywhere – overlays, flakes, home-manager configs, scripts, …

---

## 1  Why would I reach for Infuse?

• You need to tweak a derivation several levels deep (e.g. modify `passthru.xorgxrdp.configureFlags`) without writing a custom function.  
• You want something more expressive than `lib.recursiveUpdate` but *way* lighter than `lib.modules`.  
• You would like one operator that works on attrsets, lists **and** functions so you can compose patches programmatically.
• You need predictable algebraic behavior (identity and associativity laws) across all three non-finite Nix types.

If any of those ring true – Infuse is your friend.

---

## 2  Getting it into a project

As a self-contained flake, `infuse` can be added to your own `flake.nix` inputs.

```nix
# flake.nix
{
  inputs = {
    infuse.url = "github:g-structure/infuse.nix";
    # Or, if you use sixos, it's already an input:
    # sixos.inputs.infuse.follows = "infuse";
  };

  outputs = { self, nixpkgs, infuse, ... }:
    let
      # Get the infuse library function
      infuseLib = infuse.lib { inherit (nixpkgs) lib; };

      # Now use it to modify a derivation
      modified-pkgs = pkgs.extend (final: prev:
        infuseLib.v1.infuse prev {
          some-package.__output.doCheck = _: false;
        }
      );
    in
      # ...
}
```

The library is self-contained – no other deps than `<nixpkgs/lib>`.

---

## 3  Mental model in 60 seconds

1. **Infusion** = a value whose *leaves are functions* (it can itself be a
   function, an attrset, or a list).  
2. `infuse target infusion` walks both trees simultaneously.
   • At a **function leaf**: call it with the previous value (or a sentinel if
   it was missing).  
   • At an **attrset node**: merge recursively.
3. *Sugars* – double-underscore attributes – translate to real functions
   during **desugaring**.  They're just syntax sugar; you can always write the
   underlying function yourself.

### Default sugars cheat-sheet

**__assign = v**
- Overwrite, no questions asked

**__default = v**  
- Set `v` **only if** attribute is missing

**__init = v**
- Like `__default` but *throws* if attribute exists

**__prepend = v**
- String/list prefix

**__append = v**
- String/list suffix

**__input = f|inf**
- Shorthand for `.override`

**__output = f|inf**
- Shorthand for `.overrideAttrs`

**__underlay/overlay**
- Extend overlay chain before/after

**__infuse = inf**
- Recurse: `infuse target inf` at that point

You can extend/override the sugar set via the `sugars` argument to
`import infuse.nix`.

---

## 4  Basic examples

```nix
# 1. Flip a flag deeply inside a derivation
xrdp.__input.systemd           = _: null;           # via .override
xrdp.__output.env.NIX_CFLAGS_COMPILE.__append = " -w";

# 2. Append to configureFlags of a nested passthru package
xrdp.__output.passthru.xorgxrdp.__output.configureFlags.__append = [
  "--without-fuse"
];

# 3. Work with Python overrides (packageOverrides is itself an overlay)
python311.__input.packageOverrides.__overlay.dnspython.__output.doCheck = _: false;

# 4. Treat lists and attrsets uniformly
infuse { x = 3; } [ { x = x: x*x; } (r: r.x + 1) ]  # ⇒ 10
```

---

## 5  Common patterns

• **Disable tests for many packages at once**
```nix
(final: prev: infuse prev {
  repoA.__output.doCheck = _: false;
  repoB.__output.doCheck = _: false;
})
```

• **Toggle optional dependencies** (example without PulseAudio/Systemd)
```nix
(final: prev: infuse prev {
  pulseaudioSupport = _: false;  # many derivations honour this name
  systemdSupport    = _: false;
  systemd           = _: null;   # for pkg expecting real drv
})
```

• **Construct overlay chains programmatically**
```nix
(overlaysToInject: prev: infuse prev {
  pythonPackages.__input.packageOverrides.__underlay = overlaysToInject;
})
```

---

## 6  Advanced Features

### 6.1  Custom Sugars

You can define your own double-underscore operators:

```nix
# First import Infuse normally to get access to the stock sugar list …
let
  baseInfuse = import ./infuse.nix { inherit lib; };

  # … then re-import with our additional sugar(s)
  infuse = import ./infuse.nix {
    inherit lib;
    sugars = baseInfuse.v1.default-sugars ++ [
      (nameValuePair "__concatStringsSep" (path: sep: target:
        lib.strings.concatStringsSep sep target))
    ];
  };
in

infuse { items = ["a" "b" "c"]; } { items.__concatStringsSep = "-"; }
# ⇒ { items = "a-b-c"; }
```

The two-step import avoids referencing `infuse` inside its own definition and works in all evaluation modes.

#### Verifying upstream checkouts

If you fetch Infuse from a git URL you can (optionally) pin and PGP-verify the commit as shown in the source file header:

```nix
(import (builtins.fetchGit {
  url       = "https://codeberg.org/amjoseph/infuse.nix";
  ref       = "refs/tags/v2.4";
  rev       = "";                # empty ⇒ use commit of the tag
  shallow   = true;
  publicKey = "F0B74D717CDE8412A3E0D4D5F29AC8080DA8E1E0";
  keytype   = "pgp-ed25519";
}) { inherit lib; }).v1.infuse
```

### 6.2  Desugaring and Optimization

- **Desugaring** converts all `__*` attributes into pure functions
- **Optimization** improves performance by flattening nested lists and merging contiguous attrsets
- **Pruning** removes "leafless" empty attrsets to avoid creating spurious attributes

```nix
# Available in the v1 API:
infuse.v1.desugar    # Convert sugared → desugared infusion
infuse.v1.optimize   # Optimize infusion for better performance
```

### 6.3  Error Handling

Infuse provides detailed error messages with full attribute paths:

```nix
# This will show: "infuse.flip-infuse-desugared-pruned: at path a.b.c: ..."
infuse target { a.b.c = "not a function"; }  # ERROR: non-function in desugared infusion
```

### 6.4  Missing Attribute Semantics

When infusing to missing attributes, Infuse uses a special marker system rather than `null` or throwing immediately. This preserves performance while allowing sugars like `__default` to work correctly.

---

## 7  Algebraic Laws & Semantics

Infuse preserves important mathematical properties:

**Identity Laws:**
- `infuse target {}` ≡ `target` (empty attrset)
- `infuse target []` ≡ `target` (empty list)  
- `infuse target id` ≡ `target` (identity function)

**Associativity Laws:**
- `infuse (infuse target a) b` ≡ `infuse target (a ++ b)` (for lists)
- `infuse (infuse target a) b` ≡ `infuse target (a // b)` (for attrsets, with proper merging)

These laws hold across all three non-finite Nix types: attrsets, lists, and functions.

---

## 8  Testing that your infusion does what you think

Infuse ships with a comprehensive test-suite that verifies all algebraic laws:

```bash
# In the infuse.nix directory:
just run-tests            # or nix-instantiate --eval tests/default.nix
```

If everything reduces to `true`, the algebraic laws still hold. The test suite includes:
- Identity and associativity law verification
- Sugar behavior testing  
- Real-world derivation modification examples
- Error condition testing

---

## 9  Performance Considerations

- **Leafless Attrset Pruning**: Empty nested attrsets are removed to avoid creating spurious attributes
- **Optimizer**: Flattens nested lists and merges contiguous attrsets for better performance
- **Missing Attribute Handling**: Uses an efficient marker system instead of expensive attrset wrapping
- **Thunk Sharing**: Implementation encourages sharing of intermediate computations

For performance-critical applications, consider using `optimize` on your infusions.

---

## 10  Resources & references

• Upstream repo + issues: <https://codeberg.org/amjoseph/infuse.nix>  
• 38C3 talk & commutative diagram: `infuse.nix/doc/commutative-diagram.md`  
• Example overlay (real-world): `infuse.nix/examples/amjoseph-overlays.nix`  
• Design notes (missing attrs, leafless sets): see `doc/` folder in repo.

It is used extensively throughout Adam's other projects:
    - [sixos](sixos.md)

Files to fetch:
    - [Infuse Readme](https://codeberg.org/amjoseph/infuse.nix/raw/branch/trunk/README.md)
    - [Commutative Diagram](https://codeberg.org/amjoseph/infuse.nix/raw/branch/trunk/doc/commutative-diagram.md)
    - [Design notes – leafless attrsets](https://codeberg.org/amjoseph/infuse.nix/raw/branch/trunk/doc/design-notes-leafless-attrsets.md)
    - [Design notes – missing attributes](https://codeberg.org/amjoseph/infuse.nix/raw/branch/trunk/doc/design-notes-on-missing-attributes.md)
    - [Example overlays using Infuse](https://codeberg.org/amjoseph/infuse.nix/raw/branch/trunk/examples/amjoseph-overlays.nix)

Happy infusing! ٩(◕‿◕｡)۶

## Backlinks
- [SixOS – 8.1 Prerequisites and Dependencies](sixos.md#81-prerequisites-and-dependencies)
