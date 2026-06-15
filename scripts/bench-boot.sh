#!/bin/sh
# Benchmark Alpenglow boot times in QEMU.
# Times phases: power-on → kernel → init → services → login prompt.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
IMG="${1:-${ROOT_DIR}/build/native/alpenglow.img}"
KERNEL="${ROOT_DIR}/build/native/vmlinuz"
INITRAMFS="${ROOT_DIR}/build/native/initramfs.cpio.gz"
OUT_DIR="${ROOT_DIR}/build/native"

fail() { echo "bench: $1" >&2; exit 1; }

[ -f "${KERNEL}" ] || fail "kernel not found at ${KERNEL}. Run ./start.sh build first."
[ -f "${INITRAMFS}" ] || fail "initramfs not found at ${INITRAMFS}. Run ./start.sh build first."

# boot-native.sh uses QEMU-specific kernel+initrd boot, not a disk image
echo "==> Booting Alpenglow in QEMU and timing boot phases..."

# We capture serial output, prefix each line with relative time (seconds since start).
# Known markers:
#   - first line printed        → kernel starts
#   - "Alpenglow boot"          → init (dinit) starts
#   - "mount-filesystems"       → mount-filesystems service completion
#   - "ttyS0" or "login:"      → getty ready / login prompt

# Use a temp fifo for timing
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT INT TERM
FIFO="${TMPDIR}/serial"
mkfifo "${FIFO}"

START="$(date +%s%N)"

# Launch QEMU, output to fifo
qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -m 512 \
  -smp 2 \
  -nographic \
  -no-reboot \
  -kernel "${KERNEL}" \
  -initrd "${INITRAMFS}" \
  -append "console=ttyS0 init=/init" \
  < /dev/null > "${FIFO}" 2>&1 &
QEMU_PID=$!

# Read serial output with timestamps
PHASE_KERNEL=""
PHASE_INIT=""
PHASE_MOUNT=""
PHASE_GETTY=""
PHASE_LOGIN=""

now_ns() { date +%s%N; }

elapsed() {
  e_begin="$1"
  e_now="$(now_ns)"
  awk "BEGIN { printf \"%.1f\", (${e_now} - ${e_begin}) / 1000000000 }"
}

KERNEL_TIME=""
INIT_TIME=""
MOUNT_TIME=""
GETTY_TIME=""
LOGIN_TIME=""

while IFS= read -r line; do
  ts="$(elapsed "${START}")"
  case "${line}" in
    *"Alpenglow boot"*)
      [ -z "${INIT_TIME}" ] && INIT_TIME="${ts}"
      ;;
    *"mount-filesystems"*)
      # dinit service completion indicator
      [ -z "${MOUNT_TIME}" ] && MOUNT_TIME="${ts}"
      ;;
    *"ttyS0"*"getty"*|*"ttyS0"*"login"*)
      [ -z "${GETTY_TIME}" ] && GETTY_TIME="${ts}"
      ;;
    *"login:"*)
      [ -z "${LOGIN_TIME}" ] && LOGIN_TIME="${ts}"
      ;;
  esac
  # capture first line as kernel start
  [ -z "${KERNEL_TIME}" ] && KERNEL_TIME="${ts}"
done < "${FIFO}"

wait "${QEMU_PID}" 2>/dev/null || true

# Defaults for missing phases
[ -z "${KERNEL_TIME}" ] && KERNEL_TIME="0.0"
[ -z "${INIT_TIME}" ] && INIT_TIME="${KERNEL_TIME}"
[ -z "${MOUNT_TIME}" ] && MOUNT_TIME="${INIT_TIME}"
[ -z "${GETTY_TIME}" ] && GETTY_TIME="${MOUNT_TIME}"
[ -z "${LOGIN_TIME}" ] && LOGIN_TIME="${GETTY_TIME}"

echo ""
echo "=== Boot Time Benchmarks ==="
echo ""
printf "Power-on to kernel decompress:    %5ss\n" "${KERNEL_TIME}"
printf "Kernel start to init:             %5ss\n" "$(awk "BEGIN { printf \"%.1f\", ${INIT_TIME} - ${KERNEL_TIME} }")"
printf "Init to mount-filesystems:        %5ss\n" "$(awk "BEGIN { printf \"%.1f\", ${MOUNT_TIME} - ${INIT_TIME} }")"
printf "mount-filesystems to getty ready: %5ss\n" "$(awk "BEGIN { printf \"%.1f\", ${GETTY_TIME} - ${MOUNT_TIME} }")"
printf "getty to login prompt:            %5ss\n" "$(awk "BEGIN { printf \"%.1f\", ${LOGIN_TIME} - ${GETTY_TIME} }")"
printf "Total boot (power-on to login):   %5ss\n" "${LOGIN_TIME}"
echo ""

# Initramfs and kernel sizes
INITRAMFS_SIZE="$(du -sh "${INITRAMFS}" 2>/dev/null | cut -f1 || echo "?")"
KERNEL_SIZE="$(du -sh "${KERNEL}" 2>/dev/null | cut -f1 || echo "?")"
echo "=== Size Metrics ==="
echo "  initramfs: ${INITRAMFS_SIZE}"
echo "  kernel:    ${KERNEL_SIZE}"
echo ""

# Comparison table (reference values from README)
echo "=== Comparative Reference (QEMU TCG, Linux 7.0.12) ==="
echo "  Alpenglow: total ${LOGIN_TIME}s  initramfs ${INITRAMFS_SIZE}  kernel ${KERNEL_SIZE}"
echo "  Alpine:    ~3s  initramfs 8MB  kernel 6.5MB"
echo "  Void:      ~4s  initramfs 12MB  kernel 7.0MB"
echo "  Ubuntu:    ~15s  initramfs 40MB  kernel 12MB"
echo ""
echo "bench: ok"
