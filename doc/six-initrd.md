# six-initrd – Advanced Initial RAM Disk Builder for Nix

**six-initrd** is a sophisticated Nix-based toolkit for creating custom initramfs (initial RAM filesystem) images. It's designed specifically for building custom Linux boot environments, rescue systems, and specialized ISOs with precise control over the early boot process.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Usage with Flakes](#usage-with-flakes)
- [API Reference](#api-reference)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

## Overview

### What is six-initrd?

six-initrd provides two main components:

1. **`minimal.nix`** - A comprehensive, configurable initramfs builder
2. **`abduco.nix`** - An advanced overlay for sophisticated early-boot process management

### Key Features

- **Declarative Configuration** - Everything defined in pure Nix
- **Flexible Content System** - Add files, scripts, symlinks via attribute sets
- **Multi-Console Support** - Handle both serial and display consoles elegantly
- **Process Management** - Robust PID1 handling with abduco terminal multiplexing
- **Modular Design** - Overlay pattern allows easy customization
- **Kernel Module Support** - Include specific kernel modules as needed
- **Compression Options** - Optional gzip compression of final initramfs

### Licensing

GPL v2 or v3 (user's choice) - see `COPYING/` directory for full license texts.

## Architecture

### Core Components

```
six-initrd/
├── default.nix     # Main entry point - exports minimal and abduco
├── minimal.nix     # Base initramfs builder (162 lines)
├── abduco.nix      # Advanced process management overlay (172 lines)
└── COPYING/        # License files (GPL v2/v3)
```

### Design Philosophy

- **Single Responsibility** - Each component has a clear, focused purpose
- **Composability** - Use overlays and the override pattern for customization
- **Robustness** - Handle edge cases and failure modes gracefully
- **Flexibility** - Support a wide range of use cases from minimal rescue to complex boot scenarios

## Usage with Flakes

`six-initrd` is a flake that exposes its builders as library functions. You can use it in your own `flake.nix` to create a custom initramfs derivation.

### 1. Add `six-initrd` to your inputs:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    six-initrd.url = "github:g-structure/six-initrd";
  };

  outputs = { self, nixpkgs, six-initrd, ... }:
    # ...
}
```

### 2. Build a custom initramfs:

The `minimal` builder creates a basic initramfs. You can use its `override` attribute to inject your own files and scripts.

```nix
# flake.nix (outputs)
let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};

  # Create an initrd with a custom boot script.
  myInitrd = six-initrd.lib.${system}.minimal.override {
    contents = {
      # This script will be executed as the init process (PID 1).
      "/init" = pkgs.writeShellScript "initrd-init" ''
        #!${pkgs.busybox}/bin/sh
        echo "Hello from the custom initramfs!"

        # Mount essential filesystems
        /bin/mount -t proc proc /proc
        /bin/mount -t sysfs sysfs /sys
        /bin/mount -t devtmpfs dev /dev

        echo "Dropping to a shell. Type 'poweroff' to exit."
        /bin/sh

        # Clean shutdown
        /bin/mount -o remount,ro /
        /bin/poweroff -f
      '';
    };
  };
in
{
  packages.${system}.default = myInitrd;
}
```

### 3. Using `abduco` for multi-console output:

For more advanced use cases, such as mirroring the boot process on both a VGA console and a serial port, you can use the `abduco` helper. It provides a pre-configured set of scripts to manage a multiplexed console session.

```nix
# flake.nix (outputs)
let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};

  # Get the scripts and configuration for a multiplexed console.
  abducoContents = six-initrd.lib.${system}.abduco {
    ttys = {
      tty0 = null;      # VGA console
      ttyS0 = "115200"; # Serial console at 115200 baud
    };
  };

  # Create an initrd that uses the abduco console.
  myInitrd = six-initrd.lib.${system}.minimal.override {
    # Combine the abduco contents with your custom boot scripts.
    contents = abducoContents // {
      # This script runs inside the abduco session.
      "early/run" = pkgs.writeShellScript "run-script" ''
        #!${pkgs.busybox}/bin/sh
        echo "This is visible on both tty0 and ttyS0."
        echo "Dropping to a shell."
        /bin/sh
        # Exit with 0 to proceed to /early/finish
        exit 0
      '';

      # This runs after early/run exits successfully.
      "early/finish" = pkgs.writeShellScript "finish-script" ''
        #!${pkgs.busybox}/bin/sh
        echo "Boot process finished."
        /bin/poweroff -f
      '';

      # This runs if early/run exits with a non-zero code.
      "early/fail" = pkgs.writeShellScript "fail-script" ''
        #!${pkgs.busybox}/bin/sh
        echo "Boot process failed!"
        /bin/sh
      '';
    };
  };
in
{
  packages.${system}.default = myInitrd;
}
```

## API Reference

### `minimal.nix` Arguments

| Argument | Type | Default | Description |
|---|---|---|---|
| `lib` | Attrset | `pkgs.lib` | Nixpkgs library instance. |
| `pkgs` | Attrset | (required) | Nixpkgs instance. |
| `busybox` | Derivation | `pkgs.busybox` | The BusyBox package to include. Set to `null` to exclude. |
| `contents` | Attrset | `{}` | A set of files and directories to add to the initramfs. Keys are destination paths, values are source paths or derivations. |
| `compress` | String or Bool | `"gzip"` | Compression method (`"gzip"`, `"xz"`, etc.) or `false` to disable. |
| `kernel` | Derivation | `null` | A kernel package. If provided, its modules will be included. |
| `module-names` | List of Strings | `[]` | A list of kernel module filenames to include (e.g., `"ext4/ext4.ko"`). Requires `kernel` to be set. |

### `abduco.nix` Arguments

| Argument | Type | Default | Description |
|---|---|---|---|
| `lib` | Attrset | `pkgs.lib` | Nixpkgs library instance. |
| `pkgs` | Attrset | (required) | Nixpkgs instance. |
| `abduco` | Derivation | `pkgs.abduco` | The abduco package. |
| `busybox` | Derivation | `pkgs.busybox` | The BusyBox package. **Required** for the generated scripts. |
| `ttys` | Attrset | `{ tty0 = null; }` | An attribute set mapping console device names (e.g., `"ttyS0"`) to a baud rate string or `null`. |
| `getty` | Derivation | `busybox` | The package providing the `getty` command. |
| `mdev` | Derivation | `busybox` | The package providing the `mdev` command. |
| `cttyhack` | Derivation | `busybox` | The package providing the `cttyhack` command. |
| `setsid` | Derivation | `busybox` | The package providing the `setsid` command. |
| `final-sleeptime-ms` | Integer | `3000` | Milliseconds to sleep before powering off after `finish` or `fail` scripts. |
| `default-timezone` | String | `"PST8PDT,M3.2.0,M11.1.0"` | The `TZ` environment variable to set. |

## Common Patterns

### Creating a Rescue Image

```nix
let
  rescueInitrd = six-initrd.lib.${system}.minimal.override {
    contents = {
      "/init" = pkgs.writeShellScript "rescue" ''
        # ... mount filesystems, start sshd, etc. ...
        /bin/sh
      '';
      "/usr/bin/sshd" = "${pkgs.openssh}/bin/sshd";
      # ... add other rescue tools ...
    };
  };
in # ...
```

### Building a Bootable ISO with a Custom Initrd

You can use the `nixos-generators` project or a custom `mkDerivation` with `genisoimage` to package your `kernel` and custom `initrd` into a bootable ISO file. The implementation is specific to your bootloader (e.g., syslinux, grub) and is not covered here.

## Troubleshooting

- **"File not found" in init script**: Ensure the required binary is in your `contents` set. Remember that only BusyBox is included by default.
- **Kernel panic (no init found)**: Verify your `contents` attribute set includes a script at the path `/init`. If using `abduco`, ensure `early/run`, `early/finish`, and `early/fail` are defined.
- **Serial console not working**: Check that `console=ttyS0,...` is in your kernel command line and that the `ttys` attribute in `abduco` is configured correctly.

---

*This documentation covers six-initrd v1.0. For the latest updates and examples, see the SixOS project documentation.*

[SixOS – A Nix-based Operating System without systemd](sixos.md#sixos--a-nix-based-operating-system-without-systemd)

## Backlinks
- [SixOS – 8.1 Prerequisites and Dependencies](sixos.md#81-prerequisites-and-dependencies)
