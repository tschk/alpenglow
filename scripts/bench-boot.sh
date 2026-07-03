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
SMP="${SMP:-2}"

fail() { echo "bench: $1" >&2; exit 1; }
[ -f "${KERNEL}" ] || fail "kernel not found at ${KERNEL}"
[ -f "${INITRAMFS}" ] || fail "initramfs not found at ${INITRAMFS}"

echo "==> Booting Alpenglow in QEMU (${SMP} vCPU, ${MEMORY_MB}MB, ${ACCEL}) and timing boot phases..."

OUTFILE="${OUT_DIR}/bench-serial.log"
rm -f "${OUTFILE}"
touch "${OUTFILE}"

START="$(date +%s%N)"

qemu-system-x86_64 \
  -machine q35,accel="${ACCEL}" \
  -m "${MEMORY_MB}" \
  -smp "${SMP}" \
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

# Check which boot markers were reached.
has_marker() { grep -q "$1" "${OUTFILE}" 2>/dev/null; }

echo ""
echo "=== Boot Time Benchmarks ==="
echo "  Wall clock: ${TOTAL_MS}ms"
printf "  Total (power-on to login):     %5sms\n" "${TOTAL_MS}"
has_marker 'Alpenglow boot' && echo "  marker: Alpenglow boot"
has_marker 'mount-filesystems' && echo "  marker: mount-filesystems"
has_marker 'shell-ttyS0' && echo "  marker: shell-ttyS0"
has_marker 'login:' && echo "  marker: login"

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
