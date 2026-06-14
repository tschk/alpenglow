# Immutable Rootfs And State Filesystem

Soliloquy uses an image-based root filesystem plus a separate persistent state filesystem. The root image is sealed at build time and mounted read-only at `/`. Runtime writes are limited to tmpfs mounts and the state filesystem mounted at `/state`.

## Image Contract

The appliance root image is built from `build/alpine/rootfs` using `system/alpine/scripts/build-rootfs-image.sh`.

The preferred format is SolFS because the Soliloquy target is a read-mostly internet appliance with generation verification, browser-runtime provenance, and disposable cache semantics in the filesystem contract. EROFS remains the mature immutable fallback, and SquashFS remains the fallback for hosts or boot experiments that lack EROFS tooling.

Concrete image outputs:

- `SOLILOQUY_ROOTFS_FORMAT=solfs system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images` creates `build/alpine/images/soliloquy-rootfs.solfs`.
- `SOLILOQUY_ROOTFS_FORMAT=erofs system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images` creates `build/alpine/images/soliloquy-rootfs.erofs`.
- `SOLILOQUY_ROOTFS_FORMAT=squashfs system/alpine/scripts/build-rootfs-image.sh build/alpine/rootfs build/alpine/images` creates `build/alpine/images/soliloquy-rootfs.squashfs`.

The source manifest is `system/alpine/filesystems/rootfs-layout.json`. The configured rootfs installs it as `/etc/soliloquy/filesystems/rootfs-layout.json`.

## Runtime Mount Plan

The booted filesystem plan is:

| Mount | Type | Options | Purpose |
| --- | --- | --- | --- |
| `/` | SolFS, EROFS fallback, SquashFS fallback | `ro,nodev` | Immutable Alpine, OpenRC, Servo launcher, sold, policy, service registry |
| `/state` | ext4 | `rw,nosuid,nodev` | Persistent user and system state |
| `/run` | tmpfs | `nosuid,nodev,mode=0755` | PID files, sockets, runtime telemetry |
| `/tmp` | tmpfs | `nosuid,nodev,mode=0755` | Short-lived system scratch |
| `/dev/shm` | tmpfs | `nosuid,nodev,mode=1777,size=256m` | Wayland and compositor shared memory |
| `/home` | bind from `/state/home` | bind | User workspaces |
| `/var/lib/soliloquy` | bind from `/state/var/lib/soliloquy` | bind | Browser profiles, system state, plugin state, Wax state |
| `/var/cache/soliloquy` | bind from `/state/var/cache/soliloquy` | bind | Browser and service cache |
| `/var/log/soliloquy` | bind from `/state/var/log/soliloquy` | bind | Appliance logs |

The source state manifest is `system/alpine/filesystems/state-mounts.json`. The configured rootfs installs it as `/etc/soliloquy/filesystems/state-mounts.json`.

## Persistent State Ownership

Persistent directories are created with fixed ownership boundaries:

| Path | Owner | Mode |
| --- | --- | --- |
| `/state/home` | `root:root` | `0755` |
| `/state/var/lib/soliloquy/browser/profiles` | `soliloquy:soliloquy` | `0700` |
| `/state/var/lib/soliloquy/browser/cache` | `soliloquy:soliloquy` | `0700` |
| `/state/var/lib/soliloquy/browser/downloads` | `soliloquy:soliloquy` | `0700` |
| `/state/var/lib/soliloquy/browser/state` | `soliloquy:soliloquy` | `0700` |
| `/state/var/lib/soliloquy/browser/logs` | `soliloquy:soliloquy` | `0700` |
| `/state/var/lib/soliloquy/browser/terminal` | `soliloquy:soliloquy` | `0700` |
| `/state/var/lib/soliloquy/files` | `sold:sold` | `0700` |
| `/state/var/lib/soliloquy/system` | `sold:sold` | `0700` |
| `/state/var/lib/soliloquy/system/plugins` | `sold:sold` | `0700` |
| `/state/var/lib/soliloquy/wax` | `root:root` | `0755` |
| `/state/var/cache/soliloquy` | `soliloquy:soliloquy` | `0700` |
| `/state/var/log/soliloquy` | `root:root` | `0700` |

No persistent bind is allowed for `/etc`, `/usr`, `/opt`, `/root`, or `/var/tmp`. Updates replace root generations under `/sysroot/soliloquy`; they do not mutate the active `/` tree.

## Validation

`system/alpine/scripts/validate-filesystem-plan.sh` validates:

- root and state manifests exist and name the required image formats, mountpoints, bind targets, and forbidden persistent paths,
- configured rootfs copies both manifests into `/etc/soliloquy/filesystems`,
- `/etc/soliloquy/filesystems/fstab.plan` records the immutable root, state filesystem, and state binds without changing the current cpio QEMU boot path,
- `system.json` points services at the installed filesystem manifests,
- configured rootfs directories have the expected modes.

CI runs this validator through `scripts/ci-os-appliance.sh` after `configure-rootfs.sh` stages a temporary rootfs.
