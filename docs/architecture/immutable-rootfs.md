# Immutable Rootfs And State Filesystem

Alpenglow has two deployment modes:

- **Diskless/immutable** — root in RAM (initramfs), GlowFS/EROFS/SquashFS image, read-only `/`. State on persistent partition.
- **Rootfs/desktop** — normal r/w root on disk (ext4), package-managed, no image layers.

This doc covers the immutable/appliance mode.

## Image Contract (appliance mode only)

The root image is sealed at build time by `system/backends/appliance/scripts/build-rootfs.sh`. Mounted read-only at `/`. Runtime writes limited to tmpfs + state partition at `/state`.

Preferred format: GlowFS (kernel module, generation-verified). Fallback: EROFS, SquashFS.

## Runtime Mount Plan (appliance mode)

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

Manifests: `system/appliance/filesystems/rootfs-layout.json` and `system/appliance/filesystems/state-mounts.json`.
