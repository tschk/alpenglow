# Alpenglow Architecture (v0)

**Build**: Docker cross-compile in CI. Kernel: tracks kernel.org latest stable + custom config.
**Boot**: initramfs only (diskless) or ext4 root (rootfs mode).
**Init**: dinit (PID 1) — parallel dependency graph.
**Userland**: toybox + oksh. Static musl, no glibc.
**Package mgr**: Oil (Rust, APK-compatible).
**Net**: netd (Rust) reads /sys/class/net, emits JSON + env.
**Kernel ctrl**: kernelctl (Zig) sets cgroups + sysctls.
**Root FS**: GlowFS (kernel module), fallback erofs/squashfs.

See [AGENTS.md](../AGENTS.md) for full architecture table.
