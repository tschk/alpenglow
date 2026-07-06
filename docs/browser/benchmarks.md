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

## Web vs guest boot

| Line | What it measures |
|------|------------------|
| **boot:** (green, in guest) | Kernel uptime at login (~2s target inside the VM) |
| **web:** (dim, host terminal) | Wall clock from page load until the oksh prompt (mostly WASM + ~18MB v86 assets on first visit; CDN cache helps after) |

Lowering **web** time: long-lived CDN cache on `/_astro/*` and `/v86/*`, smaller initrd (`V86_SKIP_VRO=1` only drops vro, **fastfetch stays**), rebuild i686 kernel with `v86-i686-fast.fragment` (`FORCE_V86_KERNEL=1`). Lowering **boot:** guest uses fast-style kernel trims (see [profiles.md](profiles.md)); initramfs stays demo-rich (fastfetch, Oil, docs).

## Browser serial banner

At login the demo prints **measured** boot seconds and memory use (green), not marketing targets. Color key: [readme.md](readme.md#boot-banner-colors).
