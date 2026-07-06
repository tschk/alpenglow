# Why Alpenglow

Immutable Linux stack. Fast, small RAM, modern desktop.

## Stack

| Layer | Choice |
|-------|--------|
| Boot | initramfs + erofs/squashfs in RAM |
| Init | dinit |
| Userland | toybox |
| Shell | oksh |
| Packages | Oil / wax (Rust) |
| Kernel | Linux 7.x profiles |
| Policy | kernelctl (Zig, ~72KB) + netd |

Efficiency: small static binaries, no bloat.

## Desktop

[Alpenglowed](../alpenglowed): Wayland GPUI bar. foot, PipeWire, iwd.

## Browser demo

i686 v86 serial shell. Not the Wayland reference.
