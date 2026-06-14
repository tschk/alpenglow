# Build

Alpenglow uses Cargo for OS Rust crates and shell scripts under `system/alpine/scripts` for the current reference image path.

## Rust

```bash
cargo build
cargo test -p sold
cargo test -p alpenglow-netd
cargo test -p alpenglow-kernelctl
cargo test -p glowfsctl
```

## OS Readiness

```bash
./install.sh --check
```

This validates the backend contract, GlowFS module source, kernel config policy, and Rust OS crates.

## Reference Image

```bash
```

