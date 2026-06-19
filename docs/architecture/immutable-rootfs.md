# Immutable Rootfs And State Filesystem

Alpenglow has two deployment modes:

- **Diskless/immutable** — root in RAM (initramfs), GlowIFS/EROFS/SquashFS image, read-only `/`. State on persistent partition.
- **Rootfs/desktop** — normal r/w root on disk (GlowFS/ext4), package-managed, no image layers.

This doc covers the immutable/appliance mode.

## Image Contract (appliance mode only)

The root image is sealed at build time by `system/backends/appliance/scripts/build-rootfs.sh`. Mounted read-only at `/`. Runtime writes limited to tmpfs + state partition at `/state`.

Preferred immutable format: GlowIFS (kernel module, generation-verified). Fallback: EROFS, SquashFS. Preferred writable format: GlowFS once available, with ext4 as the compatibility baseline until GlowFS is ready.

GlowFS and GlowIFS are separate by design. GlowIFS is the sealed appliance root: immutable, read-only, digest-verified, and generation-oriented. GlowFS is the writable filesystem: journaled, recoverable, allocation-aware, and suitable for normal POSIX writes. Appliance images should not depend on mutable GlowIFS behavior.

## Runtime Mount Plan (appliance mode)

| Mount | Type | Options | Purpose |
| --- | --- | --- | --- |
| `/state` | GlowFS/ext4 | `rw,nosuid,nodev` | Persistent user and system state |
| `/run` | tmpfs | `nosuid,nodev,mode=0755` | PID files, sockets, runtime telemetry |
| `/tmp` | tmpfs | `nosuid,nodev,mode=0755` | Short-lived system scratch |
| `/dev/shm` | tmpfs | `nosuid,nodev,mode=1777,size=256m` | Wayland and compositor shared memory |
| `/home` | bind from `/state/home` | bind | User workspaces |
| `/var/lib/alpenglow` | bind from `/state/var/lib/alpenglow` | bind | Browser profiles, system state, plugin state, Oil state |
| `/var/cache/alpenglow` | bind from `/state/var/cache/alpenglow` | bind | Browser and service cache |
| `/var/log/alpenglow` | bind from `/state/var/log/alpenglow` | bind | Appliance logs |

Manifests: `system/appliance/filesystems/rootfs-layout.json` and `system/appliance/filesystems/state-mounts.json`.
