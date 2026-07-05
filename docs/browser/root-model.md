# Root model

Alpenglow boots from an **immutable root image** loaded into RAM (erofs or squashfs in production initramfs).

Mutable data—`/home`, Oil state, logs, caches—is kept on **bcachefs-backed `/state`** and bind-mounted into the running system. Replacing the OS image does not wipe user data or package metadata.

The browser demo uses a single writable tmpfs layout inside a small initramfs to illustrate commands and documentation; it does not mount bcachefs.