# Root model

## Production appliance

1. **Immutable root** -- erofs or squashfs loaded into RAM at boot (diskless system image).
2. **Mutable state** -- bcachefs volume **`/state`**, with `/home` and Oil paths bind-mounted from it.
3. **Upgrade** -- new root image + same `/state` = new OS, same data.

Replacing the image does not wipe package metadata or home directories.

## Hybrid desktop

Desktop builds use the **same split**:

- Compositor, foot, PipeWire, Wi-Fi stack live in the **immutable root image** (versioned, replaced as a unit).
- Sessions, dotfiles, user packages, caches live under **`/state`**.

So desktop Alpenglow is **not** fully diskless end-to-end; it is **RAM-immutable OS + disk-backed user/system state**. Headless minimal is the same pattern with a smaller image.

## Browser demo

Single writable layout inside a small initramfs for `cat *.md` and shell play. No bcachefs here -- illustrates commands only.