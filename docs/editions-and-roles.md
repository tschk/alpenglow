# Editions, roles, and sessions

Alpenglow stays one OS: musl userspace, dinit, Oil, immutable erofs/squashfs RAM root, bcachefs `/state`. There are exactly three public product SKUs. Roles are session + policy + artifact on top of a SKU. This is not three distros.

Source of truth: [`editions.toml`](../editions.toml), resolved by [`scripts/edition-resolve.sh`](../scripts/edition-resolve.sh). Worlds live under `system/backends/appliance/packages-*.txt`. Boot enablement is in `system/backends/appliance/scripts/configure-rootfs.sh`.

```sh
ALPENGLOW_EDITION=internet . scripts/edition-resolve.sh
ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1 . scripts/edition-resolve.sh
ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1 . scripts/edition-resolve.sh
ALPENGLOW_EDITION=potato ALPENGLOW_ARTIFACT=tar . scripts/edition-resolve.sh
sh scripts/edition-resolve.sh --list
sh scripts/edition-resolve.sh --list-all
sh scripts/edition-resolve.sh --demo
```

`ALPENGLOW_EDITION`, `ALPENGLOW_SKU`, and `ALPENGLOW_ROLE` select the same table (`ALPENGLOW_EDITION` wins). The resolver always exports `ALPENGLOW_SKU` as `potato`, `desktop`, or `internet`. `ALPENGLOW_SESSION=none|alpenglowed|sold|cage` overrides session without changing the image world. `SESSION` is an output for `configure-rootfs.sh`. Board (RK3566 and similar) is a kernel/board fragment, not a SKU.

## Public SKUs

| SKU | `BUILD_PROFILE` | `KERNEL_PROFILE` | `SESSION` | `ALPENGLOWED_ROLE` | Artifact | World |
|-----|-----------------|------------------|-----------|-------------------|----------|-------|
| `potato` | minimal | fast | alpenglowed | potato | image | `packages-potato.txt` |
| `desktop` | desktop | desktop | alpenglowed | desktop | image | `packages-runtime.txt` |
| `internet` | minimal | minimal | sold | internet | image | `packages-internet.txt` |

- **potato** — lightweight / embedded / old hardware. Fast kernel, lite GUI (`alpenglowed-lite` on Cage, seatd only, no PipeWire). Replaces the old fast + embedded + potatoes names. Export a container with `scripts/export-container.sh` or `ALPENGLOW_ARTIFACT=oci|tar` (userspace tarball / OCI layout; no kernel, firmware, eudev, initramfs, or Limine).
- **desktop** — normal GUI. Full Alpenglowed, PipeWire, greeter. Replaces desktop-full. Fleet is `ALPENGLOW_FLEET=1` (placeholder `alpenglow-fleet-agent` hook; no Fleet/osquery vendor), not its own SKU.
- **internet** — Soliloquy `sold` session. Starts from the minimal appliance world, not the potato lite GUI. Kiosk is `ALPENGLOW_KIOSK=1` or `ALPENGLOW_SESSION=cage` (Cage lock, `shell_login=0`). Dropbear stays for recovery.

## Internal aliases

These resolve to a public SKU for CI and existing scripts. Do not use them in release names or product copy.

| Alias | Public SKU | Overlay |
|-------|------------|---------|
| `fast` | potato | headless, `packages-minimal.txt`, fast kernel |
| `minimal` | potato | headless, `packages-minimal.txt`, minimal kernel |
| `standard` | potato | headless toolchain (`packages-standard.txt`). Default when no edition is set |
| `embedded` | potato | closed-device world (`packages-embedded.txt`); no firmware/SSH/NTP/DNS packages |
| `potatoes` | potato | compatibility spelling |
| `desktop-lite` | potato | lite GUI lives on potato |
| `containers` | potato | `ARTIFACT=userspace`, `packages-containers.txt` |
| `desktop-full` | desktop | compatibility; public desktop is the full GUI |
| `workstation` | desktop | `ALPENGLOW_FLEET=1` |
| `kiosk` | internet | `ALPENGLOW_KIOSK=1`, `SESSION=cage`, `packages-kiosk.txt` |

`sh scripts/edition-resolve.sh --list` prints the three public SKUs. `--list-all` includes aliases.

## Sessions

| `SESSION` | What starts | Where the binary comes from |
|-----------|-------------|-----------------------------|
| `none` | no graphical session | — |
| `alpenglowed` | `dinit/alpenglowed` or `alpenglowed-lite` → `alpenglow-session-start` | [tschk/alpenglowed](https://github.com/tschk/alpenglowed) as a **Cage Wayland client**. `--compositor` is unfinished Smithay and is not the default |
| `sold` | `dinit/sold` → `/usr/local/bin/sold-session-start` | [tschk/soliloquy](https://github.com/tschk/soliloquy). Not a crate in this repo. Wrapper exits 0 if `sold` is missing. Do not start Alpenglowed |
| `cage` | `dinit/cage` → `/usr/local/bin/kiosk-session-start` | Alpine `cage` (`system/backends/appliance/scripts/build-cage.sh`). Do not start Alpenglowed |

`GRAPHICAL=1` in `scripts/boot-native.sh` is the glibc Alpenglowed **build** path, not “any GUI”. Potato keeps `GRAPHICAL=0` and still starts `alpenglowed-lite`.

## Alpenglowed stitch ([alpenglowed#2](https://github.com/tschk/alpenglowed/pull/2))

This PR and alpenglowed #2 need to land together. They rename potatoes→potato and drop workstation as a public Alpenglowed role.

| SKU / hook | `ALPENGLOWED_ROLE` | dinit unit | PipeWire |
|------------|--------------------|------------|----------|
| potato | `potato` | `alpenglowed-lite` (seatd only) | no |
| desktop | `desktop` | `alpenglowed` | yes |
| desktop + `ALPENGLOW_FLEET=1` | `desktop` | `alpenglowed` + fleet hook | yes |
| internet | `internet` | sold only | no |
| internet + `ALPENGLOW_KIOSK=1` | `internet` | cage only | no |

Alpenglowed reads `/run/alpenglow/role` then `/etc/alpenglow/role`. `configure-rootfs.sh` writes `/etc/alpenglow/role`, `/etc/alpenglow/sku`, and `/etc/alpenglow/role.json`. `dinit/alpenglow-role` copies those into `/run/alpenglow` at boot. Foreign roles (`internet`, sold, headless) make `alpenglowed` exit 2.

`alpenglowed-lite` is `cargo build --release --no-default-features` in the sibling repo. Session contract: `alpenglowed --session-contract` and `docs/alpenglow-session-contract.md` in tschk/alpenglowed. The `velox` dinit unit still runs `/usr/bin/cage`.

## SKU naming

```
alpenglow-v0.1.<count>-potato-<arch>.iso
alpenglow-v0.1.<count>-desktop-<arch>.iso
alpenglow-v0.1.<count>-internet-<arch>.iso
alpenglow-v0.1.<count>-potato-<arch>.img.zst
alpenglow-v0.1.<count>-desktop-<arch>.img.zst
alpenglow-v0.1.<count>-internet-<arch>.img.zst
alpenglow-v0.1.<count>-potato-<arch>.tar
```

GitHub Releases (`.github/workflows/release.yml`) publishes `potato`, `desktop`, and `internet` for x86_64 and aarch64.

## Audit (2026-08)

Verified against this tree. Discarded hypotheses are marked.

1. **`editions.toml` vs `backend.json` desktop world — confirmed, then collapsed.** Public `desktop` is the full GUI (`packages-runtime.txt`, `ALPENGLOW_DESKTOP_FULL=1`). Lite GUI is `potato`. `BUILD_PROFILE=desktop` still defaults `ALPENGLOW_DESKTOP_FULL=1`.
2. **Desktop-lite dropped net/SSH/NTP vs minimal — confirmed.** `packages-desktop-lite.txt` lacked `linux-firmware`, `dropbear`, `chrony`, `dnsmasq`, and lite `BOOT_SERVICES` omitted those daemons. README claimed desktop had SSH/NTP/DNS. Fixed in the lite world and lite boot list. Internet still starts from **minimal**, not lite GUI. Lite GUI now ships as potato (`packages-potato.txt`) and keeps those daemons.
3. **`atomic-generations` / `update-policy.json` — confirmed scaffold.** `rootfs-layout.json` lists `/etc/alpenglow/update-policy.json` as a sealed input; the file did not exist. `configure-rootfs.sh` only created `etc/alpenglow/generations`. This PR seeds `system/appliance/filesystems/update-policy.json` with `status: scaffold` and a mark-good stub. There is still no updater.
4. **Soliloquy vs Alpenglowed — confirmed.** Desktop still uses Alpenglowed (`dinit/alpenglowed`, `packages-runtime.txt`). CI asserts `alpenglow-session` does not depend on `sold`. `configure-rootfs.sh` kept a sold uid comment (`sold group moved to soliloquy`) and chowned some paths as 771. This PR adds a staging unit and docs only. No crate dependency.
5. **glibc vs static musl — confirmed, with a narrow exception.** Appliance userland (toybox, dinit, oil, alpenglow-ctl) is musl. `scripts/boot-native.sh` builds Alpenglowed with `build-alpenglowed-glibc.sh` and isolated Debian graphics libs when `GRAPHICAL=1`. README "no glibc" is the appliance claim, not the desktop compositor.
6. **OpenRC leftovers — mostly discarded.** No OpenRC units. `configure-rootfs.sh` removes leftover `/etc/runit`. Docs had a stale "replace ad hoc OpenRC" line; updated.
7. **RK3566 / riscv64 — confirmed.** `main` has `scripts/build-uboot-rk3566.sh` only. Readme points at `arch/riscv64` and `board/rk3566`. Board trees are fragments, not SKUs. A `v0.1.435-fast-riscv64.tar.zst` exists on the last published GitHub Release; new naming is `potato-riscv64`.
8. **Oil `.rej` leftovers — confirmed.** `system/oil/src/tap.rs.rej` and `system/oil/src/main.rs.rej`. The tap HomeGuard test is already in `tap.rs`. Removed the reject files.
9. **Release tags vs published assets — confirmed.** Tags reach `v0.1.506` (HEAD count is higher). Latest GitHub Release is [v0.1.435](https://github.com/tschk/alpenglow/releases/tag/v0.1.435) (2026-07-16).
10. **Dead units / flag drift — partial.** `dinit/velox` is a Cage unit by contents, unused in boot lists; `velox` remains in desktop worlds though Alpenglowed does not depend on it. `dinit/elogind` is not in `BOOT_SERVICES` even on desktop. `dinit/foot` is enabled on desktop. `GRAPHICAL` ≠ `SESSION`. Potato keeps `GRAPHICAL=0` and still starts `alpenglowed-lite`.

Remaining gaps: sold is not built or packaged; Cage is not fetched unless `build-cage.sh` runs; container export does not invoke Oil (`configure-rootfs` overlay only unless you pass a built rootfs); fleet agent is a hook; generations are not applied by Oil; board trees stay on other branches.

## What this repo will not add

systemd, snap, flatpak, Nix, Yocto, a vendored MDM, or Soliloquy OS logic.
