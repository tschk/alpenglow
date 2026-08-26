# Editions and roles

One OS. Three public SKUs. Source: [`editions.toml`](../editions.toml), [`scripts/edition-resolve.sh`](../scripts/edition-resolve.sh).

| SKU | Userspace | Kernel | Session | World |
|-----|-----------|--------|---------|-------|
| `potato` | minimal | fast | none | `packages-potato.txt` |
| `desktop` | desktop | desktop | alpenglowed | `packages-runtime.txt` |
| `internet` | minimal | minimal | sold | `packages-internet.txt` |

`potato` is the small OS: the old `fast` + `minimal` cut in one name (Zig init / fast kernel, appliance net, SSH, time, logs, DNS, OOM). Skinny GUI packages (`alpenglowed-lite`) may be on that world; they stay stopped unless `ALPENGLOW_SESSION=alpenglowed`. Potato is not a fourth lite-desktop edition beside fast and minimal.

```sh
ALPENGLOW_EDITION=potato
ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1
ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1
ALPENGLOW_ARTIFACT=tar sh scripts/export-container.sh
sh scripts/edition-resolve.sh --list
```

`ALPENGLOW_SKU` is always `potato|desktop|internet`. Board (RK3566) is a kernel fragment, not a SKU.

Aliases and flags (not public SKUs):

- `fast`, `minimal` — resolve to `potato` (same image family)
- `standard` — `potato` plus the toolchain world (`BUILD_PROFILE=standard`, `packages-standard.txt`)
- `kiosk` — `internet` plus lock (`ALPENGLOW_KIOSK=1` / `ALPENGLOW_SESSION=cage`)
- `fleet` — `ALPENGLOW_FLEET=1` on desktop (no agent in tree)
- `container` — potato artifact (`scripts/export-container.sh` / `ALPENGLOW_ARTIFACT=oci|tar`)
- `potatoes`, `desktop-lite`, `embedded`, `containers` — resolve to `potato`
- `desktop-full`, `workstation` — resolve to `desktop`

Default SKU is `potato`. `--list` prints only the three public names.

Alpenglowed is a Cage Wayland client. potato skinny GUI: `cargo build --release --no-default-features`. desktop: `cargo build --release`. `--features compositor` is experimental and is not in the image. Contract: [alpenglowed#2](https://github.com/tschk/alpenglowed/pull/2).

Release names: `alpenglow-v0.1.n-{potato|desktop|internet}-arch.{iso,img.zst}` and `alpenglow-v0.1.n-potato-arch.tar`. RISC-V boot bundle: `alpenglow-v0.1.n-potato-riscv64.tar.zst`.

## Measured 2026-08-26 (x86_64 Cloud Agent, QEMU TCG)

Host: Linux 6.12.94+ x86_64, 4 vCPU, 15 GiB RAM. Installed `qemu-system-x86` and `qemu-system-arm` 8.2.2 via apt. Docker was **not** installed. toybox 0.8.11, dinit 0.19.2, and Linux 7.1.3 were compiled on the host. `/dev/kvm` is writable via group `rdma`; QEMU `accel=kvm` produced empty serial output on this nested hypervisor, so those boots are discarded. All boot numbers below are **QEMU TCG**.

`ALPENGLOW_EDITION=potato` `BUILD_ONLY=1` composed the initramfs (`scripts/boot-native.sh`). The FAST kernel was built with the same config as `build-kernel-fast.sh` (embedded lz4 initramfs) without Docker. Boot: `scripts/bench-boot.sh ACCEL=tcg MACHINE=pc` and `MACHINE=q35`.

| SKU | Boot to login | Kernel | Initramfs | Image | RAM at login |
|-----|---------------|--------|-----------|-------|--------------|
| `potato` | **1017 ms** (pc), **1018 ms** (q35) | 8610816 B (8.3 MiB) Linux 7.1.3 FAST, embeds initramfs | 3718491 B (3.6 MiB lz4, 124 files) | no ISO/`img.zst` | not sampled (`quiet` hides `Memory:`; no `/proc/meminfo` on console) |
| `desktop` | not booted | not built | not built | not built | not measured |
| `internet` | not booted | not rebuilt (`KERNEL_PROFILE=minimal` needs a second compile) | 3716444 B compose without `sold` | not built | not measured |

potato extra: n=3 TCG `pc` with explicit `-initrd` (not the embedded-only `bench-boot` path) was 1125 / 1126 / 1126 ms. One non-quiet TCG boot printed kernel-early `Memory: 2036700K/2096632K available` (2048 MiB VM) — that is not idle RAM at login.

desktop was not built: `GRAPHICAL=1` needs Docker for alpenglowed and Mesa. internet compose is the same toybox/dinit headless rootfs as potato; `sold` is not in-tree.

## Measured 2026-08-25 (contract only)

`scripts/edition-resolve.sh --demo` plus `configure-rootfs.sh` (world package count, dinit `depends-on`). Overlay-only tarballs (~120 KiB) are not image sizes.

| SKU | Kernel | Session | World pkgs | Boot depends |
|-----|--------|---------|------------|--------------|
| `potato` | fast | none | 22 (`packages-potato.txt`) | 9 |
| `desktop` | desktop | alpenglowed | 53 (`packages-runtime.txt`) | 21 |
| `internet` | minimal | sold | 19 (`packages-internet.txt`) | 11 |

`fast` and `minimal` resolve to the potato row. `standard` is potato + toolchain (`packages-standard.txt`, 38 pkgs), not a public SKU.

Zig tools (2026-08-25, Zig 0.16.0, not SKU images): `init` 4912 B (x86_64 and aarch64); `alpenglow-ctl` multicall 163032 B (x86_64 musl).
