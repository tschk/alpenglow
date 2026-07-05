# Profiles

Alpenglow separates **build profiles** (userspace image) from **kernel profiles** (hardware and boot policy). Desktop means **Alpenglowed** + foot + audio/Wi-Fi -- see `desktop.md`.

| Build profile | Scope |
|---------------|--------|
| `minimal` | Headless appliance: shell, network, SSH, time, logs, DNS |
| `standard` | Minimal plus toolchain and system utilities |
| `desktop` | Standard plus graphics, audio, Wi-Fi, greetd, Alpenglowed, foot (hybrid: RAM root + `/state` on disk) |

| Kernel profile | Scope |
|----------------|--------|
| `fast` | Smallest diskless boot path |
| `minimal` | Networked appliance: cgroups, PSI, zram, seccomp, Landlock |
| `desktop` | Minimal plus display, audio, USB, HID, Wi‑Fi, firmware |

The v86 demo does not expose profile switching; it ships one fixed i686 initramfs. See `ideology.md` for intent and `root-model.md` for the hybrid desktop model.
