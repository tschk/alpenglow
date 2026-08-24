# Profiles

Build profiles are the userspace axis. Public SKUs are `potato`, `desktop`, and `internet` — see [Editions and roles](../editions-and-roles.md).

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

| Session | Scope |
|---------|-------|
| none | No graphical session |
| alpenglowed | Default desktop ([Alpenglowed](https://github.com/tschk/alpenglowed)) |
| sold | Optional [Soliloquy](https://github.com/tschk/soliloquy) session (not in this tree) |
| cage | Single-app kiosk |

v86 demo ships one fixed i686 initramfs.
