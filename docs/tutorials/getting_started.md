# Getting Started

1. Install Rust, Bun, and system packages through `wax`.
2. Run Rust checks:

```bash
cargo test -p sold
```

3. Build the UI:

```bash
cd ui/desktop
bun install
bun run build
```

4. Start local runtime:

```bash
./tools/soliloquy/start.sh
```
