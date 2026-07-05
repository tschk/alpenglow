# Why Alpenglow

## Intentions

1. **Ship a small, fast OS** -- headless appliance *or* a real **desktop** (Wayland, Alpenglowed, foot) on the same immutable-root model.
2. **Make the OS replaceable** -- the running root is a versioned artifact; rollback is "boot the previous image", not surgery on `/usr`.
3. **Keep user and package state durable** -- `/state` on bcachefs so reinstall/upgrade does not nuke home or Oil pins.
4. **Stay honest about scope** -- no baked-in VPN mesh in base; add what your deployment needs via Oil or `/usr/local`.

## Headless and desktop (both first-class)

| Profile | What you get |
|---------|----------------|
| `minimal` / `standard` | Appliance: SSH, net, time, logs, Oil -- smallest boot path |
| `desktop` | Above plus greetd, PipeWire, Wi-Fi stack, **Alpenglowed** compositor, foot terminal |

We are **not** "appliance only with desktop as an afterthought". Desktop is a **product profile** with the same hybrid root model as headless.

## What makes us different

| Typical distro | Alpenglow |
|----------------|-----------|
| Mutable `/usr`, rolling updates on live system | Immutable RAM root image |
| Package manager owns the whole tree | Oil installs into composed root; system image is separate |
| Large desktop live ISO | Profiles on one philosophy: minimal / standard / desktop |
| Generic cloud or desktop image | Purpose-built: dinit graph, kernel profiles, kernelctl |

We optimize for **cold boot time**, **RAM footprint**, and **clear split** (image vs `/state`) over base-image feature bloat.

## Fastest and lightest

Targets (real hardware, not this browser VM):

- Sub-~2s to login on headless minimal
- Musl userspace, toybox core, parallel dinit
- Kernel profiles: `fast`, `minimal`, `desktop` (GPU/audio/Wi-Fi when needed)

Browser demo is **i686 v86** for accessibility; not the performance reference.

## Hybrid model (headless and desktop)

**Root** = immutable erofs/squashfs in RAM. **`/state`** = bcachefs on disk (home, Oil, caches). Desktop sessions use the same split: reproducible OS layer, durable user data -- not "everything in RAM forever" and not a classic mutable distro desktop either.