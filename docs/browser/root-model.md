# Root model

- Immutable root: erofs/squashfs in RAM
- `/state`: bcachefs; `/home` and Oil bind-mounted
- Upgrade: replace root image, keep `/state`

v86 demo: writable tmpfs, no bcachefs.
