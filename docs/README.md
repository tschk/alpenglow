# Alpenglow Docs

## Quick Start

```sh
# Build + boot
./scripts/boot-native.sh
system/backends/appliance/scripts/qemu.sh
```

## Key Paths

| What | Where |
|------|-------|
| Kernel configs | `system/backends/appliance/kernel/` |
| QEMU runner | `system/backends/appliance/scripts/qemu.sh` |
| Dinit services | `system/backends/appliance/dinit/` |
| Appliance build | `scripts/boot-native.sh` |
| CI tests | `scripts/ci-*.sh` |

## Architecture

- [Index](./INDEX.md)
- [V0 Architecture](./v0-architecture.md)
- [Appliance System](./architecture/appliance-system.md)
- [Immutable Rootfs](./architecture/immutable-rootfs.md)
