# Alpenglow browser demo

You are running Alpenglow's own userspace in the browser (busybox ash, Oil, wax) on **Linux 7.0.12 i686**. The shell is **busybox** (build-time static binary); `help` shows the busybox version string, not "Debian" as your OS. APK packages (e.g. fastfetch) are fetched by Oil as payloads only. Production appliances are **x86_64 / aarch64** musl images from `scripts/boot-native.sh`.

## What Alpenglow is

**Fastest and lightest** immutable Linux appliance we know how to ship: ~2s boot to login on real hardware, tiny userspace (toybox/oksh, dinit, Oil), hardened kernel profiles, no systemd bloat.

**Ideology (short):**

- **Immutable system image** in RAM (erofs/squashfs) -- upgrades replace the image, not `apt upgrade` on a live root.
- **Mutable life on disk** under `/state` (bcachefs): home, Oil metadata, logs, caches -- your data survives OS swaps.
- **Native package manager (Oil / wax)** -- sync HTTP, APK payloads, recipes in-repo; no mystery remote rootfs.
- **Appliance-first** -- SSH, net, time, logs in minimal; desktop is optional profile, not a kitchen-sink live ISO.
- **You add VPN, firewall extras, Tailscale** -- base stays small; that is intentional.

## Desktop is a hybrid (not "all RAM")

Even with `BUILD_PROFILE=desktop`, Alpenglow is **not** a fully diskless RAM-only desktop:

| Layer | Model |
|-------|--------|
| OS root (`/usr`, `/bin`, system tree) | Immutable image in RAM |
| User + package state (`/home`, Oil, caches) | Persistent **bcachefs `/state`** on disk |
| Desktop session | Wayland (Alpenglowed + foot), audio, Wi-Fi -- same hybrid: fixed root, mutable state |

So: **diskless immutable core + disk-backed state** -- fastest boot, reproducible system, without wiping your files every reboot.

## This demo

- **Oil / wax** -- `wax info vro`, `wax tap undivisible/tap`, `oil search …`
- **fastfetch** -- preinstalled in the image
- **Docs** -- `cat README.md`, `cat root-model.md`, `cat ideology.md` (paths are **case-sensitive**)
- Writable tmpfs only here; no bcachefs in v86.

More: `/usr/share/alpenglow/browser/`