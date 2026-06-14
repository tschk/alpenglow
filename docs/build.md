# Build

Soliloquy uses Cargo for Rust, Bun for the Svelte UI, and `system/alpine/scripts` for appliance staging.

## Rust

```bash
cargo build
cargo test -p sold
cargo test -p sold
cargo test -p sol-netd
cargo test -p sol-kernelctl
cargo test -p glowfsctl
```

The sibling RV8 repo is checked directly:

```bash
cargo test --manifest-path ../rv8/Cargo.toml
```

## UI

```bash
cd ui/desktop
bun install
bun run check
bun run build
```

## macOS Desktop Smoke

```bash
./tools/soliloquy/smoke_macos.sh
```

This checks the non-GPUI desktop binary, checks the Crepuscularity GPUI desktop binary, and dry-runs the macOS launch contract. The supported macOS desktop path is Crepuscularity chrome plus Servo with `--no-browser-chrome`; it must not load the Svelte appliance chrome. The Svelte desktop bundle belongs to the Alpine appliance path.
The smoke script sets `SOL_MACOS_DRY_RUN=1`, so it checks the launch contract without starting `sold` or opening a persistent GUI.

To launch the macOS browser:

```bash
./tools/soliloquy/start_macos.sh
```

The real macOS launcher starts or reuses `sold` for local runtime APIs, then launches the Crepuscularity GPUI chrome with Servo's built-in browser chrome disabled. It still does not serve the Svelte appliance chrome.

## Local Runtime

```bash
./tools/soliloquy/start.sh
```

The appliance session defaults to `SOL_SERVO_NO_BROWSER_CHROME=1`. Keep Soliloquy's Svelte appliance shell as the single visible browser chrome; Servo should render page content only. Browser UI modes are available from the appliance chrome: Zen sidebar, compact, split columns, split rows, and grid.

## Alpine Appliance

```bash
./system/alpine/scripts/setup-host.sh
./system/alpine/scripts/qemu-v0.sh
```

`qemu-v0.sh` builds `ui/desktop/build`, prepares Linux runtime binaries, stages the bundle at `/usr/local/share/soliloquy/bundle`, builds the rootfs image, creates the initramfs, and runs QEMU. Use `QEMU_RUN=0 ./system/alpine/scripts/qemu-v0.sh` to verify all build and staging steps without launching the VM.

Validate the custom appliance kernel profile without a full kernel build:

```bash
./system/alpine/kernel/validate-kernel-config.sh
./system/alpine/kernel/validate-kernel-config.sh /path/to/linux/.config
```

The custom kernel packaging scaffold lives under `system/alpine/kernel`. Its fragment keeps cgroup v2, zram, virtio, DRM/KMS, seccomp, Landlock, fq, and BBR enabled while rejecting unused desktop/server drivers, filesystems, and network protocols.
