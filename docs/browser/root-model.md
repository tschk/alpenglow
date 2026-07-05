# Root model

## Production

1. **Immutable root** -- erofs or squashfs loaded into RAM at boot.
2. **`/state`** -- bcachefs volume; `/home` and Oil paths bind-mounted from it.
3. **Upgrade** -- replace root image artifact; keep `/state`.

## Desktop uses the same split

Alpenglowed, foot, PipeWire binaries are in the **image**. Your files and package choices are on **`/state`**. Fast boot + reproducible OS layer without wiping home.

## v86 demo

Writable tmpfs initramfs for docs and shell play -- no bcachefs mount.