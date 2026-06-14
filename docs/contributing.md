# Contributing

Use current repo paths only: Cargo, Bun, `sold`, Servo/RV8 bridge scripts, and Alpine appliance scripts.

## Gates

```bash
cargo fmt --check
cargo test -p sold
cargo test -p sold
cargo test -p sol-netd
cargo test -p sol-kernelctl
cargo test -p glowfsctl
cd ui/desktop && bun run check && bun run build
```

## Package Manager

Use `wax` for system packages. Use `bun` for JavaScript. Do not add telemetry or secret-bearing config.

## License

First-party code is MPL-2.0.
