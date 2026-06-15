# Alpenglow — Rust Optimization TODO

## ✅ Done (this branch)

### kernelctl — sync rewrite
- [x] Removed tokio (full → nothing)
- [x] Replaced JoinSet parallelism with sequential loops
- [x] tokio::fs → std::fs, tokio::process → std::process
- [x] Tests pass (6/6)

### netd — type fix
- [x] `generated_unix_ms: u128` → `u64` (correct for unix ms)

### glowfsctl — buffer & hex fixes
- [x] `write_zeroes_until` uses fixed 4KB buffer loop (no `vec![0; n]` for large gaps)
- [x] `hex_digest` uses `write!` into pre-allocated String

### Oil — purpose-built APK manager
- [x] Removed 26 source files (Homebrew, non-APK registries, etc.)
- [x] tokio+reqwest → ureq (sync)
- [x] tracing → eprintln
- [x] indicatif/console/inquire → plain stdout
- [x] rayon → sequential
- [x] thiserror → manual Display impls
- [x] Delete non-APK archive formats (zstd, xz, bzip2, rpm, deb, pacman, xbps, nar)
- [x] Delete multi-registry support (apt, dnf, pacman, xbps, nix)
- [x] Delete Homebrew clone (api, bottle, builder, cask, formula, tap, services, bundle, doctor, etc.)
- [x] APK-only CLI: search, info, list, install, uninstall, upgrade, outdated, pin, etc.
- [x] Tests pass (16/16)

### Release profile
- [x] `opt-level = "z"`, `lto = "fat"`, `strip = true`, `codegen-units = 1`

## 📋 To Do

### High priority
- [ ] Verify release binaries boot in initramfs (`cargo build --release` → `scripts/boot-native.sh`)

### Medium
- [ ] Oil: replace remaining `serde_json` with `miniserde` or manual JSON (saves ~15 crates)
- [ ] kernelctl: remove `serde_json` dependency, parse JSON with `miniserde` or manual
- [ ] netd: remove `axum` dependency, use `std::net::TcpListener` + manual HTTP
- [ ] netd: remove `serde_json`, inline JSON rendering
- [ ] kernelctl: replace `std::process::Command::new("modprobe")` with direct syscall via `libc::syscall`

### Low priority / Future
- [ ] Remove `tempfile` dependency from all crates (use `/tmp/` + `std::fs::rename` directly)
- [ ] netd: investigate tracing removal (already sync, need log rotation story)
- [ ] Zig via equilibrium: new <100KB initramfs helpers (kernel-adjacent, syscall wrappers)
