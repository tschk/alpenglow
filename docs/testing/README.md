# Soliloquy Testing Documentation

Current test coverage is centered on Rust, Bun, the local `sold` bridge, and targeted Servo/RV8 checks.

## Quick Start

```bash
cargo test -p sold
cargo test -p sold
cargo test -p sol-netd
cargo test -p sol-kernelctl
cargo test -p glowfsctl
```

The sibling RV8 repo is available at `../rv8`:

```bash
cargo test --manifest-path ../rv8/Cargo.toml
```

For UI checks:

```bash
cd ui/desktop
bun run check
bun run build
```

For macOS desktop shell smoke checks:

```bash
./tools/soliloquy/smoke_macos.sh
```

The macOS smoke path compiles the non-GPUI desktop path, compiles the Crepuscularity GPUI desktop path, and dry-runs the desktop launch contract. It is intended for pre-launch validation and does not keep a GUI process open. Svelte and `sold` checks are appliance checks, not desktop browser checks.
Because the smoke command uses `SOL_MACOS_DRY_RUN=1`, it does not start `sold`. A real `tools/soliloquy/start_macos.sh` launch can start or reuse `sold` for runtime APIs while still avoiding the Svelte appliance chrome.

For Servo/RV8 bridge checks:

```bash
./tools/rv8_servo_test.sh bridge
./tools/rv8_servo_test.sh v8
```

## Appliance Checks

```bash
sh -n system/alpine/scripts/*.sh
./system/alpine/scripts/qemu-v0.sh
```

For build-only validation:

```bash
QEMU_RUN=0 ./system/alpine/scripts/qemu-v0.sh
```

For scripted contract checks:

```bash
./scripts/ci-os-appliance.sh
QEMU_TIMEOUT=180 ./scripts/ci-qemu-appliance.sh
```

`qemu-v0.sh` builds the Svelte bundle, prepares Linux runtime binaries, stages `ui/desktop/build` at `/usr/local/share/soliloquy/bundle`, overlays `bundle/terminal`, builds the rootfs image and initramfs, and starts QEMU when `QEMU_RUN=1`.

Wayland appliance boot should show Cage/Wayland, `sold` health, `/api/runtime` readiness, a Soliloquy title redraw, and Servo paint completion in serial logs. `scripts/ci-qemu-appliance.sh` is the current headless visual-smoke gate for those log signals.
The default appliance config sets `SOL_SERVO_NO_BROWSER_CHROME=1`; visual checks should show only Soliloquy's Svelte appliance browser chrome, not Servo's built-in toolbar.
