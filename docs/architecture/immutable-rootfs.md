# Immutable Rootfs And State Filesystem

Alpenglow has two deployment modes:

- **Diskless/immutable** — full OS in RAM (initramfs), immutable image, read-only `/`. State on persistent bcachefs.
- **Rootfs/desktop** — normal r/w root on disk, package-managed, no image layers.

This doc covers the immutable/appliance mode.

## Image Contract (appliance mode only)

The root image is sealed at build time by `system/backends/appliance/scripts/build-rootfs.sh`. Mounted read-only at `/` from RAM. Runtime writes are limited to tmpfs and the bcachefs-backed state partition at `/state`.

GlowIFS is the planned immutable format, but it is under development. Current appliance builds should treat EROFS or SquashFS as realistic immutable-image fallbacks while the repository's prototype `glowfs` code is still being renamed and redesigned.

GlowFS and GlowIFS are separate by design, but neither should be documented as production-ready yet. GlowIFS is the sealed appliance-root direction: immutable, read-only, digest-verified, and generation-oriented. GlowFS is the writable-filesystem direction: journaled, recoverable, allocation-aware, and suitable for normal POSIX writes. Appliance images should not depend on mutable GlowIFS behavior.

GlowIFS editability is planned as object policy rather than path-only policy. A path such as `/home` is just a binding to editable objects; the durable identity lives in the object manifest. The current bind-mount plan below is the practical compatibility shape until object-policy mounting exists.

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
