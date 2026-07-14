# AGENTS.md — Alpenglow

Guide for humans and coding agents working in this repo.

## What Alpenglow is

Musl Linux distribution: **immutable root** loaded from initramfs (erofs/squashfs) into RAM, **mutable state** on bcachefs (`/state`, `/home` bind mounts). **dinit** PID 1, **toybox** userland, **oksh** on appliance, **Oil** package manager (APK payloads, Rust).

Early-stage; not production-hardened for arbitrary deployments.

## Non-negotiables for agents

- **JS/TS**: Bun only (no npm/yarn/pnpm).
- **Rust**: workspace under `system/oil`, kernel modules, installer crates — run `scripts/ci-rust-core.sh` before claiming done.
- **Zig**: `system/kernelctl-zig`, `netd-zig`, etc. — `scripts/ci-zig.sh` when touched.
- **Do not** pipe remote install scripts (`curl | sh`). Oil comes from **this tree**, **https://github.com/semitechnological/oil**, or the **undivisible/tap** index (`oil tap add undivisible/tap` → `https://github.com/undivisible/tap`). Not oil.sh.
- **CLAUDE.md** must stay a symlink to **AGENTS.md** (enforced in `scripts/ci-os-appliance.sh`).
- Preserve existing comments in files you edit; no license banners or drive-by reformatting.

## Design snapshot

| Area | Choice |
|------|--------|
| Boot | Initramfs → RAM root; Limine/UEFI on disk images |
| Init | dinit (parallel service graph) |
| Packages | Oil — sync HTTP, Alpine APK index + optional taps |
| Shell (appliance) | oksh |
| Shell (v86 browser demo) | bash (demo initramfs only) |
| Kernel | Profiles: `fast`, `minimal`, `desktop` — see `system/backends/appliance/kernel/` |
| Desktop | `BUILD_PROFILE=desktop` + [Alpenglowed](https://github.com/tschk/alpenglowed) (Wayland/Smithay) |
| Arch | x86_64 primary; branches for aarch64, riscv64, RK3566 |

**Build profiles** (`BUILD_PROFILE`): `minimal` (boot + SSH + time + logs), `standard` (+ tooling), `desktop` (+ graphics stack). **Editions** pair userspace profile with kernel profile — see root `readme.md`.

**Kernel profiles** ≠ build profiles: `fast` = smallest boot; `minimal` = networked appliance kernel; `desktop` = display/audio/WiFi firmware path.

Base image stays lean; VPN, extra daemons, etc. via `oil install` or `/usr/local`.

## Repo layout

```
system/
  oil/                 Package manager (Rust); recipes in recipes/
  backends/appliance/  Kernel configs, dinit units, rootfs scripts
  kernelctl-zig/       Kernel/cgroup policy (~72–89KB static)
  netd-zig/            Network daemon
  kernel-modules/      Rust modules (alpenglow_core, …)
scripts/               boot-native.sh, CI, v86 initramfs, release
docs/                  Architecture; docs/browser/ = v86 guest copy
public/v86/            Browser demo kernel + initrd artifacts
```

## Oil (agents)

- **In-tree build**: `OIL_BUILD=1 system/appliance/scripts/oil-installer.sh` or `cargo build -p oil --release` in `system/oil`.
- **Upstream source**: https://github.com/semitechnological/oil
- **Tap / binary channel**: `undivisible/tap` → https://github.com/undivisible/tap (`wax` is the user-facing name for the oil binary in some paths).
- **CLI**: short aliases on subcommands (`oil i`, `oil up`, `oil rm`, …) — defined in `system/oil/src/main.rs`.
- **Recipes**: declarative `.yml` under `system/oil/recipes/`.

## Common commands

```sh
./scripts/boot-native.sh                    # build + QEMU boot
./scripts/ci-rust-core.sh
./scripts/ci-zig.sh                         # if zig installed
./scripts/ci-os-appliance.sh
sh scripts/build-v86-initramfs.sh           # browser i686 initrd → public/v86/
cargo test -p oil
```

Release tags use `v0.1.<git rev-list --count HEAD>`.

`KERNEL_BUILD=1`, `BUILD_PROFILE=desktop`, `ALPENGLOW_EDITION=…` — see `readme.md` and `docs/`.

## CI gates

| Gate | Script |
|------|--------|
| Rust | `scripts/ci-rust-core.sh` |
| Zig | `scripts/ci-zig.sh` |
| Appliance contract | `scripts/ci-os-appliance.sh` |
| Boot bench | `scripts/bench-boot.sh` (needs image) |

## SSH lab hosts (optional)

| Host | IP | Notes |
|------|-----|--------|
| ultramarine | 192.168.4.134 | x86_64, WSL2, zig, docker, qemu+kvm |
| chimera | 192.168.4.168 | musl, kvm; no zig/docker |

Alpenglow targets **musl + Linux**. Use ultramarine for cross/docker/QEMU.

## v86 browser demo

Not the full appliance: fixed **i686** initramfs (busybox, oil/wax, bash, fastfetch, browser docs). Artifacts under `public/v86/`. Production appliance uses oksh and full dinit graph — do not assume v86 behavior matches hardware images.

## Status (high level)

Boot to login, Oil in initramfs, bcachefs state model, dropbear/chrony/dnsmasq/syslogd via dinit, desktop path with Alpenglowed — largely working in tree. Interactive installer: partial. Full milestone table lives in root `readme.md` **Status** section.

## Where to read more

- `readme.md` — editions, performance table, downloads
- `docs/` — architecture and install flows
- `docs/browser/` — text copied into the v86 guest

When instructions conflict: user message wins unless it weakens security (secrets, `curl | sh`, disabling verification).
