#!/bin/sh
# Benchmark Alpenglow aarch64 boot in QEMU (macOS arm64 HVF target).
# Expects build/cross/aarch64/{vmlinuz,initramfs.cpio.gz} from build-aarch64.sh.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_OUT="${ROOT_DIR}/build/cross/aarch64"
KERNEL="${BUILD_OUT}/vmlinuz"
INITRAMFS="${INITRAMFS:-${BUILD_OUT}/initramfs-proper.cpio.lz4}"
[ -f "${INITRAMFS}" ] || INITRAMFS="${BUILD_OUT}/initramfs-proper.cpio.gz"
[ -f "${INITRAMFS}" ] || INITRAMFS="${BUILD_OUT}/initramfs.cpio.gz"

MEMORY_MB="${MEMORY_MB:-512}"
SMP="${SMP:-2}"
ACCEL="${ACCEL:-hvf}"
MACHINE="${MACHINE:-virt}"
CPU="${CPU:-}"

fail() { echo "bench: $1" >&2; exit 1; }
[ -f "${KERNEL}" ] || fail "kernel not found at ${KERNEL}"
[ -f "${INITRAMFS}" ] || fail "initramfs not found at ${INITRAMFS}"

echo "==> Booting Alpenglow aarch64 in QEMU (${SMP} vCPU, ${MEMORY_MB}MB, ${ACCEL}) and timing boot..."

OUTFILE="$(mktemp -t alpenglow-aarch64-bench-serial.XXXXXX)"
rm -f "${OUTFILE}"

START="$(date +%s%N)"

QEMU_CPU=""
if [ -z "${CPU}" ]; then
  QEMU_CPU="-cpu max"
elif [ -n "${CPU}" ]; then
  QEMU_CPU="-cpu ${CPU}"
fi

stdbuf -oL -eL qemu-system-aarch64 \
  -M "${MACHINE}" \
  ${QEMU_CPU} \
  -m "${MEMORY_MB}" \
  -smp "${SMP}" \
  -nographic \
  -no-reboot \
  -kernel "${KERNEL}" \
  -initrd "${INITRAMFS}" \
  -append "console=ttyAMA0,115200 init=/init quiet" \
  < /dev/null > "${OUTFILE}" 2>&1 &
QEMU_PID=$!

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
# QEMU may exit immediately after login (e.g. aarch64 init halts/reboots)
if [ "${LOGIN_FOUND}" = "0" ] && grep -q "login:" "${OUTFILE}" 2>/dev/null; then
  LOGIN_FOUND=1
fi

END="$(date +%s%N)"
kill "${QEMU_PID}" 2>/dev/null || true
wait "${QEMU_PID}" 2>/dev/null || true

TOTAL_MS=$(( (END - START) / 1000000 ))

echo ""
echo "=== Boot Time Benchmarks ==="
echo "  Total (power-on to login):     ${TOTAL_MS}ms"

if [ "${LOGIN_FOUND}" = "1" ]; then
  echo "  marker: login"
  echo ""
  echo "bench: ok"
else
  echo "  marker: login not found"
  echo ""
  echo "bench: timeout"
  exit 1
fi
