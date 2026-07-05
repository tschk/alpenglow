# Welcome

You are in `/home/alpenglow`.

No login prompt. No account gate. The browser surface lands directly in the
home folder and fetches these markdown files as plain user content.

The real Alpenglow system is a musl Linux distribution with an immutable root
image loaded into RAM. Persistent state, including `/home`, package state,
browser profiles, logs, and caches, stays on disk under a bcachefs-backed
`/state`.
