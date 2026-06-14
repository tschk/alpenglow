# Testing

## Quick Start

```bash
./install.sh --check
```

## Focused Gates

```bash
./scripts/ci-os-appliance.sh
./scripts/ci-rust-core.sh
./scripts/ci-glowfs-kernel-module.sh
```

## Reference Boot Work

```bash
SERVO_DIR=/path/to/alpenglow-servo QEMU_RUN=0 ./system/alpine/scripts/qemu-v0.sh
```

The QEMU path is not yet a passing complete-boot proof in the standalone OS shape. See [Readiness](../readiness.md).
