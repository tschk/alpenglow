#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

QEMU_TIMEOUT="${QEMU_TIMEOUT:-180}"
QEMU_LOG="${QEMU_LOG:-${TMPDIR:-/tmp}/alpenglow-qemu-glowfs-disk-root.log}"
QEMU_DIR="${QEMU_DIR:-build/alpine/qemu}"
ALPENGLOW_ROOTFS_IMAGE="${ALPENGLOW_ROOTFS_IMAGE:-${QEMU_DIR}/alpenglow-rootfs.glowfs}"

fail() {
  printf 'ci-qemu-glowfs-disk-root: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

require_log() {
  pattern="$1"
  grep -Eq "${pattern}" "${QEMU_LOG}" || fail "missing QEMU log pattern: ${pattern}"
}

reject_log() {
  pattern="$1"
  if grep -Eq "${pattern}" "${QEMU_LOG}"; then
    fail "unexpected QEMU log pattern: ${pattern}"
  fi
}

require_tool qemu-system-x86_64

[ -f "${QEMU_DIR}/vmlinuz-virt" ] || fail "missing ${QEMU_DIR}/vmlinuz-virt"
[ -f "${QEMU_DIR}/rootfs.cpio.gz" ] || fail "missing ${QEMU_DIR}/rootfs.cpio.gz"
[ -f "${QEMU_DIR}/glowfs.ko" ] || fail "missing ${QEMU_DIR}/glowfs.ko"
[ -f "${ALPENGLOW_ROOTFS_IMAGE}" ] || fail "missing ${ALPENGLOW_ROOTFS_IMAGE}"

rm -f "${QEMU_LOG}"
set +e
if command -v timeout >/dev/null 2>&1; then
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" ALPENGLOW_RAM_ROOT=disk \
    ALPENGLOW_ROOTFS_IMAGE="${ALPENGLOW_ROOTFS_IMAGE}" ALPENGLOW_ROOTFS_IMAGE_REQUIRED=1 \
    ALPENGLOW_ROOT_FALLBACK_FSTYPE=glowfs timeout "${QEMU_TIMEOUT}" \
    system/alpine/scripts/run-qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1
  status=$?
elif command -v gtimeout >/dev/null 2>&1; then
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" ALPENGLOW_RAM_ROOT=disk \
    ALPENGLOW_ROOTFS_IMAGE="${ALPENGLOW_ROOTFS_IMAGE}" ALPENGLOW_ROOTFS_IMAGE_REQUIRED=1 \
    ALPENGLOW_ROOT_FALLBACK_FSTYPE=glowfs gtimeout "${QEMU_TIMEOUT}" \
    system/alpine/scripts/run-qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1
  status=$?
else
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" ALPENGLOW_RAM_ROOT=disk \
    ALPENGLOW_ROOTFS_IMAGE="${ALPENGLOW_ROOTFS_IMAGE}" ALPENGLOW_ROOTFS_IMAGE_REQUIRED=1 \
    ALPENGLOW_ROOT_FALLBACK_FSTYPE=glowfs \
    system/alpine/scripts/run-qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1 &
  qemu_pid=$!
  (
    sleep "${QEMU_TIMEOUT}"
    kill "${qemu_pid}" >/dev/null 2>&1 || true
  ) &
  watchdog_pid=$!
  wait "${qemu_pid}"
  status=$?
  kill "${watchdog_pid}" >/dev/null 2>&1 || true
fi
set -e

case "${status}" in
  0|124|143) ;;
  *) tail -n 160 "${QEMU_LOG}" >&2; fail "QEMU exited with status ${status}" ;;
esac

require_log 'Using rootfs image: .*alpenglow-rootfs\.glowfs'
require_log '\[init\] switching to disk root /dev/vda'
require_log 'OpenRC .*Linux 6\.12\.[0-9]+-0-virt'
require_log 'Starting alpenglow-kernel-policy .*ok'
require_log 'Starting sold .*ok'
require_log 'Starting alpenglow-session'
reject_log 'mount: mounting /dev/vda on /sysroot failed'
reject_log 'invalid module format'
reject_log '/etc/resolv\.conf\.[A-Za-z0-9]+'
reject_log '\[alpenglow-servo\] pump_servo_event_loop start'
reject_log '\[alpenglow-servo\] running_app_state\.spin_event_loop start'
reject_log '\[alpenglow-servo\] winit about_to_wait'
reject_log '\[alpenglow-servo\] request_repaint:'
reject_log '\[alpenglow-servo\] gui\.paint begin:'
reject_log 'ERROR: alpenglow-session failed to start'

printf 'ci-qemu-glowfs-disk-root: ok\n'
