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
