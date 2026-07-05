# Alpenglow

This is the Alpenglow browser shell image running in v86. It is not the full
x86_64 or aarch64 system image.

The system image is copied into RAM and treated as immutable after boot.
Real hardware keeps `/home` and machine state on disk under bcachefs-backed
`/state`, so the OS can stay replaceable without wiping user data.

This image uses a 32-bit v86-compatible kernel and a small Alpenglow initramfs
payload. The real Alpenglow targets remain x86_64 and aarch64.

Run `./alpenglowed.sh` to see how the desktop build fits in.
