# Benchmarks

Target: ~2s boot to login on headless minimal on real hardware.

| Measurement | Target |
|-------------|--------|
| Boot to shell | ~2s |
| Idle RAM | <64 MiB |
| Kernel image | <8 MiB (fast profile) |
| Static kernelctl | ~72 KB |
| Oil binary | ~1 MB |

v86 browser demo is slower and heavier; it is a preview, not the performance target.

## Browser guest boot

**boot:** (green) is kernel uptime at login inside v86. First visit also waits on WASM + v86 assets (CDN cache helps). Rebuild trimmed kernel: `V86_SSH=1` or `FORCE_V86_KERNEL=1` on Linux/docker ([profiles.md](profiles.md)).

## Browser serial banner

At login the demo prints **measured** boot seconds and memory use (green), not marketing targets. Color key: [readme.md](readme.md#boot-banner-colors).
