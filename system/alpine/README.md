# Alpine tree (in-repo)

This directory carries the Alpine-specific boot/runtime layout for the Alpenglow browser appliance:

- `packages-v0.txt` - minimal runtime package manifest
- `packages-v0-dev.txt` - optional dev extras (terminal-oriented)
- `rootfs-overlay/` - files copied directly into Alpine rootfs
- `filesystems/` - immutable root and writable state mount manifests
- `openrc/` - OpenRC service units for the browser session
- `scripts/` - helper scripts for rootfs assembly and image prep
- `docker/` - rootfs builder implementation for reproducible output

## Expected v0 boot

1. OpenRC starts core services (`seatd`).
2. OpenRC starts `sold` to serve the local browser UI and PTY bridge.
3. OpenRC starts and respawns `alpenglow-session`.
4. `cage` launches Servo fullscreen on the visible VT.
5. Servo opens the local Alpenglow browser surface.

The root filesystem is treated as immutable at runtime; browser profile, cache, downloads, logs, and terminal state are the writable areas.
The concrete root and state contract lives in `filesystems/rootfs-layout.json` and `filesystems/state-mounts.json`, with the design captured in `docs/architecture/immutable-rootfs.md`.

The first-boot hook prunes nonessential default services (logging daemons, avahi, cron, bluetooth, etc.) to keep startup and memory overhead low.

## Build rootfs with Docker

```sh
./system/alpine/scripts/setup-host.sh
./system/alpine/scripts/build-rootfs.sh
```

`setup-host.sh` checks for Wax first, then bootstraps the minimal host tools plus Servo's macOS GStreamer/framework dependencies when needed. The rootfs builder reuses the staged Alpine artifact when it is already present, and only regenerates it when the cache is cold or `FORCE_ROOTFS_REBUILD=1`.

Output:

- `build/alpine/rootfs.tar.gz`
- `build/alpine/rootfs/` (extracted rootfs)

Build a sealed rootfs image from the configured rootfs:

```sh
ALPENGLOW_ROOTFS_FORMAT=glowfs ./system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images
ALPENGLOW_ROOTFS_FORMAT=erofs ./system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images
ALPENGLOW_ROOTFS_FORMAT=squashfs ./system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images
```

## Full QEMU flow

```sh
./system/alpine/scripts/qemu-v0.sh
```

Build-only validation without starting the VM:

```sh
QEMU_RUN=0 ./system/alpine/scripts/qemu-v0.sh
```

For architecture selection:

```sh
QEMU_ARCH=x86_64 ./system/alpine/scripts/qemu-v0.sh
```

Servo fork requirements (in-tree):

```sh
SERVO_FORK_URL=https://github.com/<org-or-user>/servo.git QEMU_ARCH=x86_64 ./system/alpine/scripts/qemu-v0.sh
```

This clones your fork into `third_party/servo` (if missing), builds it, and stages:

- `third_party/servo/target/release/servoshell` -> `/usr/local/bin/servo`
- `target/release/sold` -> `/usr/local/bin/sold`
- `bundle/` -> `/usr/local/share/alpenglow/bundle`

Important: the staged `servo` and `sold` binaries must be Linux ELF binaries for the selected `QEMU_ARCH`.
Building on macOS produces Mach-O binaries, which cannot run inside the Alpine Linux VM.
The staging script now fails fast when binary formats do not match.

`qemu-v0.sh` now prepares Linux binaries automatically before staging:

- `sold` is built in a Linux container and stored under `build/alpine/artifacts/linux-<arch>/sold`
- `alpenglow-netd` and `alpenglow-kernelctl` are built for the same Linux target
- `servo` prefers an in-tree Linux ELF build; if unavailable on `x86_64`, it fetches the Servo Linux release binary into `build/alpine/artifacts/linux-<arch>/servo`

Override servo source explicitly:

```sh
SERVO_BIN_LINUX=/absolute/path/to/linux/servo QEMU_ARCH=x86_64 ./system/alpine/scripts/qemu-v0.sh
```

Force a clean Servo rebuild during QEMU flow:

```sh
SERVO_FORCE_REBUILD=1 QEMU_ARCH=x86_64 ./system/alpine/scripts/qemu-v0.sh
```

Manual steps:

```sh
QEMU_ARCH="${QEMU_ARCH:-x86_64}"
export QEMU_ARCH
SERVO_BUILD=0 ./system/alpine/scripts/ensure-servo-fork.sh
./install.sh --check
LINUX_BIN_DIR="$(./system/alpine/scripts/ensure-linux-runtime-binaries.sh)"
./system/alpine/scripts/build-rootfs.sh
./system/alpine/scripts/fetch-qemu-kernel.sh build/alpine/qemu
ALPENGLOW_ROOTFS_FORMAT="${ALPENGLOW_ROOTFS_FORMAT:-glowfs}"
if [ "${ALPENGLOW_ROOTFS_FORMAT}" = "glowfs" ]; then
  GLOWFS_MODULE="${GLOWFS_MODULE:-build/alpine/qemu/glowfs.ko}"
  ./system/alpine/scripts/build-glowfs-module.sh "${GLOWFS_MODULE}"
  export GLOWFS_MODULE
fi
export SERVO_BIN="${LINUX_BIN_DIR}/servo"
export SOLD_BIN="${LINUX_BIN_DIR}/sold"
export ALPENGLOW_NETD_BIN="${LINUX_BIN_DIR}/alpenglow-netd"
export ALPENGLOW_KERNELCTL_BIN="${LINUX_BIN_DIR}/alpenglow-kernelctl"
if [ -d "${LINUX_BIN_DIR}/servo-runtime-root" ]; then
  export SERVO_RUNTIME_DIR="${LINUX_BIN_DIR}/servo-runtime-root"
else
  unset SERVO_RUNTIME_DIR
fi
./system/alpine/scripts/stage-alpenglow-artifacts.sh build/alpine/rootfs
ALPENGLOW_ROOTFS_FORMAT="${ALPENGLOW_ROOTFS_FORMAT}" ./system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/qemu
./system/alpine/scripts/build-qemu-initramfs.sh build/alpine/rootfs build/alpine/qemu/rootfs.cpio.gz
ALPENGLOW_RAM_ROOT="${ALPENGLOW_RAM_ROOT:-auto}" \
ALPENGLOW_RAM_ROOT_MIN_MB="${ALPENGLOW_RAM_ROOT_MIN_MB:-3072}" \
ALPENGLOW_ROOTFS_IMAGE="${ALPENGLOW_ROOTFS_IMAGE:-build/alpine/qemu/alpenglow-rootfs.${ALPENGLOW_ROOTFS_FORMAT}}" \
ALPENGLOW_ROOTFS_IMAGE_REQUIRED="${ALPENGLOW_ROOTFS_IMAGE_REQUIRED:-1}" \
ALPENGLOW_ROOT_FALLBACK_FSTYPE="${ALPENGLOW_ROOT_FALLBACK_FSTYPE:-${ALPENGLOW_ROOTFS_FORMAT}}" \
./system/alpine/scripts/run-qemu.sh build/alpine/qemu
```

The manual sequence mirrors `scripts/qemu-v0.sh`. In normal use prefer `./system/alpine/scripts/qemu-v0.sh`; keep manual runs aligned with that script when debugging one stage at a time.

The staged UI path is `/usr/local/share/alpenglow/bundle`. `stage-alpenglow-artifacts.sh` copies the local `bundle/` directory there.

`run-qemu.sh` defaults to `console=tty0 console=ttyS0 rdinit=/init`, so boot logs appear in both the QEMU window and terminal.
You can override kernel args with:

```sh
KERNEL_CMDLINE='console=ttyS0 rdinit=/init loglevel=7' ./system/alpine/scripts/run-qemu.sh build/alpine/qemu
```

`alpenglow-session-start` and `alpenglow-servo-wrapper` mirror their logs (including Cage/Servo stderr/stdout) to `ttyS0`, so runtime failures are visible in the terminal even when the graphical VT is blank.
