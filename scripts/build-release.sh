#!/bin/sh
# Build a bootable Alpenglow disk image for real hardware.
# Uses Limine bootloader, creates GPT disk with boot + state partitions.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/release"
IMAGE="${OUT_DIR}/alpenglow.img"
KERNEL="${OUT_DIR}/vmlinuz"
INITRAMFS="${OUT_DIR}/initramfs.cpio.gz"
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
KERNEL_BUILD=1 BUILD_ONLY=1 "${ROOT_DIR}/scripts/boot-native.sh" 2>&1 | tail -5 || {
  echo "WARNING: boot-native.sh failed, trying without custom kernel"
  BUILD_ONLY=1 "${ROOT_DIR}/scripts/boot-native.sh" 2>&1 | tail -5
}
cp "${KERNEL}" "${OUT_DIR}/vmlinuz" 2>/dev/null || true
cp "${OUT_DIR}/../native/vmlinuz" "${KERNEL}" 2>/dev/null || true
for native_initramfs in "${OUT_DIR}/../native/initramfs.cpio.zst" "${OUT_DIR}/../native/initramfs.cpio.lz4"; do
  if [ -f "${native_initramfs}" ]; then
    cp "${native_initramfs}" "${INITRAMFS}"
    break
  fi
done

# ── 2. Fetch Limine bootloader ─────────────────────────────────────
echo "→ Fetching Limine ${LIMINE_VERSION}..."
if [ ! -f "${LIMINE_DIR}/limine" ]; then
  mkdir -p "${LIMINE_DIR}"
  curl -fsSL "https://github.com/limine-bootloader/limine/releases/download/v${LIMINE_VERSION}/limine-binary.tar.xz" \
    -o "${OUT_DIR}/limine.tar.xz"
  tar -xJf "${OUT_DIR}/limine.tar.xz" -C "${LIMINE_DIR}" --strip-components=1 2>/dev/null || {
    tar -xJf "${OUT_DIR}/limine.tar.xz" -C "${LIMINE_DIR}"
  }
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

sgdisk_ok -o "${IMAGE}"
sgdisk_ok -n 1:${ROOT_START}:${ROOT_END} -t 1:8300 -c 1:"alpenglow-boot" "${IMAGE}"
sgdisk_ok -n 2:${STATE_START}:${STATE_END} -t 2:8300 -c 2:"alpenglow-state" "${IMAGE}"
sgdisk_ok -n 3:${STATE_END}: -t 3:8301 -c 3:"Limine" "${IMAGE}"
sgdisk_ok -A 3:set:2 "${IMAGE}"

# ── 4. Format partitions ──────────────────────────────────────────
echo "→ Formatting partitions..."
LOOP_DEV=$(sudo losetup -f --show "${IMAGE}" 2>/dev/null || echo "")
if [ -z "${LOOP_DEV}" ]; then
  echo "  (using direct partition mapping)"
  sudo kpartx -a "${IMAGE}" 2>/dev/null || true
  LOOP_ROOT="/dev/mapper/loop0p1"
  LOOP_STATE="/dev/mapper/loop0p2"
  LOOP_LIMINE="/dev/mapper/loop0p3"
else
  LOOP_ROOT="${LOOP_DEV}p1"
  LOOP_STATE="${LOOP_DEV}p2"
  LOOP_LIMINE="${LOOP_DEV}p3"
fi

sudo mkfs.ext4 -L alpenglow-boot "${LOOP_ROOT}" >/dev/null 2>&1
sudo mkfs.bcachefs -L alpenglow-state "${LOOP_STATE}" >/dev/null 2>&1

# ── 5. Install boot files ──────────────────────────────────────────
echo "→ Installing system..."
sudo mount "${LOOP_ROOT}" "${MNT_ROOT}"
sudo mkdir -p "${MNT_ROOT}/boot" "${MNT_ROOT}/state"
sudo cp "${KERNEL}" "${MNT_ROOT}/boot/vmlinuz"
sudo cp "${INITRAMFS}" "${MNT_ROOT}/boot/initramfs.cpio.gz"

# ── 6. Install Limine ─────────────────────────────────────────────
echo "→ Installing Limine bootloader..."
sudo mkdir -p "${MNT_ROOT}/boot/limine"
cat > /tmp/limine.conf << 'LIMINE'
# Alpenglow Limine configuration
timeout: 5
verbose: no

/Alpenglow
  protocol: linux
  path: boot():/boot/vmlinuz
  cmdline: console=tty0 console=ttyS0 init=/init alpenglow.state=LABEL=alpenglow-state
  module_path: boot():/boot/initramfs.cpio.gz
LIMINE
sudo cp /tmp/limine.conf "${MNT_ROOT}/boot/limine/limine.conf"
sudo "${LIMINE_DIR}/limine" bios-install "${IMAGE}" 2>/dev/null || true

# ── 7. Install state partition (first-boot setup) ──────────────────
echo "→ Setting up state partition..."
sudo mount "${LOOP_STATE}" "${MNT_STATE}"
sudo mkdir -p "${MNT_STATE}/home" "${MNT_STATE}/var/lib/alpenglow" "${MNT_STATE}/var/cache/alpenglow" "${MNT_STATE}/var/log/alpenglow"
sudo chmod 700 "${MNT_STATE}"
sudo umount "${MNT_STATE}"

# ── 8. Cleanup ─────────────────────────────────────────────────────
sudo umount "${MNT_ROOT}" 2>/dev/null || true
if [ -n "${LOOP_DEV}" ]; then
  sudo losetup -d "${LOOP_DEV}" 2>/dev/null || true
fi
sudo kpartx -d "${IMAGE}" 2>/dev/null || true

echo ""
echo "✓ Alpenglow release image created:"
echo "  ${IMAGE} ($(du -sh "${IMAGE}" | cut -f1))"
echo ""
echo "  To write to USB:"
echo "    sudo dd if=${IMAGE} of=/dev/sdX bs=4M status=progress"
echo ""
echo "  To boot in QEMU:"
echo "    qemu-system-x86_64 -m 4G -hda ${IMAGE}"
