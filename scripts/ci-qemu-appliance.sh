#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

QEMU_TIMEOUT="${QEMU_TIMEOUT:-60}"
QEMU_LOG="${QEMU_LOG:-${TMPDIR:-/tmp}/alpenglow-qemu-appliance.log}"
QEMU_DIR="${QEMU_DIR:-build/native}"

fail() {
  printf 'ci-qemu-appliance: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

require_log() {
  pattern="$1"
  grep -Eq "${pattern}" "${QEMU_LOG}" || fail "missing log pattern: ${pattern}"
}

reject_log() {
  pattern="$1"
  if grep -Eq "${pattern}" "${QEMU_LOG}"; then
    fail "unexpected log pattern: ${pattern}"
  fi
}

require_tool qemu-system-x86_64

[ -f "${QEMU_DIR}/vmlinuz" ] || fail "missing ${QEMU_DIR}/vmlinuz (run scripts/boot-native.sh)"
[ -f "${QEMU_DIR}/initramfs.cpio.zst" ] || fail "missing ${QEMU_DIR}/initramfs.cpio.zst"

rm -f "${QEMU_LOG}"
set +e
if command -v timeout >/dev/null 2>&1; then
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" timeout "${QEMU_TIMEOUT}" \
    system/backends/appliance/scripts/qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1
  status=$?
elif command -v gtimeout >/dev/null 2>&1; then
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" gtimeout "${QEMU_TIMEOUT}" \
    system/backends/appliance/scripts/qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1
  status=$?
else
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" \
    system/backends/appliance/scripts/qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1 &
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
  *) tail -n 120 "${QEMU_LOG}" >&2; fail "QEMU exited with status ${status}" ;;
esac

require_log 'Alpenglow boot'
require_log 'mount-filesystems'
require_log 'shell-ttyS0'
require_log 'login:'
reject_log 'No such file or directory'

printf 'ci-qemu-appliance: ok\n'
