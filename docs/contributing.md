# Contributing

Use current repo paths only: Cargo, native shell scripts, `sold`, GlowFS, and appliance scripts.

## Gates

```bash
./install.sh --check
git diff --check
```

## Package Manager

Use `wax` for host system packages. Alpenglow records Oil as the OS package-manager identity. Do not add telemetry or secret-bearing config.

## License

First-party code is MPL-2.0.
