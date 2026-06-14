# Developer Guide

## Local Loop

```bash
./scripts/ci-os-appliance.sh
./scripts/ci-rust-core.sh
```

## Image Loop

```bash
SERVO_DIR=/path/to/alpenglow-servo QEMU_RUN=0 ./system/alpine/scripts/qemu-v0.sh
```

Use `SERVO_SOURCE_BUILD=0` to test the release fallback. That path currently fails the required `--no-browser-chrome` compatibility check.
