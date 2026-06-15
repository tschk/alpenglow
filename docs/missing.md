# Missing — gaps between current state and production-ready appliance

| Gap | Priority | Notes |
|-----|----------|-------|
| Real hardware boot | HIGH | QEMU only. Need real NIC/disk/GPU drivers and boot testing on bare metal. |
| GlowFS kernel module | HIGH | Core feature (immutable rootfs). Builds but symbol exports broken; CI times out on kernel download. |
| Secure boot | MEDIUM | Kernel + initramfs not signed. UEFI Secure Boot = `sbctl` + enrolled keys. |
| FDE (state partition) | MEDIUM | Persistent data on ext4, unencrypted. Add cryptsetup + LUKS to initramfs. |
| Over-the-air updates | MEDIUM | No atomic update mechanism. A/B rootfs slots or `rauc` + `swupdate`. |
| Backup/restore | LOW | No state snapshot/restore tooling. `tar` + `rclone` covers 90%. |
| User provisioning | LOW | No `adduser`, no PAM. getty + manual `/etc/passwd` editing. toybox has `adduser` but not wired into init. |
| Monitoring | LOW | No health checks. `ponytail: add when someone pages you` |
| VPN / WireGuard | N/A | User-installable via Oil, not part of base. |
| Container runtime | N/A | Not planned. Appliance runs native services. |
| SELinux / AppArmor | N/A | Kernel has LSM but no policy loaded. Not needed for single-purpose appliance. |
