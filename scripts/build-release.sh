#!/bin/sh
# Build a bootable Alpenglow disk image for real hardware.
# Uses Limine bootloader, creates GPT disk with boot + state partitions.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/initramfs-codec-identity.sh"
OUT_DIR="${ROOT_DIR}/build/release"
IMAGE="${OUT_DIR}/alpenglow.img"
KERNEL="${OUT_DIR}/vmlinuz"
INITRAMFS=""
LIMINE_DIR="${OUT_DIR}/limine"
MNT_ROOT="${OUT_DIR}/mnt/root"
MNT_STATE="${OUT_DIR}/mnt/state"

ALPENGLOW_VERSION="${ALPENGLOW_VERSION:-$(date +%Y%m%d)}"
ALPENGLOW_ARCH="${ALPENGLOW_ARCH:-x86_64}"
IMAGE_SIZE_MB="${IMAGE_SIZE_MB:-4096}"
BOOT_SIZE_MB="${BOOT_SIZE_MB:-2048}"
STATE_SIZE_MB="${STATE_SIZE_MB:-1024}"
LIMINE_VERSION="${LIMINE_VERSION:-12.4.0}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
sgdisk_ok() {
  set +e
  sgdisk "$@"
  code=$?
  set -e
  [ "${code}" -eq 0 ] || [ "${code}" -eq 4 ]
}

echo "=== Alpenglow release build v${ALPENGLOW_VERSION} ==="
echo "  arch:  ${ALPENGLOW_ARCH}"
echo "  image: ${IMAGE}"
echo "  size:  ${IMAGE_SIZE_MB}MB"
echo ""

mkdir -p "${OUT_DIR}" "${MNT_ROOT}" "${MNT_STATE}"

# ── 1. Build kernel + initramfs ────────────────────────────────────
echo "→ Building kernel and initramfs..."
NATIVE_DIR="${ROOT_DIR}/build/native"
mkdir -p "${NATIVE_DIR}"
if command -v lz4 >/dev/null 2>&1; then
  NATIVE_INITRAMFS="${NATIVE_DIR}/initramfs.cpio.lz4"
else
  NATIVE_INITRAMFS="${NATIVE_DIR}/initramfs.cpio.zst"
fi
rm -f "${NATIVE_DIR}/vmlinuz" "${NATIVE_INITRAMFS}"
KERNEL_BUILD=1 BUILD_ONLY=1 INITRAMFS="${NATIVE_INITRAMFS}" "${ROOT_DIR}/scripts/boot-native.sh"
test -f "${NATIVE_DIR}/vmlinuz" && test -f "${NATIVE_INITRAMFS}" || {
  echo "boot build did not produce the requested kernel and initramfs" >&2
  exit 1
}
python3 "${ROOT_DIR}/scripts/check-release-architecture.py" \
  "${ALPENGLOW_ARCH}" "${NATIVE_DIR}/rootfs" "${NATIVE_DIR}/vmlinuz"
if [ "${ALPENGLOW_ARCH}" = "x86_64" ] && [ "$(od -An -tu1 -j 564 -N 1 "${NATIVE_DIR}/vmlinuz" | tr -d ' ')" != "1" ]; then
  echo "x86_64 UEFI requires a relocatable kernel (CONFIG_RELOCATABLE=y)" >&2
  exit 1
fi
cp "${NATIVE_DIR}/vmlinuz" "${KERNEL}"
INITRAMFS="${OUT_DIR}/$(basename -- "${NATIVE_INITRAMFS}")"
cp "${NATIVE_INITRAMFS}" "${INITRAMFS}"
test -f "${KERNEL}" || { echo "missing built kernel: ${KERNEL}" >&2; exit 1; }
test -n "${INITRAMFS}" && test -f "${INITRAMFS}" || { echo "missing built initramfs under ${OUT_DIR}" >&2; exit 1; }
initramfs_assert_codec_identity "${INITRAMFS}" || exit 1
INITRAMFS_BASENAME="$(basename -- "${INITRAMFS}")"

# ── 2. Fetch Limine bootloader ─────────────────────────────────────
echo "→ Fetching Limine ${LIMINE_VERSION}..."
if [ ! -f "${LIMINE_DIR}/limine" ]; then
  mkdir -p "${LIMINE_DIR}"
  curl -fsSL "https://github.com/limine-bootloader/limine/releases/download/v${LIMINE_VERSION}/limine-binary.tar.xz" \
    -o "${OUT_DIR}/limine.tar.xz"
  tar -xJf "${OUT_DIR}/limine.tar.xz" -C "${LIMINE_DIR}" --strip-components=1 2>/dev/null || {
    tar -xJf "${OUT_DIR}/limine.tar.xz" -C "${LIMINE_DIR}"
  }
  make -C "${LIMINE_DIR}"
fi
[ -x "${LIMINE_DIR}/limine" ] && [ -s "${LIMINE_DIR}/limine-bios.sys" ] || {
  echo "missing Limine installer or limine-bios.sys in ${LIMINE_DIR}" >&2
  exit 1
}
if [ "${ALPENGLOW_ARCH}" = "x86_64" ] && [ ! -s "${LIMINE_DIR}/BOOTX64.EFI" ]; then
  echo "missing Limine BOOTX64.EFI in ${LIMINE_DIR}" >&2
  exit 1
fi

# ── 3. Create disk image ───────────────────────────────────────────
echo "→ Creating disk image (${IMAGE_SIZE_MB}MB)..."
rm -f "${IMAGE}"
dd if=/dev/zero of="${IMAGE}" bs=1M count="${IMAGE_SIZE_MB}" 2>/dev/null

# Partition: GPT with boot + bcachefs state + Limine
ROOT_START=2048
ROOT_END=$(( ROOT_START + (BOOT_SIZE_MB * 2048) ))
STATE_START=$(( ROOT_END + 2048 ))
STATE_END=$(( STATE_START + (STATE_SIZE_MB * 2048) ))
LIMINE_START=$(( STATE_END + 2048 ))

sgdisk_ok -o "${IMAGE}"
if [ "${ALPENGLOW_ARCH}" = "x86_64" ]; then
  BOOT_TYPE=ef00
else
  BOOT_TYPE=8300
fi
sgdisk_ok -n 1:${ROOT_START}:${ROOT_END} -t 1:${BOOT_TYPE} -c 1:"alpenglow-boot" "${IMAGE}"
sgdisk_ok -n 2:${STATE_START}:${STATE_END} -t 2:8300 -c 2:"alpenglow-state" "${IMAGE}"
sgdisk_ok -n 3:${LIMINE_START}: -t 3:ef02 -c 3:"Limine" "${IMAGE}"
sgdisk_ok -A 3:set:2 "${IMAGE}"

# ── 4. Format partitions ──────────────────────────────────────────
echo "→ Formatting partitions..."
LOOP_ROOT=$(sudo losetup -f --show -o $((ROOT_START * 512)) --sizelimit $(((ROOT_END - ROOT_START + 1) * 512)) "${IMAGE}") || {
  echo "failed to attach release boot partition to a loop device" >&2
  exit 1
}
[ -n "${LOOP_ROOT}" ] || { echo "losetup returned no boot loop device" >&2; exit 1; }
LOOP_STATE=""
cleanup() {
  sudo umount "${MNT_ROOT}" 2>/dev/null || true
  [ -z "${LOOP_STATE}" ] || sudo losetup -d "${LOOP_STATE}" 2>/dev/null || true
  sudo losetup -d "${LOOP_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
LOOP_STATE=$(sudo losetup -f --show -o $((STATE_START * 512)) --sizelimit $(((STATE_END - STATE_START + 1) * 512)) "${IMAGE}") || {
  echo "failed to attach release state partition to a loop device" >&2
  exit 1
}
[ -n "${LOOP_STATE}" ] || { echo "losetup returned no state loop device" >&2; exit 1; }

if [ "${ALPENGLOW_ARCH}" = "x86_64" ]; then
  sudo mkfs.vfat -F 32 -n ALPGBOOT "${LOOP_ROOT}" >/dev/null
else
  sudo mkfs.ext4 -L alpenglow-boot "${LOOP_ROOT}" >/dev/null
fi
# /state compression is a format-time default (editions.toml state_compression);
# it lives in the superblock, so mounts need no extra option. fast: none.
STATE_MKFS_OPTS=""
case "${STATE_COMPRESSION:-none}" in
  none) ;;
  *) STATE_MKFS_OPTS="--compression=${STATE_COMPRESSION}" ;;
esac
sudo mkfs.bcachefs ${STATE_MKFS_OPTS} -L alpenglow-state "${LOOP_STATE}" >/dev/null

# ── 5. Install boot files ──────────────────────────────────────────
echo "→ Installing system..."
sudo mount "${LOOP_ROOT}" "${MNT_ROOT}"
sudo mkdir -p "${MNT_ROOT}/boot" "${MNT_ROOT}/state"
sudo cp "${KERNEL}" "${MNT_ROOT}/boot/vmlinuz"
sudo cp "${INITRAMFS}" "${MNT_ROOT}/boot/${INITRAMFS_BASENAME}"

# ── 6. Install Limine ─────────────────────────────────────────────
echo "→ Installing Limine bootloader..."
sudo mkdir -p "${MNT_ROOT}/boot/limine"
cat > /tmp/limine.conf << LIMINE
# Alpenglow Limine configuration
timeout: 5
verbose: no

/Alpenglow
  protocol: linux
  path: boot():/boot/vmlinuz
  cmdline: console=tty0 console=ttyS0 init=/init alpenglow.state=LABEL=alpenglow-state
  module_path: boot():/boot/${INITRAMFS_BASENAME}
LIMINE
sudo cp /tmp/limine.conf "${MNT_ROOT}/boot/limine/limine.conf"
sudo cp "${LIMINE_DIR}/limine-bios.sys" "${MNT_ROOT}/boot/limine/limine-bios.sys"
if [ "${ALPENGLOW_ARCH}" = "x86_64" ]; then
  sudo mkdir -p "${MNT_ROOT}/EFI/BOOT"
  sudo cp "${LIMINE_DIR}/BOOTX64.EFI" "${MNT_ROOT}/EFI/BOOT/BOOTX64.EFI"
fi
if ! sudo "${LIMINE_DIR}/limine" bios-install "${IMAGE}"; then
  echo "failed to install the Limine BIOS bootloader" >&2
  exit 1
fi

# ── 7. Install state partition (first-boot setup) ──────────────────
echo "→ Setting up state partition..."
if sudo mount "${LOOP_STATE}" "${MNT_STATE}" 2>/dev/null; then
  sudo mkdir -p "${MNT_STATE}/home" "${MNT_STATE}/var/lib/alpenglow" "${MNT_STATE}/var/cache/alpenglow" "${MNT_STATE}/var/log/alpenglow"
  sudo chmod 700 "${MNT_STATE}"
  sudo umount "${MNT_STATE}"
else
  echo "  state partition formatted; skipping host-side bcachefs mount"
fi

# ── 8. Cleanup ─────────────────────────────────────────────────────
cleanup
trap - EXIT HUP INT TERM
if [ "${ALPENGLOW_ARCH}" = "aarch64" ]; then
  python3 "${ROOT_DIR}/scripts/check-release-architecture.py" --uefi-image "${IMAGE}"
else
  python3 "${ROOT_DIR}/scripts/check-release-architecture.py" --bios-image "${IMAGE}"
  python3 "${ROOT_DIR}/scripts/check-release-architecture.py" --uefi-image "${IMAGE}"
fi

echo ""
echo "✓ Alpenglow release image created:"
echo "  ${IMAGE} ($(du -sh "${IMAGE}" | cut -f1))"
echo ""
echo "  To write to USB:"
echo "    sudo dd if=${IMAGE} of=/dev/sdX bs=4M status=progress"
echo ""
echo "  To boot in QEMU:"
echo "    qemu-system-x86_64 -m 4G -hda ${IMAGE}"
