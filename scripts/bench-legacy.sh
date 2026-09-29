#!/bin/sh
# Boot the Alpenglow legacy image on old QEMU machines and time power-on to
# the "Alpenglow legacy" banner. Serial output is the measurement; each run
# stops as soon as the banner appears.
#
# i686 machines boot the shipped v86 kernel directly. Other architectures have
# no Alpenglow kernel, so they are reported as skipped rather than timed.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
KERNEL="${REPO_ROOT}/site/public/v86/alpenglow-v86-vmlinuz"
INITRD="${REPO_ROOT}/build/legacy/initramfs.cpio.gz"
TIMEOUT="${TIMEOUT:-90}"

[ -f "${INITRD}" ] || "${REPO_ROOT}/scripts/build-legacy-initramfs.sh"

boot_i686() {
  name="$1"; shift
  log="$(mktemp)"
  start="$(date +%s)"
  qemu-system-i386 "$@" \
    -nographic -no-reboot -serial mon:stdio \
    -kernel "${KERNEL}" -initrd "${INITRD}" \
    -append "console=ttyS0,115200 init=/init" \
    >"${log}" 2>&1 &
  pid=$!
  deadline=$((start + TIMEOUT))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    if grep -q "Alpenglow legacy" "${log}" 2>/dev/null; then
      elapsed=$(( $(date +%s) - start ))
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      printf '%-22s %4ss  booted\n' "${name}" "${elapsed}"
      rm -f "${log}"
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  reason="$(grep -m1 -E 'Unable to boot|Kernel panic|invalid opcode' "${log}" | tr -d '\r' | cut -c1-60)"
  printf '%-22s  FAIL  %s\n' "${name}" "${reason:-no banner within ${TIMEOUT}s}"
  rm -f "${log}"
  return 1
}

echo "Alpenglow legacy boot times (power-on to banner, 1s resolution)"
echo

fail=0
boot_i686 "486"        -machine pc-i440fx-8.2 -cpu 486 -m 64 -smp 1        || fail=1
boot_i686 "pentium"    -machine pc-i440fx-8.2 -cpu pentium -m 64 -smp 1    || fail=1
boot_i686 "pentium2"   -machine pc-i440fx-8.2 -cpu pentium2 -m 96 -smp 1   || fail=1
boot_i686 "pentium3"   -machine pc-i440fx-8.2 -cpu pentium3 -m 128 -smp 1  || fail=1

printf '%-22s  SKIP  %s\n' "ppc g3beige" "no powerpc kernel"
printf '%-22s  SKIP  %s\n' "arm collie (SA-1110)" "no armv5 kernel; nearest iPAQ machine"

exit "${fail}"
