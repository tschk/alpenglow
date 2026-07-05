#!/bin/sh
# Fetch cage (Wayland kiosk compositor) + Xwayland + all musl runtime deps
# from Alpine 3.21 packages. Output: $OUT_DIR/cage/
set -eu

OUT_DIR="${1:-/build/out}"
[ -d "${OUT_DIR}" ] || mkdir -p "${OUT_DIR}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
mkdir -p "${OUT_DIR}/cage"

echo "→ Fetching cage + musl deps from Alpine 3.21..."

docker run --rm --platform linux/amd64 -v "${OUT_DIR}/cage:/out" alpine:3.21 sh -c '
  set -e
  apk add --no-cache cage xwayland seatd 2>/dev/null >/dev/null

  # Copy binaries
  mkdir -p /out/usr/bin
  cp /usr/bin/cage /out/usr/bin/
  cp /usr/bin/Xwayland /out/usr/bin/ 2>/dev/null || true
  cp /usr/bin/seatd /out/usr/bin/ 2>/dev/null || true
  cp /usr/bin/seatd-launch /out/usr/bin/ 2>/dev/null || true

  # Copy all runtime shared libs from /usr/lib
  mkdir -p /out/usr/lib
  copy_deps() {
    for bin in "$@"; do
      [ -e "$bin" ] || continue
      ldd "$bin" 2>/dev/null | awk "{print \$3}" | grep "^/" | while read dep; do
        cp -a "$dep" /out/usr/lib/ 2>/dev/null || true
      done
    done
  }
  copy_deps /usr/bin/cage /usr/bin/Xwayland /usr/bin/seatd /usr/bin/seatd-launch

  # Copy DRI drivers
  mkdir -p /out/usr/lib/dri
  cp /usr/lib/dri/swrast_dri.so /out/usr/lib/dri/ 2>/dev/null || true
  cp /usr/lib/dri/kms_swrast_dri.so /out/usr/lib/dri/ 2>/dev/null || true
  copy_deps /usr/lib/dri/swrast_dri.so /usr/lib/dri/kms_swrast_dri.so

  # Copy gallium pipe loaders
  mkdir -p /out/usr/lib/gallium-pipe
  cp /usr/lib/gallium-pipe/pipe_swrast.so /out/usr/lib/gallium-pipe/ 2>/dev/null || true
  copy_deps /usr/lib/gallium-pipe/pipe_swrast.so

  # Copy gbm backends
  mkdir -p /out/usr/lib/gbm
  cp /usr/lib/gbm/gbm_dri.so /out/usr/lib/gbm/ 2>/dev/null || true
  copy_deps /usr/lib/gbm/gbm_dri.so

  # Copy Xwayland xorg config
  mkdir -p /out/usr/share/X11/xorg.conf.d
  cp /usr/share/X11/xorg.conf.d/*.conf /out/usr/share/X11/xorg.conf.d/ 2>/dev/null || true

  # Copy musl dynamic linker (Alpine 3.21 is already usrmerged: /lib -> usr/lib)
  mkdir -p /out/lib
  cp /usr/lib/ld-musl-x86_64.so.1 /out/lib/ 2>/dev/null || cp /lib/ld-musl-x86_64.so.1 /out/lib/

  echo "  cage: $(ls -la /out/usr/bin/cage | awk "{print \$5}") bytes"
  echo "  libs: $(ls /out/usr/lib/lib*.so* 2>/dev/null | wc -l) files"
  chown -R "$(stat -c %u /out):$(stat -c %g /out)" /out 2>/dev/null || true
'

echo "  output: ${OUT_DIR}/cage"
