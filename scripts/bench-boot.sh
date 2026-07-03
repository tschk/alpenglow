#!/bin/sh
# Benchmark Alpenglow boot times in QEMU.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
KERNEL="${ROOT_DIR}/build/native/vmlinuz"
# Prefer the small headless initramfs; the .gz graphical image is much larger
# and not suitable for serial boot timing.
INITRAMFS="${ROOT_DIR}/build/native/initramfs.cpio.zst"
[ -f "${INITRAMFS}" ] || INITRAMFS="${ROOT_DIR}/build/native/initramfs.cpio.gz"
OUT_DIR="${ROOT_DIR}/build/native"
ACCEL="${ACCEL:-tcg}"
MEMORY_MB="${MEMORY_MB:-2048}"

fail() { echo "bench: $1" >&2; exit 1; }
[ -f "${KERNEL}" ] || fail "kernel not found at ${KERNEL}"
[ -f "${INITRAMFS}" ] || fail "initramfs not found at ${INITRAMFS}"

echo "==> Booting Alpenglow in QEMU and timing boot phases..."

OUTFILE="${OUT_DIR}/bench-serial.log"
rm -f "${OUTFILE}"
touch "${OUTFILE}"

START="$(date +%s%N)"

qemu-system-x86_64 \
  -machine q35,accel="${ACCEL}" \
  -m "${MEMORY_MB}" \
  -smp 2 \
  -nographic \
  -no-reboot \
  -kernel "${KERNEL}" \
  -initrd "${INITRAMFS}" \
  -append "console=ttyS0 init=/init" \
  < /dev/null > "${OUTFILE}" 2>&1 &
QEMU_PID=$!

# Wait for the login prompt, then stop QEMU. The appliance does not
# power off automatically, so the wall-clock time must be measured at
# the login marker.
MAX_ITER=600
LOGIN_FOUND=0
while kill -0 "${QEMU_PID}" 2>/dev/null; do
  if grep -q "login:" "${OUTFILE}" 2>/dev/null; then
    LOGIN_FOUND=1
    break
  fi
  sleep 0.1
  MAX_ITER=$((MAX_ITER - 1))
  [ "${MAX_ITER}" -le 0 ] && { kill "${QEMU_PID}" 2>/dev/null; break; }
done

END="$(date +%s%N)"
kill "${QEMU_PID}" 2>/dev/null || true
wait "${QEMU_PID}" 2>/dev/null || true

TOTAL_MS=$(( (END - START) / 1000000 ))

# Parse timestamps from serial log
find_marker() {
  grep -m1 -n "$1" "${OUTFILE}" 2>/dev/null | head -1 | cut -d: -f1 || echo ""
}

KERNEL_LINE="$(find_marker 'Linux version')"
[ -z "${KERNEL_LINE}" ] && KERNEL_LINE="$(find_marker 'Alpenglow boot')"
INIT_LINE="$(find_marker 'Alpenglow boot')"
MOUNT_LINE="$(find_marker 'mount-filesystems')"
SHELL_LINE="$(find_marker 'shell-ttyS0')"
LOGIN_LINE="$(find_marker 'login:')"

# Calculate elapsed seconds between two line numbers
elapsed_between() {
  a="$1"
  b="$2"
  if [ -z "$a" ] || [ -z "$b" ]; then
    echo "?"
    return
  fi
  # Line-based timing isn't precise but gives relative ordering
  diff=$((b - a))
  # Each line roughly corresponds to wall time
  # Use total time / total lines as calibration
  total_lines=$(wc -l < "${OUTFILE}" 2>/dev/null || echo 1)
  [ "${total_lines}" -le 0 ] && total_lines=1
  ms_per_line=$((TOTAL_MS / total_lines))
  elapsed_ms=$((diff * ms_per_line))
  awk "BEGIN { printf \"%.1f\", ${elapsed_ms} / 1000 }"
}

echo ""
echo "=== Boot Time Benchmarks ==="
echo "  Wall clock: ${TOTAL_MS}ms"

if [ -n "${KERNEL_LINE}" ]; then
  printf "  Kernel decompress to init:     %5ss\n" "$(elapsed_between "${KERNEL_LINE}" "${INIT_LINE}")"
fi
if [ -n "${INIT_LINE}" ]; then
  printf "  Init to mount-filesystems:     %5ss\n" "$(elapsed_between "${INIT_LINE}" "${MOUNT_LINE}")"
fi
if [ -n "${MOUNT_LINE}" ]; then
  printf "  mount-filesystems to getty:    %5ss\n" "$(elapsed_between "${MOUNT_LINE}" "${SHELL_LINE}")"
fi
if [ -n "${SHELL_LINE}" ]; then
  printf "  Getty to login:                %5ss\n" "$(elapsed_between "${SHELL_LINE}" "${LOGIN_LINE}")"
fi
printf "  Total (power-on to login):     %5sms\n" "${TOTAL_MS}"

# Parse memory from serial log. Newer kernels print "Memory: XK/YK available"
# at boot; /proc/meminfo lines are not echoed to the console by default.
MEM_LINE="$(grep -o 'Memory: [0-9]*K/[0-9]*K available' "${OUTFILE}" 2>/dev/null | head -1)"
MEM_TOTAL="?"
MEM_FREE="?"
if [ -n "${MEM_LINE}" ]; then
  MEM_FREE="$(echo "${MEM_LINE}" | awk -F'[ /K]' '{print $2"K"}')"
  MEM_TOTAL="$(echo "${MEM_LINE}" | awk -F'[ /]' '{print $3}')"
fi

# Count unique files in initramfs (handle both gzip and zstd)
if command -v zstdcat >/dev/null 2>&1; then
  INITRAMFS_FILES="$(zstdcat "${INITRAMFS}" 2>/dev/null | cpio -t 2>/dev/null | wc -l || echo "?")"
else
  INITRAMFS_FILES="$(zcat "${INITRAMFS}" 2>/dev/null | cpio -t 2>/dev/null | wc -l || echo "?")"
fi

echo ""
echo "=== Resource Metrics ==="
echo "  initramfs: $(du -sh "${INITRAMFS}" 2>/dev/null | awk '{print $1}' || echo "?")"
echo "  initramfs files: ${INITRAMFS_FILES}"
echo "  kernel:    $(du -shL "${KERNEL}" 2>/dev/null | awk '{print $1}' || echo "?")"
echo "  memory:    ${MEM_TOTAL} total, ${MEM_FREE} free"

echo ""
echo "bench: ok"
