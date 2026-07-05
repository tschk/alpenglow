# Why Alpenglow

Alpenglow is an immutable Linux stack built for **speed**, **small RAM footprint**, and a **modern desktop** -- not a fork of a general-purpose distro.

## How we are fast and light

| Layer | Choice | Why |
|-------|--------|-----|
| Boot | Diskless initramfs + erofs/squashfs root in RAM | No mutable `/usr` on disk; image is a versioned blob |
| Init | **dinit** dependency graph | Parallel service bring-up, not sequential sysv |
| Userland | **toybox** (production) | One binary, BSD coreutils surface, musl |
| Shell | **oksh** (production) | Small, POSIX, no bash weight in minimal images |
| Packages | **Oil / wax** (Rust, ~2.3k LOC) | Sync HTTP, APK payloads, recipes in-repo |
| Kernel | **Linux 7.x** profiles (`fast` / `minimal` / `desktop`) | Trimmed drivers per role; hardened options |
| Policy | **kernelctl** (Zig ~72KB static) + netd | cgroups, PSI, network state without bloat |

Target on real hardware: **~2s to login** on headless minimal.

## How we are modern (desktop)

Production desktop is not wallpaper + panel + tray. **[Alpenglowed](../alpenglowed)** (`../alpenglowed` in the monorepo) is a **GPU-accelerated bar launcher** (Crepuscularity GPUI + Wayland):

- Super+Space summon bar: launch, fuzzy search, calculator, shell, plugins
- Status pills: time, battery, CPU, Wi-Fi, weather
- **Smithay** compositor path (`cargo run --features compositor`) for embedded Wayland
- **foot** terminal on the immutable root image; greetd, PipeWire, iwd in desktop profile

Same immutable-root / **`/state` on bcachefs** hybrid as headless: OS image swaps; home and Oil state stay.

## Headless and desktop

Both are **first-class build profiles** (`BUILD_PROFILE=minimal|standard|desktop`), not "server distro + optional DE".

## What we skip in the base (on purpose)

VPN meshes, Tailscale, custom firewall products in the base image. Install via Oil or drop binaries in `/usr/local` when you need them.

## Browser demo (this VM)

i686 **v86** serial shell: busybox + **bash**, Oil, fastfetch, docs. Not the performance or UX reference for Alpenglowed Wayland -- that is x86_64/aarch64 `scripts/boot-native.sh` + desktop profile.