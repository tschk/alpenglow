#!/bin/sh
# Smoke-test the aarch64 musl installer GUI (see build-aarch64-gui.sh) in an Alpine arm64
# userland. Needs docker with arm64 binfmt/qemu-user; boots no kernel and installs nothing.
#
#   smoke-aarch64-gui.sh check <binary>   ELF shape + every shared library resolves
#   smoke-aarch64-gui.sh run   <binary>   start it under a headless compositor and screenshot
#
# `check` is deterministic. `run` exercises Wayland connect and Vulkan (lavapipe) start-up
# under emulation, so it is slow and only informative about GPU initialisation.
set -eu

MODE="${1:?usage: $0 check|run <binary>}"
BIN="${2:?usage: $0 check|run <binary>}"
IMAGE="${ALPENGLOW_AARCH64_SMOKE_IMAGE:-alpine:3.21}"
RUN_SECONDS="${ALPENGLOW_AARCH64_SMOKE_SECONDS:-240}"

fail() { printf 'smoke-aarch64-gui: FAIL: %s\n' "$1" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || fail "missing: docker"
command -v readelf >/dev/null 2>&1 || fail "missing: readelf"
test -f "${BIN}" || fail "missing binary: ${BIN}"
BIN="$(CDPATH='' cd -- "$(dirname -- "${BIN}")" && pwd)/$(basename -- "${BIN}")"

# Runtime userland a desktop rootfs provides (see test-aarch64-installers.sh).
RUNTIME_PKGS="libxkbcommon-x11 wayland-libs-client vulkan-loader fontconfig ttf-dejavu mesa-dri-gallium mesa-vulkan-swrast"

# Static musl cannot dlopen libwayland-client/libvulkan, and raw rust-lld needs an explicit
# program interpreter and start file; see system/installer/build.rs.
header="$(readelf -h "${BIN}")"
printf '%s\n' "${header}" | grep -q 'Machine:.*AArch64' || fail "not an aarch64 binary"
entry="$(printf '%s\n' "${header}" | sed -n 's/.*Entry point address:[[:space:]]*//p')"
[ "${entry}" != "0x0" ] || fail "entry point is 0 (missing musl start file)"
readelf -lW "${BIN}" | grep -q 'Requesting program interpreter: /lib/ld-musl-aarch64.so.1' ||
  fail "no musl program interpreter (static or mislinked binary)"

run_in_alpine() {
  docker run --rm -i --platform linux/arm64 -v "${BIN}:/usr/bin/alpenglow-install-gui:ro" \
    -e RUNTIME_PKGS="${RUNTIME_PKGS}" -e RUN_SECONDS="${RUN_SECONDS}" "$@"
}

case "${MODE}" in
  check)
    out="$(run_in_alpine "${IMAGE}" sh -eu -s 2>&1 <<'EOS'
apk add --no-cache ${RUNTIME_PKGS} >/dev/null
ldd /usr/bin/alpenglow-install-gui
EOS
)" || fail "loader check failed: ${out}"
    printf '%s\n' "${out}"
    case "${out}" in
      *"not found"*|*"Error loading"*|*"symbol not found"*) fail "unresolved shared libraries" ;;
    esac
    printf 'smoke-aarch64-gui: check ok\n'
    ;;
  run)
    out="$(run_in_alpine "${IMAGE}" sh -eu -s 2>&1 <<'EOS'
apk add --no-cache cage grim ${RUNTIME_PKGS} >/dev/null
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -m 700 "${XDG_RUNTIME_DIR}"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 LIBSEAT_BACKEND=noop
# Record the GUI's own PID: under arm64 emulation /proc/<pid>/cmdline names the qemu wrapper,
# so matching the command line is unreliable. exec keeps the PID.
cage -- sh -c 'echo $$ >/tmp/gui.pid; exec /usr/bin/alpenglow-install-gui' >/tmp/gui.log 2>&1 &
cage_pid=$!
shot=
elapsed=0
while [ "${elapsed}" -lt "${RUN_SECONDS}" ]; do
  sleep 10
  elapsed=$((elapsed + 10))
  kill -0 "${cage_pid}" 2>/dev/null || break
  if WAYLAND_DISPLAY=wayland-0 grim /tmp/shot.png 2>/dev/null && [ "$(wc -c < /tmp/shot.png)" -gt 20000 ]; then
    shot=ok
    break
  fi
done
echo '--- gui log'
cat /tmp/gui.log
[ "${shot}" = ok ] || { echo 'no rendered window captured'; exit 1; }
# The captured window must be the installer, still running, not just cage's empty output.
gui_pid="$(cat /tmp/gui.pid 2>/dev/null || true)"
if [ -z "${gui_pid}" ] || ! kill -0 "${gui_pid}" 2>/dev/null; then
  echo "GUI process is not running (pid '${gui_pid}')"
  ps || true
  exit 1
fi
echo "rendered window captured with the GUI process (pid ${gui_pid}) running"
EOS
)" || { printf '%s\n' "${out}"; fail "run smoke failed"; }
    printf '%s\n' "${out}"
    case "${out}" in
      *"NoWaylandLib"*|*"panicked"*|*"Failed to open window"*) fail "GUI reported a start-up error" ;;
    esac
    printf 'smoke-aarch64-gui: run ok\n'
    ;;
  *) fail "unknown mode: ${MODE}" ;;
esac
