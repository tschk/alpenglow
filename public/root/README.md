# Alpenglow

This is the minimal Alpenglow browser image running in v86.

The system image is copied into RAM and treated as immutable after boot.
Real hardware keeps `/home` and machine state on disk under bcachefs-backed
`/state`, so the OS can stay replaceable without wiping user data.

The browser build uses a 32-bit v86-compatible kernel because v86 is a 32-bit
x86 emulator. The normal Alpenglow targets remain x86_64 and aarch64.

Alpenglowed is the desktop path. Run `./alpenglowed.sh` for the build target.

Links:
https://tsc.hk
https://github.com/tschk/alpenglow
https://github.com/tschk/alpenglowed
https://github.com/sponsors/tschk
