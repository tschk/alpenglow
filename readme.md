# Alpenglow

Diskless, hardened, immutable Linux appliance. GlowFS root, dinit init, LLVM/clang, Oil native packages, toybox userland. Runs from disk but loads entirely into RAM at boot.

Early-stage. Not production-ready.

## Design

| Layer | Choice |
|-------|--------|
| Boot model | **Diskless** — rootfs in RAM via initramfs. State on persistent media. |
| Root FS | **GlowFS** — custom kernel module. Fallback: erofs, squashfs. |
| Init | **dinit** — fast parallel dependency-graph init. |
| Compiler | **LLVM/Clang** default. Inauguration as future codegen. |
| Package mgr | **Oil** — native. No distro bootstrap. |
| Userland | **toybox** — minimal BSD-licensed coreutils. |
| Shell | **oksh** |
| Crypto | **BearSSL** |
| Kernel | **Hardened** — minimal appliance config. |
| Initramfs | **Custom** — best of Limine + UEFI stub + extlinux. |
| Arch | **Generic** — x86_64, aarch64, etc. |

## Repo layout

```
system/
  appliance/         Backend contract, selector, metadata
  backends/
    appliance/       Primary target (dinit, toybox, LLVM, Oil, diskless)
    void/            Void reference backend
  alpine/            Alpine reference backend (QEMU flow)
  glowfs/            GlowFS kernel module
  glowfsctl/         GlowFS image tooling
  kernelctl/         cgroup + kernel policy helpers
  netd/              Network state daemon
sold/                Local Axum system bridge
initramfs/           Custom boot initramfs
docs/                Architecture, build, install docs
```

## Build

```
cargo build
cargo test
```

Select and build the target appliance:

```sh
./system/appliance/scripts/select-backend.sh        # default: alpenglow-native
./system/backends/appliance/scripts/build-rootfs.sh  # build rootfs via Oil
```

Reference backends (Void, Alpine) still work for development:

```sh
./system/appliance/scripts/select-backend.sh void-musl-runit
./system/alpine/scripts/setup-host.sh
./system/alpine/scripts/qemu-v0.sh
```

## Testing

```
./install.sh --check
./scripts/ci-os-appliance.sh
./scripts/ci-glowfs-kernel-module.sh
./scripts/ci-rust-core.sh
cargo test -p sold
cargo test -p alpenglow-netd
cargo test -p alpenglow-kernelctl
cargo test -p glowfsctl
```
