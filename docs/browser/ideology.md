# Why Alpenglow

## Intentions

1. **Ship a small, fast appliance** -- boot, SSH, time, logs, optional desktop -- without dragging a general-purpose distro root.
2. **Make the OS replaceable** -- the running root is a versioned artifact; rollback is "boot the previous image", not surgery on `/usr`.
3. **Keep user and package state durable** -- `/state` on bcachefs so reinstall/upgrade does not nuke home or Oil pins.
4. **Stay honest about scope** -- no baked-in VPN mesh, no custom firewall product in base; add what your deployment needs via Oil or `/usr/local`.

## What makes us different

| Typical distro | Alpenglow |
|----------------|-----------|
| Mutable `/usr`, rolling updates on live system | Immutable RAM root image |
| Package manager owns the whole tree | Oil installs into composed root; system image is separate |
| Desktop ISO = large live environment | Profiles: minimal / standard / desktop on same philosophy |
| "Cloud image" or generic minimal | Purpose-built appliance: dinit graph, kernel profiles, kernelctl |

We optimize for **cold boot time**, **RAM footprint**, and **operational clarity** (what is in the image vs what is on `/state`) over feature checklists on the base image.

## Fastest and lightest

Targets (real hardware, not this browser VM):

- Sub-~2s to login on headless minimal
- Musl userspace, toybox core, parallel dinit
- Kernel profiles trim drivers: `fast` for smallest path, `desktop` only when you need GPU/audio/Wi-Fi firmware

The browser demo is **i686 v86** for accessibility; it is not the performance reference platform.

## Desktop profile (hybrid again)

`BUILD_PROFILE=desktop` adds graphics, audio, greetd, Alpenglowed, foot -- but the **root filesystem is still the immutable RAM image**. Only `/state` (and bind mounts from it) stays writable across reboots. That is the hybrid model: not "everything in RAM forever", not "classic mutable distro desktop either".