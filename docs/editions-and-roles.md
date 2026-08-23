# Editions, roles, and sessions

Alpenglow stays one OS: musl userspace, dinit, Oil, immutable erofs/squashfs RAM root, bcachefs `/state`. Editions are images. Roles are session + policy + artifact on top of an edition. This is not six distros.

Source of truth: [`editions.toml`](../editions.toml), resolved by [`scripts/edition-resolve.sh`](../scripts/edition-resolve.sh). Worlds live under `system/backends/appliance/packages-*.txt`. Boot enablement is in `system/backends/appliance/scripts/configure-rootfs.sh`.

```sh
ALPENGLOW_EDITION=internet . scripts/edition-resolve.sh
ALPENGLOW_ROLE=kiosk . scripts/edition-resolve.sh
ALPENGLOW_EDITION=minimal ALPENGLOW_SESSION=sold . scripts/edition-resolve.sh
sh scripts/edition-resolve.sh --list
sh scripts/edition-resolve.sh --demo
```

`ALPENGLOW_EDITION`, `ALPENGLOW_SKU`, and `ALPENGLOW_ROLE` select the same table (`ALPENGLOW_EDITION` wins). `ALPENGLOW_SESSION=none|alpenglowed|sold|cage` overrides session without changing the image world. `SESSION` is an output for `configure-rootfs.sh`.

## Matrix

| SKU | Base image | `BUILD_PROFILE` | `KERNEL_PROFILE` | `SESSION` | Artifact | World |
|-----|------------|-----------------|------------------|-----------|----------|-------|
| `fast` | — | minimal | fast | none | image | `packages-minimal.txt` |
| `minimal` | — | minimal | minimal | none | image | `packages-minimal.txt` |
| `standard` | — | standard | minimal | none | image | `packages-standard.txt` |
| `desktop` | — | desktop | desktop | alpenglowed | image | `packages-desktop-lite.txt` |
| `desktop-full` | — | desktop | desktop | alpenglowed | image | `packages-runtime.txt` |
| `embedded` | fast | minimal | fast | none | image | `packages-embedded.txt` |
| `potatoes` | fast | minimal | fast | none | image | `packages-potatoes.txt` |
| `internet` | minimal | minimal | minimal | sold | image | `packages-internet.txt` |
| `kiosk` | minimal | minimal | minimal | cage | image | `packages-kiosk.txt` |
| `workstation` | desktop-full | desktop | desktop | alpenglowed | image | `packages-runtime.txt` |
| `containers` | userspace | minimal | unused | none | userspace | `packages-containers.txt` |

Roles:

- **embedded** — closed device. Strips `linux-firmware`, dropbear, chrony, dnsmasq. Board overlays (RK3566, device trees) stay on `board/*` branches.
- **potatoes** — low-end. Fast kernel, minimal net stack, no toolchain. Cage/foot/seatd are on disk; default session is `none`. `ALPENGLOW_SESSION=cage` starts the skinny GUI.
- **containers** — different artifact. `scripts/export-container.sh` writes a rootfs tarball and an OCI image layout. No kernel, firmware, eudev, initramfs, or Limine.
- **internet** — minimal + Soliloquy `sold` staging. Not desktop-lite (desktop-lite is a graphical live image, not an appliance base).
- **kiosk** — minimal + Cage, `lock_session=1`, `shell_login=0`. Dropbear stays for recovery. Serial getty is not a dinit unit in this tree.
- **desktop** — Alpenglowed. Lite world now keeps firmware, SSH, NTP, and DNS.
- **workstation** — desktop-full plus `/etc/alpenglow/fleet-agent.json` and a no-op `alpenglow-fleet-agent` hook. No Fleet/osquery vendor.

## Sessions

| `SESSION` | What starts | Where the binary comes from |
|-----------|-------------|-----------------------------|
| `none` | no graphical session | — |
| `alpenglowed` | `dinit/alpenglowed` | [tschk/alpenglowed](https://github.com/tschk/alpenglowed); desktop path currently links glibc for the compositor |
| `sold` | `dinit/sold` → `/usr/local/bin/sold-session-start` | [tschk/soliloquy](https://github.com/tschk/soliloquy). Not a crate in this repo. Wrapper exits 0 if `sold` is missing |
| `cage` | `dinit/cage` → `/usr/local/bin/kiosk-session-start` | Alpine `cage` (`system/backends/appliance/scripts/build-cage.sh`) |

`GRAPHICAL=1` in `scripts/boot-native.sh` is the Alpenglowed/glibc stack. Kiosk and potatoes GUI use `SESSION=cage` and keep `GRAPHICAL=0` so they do not pull that path.

## SKU naming

```
alpenglow-v0.1.<git-rev-list-count>-<sku>-<arch>.iso
alpenglow-v0.1.<git-rev-list-count>-<sku>-<arch>.img.zst
alpenglow-v0.1.<git-rev-list-count>-containers-<arch>.tar
alpenglow-v0.1.<git-rev-list-count>-standard-x86_64-wsl.tar
```

Examples: `alpenglow-embedded`, `alpenglow-internet`, `alpenglow-kiosk`, `alpenglow-workstation`.

GitHub Releases GHA (`.github/workflows/release.yml`) still builds only `fast`, `minimal`, `standard`, `desktop`, `desktop-full` for x86_64 and aarch64. Role SKUs are local until that matrix grows.

## Audit (2026-08)

Verified against this tree. Discarded hypotheses are marked.

1. **`editions.toml` vs `backend.json` desktop world — confirmed.** `editions.desktop` uses `packages-desktop-lite.txt`. `backend.json` `profiles.desktop` and `BUILD_PROFILE=desktop` default `ALPENGLOW_DESKTOP_FULL=1`, so they use `packages-runtime.txt`. This PR adds `backend.json` `editions` that match `editions.toml`, and documents the profile default.
2. **Desktop-lite dropped net/SSH/NTP vs minimal — confirmed.** `packages-desktop-lite.txt` lacked `linux-firmware`, `dropbear`, `chrony`, `dnsmasq`, and lite `BOOT_SERVICES` omitted those daemons. README claimed desktop had SSH/NTP/DNS. Fixed in the lite world and lite boot list. Internet/kiosk still start from **minimal**, not desktop-lite.
3. **`atomic-generations` / `update-policy.json` — confirmed scaffold.** `rootfs-layout.json` lists `/etc/alpenglow/update-policy.json` as a sealed input; the file did not exist. `configure-rootfs.sh` only created `etc/alpenglow/generations`. This PR seeds `system/appliance/filesystems/update-policy.json` with `status: scaffold` and a mark-good stub. There is still no updater.
4. **Soliloquy vs Alpenglowed — confirmed.** Desktop still uses Alpenglowed (`dinit/alpenglowed`, `packages-runtime.txt`). CI asserts `alpenglow-session` does not depend on `sold`. `configure-rootfs.sh` kept a sold uid comment (`sold group moved to soliloquy`) and chowned some paths as 771. This PR adds a staging unit and docs only. No crate dependency.
5. **glibc vs static musl — confirmed, with a narrow exception.** Appliance userland (toybox, dinit, oil, alpenglow-ctl) is musl. `scripts/boot-native.sh` builds Alpenglowed with `build-alpenglowed-glibc.sh` and isolated Debian graphics libs when `GRAPHICAL=1`. README "no glibc" is the appliance claim, not the desktop compositor.
6. **OpenRC leftovers — mostly discarded.** No OpenRC units. `configure-rootfs.sh` removes leftover `/etc/runit`. Docs had a stale "replace ad hoc OpenRC" line; updated.
7. **RK3566 / riscv64 — confirmed.** `main` has `scripts/build-uboot-rk3566.sh` only. Readme points at `arch/riscv64` and `board/rk3566`. A `v0.1.435-fast-riscv64.tar.zst` exists on the last published GitHub Release; that is not a `main` build path.
8. **Oil `.rej` leftovers — confirmed.** `system/oil/src/tap.rs.rej` and `system/oil/src/main.rs.rej`. The tap HomeGuard test is already in `tap.rs`. Removed the reject files.
9. **Release tags vs published assets — confirmed.** Tags reach `v0.1.506` (HEAD count is higher). Latest GitHub Release is [v0.1.435](https://github.com/tschk/alpenglow/releases/tag/v0.1.435) (2026-07-16).
10. **Dead units / flag drift — partial.** `dinit/velox` is a Cage unit by contents, unused in boot lists; `velox` remains in desktop worlds though Alpenglowed does not depend on it. `dinit/elogind` is not in `BOOT_SERVICES` even on desktop-full. `dinit/foot` is enabled on desktop. `GRAPHICAL` ≠ `SESSION`. Role SKUs keep `GRAPHICAL=0` unless they are Alpenglowed desktops.

Remaining gaps: sold is not built or packaged; Cage is not fetched unless `build-cage.sh` runs; container export does not invoke Oil (`configure-rootfs` overlay only unless you pass a built rootfs); workstation agent is a hook; generations are not applied by Oil; release GHA does not publish role SKUs; board trees stay on other branches.

## What this repo will not add

systemd, snap, flatpak, Nix, Yocto, a vendored MDM, or Soliloquy OS logic.
