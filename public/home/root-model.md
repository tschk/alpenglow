# Root Model

Alpenglow has one root model.

The system image is immutable and loaded into RAM at boot. The OS can be
replaced atomically without mutating the running root.

Mutable data stays on disk:

- `/home`
- package state
- browser profiles
- logs
- caches
- host-specific state

The target persistent filesystem is bcachefs-backed `/state`, with bind mounts
placing user state where normal Linux software expects it.
