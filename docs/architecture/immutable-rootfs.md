# Immutable Rootfs And State Filesystem

Alpenglow uses an image-based root filesystem plus a separate persistent state filesystem. The root image is sealed at build time and mounted read-only at `/`. Runtime writes are limited to tmpfs mounts and the state filesystem mounted at `/state`.

## Image Contract

The appliance root image is built from `build/alpine/rootfs` using `system/alpine/scripts/build-rootfs-image.sh`.

The preferred format is GlowFS because the Alpenglow target is a read-mostly internet appliance with generation verification, browser-runtime provenance, and disposable cache semantics in the filesystem contract. EROFS remains the mature immutable fallback, and SquashFS remains the fallback for hosts or boot experiments that lack EROFS tooling.

Concrete image outputs:

- `ALPENGLOW_ROOTFS_FORMAT=glowfs system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images` creates `build/alpine/images/alpenglow-rootfs.glowfs`.
- `ALPENGLOW_ROOTFS_FORMAT=erofs system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images` creates `build/alpine/images/alpenglow-rootfs.erofs`.
- `ALPENGLOW_ROOTFS_FORMAT=squashfs system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images` creates `build/alpine/images/alpenglow-rootfs.squashfs`.

The source manifest is `system/alpine/filesystems/rootfs-layout.json`. The configured rootfs installs it as `/etc/alpenglow/filesystems/rootfs-layout.json`.

## Runtime Mount Plan

The booted filesystem plan is:

| Mount | Type | Options | Purpose |
| --- | --- | --- | --- |
| `/state` | ext4 | `rw,nosuid,nodev` | Persistent user and system state |
| `/run` | tmpfs | `nosuid,nodev,mode=0755` | PID files, sockets, runtime telemetry |
| `/tmp` | tmpfs | `nosuid,nodev,mode=0755` | Short-lived system scratch |
| `/dev/shm` | tmpfs | `nosuid,nodev,mode=1777,size=256m` | Wayland and compositor shared memory |
| `/home` | bind from `/state/home` | bind | User workspaces |
| `/var/lib/alpenglow` | bind from `/state/var/lib/alpenglow` | bind | Browser profiles, system state, plugin state, Oil state |
| `/var/cache/alpenglow` | bind from `/state/var/cache/alpenglow` | bind | Browser and service cache |
| `/var/log/alpenglow` | bind from `/state/var/log/alpenglow` | bind | Appliance logs |

The source state manifest is `system/alpine/filesystems/state-mounts.json`. The configured rootfs installs it as `/etc/alpenglow/filesystems/state-mounts.json`.

## Persistent State Ownership

Persistent directories are created with fixed ownership boundaries:

| Path | Owner | Mode |
| --- | --- | --- |
| `/state/home` | `root:root` | `0755` |
| `/state/var/lib/alpenglow/browser/profiles` | `alpenglow:alpenglow` | `0700` |
| `/state/var/lib/alpenglow/browser/cache` | `alpenglow:alpenglow` | `0700` |
| `/state/var/lib/alpenglow/browser/downloads` | `alpenglow:alpenglow` | `0700` |
| `/state/var/lib/alpenglow/browser/state` | `alpenglow:alpenglow` | `0700` |
| `/state/var/lib/alpenglow/browser/logs` | `alpenglow:alpenglow` | `0700` |
| `/state/var/lib/alpenglow/browser/terminal` | `alpenglow:alpenglow` | `0700` |
| `/state/var/lib/alpenglow/files` | `sold:sold` | `0700` |
| `/state/var/lib/alpenglow/system` | `sold:sold` | `0700` |
| `/state/var/lib/alpenglow/system/plugins` | `sold:sold` | `0700` |
| `/state/var/lib/alpenglow/oil` | `root:root` | `0755` |
| `/state/var/cache/alpenglow` | `alpenglow:alpenglow` | `0700` |
| `/state/var/log/alpenglow` | `root:root` | `0700` |

No persistent bind is allowed for `/etc`, `/usr`, `/opt`, `/root`, or `/var/tmp`. Updates replace root generations under `/sysroot/alpenglow`; they do not mutate the active `/` tree.

## Validation

`system/alpine/scripts/validate-filesystem-plan.sh` validates:

- root and state manifests exist and name the required image formats, mountpoints, bind targets, and forbidden persistent paths,
- configured rootfs copies both manifests into `/etc/alpenglow/filesystems`,
- `/etc/alpenglow/filesystems/fstab.plan` records the immutable root, state filesystem, and state binds without changing the current cpio QEMU boot path,
- `system.json` points services at the installed filesystem manifests,
- configured rootfs directories have the expected modes.

CI runs this validator through `scripts/ci-os-appliance.sh` after `configure-rootfs.sh` stages a temporary rootfs.
