# v0.1.721 release boot audit

For the corrected release decision, see [v0.1.722 release readiness](release-v0.1.722-readiness.md).

## The release gate did not prove a usable boot

The common x86 release image had multiple independent blockers: an absent BIOS boot chain, then, in a fresh corrected build, a shell unable to execute the state script, unresolved state labels, missing disk support, and services whose executables were absent. Reaching the kernel alone would not establish a usable system. The release pipeline did not boot the x86 disk and verify its state mount before upload. That missing end-to-end gate allowed these failures to escape together; fixing individual faults without adding that gate would leave the same gap.

The workflow does include a separate aarch64 desktop ISO QEMU check, but it checks only for the root-ready message, not a working desktop, state, or installation. It did not cover the common x86 disk path.

## Suppressed bootloader failure produced unbootable disks

The common disk builder extracted the Limine 12.4.0 binary distribution without compiling its Linux `limine` utility. That distribution contains `limine.c` and a Makefile, not a Linux executable. The builder then ignored errors from `limine bios-install`. Independently, its partition named `Limine` had GPT type `8301` (Linux reserved), but Limine selects a BIOS boot partition by type `EF02`, not by name. Either a missing executable or the incorrect type can prevent the install. The released image alone does not establish which error occurred in its build.

The common builder also compiles Toybox and dinit in `linux/amd64` containers, targets Zig at x86_64, and builds an x86 kernel even when the release target is aarch64. The separate aarch64 desktop builder does not use that path.

## Published assets inspected

The checks below used checksum-verified v0.1.721 downloads, QEMU TCG, and disposable read-only images. They do not establish behavior on all physical machines.

### No working boot chain for the advertised architecture

- The x86_64 potato, internet, and desktop disk images have zero MBR boot-code bytes, an empty Linux-reserved partition named `Limine`, and no EFI System Partition. SeaBIOS did not reach Linux, and OVMF entered its firmware shell for each disk.
- The aarch64 potato and internet disks have x86 kernels, x86 initramfs executables, and no EFI System Partition. ARM64 UEFI QEMU entered its firmware shell for both. Their live ISO kernels and initramfs executables are also x86, although the ISOs contain an aarch64 installer; these ISOs cannot boot the advertised architecture with those payloads.

### Conditional failure

The x86_64 potato live ISO reached serial login under SeaBIOS. Under the tested OVMF configuration, Limine panicked because its non-relocatable kernel could not load at the required address `0x1000000`. This does not establish failure on every UEFI firmware.

### Booted, but unusable as tested

- The x86_64 desktop live ISO reached Linux and init under SeaBIOS and OVMF, then entered dinit boot-failure recovery. No state disk or network was attached.
- The aarch64 desktop disk reached its root-ready message, but its graphical session failed. In QEMU 7.2.22 with ARM UEFI and Cortex-A72, the tested minimum for reaching root-ready was 1,288 MiB RAM, with three successful runs. At 1,287 MiB, three runs reported `Initramfs unpacking failed: write error`, followed by `Kernel panic - not syncing: Requested init /init failed (error -26)`. This minimum is specific to that virtual machine, not physical hardware.

### Limited boot control

The x86_64 internet live ISO reached a serial login prompt under both SeaBIOS and OVMF. No interactive authentication, installer, or persistence was tested. None of these observations establishes a usable desktop.

The corresponding release assets have not been changed. Wait for a corrected and verified release rather than treating the limited boot tests as proof of a working installation.

In the aarch64 desktop QEMU guest, devtmpfs hid the staged `/dev/pts` directory, and devpts was not mounted. A diagnostic image that recreated `/dev/pts` before mounting devpts let foot open a PTY. The guest had seatd and input device nodes but no udev daemon or `/run/udev/data`. Synthetic metadata for the two emulated input devices let seatd open them. Adding a `/dev/shm` tmpfs then let QEMU-injected keystrokes reach the foot shell. These diagnostic changes are not a release fix and do not establish behavior for other devices or physical hardware.

## Corrected release work

- [ ] Verify a corrected x86 release on the normal release build host. A fresh local build with the corrected shell, service graph, kernel, initramfs and real bcachefs state passed `scripts/test-release-x86-boot.sh` under both SeaBIOS and OVMF: each reached a root shell, mounted `/state` read-write as bcachefs, and retained a marker across a forced guest reset using a disposable persistent overlay. This does not verify graceful shutdown or physical hardware. The orb lacked a FAT kernel driver, so image assembly used an experimental FUSE FAT mount. One compressed copy contained a corrupted initramfs even though a later read of the disk was intact; the passing run used a flushed copy. Repeat on the normal release build host without FUSE before treating the release as reproducible.
- [x] Put Limine's BIOS stage 3 on a FAT32 EFI System Partition, and provide the EFI executable for UEFI boot.
- [ ] Fix the x86 potato live ISO's Limine failure under OVMF. Investigate the non-relocatable kernel's required load address `0x1000000`, then rerun the affected ISO under OVMF.
- [ ] Build the aarch64 potato and internet images with an ARM64 kernel and userspace and a UEFI boot chain, then boot their disk and live ISO assets.
- [ ] Build and boot a fresh aarch64 desktop image with devpts and `/dev/shm` mounted after devtmpfs. Use eudev and its hardware database to populate device metadata, wait for coldplug before starting the desktop, and keep the daemon running for subsequent events. A disposable diagnostic image with real eudev reached a foot shell in QEMU; physical hardware and hotplug remain unverified. Run `scripts/test-aarch64-desktop-pty-qemu.sh` against the built kernel and initramfs to verify a shell on a PTY.
- [ ] Verify the desktop service, graphical installer, interactive login, and persistent state on each supported desktop target.

## Release checks

The release scripts check the kernel header and every ELF in the staged root filesystem and live installer against the advertised architecture. The check also reads compressed kernel modules. UEFI disks must contain a GPT EFI System Partition with a FAT boot sector. BIOS disks must contain MBR boot code and a non-empty GPT BIOS boot partition of type `EF02`. These checks detect architecture and partition errors but do not by themselves prove that firmware can boot an image or that the installed system works.

One compressed disk had an initramfs of the correct 4,706,426-byte length, but its contents included zeroed regions and its SHA-256 did not match the input; LZ4 rejected it. A later compressed copy and the later raw disk matched the input. Both Zstandard streams were valid. The evidence is consistent with writes not yet being visible when the first copy was read, but does not distinguish missing synchronization, FUSE behavior, or a concurrent write. The builder now requires a successful boot-filesystem unmount after synchronization, and the x86 asset build extracts the initramfs from the actual compressed disk and compares both size and SHA-256 against the input. A size-only check would have certified this corrupt file: verify the content that matters, not an adjacent property. This check does not establish that the experimental FUSE assembly path is reproducible or that the remaining disk contents are correct.
