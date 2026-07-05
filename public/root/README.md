# Alpenglow

Shell-only browser build.

Alpenglow loads the operating system into RAM from an immutable image. Real
hardware builds keep `/home` and mutable state on disk under bcachefs-backed
`/state`.

This v86 build is 32-bit x86 because v86 does not run 64-bit kernels. The main
Alpenglow targets remain x86_64 and aarch64.

Run `./alpenglowed.sh` if you want the desktop path.
