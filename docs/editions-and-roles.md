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

## Measured 2026-08-25 (x86_64 Cloud Agent)

Host: Linux 6.12.94+ x86_64. `/dev/kvm` exists but is not writable by the runner. `qemu-system-x86_64` and Docker are missing, so `scripts/boot-native.sh`, `scripts/bench-boot.sh`, and `scripts/ci-qemu-appliance.sh` did not run. No kernel, initramfs, ISO, or `img.zst` was built.

What was measured: `scripts/edition-resolve.sh --demo` plus `configure-rootfs.sh` per public SKU (world package count, dinit `depends-on` count). That is the cheapest honest artifact the tree can produce without Docker. Configured-rootfs tarballs were ~120 KiB for every SKU because they are overlay + policy files only, not a userspace image — those byte sizes are discarded as a SKU size metric.

| SKU | Kernel | Session | World pkgs | Boot depends | Boot to login | Initramfs | Image | RAM |
|-----|--------|---------|------------|--------------|---------------|-----------|-------|-----|
| `potato` | fast | none | 22 (`packages-potato.txt`) | 9 | not booted | not built | not built | not measured |
| `desktop` | desktop | alpenglowed | 53 (`packages-runtime.txt`) | 21 | not booted | not built | not built | not measured |
| `internet` | minimal | sold | 19 (`packages-internet.txt`) | 11 | not booted | not built | not built | not measured |

`fast` and `minimal` resolve to the potato row (same SKU, world, kernel, session). `standard` stays potato + toolchain (`packages-standard.txt`, 38 pkgs) and is not a public SKU.

Boot-to-login, initramfs size, and RAM need `build/native/vmlinuz` plus an initramfs, then `scripts/bench-boot.sh` on a KVM-writable QEMU host (lab: ultramarine). This run could not produce those numbers.

Zig tools measured on this host (Zig 0.16.0, `-Drelease=true` / `-O ReleaseSmall`, not SKU images): `init` 4912 B (x86_64 and aarch64); `alpenglow-ctl` multicall 163032 B (x86_64 musl), `alpenglow-kernelctl` 161408 B (aarch64 musl).
