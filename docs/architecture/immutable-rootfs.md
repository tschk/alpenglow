# Immutable Rootfs And State Filesystem

Alpenglow has one root model:

- **Immutable rootfs** — full OS in RAM (initramfs), immutable erofs/squashfs image, read-only `/`. State on persistent bcachefs.
- **Desktop** — a build profile on top of the immutable rootfs model, not a separate root-on-disk mode.

This doc covers the immutable/appliance mode.

## Image Contract (appliance mode only)

The root image is sealed at build time by `system/backends/appliance/scripts/build-rootfs.sh`. Mounted read-only at `/` from RAM. Runtime writes are limited to tmpfs and the bcachefs-backed state partition at `/state`.

Future filesystem experiments should stay separate from current immutable builds.

## Runtime Mount Plan (appliance mode)

| Mount | Type | Options | Purpose |
| --- | --- | --- | --- |
| `/state` | bcachefs writable state filesystem | `rw,nosuid,nodev` | Persistent user and system state |
| `/run` | tmpfs | `nosuid,nodev,mode=0755` | PID files, sockets, runtime telemetry |
| `/tmp` | tmpfs | `nosuid,nodev,mode=0755` | Short-lived system scratch |
| `/dev/shm` | tmpfs | `nosuid,nodev,mode=1777,size=256m` | Wayland and compositor shared memory |
| `/home` | bind from `/state/home` | bind | User workspaces |
| `/var/lib/alpenglow` | bind from `/state/var/lib/alpenglow` | bind | Browser profiles, system state, plugin state, Oil state |
| `/var/cache/alpenglow` | bind from `/state/var/cache/alpenglow` | bind | Browser and service cache |
| `/var/log/alpenglow` | bind from `/state/var/log/alpenglow` | bind | Appliance logs |

Manifests: `system/appliance/filesystems/rootfs-layout.json` and `system/appliance/filesystems/state-mounts.json`.
