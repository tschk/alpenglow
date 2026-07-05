# Root Model

Alpenglow boots from an immutable image loaded into RAM.

The root filesystem is replaceable. Mutable data is not stored there. Real
installations keep `/home` and machine state under bcachefs-backed `/state`,
then bind the needed paths into the running system.

This gives Alpenglow a simple update model: build a new image, boot it, keep
the user's data and package state.
