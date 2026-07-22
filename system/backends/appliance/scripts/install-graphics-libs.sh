#!/bin/sh
# Fetch glibc Mesa/Vulkan/EGL shared libraries from Debian for alpenglowed.
# alpenglowed is glibc-linked and dlopens libvulkan.so.1, libEGL.so.1, etc.
# These must be glibc versions, separate from cage's musl libs.
#
# Usage: install-graphics-libs.sh <out-dir>
# Output: $OUT_DIR/glibc-libs/ with lib/x86_64-linux-gnu/ and usr/share/vulkan/
set -eu

OUT_DIR="${1:-/build/out}"
GRAPHICS_BACKEND="${2:-software}"
[ -d "${OUT_DIR}" ] || mkdir -p "${OUT_DIR}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
mkdir -p "${OUT_DIR}/glibc-libs"

echo "→ Fetching glibc Mesa/Vulkan/EGL libs from Debian (${GRAPHICS_BACKEND})..."

docker run --rm --platform linux/amd64 -e GRAPHICS_BACKEND="${GRAPHICS_BACKEND}" -v "${OUT_DIR}/glibc-libs:/out" rust:latest sh -c '
  set -e
  rm -rf /out/lib /out/lib64 /out/usr /out/.graphics-backend
  apt-get update -qq 2>/dev/null
  apt-get install -y -qq \
    libegl1 libegl-mesa0 libgles2 libgl1 libgl1-mesa-dri \
    libgbm1 libdrm2 libvulkan1 mesa-vulkan-drivers \
    libwayland-client0 libxkbcommon0 libxkbcommon-dev \
    libstdc++6 libgcc-s1 2>/dev/null >/dev/null

  # glibc shared libs → /lib/x86_64-linux-gnu/
  mkdir -p /out/lib/x86_64-linux-gnu
  for lib in \
    libEGL.so.1 libEGL.so.1.1.0 \
    libGL.so.1 libGL.so.1.7.0 \
    libGLESv2.so.2 \
    libgbm.so.1 \
    libdrm.so.2 \
    libvulkan.so.1 \
    libGLdispatch.so.0 libGLX.so.0 \
    libwayland-client.so.0 \
    libxkbcommon.so.0 \
    libstdc++.so.6 \
    libgcc_s.so.1 \
    libc.so.6 libm.so.6 \
    libz.so.1 libzstd.so.1 liblzma.so.5 \
    libexpat.so.1 libffi.so.8 \
    libxml2.so.2 \
    libmd.so.0 \
    libX11.so.6 libX11-xcb.so.1 libXau.so.6 libXdmcp.so.6 \
    libxcb.so.1 libxcb-dri3.so.0 libxcb-present.so.0 libxcb-randr.so.0 \
    libxcb-shm.so.0 libxcb-sync.so.1 libxcb-xfixes.so.0 \
    libxshmfence.so.1; do
    src="/usr/lib/x86_64-linux-gnu/${lib}"
    [ -f "${src}" ] && cp "${src}" /out/lib/x86_64-linux-gnu/ 2>/dev/null || true
  done
  if [ "${GRAPHICS_BACKEND}" = "software" ]; then
    cp /usr/lib/x86_64-linux-gnu/libvulkan_lvp.so /out/lib/x86_64-linux-gnu/ 2>/dev/null || true
    cp /usr/lib/x86_64-linux-gnu/libLLVM.so.19.1 /out/lib/x86_64-linux-gnu/ 2>/dev/null || true
  else
    for lib in /usr/lib/x86_64-linux-gnu/libvulkan_*.so; do
      [ -f "${lib}" ] || continue
      case "$(basename "${lib}")" in libvulkan_lvp.so|libvulkan_radeon.so) continue ;; esac
      cp "${lib}" /out/lib/x86_64-linux-gnu/ 2>/dev/null || true
    done
  fi

  # glibc dynamic linker (prefer canonical usr path, legacy /lib64 as fallback)
  mkdir -p /out/lib64
  cp /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /out/lib64/ 2>/dev/null || \
    cp /lib64/ld-linux-x86-64.so.2 /out/lib64/ 2>/dev/null || true

  # DRI drivers (software rasterizer)
  mkdir -p /out/usr/lib/x86_64-linux-gnu/dri
  if [ "${GRAPHICS_BACKEND}" = "software" ]; then
    cp /usr/lib/x86_64-linux-gnu/dri/kms_swrast_dri.so /out/usr/lib/x86_64-linux-gnu/dri/ 2>/dev/null || true
    cp /usr/lib/x86_64-linux-gnu/dri/swrast_dri.so /out/usr/lib/x86_64-linux-gnu/dri/ 2>/dev/null || true
  else
    cp /usr/lib/x86_64-linux-gnu/dri/*_dri.so /out/usr/lib/x86_64-linux-gnu/dri/ 2>/dev/null || true
    rm -f /out/usr/lib/x86_64-linux-gnu/dri/kms_swrast_dri.so /out/usr/lib/x86_64-linux-gnu/dri/swrast_dri.so /out/usr/lib/x86_64-linux-gnu/dri/radeon*_dri.so
  fi

  # Vulkan lavapipe ICD
  mkdir -p /out/usr/share/vulkan/icd.d
  if [ "${GRAPHICS_BACKEND}" = "software" ]; then
    # Fix ICD json to use absolute path
    cp /usr/share/vulkan/icd.d/lvp_icd*.json /out/usr/share/vulkan/icd.d/lvp_icd.json 2>/dev/null || true
    if [ -f "/out/usr/share/vulkan/icd.d/lvp_icd.json" ]; then
      sed -i "s#\"library_path\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\"#\"library_path\": \"/lib/x86_64-linux-gnu/\\1\"#" /out/usr/share/vulkan/icd.d/lvp_icd.json
    fi
  else
    cp /usr/share/vulkan/icd.d/*.json /out/usr/share/vulkan/icd.d/ 2>/dev/null || true
    rm -f /out/usr/share/vulkan/icd.d/lvp_icd*.json /out/usr/share/vulkan/icd.d/radeon_icd*.json
    for json in /out/usr/share/vulkan/icd.d/*.json; do
      [ -f "${json}" ] || continue
      sed -i "s#\"library_path\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\"#\"library_path\": \"/lib/x86_64-linux-gnu/\\1\"#" "${json}"
    done
  fi

  # Copy any missing transitive deps
  for lib in /out/lib/x86_64-linux-gnu/lib*.so*; do
    [ -f "${lib}" ] || continue
    ldd "${lib}" 2>/dev/null | awk "{print \$3}" | grep "^/" | while read dep; do
      [ -f "${dep}" ] || continue
      base=$(basename "${dep}")
      [ -f "/out/lib/x86_64-linux-gnu/${base}" ] && continue
      [ -f "/out/lib64/${base}" ] && continue
      cp "${dep}" /out/lib/x86_64-linux-gnu/ 2>/dev/null || true
    done
  done

  echo "  glibc libs: $(ls /out/lib/x86_64-linux-gnu/lib*.so* 2>/dev/null | wc -l) files"
  echo "  dri drivers: $(ls /out/usr/lib/x86_64-linux-gnu/dri/ 2>/dev/null | wc -l) files"
  echo "  vulkan ICD: $(ls /out/usr/share/vulkan/icd.d/ 2>/dev/null | wc -l) files"
  printf "%s\n" "${GRAPHICS_BACKEND}" > /out/.graphics-backend
'

echo "  output: ${OUT_DIR}/glibc-libs"
