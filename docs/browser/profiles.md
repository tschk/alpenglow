# Profiles

| Build | Scope |
|-------|-------|
| minimal | Headless appliance |
| standard | + toolchain |
| desktop | + graphics, audio, Wi-Fi, Alpenglowed |

| Kernel | Scope |
|--------|-------|
| fast | Smallest boot |
| minimal | Networked appliance |
| desktop | + display, audio, Wi-Fi |

v86 demo ships one fixed i686 initramfs (busybox + oksh + Oil + **fastfetch**).

### v86 kernel (browser only)

Layers on `i386_defconfig`:

| Layer | Source | Role |
|-------|--------|------|
| Base | `v86-i686.fragment` | initrd, serial 8250, devtmpfs |
| Fast trim | `v86-i686-fast.fragment` | **fast** + **strip-down** style: no netfilter/IPv6/WiFi, no FB/VT/input, no kallsyms/ftrace/BPF, async probe, HZ=1000, v86 mitigations off |

Not used for v86: **minimal** kernel profile (adds DRM/VT for native images). Not used: **minimal** build profile package set (dinit/toybox/chrony — native appliance only).

Rebuild after kernel changes: `FORCE_V86_KERNEL=1 sh scripts/build-v86-initramfs.sh`.
