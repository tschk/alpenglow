# Profiles

Alpenglow separates **build profiles** (userspace image) from **kernel profiles** (hardware and boot policy).

| Build profile | Scope |
|---------------|--------|
| `minimal` | Headless appliance: shell, network, SSH, time, logs, DNS |
| `standard` | Minimal plus toolchain and system utilities |
| `desktop` | Standard plus graphics, audio, Wi‑Fi, greetd, Alpenglowed, foot |

| Kernel profile | Scope |
|----------------|--------|
| `fast` | Smallest diskless boot path |
| `minimal` | Networked appliance: cgroups, PSI, zram, seccomp, Landlock |
| `desktop` | Minimal plus display, audio, USB, HID, Wi‑Fi, firmware |

The v86 demo does not expose profile switching; it ships one fixed 32-bit initramfs described in `README.md`.