# Alpenglow Architecture (v0)

**Build**: Docker cross-compile in CI. Kernel: tracks kernel.org latest stable + custom config.
**Boot**: initramfs only; complete immutable root image loaded into RAM.
**Init**: dinit (PID 1) — parallel dependency graph.
**Userland**: toybox + oksh. Static musl, no glibc.
**Package mgr**: Oil (Rust, APK-compatible).
**Net**: netd (Zig) reads /sys/class/net, emits JSON + env.
**Kernel ctrl**: kernelctl (Zig) sets cgroups + sysctls.
**Root FS**: erofs/squashfs immutable image in RAM; bcachefs for `/state` and `/home`.

See [AGENTS.md](../AGENTS.md) for full architecture table.
