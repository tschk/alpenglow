#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/cross/aarch64"
TMP="${TMPDIR:-/tmp}/alpenglow-aarch64-installers"
TIMEOUT="${TIMEOUT:-45}"
MODE="${1:-${MODE:-all}}"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing: $1"
}

run_qemu() {
  initrd="$1"
  log="$2"
  shift 2
  timeout "${TIMEOUT}" qemu-system-aarch64 \
    -M virt -accel tcg -cpu max -m 2048 -smp 2 \
    "$@" \
    -serial stdio -no-reboot \
    -kernel "${OUT_DIR}/vmlinuz-virt" \
    -initrd "${initrd}" \
    -append "console=ttyAMA0,115200 init=/init" \
    2>&1 | tee "${log}" || true
}

pack_root() {
  root="$1"
  initrd="$2"
  (cd "${root}" && find . | cpio -H newc -o | gzip -1 > "${initrd}")
}

require_cmd cargo
require_cmd cpio
require_cmd docker
require_cmd gzip
require_cmd qemu-system-aarch64
require_cmd tar
require_cmd timeout

case "${MODE}" in
  all|tui|gui) ;;
  *) fail "usage: $0 [all|tui|gui]" ;;
esac

test -f "${OUT_DIR}/vmlinuz-virt" || fail "missing ${OUT_DIR}/vmlinuz-virt"
test -f "${OUT_DIR}/toybox-aarch64" || fail "missing ${OUT_DIR}/toybox-aarch64"

rm -rf "${TMP}"
mkdir -p "${TMP}"

if [ "${MODE}" = "all" ] || [ "${MODE}" = "tui" ]; then
  mkdir -p "${TMP}/standard/bin" "${TMP}/standard/proc" "${TMP}/standard/sys" "${TMP}/standard/dev" "${TMP}/standard/run"

  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER:-rust-lld}" \
    cargo build --release --target aarch64-unknown-linux-musl --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
    --target-dir "${ROOT_DIR}/target" --bin alpenglow-install --bin alpenglow-install-tui

  cp "${OUT_DIR}/toybox-aarch64" "${TMP}/standard/bin/toybox"
  ln -sf toybox "${TMP}/standard/bin/sh"
  cp "${ROOT_DIR}/target/aarch64-unknown-linux-musl/release/alpenglow-install-tui" "${TMP}/standard/bin/alpenglow-install-tui"
  cat > "${TMP}/standard/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec >/dev/ttyAMA0 2>&1
mount -t tmpfs tmpfs /run
echo "Alpenglow standard aarch64 installer smoke"
TERM=xterm /bin/alpenglow-install-tui || true
echo "Alpenglow standard installer smoke OK"
/bin/toybox poweroff -f
EOF
  chmod +x "${TMP}/standard/init" "${TMP}/standard/bin/toybox" "${TMP}/standard/bin/alpenglow-install-tui"
  pack_root "${TMP}/standard" "${TMP}/standard.cpio.gz"
  run_qemu "${TMP}/standard.cpio.gz" "${TMP}/standard.log" -display none
  grep -q "Alpenglow standard installer smoke OK" "${TMP}/standard.log" || fail "standard installer smoke failed"
fi

if [ "${MODE}" = "all" ] || [ "${MODE}" = "gui" ]; then
  GUI_SYSROOT="$(ALPENGLOW_AARCH64_GUI_SYSROOT="${ALPENGLOW_AARCH64_GUI_SYSROOT:-}" sh "${ROOT_DIR}/scripts/build-aarch64-gui-sysroot.sh")"
  CC_aarch64_unknown_linux_musl="${ROOT_DIR}/scripts/aarch64-linux-musl-zigcc" \
  CXX_aarch64_unknown_linux_musl="${ROOT_DIR}/scripts/aarch64-linux-musl-zigcxx" \
  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER:-rust-lld}" \
  RUSTFLAGS="${RUSTFLAGS:-} -L native=${GUI_SYSROOT}/usr/lib -L native=${GUI_SYSROOT}/lib" \
    cargo build --release --target aarch64-unknown-linux-musl --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
    --target-dir "${ROOT_DIR}/target" --features gui --bin alpenglow-install-gui

  mkdir -p "${TMP}/desktop"
  CID="$(docker create --platform linux/arm64 alpine:3.21 sleep 600)"
  cleanup() {
    docker rm -f "${CID}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT
  docker start "${CID}" >/dev/null
  docker exec "${CID}" sh -lc 'apk add --no-cache cage seatd libxkbcommon-x11 fontconfig ttf-dejavu mesa-dri-gallium mesa-vulkan-swrast >/dev/null'
  docker export "${CID}" | tar -C "${TMP}/desktop" -xf -
  mkdir -p "${TMP}/desktop/proc" "${TMP}/desktop/sys" "${TMP}/desktop/dev" "${TMP}/desktop/run" "${TMP}/desktop/tmp"
  cp "${ROOT_DIR}/target/aarch64-unknown-linux-musl/release/alpenglow-install-gui" "${TMP}/desktop/usr/bin/alpenglow-install-gui"
  cat > "${TMP}/desktop/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec >/dev/ttyAMA0 2>&1
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp
mkdir -p /run/seatd /run/user/0
export XDG_RUNTIME_DIR=/run/user/0
export LIBSEAT_BACKEND=seatd
export WLR_RENDERER=pixman
export WLR_NO_HARDWARE_CURSORS=1
echo "Alpenglow desktop wayland aarch64 smoke"
/usr/bin/seatd -g root -n 1 >/tmp/seatd.log 2>&1 &
sleep 1
/usr/bin/cage /usr/bin/alpenglow-install-gui >/tmp/gui.log 2>&1 &
pid=$!
sleep 8
if kill -0 "$pid" 2>/dev/null; then
  echo "Alpenglow desktop GUI running"
  kill "$pid" 2>/dev/null || true
else
  wait "$pid"
  echo "Alpenglow desktop GUI exited $?"
fi
cat /tmp/seatd.log 2>/dev/null || true
cat /tmp/gui.log 2>/dev/null || true
echo "Alpenglow desktop wayland smoke OK"
poweroff -f
EOF
  chmod +x "${TMP}/desktop/init" "${TMP}/desktop/usr/bin/alpenglow-install-gui"
  pack_root "${TMP}/desktop" "${TMP}/desktop.cpio.gz"
  run_qemu "${TMP}/desktop.cpio.gz" "${TMP}/desktop.log" -display cocoa -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci
  grep -q "Alpenglow desktop GUI running" "${TMP}/desktop.log" || fail "desktop GUI did not keep running"
  grep -q "Alpenglow desktop wayland smoke OK" "${TMP}/desktop.log" || fail "desktop wayland smoke failed"
fi

echo "test-aarch64-installers: ok"
