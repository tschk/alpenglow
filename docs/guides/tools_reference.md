# Tools Reference

- `./install.sh --check` runs the main readiness gate.
- `system/appliance/scripts/select-backend.sh` prints the active backend directory.
- `system/backends/void/scripts/build-rootfs.sh` builds the Void musl/runit rootfs when `xbps-install` or `VOID_ROOTFS_TARBALL` is available.
- `system/alpine/scripts/qemu-v0.sh` runs the current Alpine reference image path.
- `system/alpine/scripts/stage-alpenglow-artifacts.sh` stages Linux runtime binaries, GlowFS module, and `bundle/` into the rootfs.
- `system/alpine/scripts/build-glowfs-module.sh` builds the GlowFS kernel module against Alpine `linux-virt-dev`.
