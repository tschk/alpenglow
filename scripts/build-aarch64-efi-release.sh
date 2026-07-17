#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
EDITION="${1:?edition required}"
VERSION="${2:?version required}"
INSTALLER="${3:?installer required}"
OUT_DIR="${ROOT_DIR}/build/release"
ARM_DIR="${ROOT_DIR}/build/cross/aarch64"
ASSET_DIR="${OUT_DIR}/assets"
ASSET_BASE="alpenglow-${VERSION}-${EDITION}-aarch64"
IMAGE="${OUT_DIR}/alpenglow-aarch64.img"
ESP_IMAGE="${OUT_DIR}/alpenglow-aarch64-esp.img"
ISO="${ASSET_DIR}/${ASSET_BASE}.iso"
COMPRESSED_IMAGE="${ASSET_DIR}/${ASSET_BASE}.img.zst"
LIVE_INITRAMFS="${ARM_DIR}/initramfs-${EDITION}-live.cpio.gz"
EFI_BINARY="${OUT_DIR}/BOOTAA64.EFI"
BOOT_CONFIG="${OUT_DIR}/grub-aarch64.cfg"
LIVE_CONFIG="${OUT_DIR}/grub-aarch64-live.cfg"
ISO_ROOT="${OUT_DIR}/iso-aarch64"
MNT_ESP="${OUT_DIR}/mnt/esp-aarch64"
LOOP_DEV=""
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-2048}"
ESP_SIZE_MB="${ESP_SIZE_MB:-512}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" > "$1.sha256"
  else
    shasum -a 256 "$1" > "$1.sha256"
  fi
}

cleanup() {
  if [ -n "${LOOP_DEV}" ]; then
    sudo umount "${MNT_ESP}" >/dev/null 2>&1 || true
    sudo losetup -d "${LOOP_DEV}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for cmd in cpio grub-mkstandalone gzip losetup mcopy mmd mkfs.bcachefs mkfs.vfat sgdisk sudo xorriso zstd; do
  require_cmd "${cmd}"
done

test -x "${INSTALLER}"
sh "${ROOT_DIR}/scripts/build-aarch64-desktop.sh" "${EDITION}"

KERNEL="${ARM_DIR}/vmlinuz-${EDITION}"
INITRAMFS="${ARM_DIR}/initramfs-${EDITION}.cpio.gz"
ROOTFS="${ARM_DIR}/rootfs-${EDITION}"
test -s "${KERNEL}"
test -s "${INITRAMFS}"
test -d "${ROOTFS}"

mkdir -p "${OUT_DIR}" "${ASSET_DIR}" "${MNT_ESP}"
cat > "${BOOT_CONFIG}" <<'EOF'
set timeout=3
set default=0

menuentry 'Alpenglow desktop' {
  linux /EFI/Alpenglow/vmlinuz console=tty0 console=ttyAMA0,115200 init=/init alpenglow.state=LABEL=alpenglow-state
  initrd /EFI/Alpenglow/initramfs.cpio.gz
}
EOF
grub-mkstandalone -O arm64-efi -o "${EFI_BINARY}" "boot/grub/grub.cfg=${BOOT_CONFIG}"
file "${EFI_BINARY}" | grep -Eqi 'aarch64|arm aarch64'

rm -f "${IMAGE}"
truncate -s "${IMAGE_SIZE_MB}M" "${IMAGE}"
sgdisk -o "${IMAGE}" >/dev/null
sgdisk -n 1:2048:+"${ESP_SIZE_MB}"M -t 1:EF00 -c 1:ALPENGLOW-EFI "${IMAGE}" >/dev/null
sgdisk -n 2:0:0 -t 2:8300 -c 2:alpenglow-state "${IMAGE}" >/dev/null
LOOP_DEV="$(sudo losetup --find --show --partscan "${IMAGE}")"
sudo mkfs.vfat -F 32 -n ALPENGLOW_EFI "${LOOP_DEV}p1" >/dev/null
sudo mkfs.bcachefs -L alpenglow-state "${LOOP_DEV}p2" >/dev/null
sudo mount "${LOOP_DEV}p1" "${MNT_ESP}"
sudo mkdir -p "${MNT_ESP}/EFI/BOOT" "${MNT_ESP}/EFI/Alpenglow"
sudo cp "${EFI_BINARY}" "${MNT_ESP}/EFI/BOOT/BOOTAA64.EFI"
sudo cp "${KERNEL}" "${MNT_ESP}/EFI/Alpenglow/vmlinuz"
sudo cp "${INITRAMFS}" "${MNT_ESP}/EFI/Alpenglow/initramfs.cpio.gz"
sudo umount "${MNT_ESP}"
sudo losetup -d "${LOOP_DEV}"
LOOP_DEV=""

zstd -T0 -19 -f "${IMAGE}" -o "${COMPRESSED_IMAGE}"
sha256_file "${COMPRESSED_IMAGE}"

mkdir -p "${ROOTFS}/run/alpenglow" "${ROOTFS}/usr/bin"
cp "${INSTALLER}" "${ROOTFS}/usr/bin/alpenglow-install"
cp "${COMPRESSED_IMAGE}" "${ROOTFS}/run/alpenglow/alpenglow.img.zst"
(cd "${ROOTFS}" && find . -print | cpio -o -H newc 2>/dev/null | gzip -1 > "${LIVE_INITRAMFS}")

cat > "${LIVE_CONFIG}" <<'EOF'
set timeout=3
set default=0

menuentry 'Alpenglow live installer' {
  linux /EFI/Alpenglow/vmlinuz console=tty0 console=ttyAMA0,115200 init=/init alpenglow.live=1
  initrd /EFI/Alpenglow/initramfs.cpio.gz
}
EOF
grub-mkstandalone -O arm64-efi -o "${EFI_BINARY}" "boot/grub/grub.cfg=${LIVE_CONFIG}"

rm -rf "${ISO_ROOT}" "${ESP_IMAGE}" "${ISO}"
mkdir -p "${ISO_ROOT}/EFI/BOOT" "${ISO_ROOT}/EFI/Alpenglow"
truncate -s 64M "${ESP_IMAGE}"
mkfs.vfat -F 32 -n ALPENGLOW_ISO "${ESP_IMAGE}" >/dev/null
MTOOLS_SKIP_CHECK=1 mmd -i "${ESP_IMAGE}" ::/EFI ::/EFI/BOOT ::/EFI/Alpenglow
MTOOLS_SKIP_CHECK=1 mcopy -i "${ESP_IMAGE}" "${EFI_BINARY}" ::/EFI/BOOT/BOOTAA64.EFI
MTOOLS_SKIP_CHECK=1 mcopy -i "${ESP_IMAGE}" "${KERNEL}" ::/EFI/Alpenglow/vmlinuz
MTOOLS_SKIP_CHECK=1 mcopy -i "${ESP_IMAGE}" "${LIVE_INITRAMFS}" ::/EFI/Alpenglow/initramfs.cpio.gz
cp "${ESP_IMAGE}" "${ISO_ROOT}/efi.img"
xorriso -as mkisofs -o "${ISO}" -V ALPENGLOW -r -J \
  -eltorito-alt-boot -e efi.img -no-emul-boot -isohybrid-gpt-basdat "${ISO_ROOT}" >/dev/null
sha256_file "${ISO}"

printf '%s\n%s\n' "${COMPRESSED_IMAGE}" "${ISO}"
