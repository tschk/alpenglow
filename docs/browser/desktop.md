# Desktop (demo vs production)

## Hybrid model (important)

Alpenglow desktop is **not** "everything diskless in RAM". It is:

- **Immutable RAM root** -- OS tree, compositor binaries, system services baked into the image.
- **Persistent `/state`** -- home, Oil, logs, user config on bcachefs.

Fast boot and reproducible system layer; your files and package choices survive image updates.

## Browser demo

Serial shell only in v86 (this page). No Wayland in the browser initramfs today.

## Production (`BUILD_PROFILE=desktop`)

greetd, seatd, PipeWire, iwd, **Alpenglowed** + foot on the immutable RAM-root image. Optional cage-style demos exist for QEMU smoke tests; product path is Alpenglowed (Smithay), not cage as the shipping compositor.

See `ideology.md` and `root-model.md` for why we call this a hybrid.