# Alpenglow Docs

Current docs cover the active Cargo workspace, appliance backend, kernel policy, GlowFS, and architecture.

## Quick Start

```sh
# Build + boot the native appliance
./scripts/boot-native.sh

# Or just boot
system/backends/appliance/scripts/qemu.sh
```

## Key Paths

| What | Where |
|------|-------|
| Kernel configs | `system/backends/appliance/kernel/` |
| Kernel policy | `system/backends/appliance/kernel-policy.json` |
| QEMU runner | `system/backends/appliance/scripts/qemu.sh` |
| Dinit services | `system/backends/appliance/dinit/` |
| Appliance build | `scripts/boot-native.sh` |
| CI tests | `scripts/ci-*.sh` |

## Architecture

- [Index](./INDEX.md)
- [Build](./build.md)
- [Contributing](./contributing.md)
- [Readiness](./readiness.md)
- [V0 Architecture](./v0-architecture.md)
- [Appliance System](./architecture/appliance-system.md)
- [Browser-Centric OS Optimization](./architecture/browser-centric-os.md)
- [OS Optimization Plan](./architecture/os-optimization-plan.md)
- [API Contract](./api_contract.md)

## Reference Backends

- `system/alpine/` — legacy Alpine reference (kernel configs symlinked to appliance)
- `system/backends/void/` — Void Linux reference (deprecated)
