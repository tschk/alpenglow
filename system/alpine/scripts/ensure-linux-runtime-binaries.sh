#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
CREPUSCULARITY_DIR="${ROOT_DIR}/../crepuscularity"
SOLILOQUY_DESKTOP_ROOT="${SOLILOQUY_DESKTOP_ROOT:-${ROOT_DIR}/../soliloquy}"
QEMU_ARCH="${QEMU_ARCH:-x86_64}"
OUT_DIR="${ROOT_DIR}/build/alpine/artifacts/linux-${QEMU_ARCH}"
SERVO_SRC_BIN="${SERVO_SRC_BIN:-${SOLILOQUY_DESKTOP_ROOT}/third_party/servo/target/release/servoshell}"
SERVO_SOURCE_BUILD="${SERVO_SOURCE_BUILD:-1}"
SERVO_FORCE_REBUILD="${SERVO_FORCE_REBUILD:-0}"
SERVO_RELEASE_TAG="${SERVO_RELEASE_TAG:-v0.0.6}"
SERVO_RUNTIME_DIR="${OUT_DIR}/servo-runtime-root"
# Alpine appliance uses musl natively; default is a musl-linked servoshell (no gcompat glibc shim).
# Set SERVO_LINUX_LIBC=gnu to use the legacy Debian Bookworm glibc build + runtime bundle instead.
SERVO_LINUX_LIBC="${SERVO_LINUX_LIBC:-musl}"
SERVO_BUILD_IMAGE="${SERVO_BUILD_IMAGE:-rust:1.95-alpine}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

crepuscularity_mount_args() {
  if [ -d "${CREPUSCULARITY_DIR}" ]; then
    printf '%s\n' "-v" "${CREPUSCULARITY_DIR}:/crepuscularity:ro"
  fi
}

file_matches_arch() {
  bin_path="$1"
  file_info="$(file "${bin_path}")"
  case "${QEMU_ARCH}" in
    x86_64)
      case "${file_info}" in
        *"ELF 64-bit"*x86-64*) return 0 ;;
      esac
      ;;
    aarch64|arm64)
      case "${file_info}" in
        *"ELF 64-bit"*aarch64*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

sold_matches_runtime() {
  bin_path="$1"
  file_info="$(file "${bin_path}")"
  case "${file_info}" in
    *"static-pie linked"*|*"statically linked"*) return 0 ;;
  esac
  case "${QEMU_ARCH}" in
    x86_64)
      case "${file_info}" in
        *"interpreter /lib/ld-musl-x86_64.so.1"*) return 0 ;;
      esac
      ;;
    aarch64|arm64)
      case "${file_info}" in
        *"interpreter /lib/ld-musl-aarch64.so.1"*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

kernelctl_matches_runtime() {
  sold_matches_runtime "$1"
}

netd_matches_runtime() {
  sold_matches_runtime "$1"
}

servo_native_musl() {
  bin_path="$1"
  file_info="$(file "${bin_path}")"
  case "${file_info}" in
    *"interpreter /lib/ld-musl-x86_64.so.1"*) return 0 ;;
    *"interpreter /lib/ld-musl-aarch64.so.1"*) return 0 ;;
  esac
  return 1
}

servo_needs_glibc_runtime() {
  bin_path="$1"
  file_info="$(file "${bin_path}")"
  case "${QEMU_ARCH}" in
    x86_64)
      case "${file_info}" in
        *"interpreter /lib64/ld-linux-x86-64.so.2"*) return 0 ;;
      esac
      ;;
    aarch64|arm64)
      case "${file_info}" in
        *"interpreter /lib/ld-linux-aarch64.so.1"*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

servo_supports_soliloquy_chrome_mode() {
  bin_path="$1"
  strings "${bin_path}" 2>/dev/null | grep -q -- "no-browser-chrome"
}

servo_runtime_bundle_ready() {
  case "${QEMU_ARCH}" in
    x86_64)
      [ -f "${SERVO_RUNTIME_DIR}/lib64/ld-linux-x86-64.so.2" ] ||
        [ -f "${SERVO_RUNTIME_DIR}/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" ]
      ;;
    aarch64|arm64)
      [ -f "${SERVO_RUNTIME_DIR}/lib/ld-linux-aarch64.so.1" ] ||
        [ -f "${SERVO_RUNTIME_DIR}/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" ]
      ;;
    *)
      return 1
      ;;
  esac
}

build_sold_linux() {
  require_tool docker

  case "${QEMU_ARCH}" in
    x86_64)
      docker_platform="linux/amd64"
      ;;
    aarch64|arm64)
      docker_platform="linux/arm64"
      ;;
    *)
      echo "unsupported QEMU_ARCH: ${QEMU_ARCH}" >&2
      exit 1
      ;;
  esac

  echo "Building Linux sold for ${QEMU_ARCH}..." >&2
  docker run --rm \
    --platform "${docker_platform}" \
    -v "${ROOT_DIR}:/work" \
    $(crepuscularity_mount_args) \
    -w /work \
    rust:1.95-alpine sh -lc "
      set -eu
      export PATH=/usr/local/cargo/bin:\$PATH
      apk add --no-cache musl-dev
      cargo build --release --manifest-path sold/Cargo.toml --target-dir target/alpine-sold
      cp target/alpine-sold/release/sold build/alpine/artifacts/linux-${QEMU_ARCH}/sold
    " >&2
}

build_kernelctl_linux() {
  require_tool docker

  case "${QEMU_ARCH}" in
    x86_64)
      docker_platform="linux/amd64"
      ;;
    aarch64|arm64)
      docker_platform="linux/arm64"
      ;;
    *)
      echo "unsupported QEMU_ARCH: ${QEMU_ARCH}" >&2
      exit 1
      ;;
  esac

  echo "Building Linux sol-kernelctl for ${QEMU_ARCH}..." >&2
  docker run --rm \
    --platform "${docker_platform}" \
    -v "${ROOT_DIR}:/work" \
    $(crepuscularity_mount_args) \
    -w /work \
    rust:1.95-alpine sh -lc "
      set -eu
      export PATH=/usr/local/cargo/bin:\$PATH
      apk add --no-cache musl-dev
      cargo build --release --manifest-path system/kernelctl/Cargo.toml --target-dir target/alpine-kernelctl
      cp target/alpine-kernelctl/release/sol-kernelctl build/alpine/artifacts/linux-${QEMU_ARCH}/sol-kernelctl
    " >&2
}

build_netd_linux() {
  require_tool docker

  case "${QEMU_ARCH}" in
    x86_64)
      docker_platform="linux/amd64"
      ;;
    aarch64|arm64)
      docker_platform="linux/arm64"
      ;;
    *)
      echo "unsupported QEMU_ARCH: ${QEMU_ARCH}" >&2
      exit 1
      ;;
  esac

  echo "Building Linux sol-netd for ${QEMU_ARCH}..." >&2
  docker run --rm \
    --platform "${docker_platform}" \
    -v "${ROOT_DIR}:/work" \
    $(crepuscularity_mount_args) \
    -w /work \
    rust:1.95-alpine sh -lc "
      set -eu
      export PATH=/usr/local/cargo/bin:\$PATH
      apk add --no-cache musl-dev
      cargo build --release --manifest-path system/netd/Cargo.toml --target-dir target/alpine-netd
      cp target/alpine-netd/release/sol-netd build/alpine/artifacts/linux-${QEMU_ARCH}/sol-netd
    " >&2
}

# Native musl servoshell for Alpine (rust:alpine default target = *-unknown-linux-musl).
build_servo_linux_musl_from_source() {
  require_tool docker

  case "${QEMU_ARCH}" in
    x86_64) docker_platform="linux/amd64" ;;
    aarch64|arm64) docker_platform="linux/arm64" ;;
    *)
      echo "no musl Servo source build for QEMU_ARCH=${QEMU_ARCH}" >&2
      exit 1
      ;;
  esac

  echo "Building Servo (musl) from local source for ${QEMU_ARCH} using ${SERVO_BUILD_IMAGE}..." >&2
  docker run --rm \
    --platform "${docker_platform}" \
    -e QEMU_ARCH="${QEMU_ARCH}" \
    -v "${ROOT_DIR}:/work" \
    "${SERVO_BUILD_IMAGE}" sh -lc "
      set -eu
      export PATH=\"/usr/lib/llvm21/bin:/usr/local/cargo/bin:\${PATH}\"
      export LIBCLANG_PATH=\"/usr/lib/llvm21/lib\"
      # Default musl rustc uses +crt-static; bindgen then cannot dlopen libclang. Disable for this build.
      export RUSTFLAGS=\"-C target-feature=-crt-static\"
      apk update >/dev/null
      apk add --no-cache \
        build-base musl-dev git python3 py3-pip pkgconf cmake gcc g++ lld llvm21 llvm-dev clang-dev clang21-libclang \
        openssl-dev fontconfig-dev freetype-dev harfbuzz-dev glib-dev dbus-dev eudev-dev \
        libx11-dev libxcb-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev \
        libxkbcommon-dev mesa-dev gst-plugins-base-dev gstreamer-dev \
        gst-plugins-bad-dev wayland-dev perl nasm rsync bash wget unzip zip \
        autoconf automake gawk
      rm -rf /tmp/servo-src
      mkdir -p /tmp/servo-src
      rsync -a --delete /work/third_party/servo/ /tmp/servo-src/
      rm -rf /src /examples
      ln -s /work/src /src
      ln -s /work/examples /examples
      cd /tmp/servo-src
      export CC=gcc
      export CXX=g++
      cargo build --release \
        --locked \
        --manifest-path ports/servoshell/Cargo.toml \
        --target-dir target/linux-servoshell-musl
      cp target/linux-servoshell-musl/release/servoshell /work/build/alpine/artifacts/linux-\${QEMU_ARCH}/servo
    " >&2
}

# Legacy glibc servoshell (Debian); requires servo-runtime-root bundle on Alpine.
build_servo_linux_gnu_from_source() {
  require_tool docker

  case "${QEMU_ARCH}" in
    x86_64)
      docker_platform="linux/amd64"
      ;;
    *)
      echo "no glibc Servo Linux build configured for QEMU_ARCH=${QEMU_ARCH}" >&2
      exit 1
      ;;
  esac

  echo "Building Servo (glibc) from local source for ${QEMU_ARCH}..." >&2
  docker run --rm \
    --platform "${docker_platform}" \
    -e QEMU_ARCH="${QEMU_ARCH}" \
    -v "${ROOT_DIR}:/work" \
    rust:1.95-bookworm bash -lc '
      set -eu
      export DEBIAN_FRONTEND=noninteractive
      export PATH=/usr/local/cargo/bin:$HOME/.local/bin:$PATH
      apt-get update >/dev/null
      apt-get install -y --no-install-recommends \
        clang \
        cmake \
        libdbus-1-dev \
        libegl1-mesa-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libglib2.0-dev \
        libgstreamer-plugins-bad1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer1.0-dev \
        libssl-dev \
        libx11-dev \
        libx11-xcb-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev \
        libxcursor-dev \
        libxi-dev \
        libxinerama-dev \
        libxkbcommon-dev \
        libxkbcommon-x11-dev \
        libxrandr-dev \
        llvm-dev \
        make \
        pkg-config \
        python3 \
        python3-pip \
        rsync \
        unzip \
        wget >/dev/null
      python3 -m pip install --break-system-packages uv >/dev/null
      rm -rf /tmp/servo-src
      mkdir -p /tmp/servo-src
      rsync -a --delete /work/third_party/servo/ /tmp/servo-src/
      rm -rf /src /examples
      ln -s /work/src /src
      ln -s /work/examples /examples
      cd /tmp/servo-src
      export CC=cc
      export CXX=c++
      cargo build --release \
        --locked \
        --manifest-path ports/servoshell/Cargo.toml \
        --target-dir target/linux-servoshell \
        --config "target.x86_64-unknown-linux-gnu.linker=\"cc\"" \
        --config "target.x86_64-unknown-linux-gnu.rustflags=[]"
      cp target/linux-servoshell/release/servoshell /work/build/alpine/artifacts/linux-${QEMU_ARCH}/servo
    ' >&2
}

fetch_servo_release_linux() {
  case "${QEMU_ARCH}" in
    x86_64) asset_name="servo-x86_64-linux-gnu.tar.gz" ;;
    *)
      echo "no default Servo release asset configured for QEMU_ARCH=${QEMU_ARCH}" >&2
      echo "set SERVO_BIN_LINUX to a Linux ELF servoshell/servo binary path" >&2
      exit 1
      ;;
  esac

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT INT TERM
  archive_path="${tmp_dir}/${asset_name}"
  url="https://github.com/servo/servo/releases/download/${SERVO_RELEASE_TAG}/${asset_name}"

  echo "Fetching Servo Linux release ${SERVO_RELEASE_TAG} (${asset_name})..." >&2
  curl -fsSL "${url}" -o "${archive_path}"
  tar -xzf "${archive_path}" -C "${tmp_dir}"

  if [ ! -f "${tmp_dir}/servo/servo" ]; then
    echo "servo release archive missing expected binary at servo/servo" >&2
    exit 1
  fi

  cp "${tmp_dir}/servo/servo" "${OUT_DIR}/servo"
}

build_servo_runtime_bundle() {
  require_tool docker

  case "${QEMU_ARCH}" in
    x86_64)
      docker_platform="linux/amd64"
      loader_path="/lib64/ld-linux-x86-64.so.2"
      ;;
    *)
      echo "no glibc Servo runtime bundling configured for QEMU_ARCH=${QEMU_ARCH}" >&2
      exit 1
      ;;
  esac

  echo "Building packaged Servo runtime bundle for ${QEMU_ARCH}..." >&2
  rm -rf "${SERVO_RUNTIME_DIR}"
  mkdir -p "${SERVO_RUNTIME_DIR}"

  docker run --rm \
    --platform "${docker_platform}" \
    -e QEMU_ARCH="${QEMU_ARCH}" \
    -e SERVO_LOADER_PATH="${loader_path}" \
    -v "${ROOT_DIR}:/work" \
    -w /work \
    ubuntu:24.04 bash -lc '
      set -eu
      export DEBIAN_FRONTEND=noninteractive
      apt-get update >/dev/null
      apt-get install -y --no-install-recommends \
        python3 \
        libudev1 \
        libglib2.0-0 \
        libgstreamer1.0-0 \
        libgstreamer-plugins-base1.0-0 \
        libgstreamer-plugins-bad1.0-0 \
        libfontconfig1 \
        libwayland-client0 \
        libwayland-cursor0 \
        libwayland-egl1 \
        libxkbcommon0 \
        libdrm2 \
        libgbm1 \
        libegl1 \
        zlib1g \
        libstdc++6 >/dev/null
      python3 - <<"PY"
import os
import re
import shutil
import subprocess
from collections import deque

root = "/work"
servo = os.path.join(root, "build/alpine/artifacts/linux-" + os.environ["QEMU_ARCH"], "servo")
bundle = os.path.join(root, "build/alpine/artifacts/linux-" + os.environ["QEMU_ARCH"], "servo-runtime-root")
loader = os.environ["SERVO_LOADER_PATH"]

needed = set([loader])
queue = deque([servo])

for extra in [
    "/lib/x86_64-linux-gnu/libwayland-client.so.0",
    "/lib/x86_64-linux-gnu/libwayland-cursor.so.0",
    "/lib/x86_64-linux-gnu/libwayland-egl.so.1",
    "/lib/x86_64-linux-gnu/libxkbcommon.so.0",
    "/lib/x86_64-linux-gnu/libdrm.so.2",
    "/lib/x86_64-linux-gnu/libgbm.so.1",
    "/lib/x86_64-linux-gnu/libEGL.so.1",
]:
    if os.path.exists(extra):
        needed.add(extra)
        queue.append(extra)

while queue:
    current = queue.popleft()
    proc = subprocess.run(["ldd", current], text=True, capture_output=True, check=True)
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        match = re.search(r"=>\s+(/[^ ]+)", line)
        if match:
            lib = match.group(1)
        elif line.startswith("/"):
            lib = line.split(" ", 1)[0]
        else:
            continue
        if lib not in needed and os.path.exists(lib):
            needed.add(lib)
            queue.append(lib)

for src in sorted(needed):
    dst = os.path.join(bundle, src.lstrip("/"))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.islink(src):
      target = os.readlink(src)
      if os.path.lexists(dst):
          os.remove(dst)
      os.symlink(target, dst)
      target_dst = os.path.normpath(os.path.join(os.path.dirname(dst), target))
      real = os.path.realpath(src)
      if os.path.exists(real):
          real_dst = os.path.join(bundle, real.lstrip("/"))
          os.makedirs(os.path.dirname(real_dst), exist_ok=True)
          shutil.copy2(real, real_dst)
          os.makedirs(os.path.dirname(target_dst), exist_ok=True)
          if not os.path.exists(target_dst):
              shutil.copy2(real, target_dst)
    else:
      shutil.copy2(src, dst)
PY
    ' >&2
}

mkdir -p "${OUT_DIR}"

if [ -f "${OUT_DIR}/sold" ] && file_matches_arch "${OUT_DIR}/sold" && sold_matches_runtime "${OUT_DIR}/sold"; then
  echo "Reusing Linux sold binary: ${OUT_DIR}/sold" >&2
else
  build_sold_linux
fi

if [ -f "${OUT_DIR}/sol-kernelctl" ] && file_matches_arch "${OUT_DIR}/sol-kernelctl" && kernelctl_matches_runtime "${OUT_DIR}/sol-kernelctl"; then
  echo "Reusing Linux sol-kernelctl binary: ${OUT_DIR}/sol-kernelctl" >&2
else
  build_kernelctl_linux
fi

if [ -f "${OUT_DIR}/sol-netd" ] && file_matches_arch "${OUT_DIR}/sol-netd" && netd_matches_runtime "${OUT_DIR}/sol-netd"; then
  echo "Reusing Linux sol-netd binary: ${OUT_DIR}/sol-netd" >&2
else
  build_netd_linux
fi

if [ -n "${SERVO_BIN_LINUX:-}" ]; then
  if [ ! -f "${SERVO_BIN_LINUX}" ]; then
    echo "SERVO_BIN_LINUX does not exist: ${SERVO_BIN_LINUX}" >&2
    exit 1
  fi
  if ! file_matches_arch "${SERVO_BIN_LINUX}"; then
    echo "SERVO_BIN_LINUX is not Linux ELF for ${QEMU_ARCH}: ${SERVO_BIN_LINUX}" >&2
    echo "detected: $(file "${SERVO_BIN_LINUX}")" >&2
    exit 1
  fi
  cp "${SERVO_BIN_LINUX}" "${OUT_DIR}/servo"
  if [ "${SERVO_LINUX_LIBC}" != "gnu" ] && ! servo_native_musl "${OUT_DIR}/servo"; then
    echo "SERVO_BIN_LINUX must be musl-linked when SERVO_LINUX_LIBC=musl (default)." >&2
    echo "detected: $(file "${OUT_DIR}/servo")" >&2
    echo "Use SERVO_LINUX_LIBC=gnu for glibc servoshell + runtime bundle, or omit SERVO_BIN_LINUX." >&2
    exit 1
  fi
elif [ "${SERVO_FORCE_REBUILD}" != "1" ] && [ -f "${OUT_DIR}/servo" ] && file_matches_arch "${OUT_DIR}/servo" && servo_native_musl "${OUT_DIR}/servo" && servo_supports_soliloquy_chrome_mode "${OUT_DIR}/servo"; then
  echo "Reusing Linux musl Servo binary: ${OUT_DIR}/servo" >&2
elif [ -f "${SERVO_SRC_BIN}" ] && file_matches_arch "${SERVO_SRC_BIN}" && servo_native_musl "${SERVO_SRC_BIN}" && servo_supports_soliloquy_chrome_mode "${SERVO_SRC_BIN}"; then
  echo "Using in-tree musl Servo binary: ${SERVO_SRC_BIN}" >&2
  cp "${SERVO_SRC_BIN}" "${OUT_DIR}/servo"
elif [ "${SERVO_SOURCE_BUILD}" = "1" ] && [ -f "${ROOT_DIR}/third_party/servo/ports/servoshell/Cargo.toml" ]; then
  case "${SERVO_LINUX_LIBC}" in
    gnu) build_servo_linux_gnu_from_source ;;
    *) build_servo_linux_musl_from_source ;;
  esac
else
  fetch_servo_release_linux
fi

if ! servo_supports_soliloquy_chrome_mode "${OUT_DIR}/servo"; then
  echo "Servo binary does not support --no-browser-chrome: ${OUT_DIR}/servo" >&2
  echo "Rebuild the local Servo fork so Soliloquy's desktop chrome is the only browser UI." >&2
  exit 1
fi

if servo_needs_glibc_runtime "${OUT_DIR}/servo"; then
  if [ "${SERVO_FORCE_REBUILD}" != "1" ] && servo_runtime_bundle_ready; then
    echo "Reusing packaged Servo runtime bundle: ${SERVO_RUNTIME_DIR}" >&2
  else
    SERVO_LOADER_PATH="${loader_path:-/lib64/ld-linux-x86-64.so.2}" QEMU_ARCH="${QEMU_ARCH}" build_servo_runtime_bundle
  fi
fi

chmod +x "${OUT_DIR}/servo" "${OUT_DIR}/sold" "${OUT_DIR}/sol-kernelctl" "${OUT_DIR}/sol-netd"
echo "${OUT_DIR}"
