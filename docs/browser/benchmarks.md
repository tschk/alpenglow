# Benchmarks

Targets, not measurements. Public SKU contract numbers (2026-08-25): [Editions and roles](../editions-and-roles.md).

| Measurement | Target |
|-------------|--------|
| Boot to shell | ~2s |
| Idle RAM | <64 MiB |
| Kernel image | <8 MiB (`KERNEL_PROFILE=fast`) |
| Static kernelctl | ~72 KB |
| Oil binary | ~1 MB |

v86 browser demo is slower and heavier; it is a preview, not the performance target.
