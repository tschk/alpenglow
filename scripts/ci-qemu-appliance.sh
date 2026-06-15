#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

QEMU_TIMEOUT="${QEMU_TIMEOUT:-180}"
QEMU_LOG="${QEMU_LOG:-${TMPDIR:-/tmp}/alpenglow-qemu-appliance.log}"
QEMU_DIR="${QEMU_DIR:-build/alpine/qemu}"

fail() {
  printf 'ci-qemu-appliance: %s\n' "$1" >&2
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

rm -f "${QEMU_LOG}"
set +e
if command -v timeout >/dev/null 2>&1; then
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" timeout "${QEMU_TIMEOUT}" \
    system/alpine/scripts/run-qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1
  status=$?
elif command -v gtimeout >/dev/null 2>&1; then
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" gtimeout "${QEMU_TIMEOUT}" \
    system/alpine/scripts/run-qemu.sh "${QEMU_DIR}" >"${QEMU_LOG}" 2>&1
  status=$?
else
  QEMU_HEADLESS=1 QEMU_ACCEL="${QEMU_ACCEL:-tcg}" \
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
  *) tail -n 120 "${QEMU_LOG}" >&2; fail "QEMU exited with status ${status}" ;;
esac

require_log '\[init\] launching /sbin/init'
require_log 'OpenRC .*Linux 6\.12\.[0-9]+-0-virt'
require_log 'Starting alpenglow-kernel-policy .*ok'
require_log 'Starting alpenglow-zram .*ok'
require_log 'Starting alpenglow-pressure'
require_log 'lease of 10\.0\.2\.15 obtained'
require_log 'DRM device found; using cage \(Wayland\)'
require_log 'redraw requested: .*active_webview=true.*title=Alpenglow( Shell)?'
require_log 'gui\.paint end'
reject_log 'kernel policy required but cgroups state is unavailable'
reject_log 'Cannot find Xwayland binary'
reject_log '/etc/resolv\.conf\.[A-Za-z0-9]+'
reject_log 'cannot start .* as alpenglow-kernel-policy would not start'
reject_log 'cannot start .* as alpenglow-pressure would not start'
reject_log 'ERROR: alpenglow-session failed to start'

printf 'ci-qemu-appliance: ok\n'
