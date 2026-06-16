# Alpenglow — TODO

## ✅ Done

### Ponytail audit (June 2026)
- [x] Delete 5 dead modules (state.rs, resolver.rs, timing.rs, sudo.rs, distro.rs)
- [x] netd: hand-rolled JSON → serde derives (352 LOC, -72)
- [x] error.rs: 14 variants → 6
- [x] signal.rs: 64 lines → 13
- [x] installer.rs: zero-field struct → free function
- [x] version.rs: 139 lines → 1 (dead code)
- [x] ui.rs: remove dead copy_dir_all
- [x] Remove 6 unused deps (shellexpand, urlencoding, regex, dunce, nix, libc)
- [x] Net: -551 LOC, -4 deps

### Kernel build + GlowFS
- [x] Fix KERNEL_BUILD=1 path (configure-kernel was never called)
- [x] GlowFS in-tree building in Linux 7.0 path
- [x] GlowFS in-tree building in custom kernel path
- [x] GlowFS Kconfig + CONFIG_GLOWFS=m enable

### Move kernel configs out of system/alpine/
- [x] Move kernel configs to system/backends/appliance/kernel/
- [x] Create appliance QEMU runner
- [x] Update all CI script references
- [x] CI qemu-appliance test passing

## 📋 Remaining

### High priority
- [ ] Real hardware boot (USB/SD card on x86_64 hardware)
- [ ] Full appliance QEMU boot with all services (display, audio, wifi)
- [ ] Build custom Linux 7.0 kernel with GlowFS end-to-end

### Medium
- [ ] Oil: support additional musl APK repos (Chimera, postmarketOS)
- [ ] Drop legacy Alpine reference backend once appliance reaches parity
- [ ] Cross-build for aarch64 from x86_64

### Low
- [ ] Real hardware boot documentation
- [ ] Automated release image builds (GitHub Actions)
