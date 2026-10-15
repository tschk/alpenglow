#!/bin/sh
# Exercise boot benchmark outcomes without launching a real VM.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM
mkdir -p "${TMP_DIR}/scripts" "${TMP_DIR}/bin" \
  "${TMP_DIR}/build/native" "${TMP_DIR}/build/cross/aarch64"
cp "${ROOT_DIR}/scripts/bench-boot.sh" "${ROOT_DIR}/scripts/bench-boot-aarch64.sh" "${TMP_DIR}/scripts/"
: > "${TMP_DIR}/build/native/vmlinuz"
: > "${TMP_DIR}/build/native/initramfs.cpio.gz"
: > "${TMP_DIR}/build/cross/aarch64/vmlinuz"
: > "${TMP_DIR}/build/cross/aarch64/initramfs.cpio.gz"

cat > "${TMP_DIR}/bin/fake-qemu" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "${FAKE_QEMU_ARGS}"
case "${FAKE_QEMU_MODE}" in
  success) printf 'Alpenglow boot\nlogin:\n'; exec sleep 10 ;;
  login-exit) printf 'login:\n'; exit 0 ;;
  timeout) printf 'Alpenglow boot\n'; exec sleep 10 ;;
  no-marker) printf 'Alpenglow boot\n'; exit 0 ;;
  error) printf 'QEMU launch failed\n' >&2; exit 42 ;;
  login-error) printf 'login:\n'; exit 42 ;;
  *) exit 99 ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/fake-qemu"
ln -s fake-qemu "${TMP_DIR}/bin/qemu-system-x86_64"
ln -s fake-qemu "${TMP_DIR}/bin/qemu-system-aarch64"

fail() { printf 'test-bench-boot: %s\n' "$1" >&2; exit 1; }
run() {
  script="$1"
  mode="$2"
  accel="$3"
  case "${mode}" in
    timeout) max_polls=2 ;;
    *) max_polls=20 ;;
  esac
  : > "${TMP_DIR}/args"
  env PATH="${TMP_DIR}/bin:${PATH}" FAKE_QEMU_ARGS="${TMP_DIR}/args" \
    FAKE_QEMU_MODE="${mode}" BENCH_MAX_POLLS="${max_polls}" ACCEL="${accel}" \
    sh "${TMP_DIR}/scripts/${script}" > "${TMP_DIR}/output" 2>&1
}
expect_ok() {
  run "$1" "$2" "$3" || fail "$1 $2 $3 should succeed: $(cat "${TMP_DIR}/output")"
  grep -q 'bench: ok' "${TMP_DIR}/output" || fail "$1 $2 missing success result"
  grep -q 'VM launch to login' "${TMP_DIR}/output" || fail "$1 $2 timing label"
}
expect_fail() {
  if run "$1" "$2" "$3"; then
    fail "$1 $2 $3 should fail"
  fi
  grep -q "$4" "${TMP_DIR}/output" || fail "$1 $2 wrong failure: $(cat "${TMP_DIR}/output")"
  if grep -q 'bench: ok' "${TMP_DIR}/output"; then
    fail "$1 $2 reported success on failure"
  fi
}

for script in bench-boot.sh bench-boot-aarch64.sh; do
  expect_ok "${script}" success tcg
  expect_ok "${script}" login-exit tcg
  expect_fail "${script}" timeout tcg 'timed out waiting for login marker'
  expect_fail "${script}" no-marker tcg 'login marker not found'
  expect_fail "${script}" error tcg 'QEMU exited with an error'
  expect_fail "${script}" login-error tcg 'QEMU exited with an error'
done

expect_ok bench-boot-aarch64.sh success hvf
grep -qx 'virt,accel=hvf' "${TMP_DIR}/args" || fail 'aarch64 HVF was not passed to QEMU'
expect_ok bench-boot-aarch64.sh success kvm
grep -qx 'virt,accel=kvm' "${TMP_DIR}/args" || fail 'aarch64 KVM was not passed to QEMU'
if run bench-boot-aarch64.sh success invalid; then
  fail 'unsupported aarch64 accelerator should fail'
fi
grep -q 'unsupported aarch64 accelerator' "${TMP_DIR}/output" || fail 'unsupported accelerator message'
[ ! -s "${TMP_DIR}/args" ] || fail 'unsupported accelerator launched QEMU'

printf 'test-bench-boot: ok\n'
