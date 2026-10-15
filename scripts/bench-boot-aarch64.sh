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
case "${ACCEL}" in
  tcg|hvf|kvm) ;;
  *) fail "unsupported aarch64 accelerator: ${ACCEL} (expected tcg, hvf, or kvm)" ;;
esac
[ -f "${KERNEL}" ] || fail "kernel not found at ${KERNEL}"
[ -f "${INITRAMFS}" ] || fail "initramfs not found at ${INITRAMFS}"
MAX_ITER="${BENCH_MAX_POLLS:-600}"
case "${MAX_ITER}" in
  ''|*[!0-9]*) fail "BENCH_MAX_POLLS must be a positive integer" ;;
esac
[ "${MAX_ITER}" -gt 0 ] || fail "BENCH_MAX_POLLS must be a positive integer"

echo "==> Booting Alpenglow aarch64 in QEMU (${SMP} vCPU, ${MEMORY_MB}MB, ${ACCEL}) and timing boot..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM
OUTFILE="${TMP_DIR}/serial.log"

QEMU_CPU=""
if [ -z "${CPU}" ]; then
  QEMU_CPU="-cpu max"
elif [ -n "${CPU}" ]; then
  QEMU_CPU="-cpu ${CPU}"
fi

INITRD_ARG=""
if [ ! -f "${BUILD_OUT}/.kernel-aarch64.ok" ]; then
  INITRD_ARG="-initrd ${INITRAMFS}"
fi

# Measure the host interval from VM launch to the serial login marker.
START="$(date +%s%N)"
stdbuf -oL -eL qemu-system-aarch64 \
  -M "${MACHINE},accel=${ACCEL}" \
  ${QEMU_CPU} \
  -m "${MEMORY_MB}" \
  -smp "${SMP}" \
  -nographic \
  -no-reboot \
  -kernel "${KERNEL}" \
  ${INITRD_ARG} \
  -append "console=ttyAMA0,115200 init=/init quiet" \
  < /dev/null > "${OUTFILE}" 2>&1 &
QEMU_PID=$!

LOGIN_FOUND=0
TIMED_OUT=0
while :; do
  if grep -q "login:" "${OUTFILE}" 2>/dev/null; then
    LOGIN_FOUND=1
    break
  fi
  if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
    break
  fi
  if [ "${MAX_ITER}" -le 0 ]; then
    TIMED_OUT=1
    break
  fi
  sleep 0.1
  MAX_ITER=$((MAX_ITER - 1))
done
# QEMU may exit immediately after login (e.g. aarch64 init halts/reboots)
if [ "${LOGIN_FOUND}" = "0" ] && grep -q "login:" "${OUTFILE}" 2>/dev/null; then
  LOGIN_FOUND=1
fi

END="$(date +%s%N)"
KILL_SENT=0
if kill -0 "${QEMU_PID}" 2>/dev/null; then
  if kill "${QEMU_PID}" 2>/dev/null; then
    KILL_SENT=1
  fi
fi
if wait "${QEMU_PID}"; then
  QEMU_STATUS=0
else
  QEMU_STATUS=$?
fi
if [ "${QEMU_STATUS}" -ne 0 ] && { [ "${KILL_SENT}" -ne 1 ] || [ "${QEMU_STATUS}" -ne 143 ]; }; then
  fail "QEMU exited with an error (status ${QEMU_STATUS})"
fi
[ "${TIMED_OUT}" -eq 0 ] || fail "timed out waiting for login marker"
[ "${LOGIN_FOUND}" -eq 1 ] || fail "login marker not found"

TOTAL_MS=$(( (END - START) / 1000000 ))

echo ""
echo "=== Boot Time Benchmarks ==="
echo "  Total (VM launch to login):    ${TOTAL_MS}ms"

echo "  marker: login"
echo ""
echo "bench: ok"
