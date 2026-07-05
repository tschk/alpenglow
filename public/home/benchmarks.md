# Benchmarks

Recent QEMU KVM five-run medians:

| Target | Boot | Initramfs | Kernel | RAM |
| --- | ---: | ---: | ---: | ---: |
| Alpenglow minimal | 0.6s | 1.4K | 4.4MB | ~17MB |
| Alpenglow standard | 1.15s | 22MB | 6.0MB | ~87MB |
| Alpenglowed Desktop with Alpenglowed | 1.98s | 66MB | 6.0MB | ~253MB |

The browser VM on this page boots a 32-bit x86 Alpenglow initramfs because v86
does not support 64-bit kernels. Real Alpenglow images target x86_64 and
aarch64 Linux hardware.
