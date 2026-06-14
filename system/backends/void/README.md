# Void Musl Runit Backend

This backend is the active Soliloquy base-system target. It follows the shared appliance contract while using Void musl packages and runit services.

The design borrows from Oasis by treating the deployed system as a composed root filesystem rather than a mutable general-purpose installation. Void provides the practical bootstrap, package repository, and shared-library surface needed by Servo, V8, Wayland, GPU, and media components.

Backend properties:

- base: Void Linux
- libc: musl
- init: runit
- package manager: XBPS during image composition
- installer bridge: `../oil` through the Wax system package interface
- deployed model: immutable rootfs plus `/state`

Use `system/appliance/scripts/select-backend.sh` to resolve the active backend.

`scripts/build-rootfs.sh` bootstraps the base rootfs with XBPS. Set `SOLILOQUY_OIL_SYSTEM_PACKAGES` to a space-separated package list when extra image packages should be installed through the Oil bridge:

```sh
OIL_BUILD=1 SOLILOQUY_OIL_SYSTEM_PACKAGES="ripgrep" ./system/backends/void/scripts/build-rootfs.sh
```

That path is intentionally for additions. The base Void musl and runit image remains XBPS-backed until Oil has a Void registry backend.
