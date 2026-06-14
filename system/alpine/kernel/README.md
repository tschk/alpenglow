# Alpenglow Appliance Kernel

This directory contains the Alpine packaging and config inputs for the custom Alpenglow internet appliance kernel.

The target profile keeps the browser appliance path narrow:

- cgroup v2 controllers for `sold`, browser, and renderer resource policy
- Rust support for GlowFS and other memory-safe appliance kernel components
- zram swap compression
- virtio block, network, console, random, and GPU devices for QEMU and VM bring-up
- DRM/KMS framebuffer support for the fullscreen Servo surface
- seccomp and Landlock for browser/runtime sandboxing
- fq plus BBR for the browser-first networking profile
- GlowFS, ext4, squashfs, overlayfs, tmpfs, procfs, and sysfs as the retained filesystem set

The fragment intentionally disables broad desktop/server subsystems that are not part of the appliance runtime, including Bluetooth, USB mass storage, FireWire, InfiniBand, SCTP/DCCP, PPP, NFC, CIFS, NFS, SMB server, Btrfs, GFS2, OCFS2, ReiserFS, JFS, HFS, and non-virtio GPU families.

Validate the fragment or a generated full kernel `.config` without building the kernel:

```sh
./system/alpine/kernel/validate-kernel-config.sh
./system/alpine/kernel/validate-kernel-config.sh /path/to/linux/.config
```

The `APKBUILD` runs the same validator after `make olddefconfig`, so kernel default expansion cannot silently re-enable stripped subsystems or drop required appliance features.
