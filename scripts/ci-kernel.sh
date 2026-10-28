#!/bin/sh
# CI: Alpenglow kernel configs against the real Linux tree.
#   ci-kernel.sh config  — graft patches/series, check per-profile options survive
#                          olddefconfig, compile fs/bcachefs only (every push)
#   ci-kernel.sh build   — full potato (minimal profile) bzImage, no initramfs, no boot
# Env: KERNEL_SRC_DIR (default /tmp/linux-ci), JOBS (default nproc), CC (e.g. "ccache gcc").
set -eu

MODE="${1:?config|build}"
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
KCFG="${REPO_ROOT}/system/backends/appliance/kernel"
KERNEL_VER="$(grep -E '^KERNEL_VERSION="\$\{KERNEL_VERSION:-' "${REPO_ROOT}/scripts/boot-native.sh" | sed -n 's/.*KERNEL_VERSION:-\([0-9.]*\).*/\1/p')"
WORK="${KERNEL_SRC_DIR:-/tmp/linux-ci}"
JOBS="${JOBS:-$(nproc)}"
CC="${CC:-${CROSS_COMPILE:-}gcc}"

fail() { printf 'ci-kernel: %s\n' "$1" >&2; exit 1; }

mkdir -p "${WORK}"
cd "${WORK}"
if [ ! -d "linux-${KERNEL_VER}" ]; then
  tarball="linux-${KERNEL_VER}.tar.xz"
  fetched=0
  for url in \
    "https://cdn.kernel.org/pub/linux/kernel/v7.x/${tarball}" \
    "https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/${tarball}"
  do
    if curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "${url}" -o linux.tar.xz; then
      fetched=1
      break
    fi
  done
  [ "${fetched}" = "1" ] || fail "failed to download ${tarball}"
  tar -xf linux.tar.xz
  rm -f linux.tar.xz
fi
cd "linux-${KERNEL_VER}"
sh "${KCFG}/patches/apply.sh" .

# Same fragment order as build-kernel-fast.sh, without its scripts/config
# re-enables, so a fragment that olddefconfig drops shows up here.
configure() {
  cat "${KCFG}/alpenglow-qemu-minimal.config" "${KCFG}/lz4.config" "${KCFG}/virt.config" \
    "${KCFG}/$1.config" > .config
  make ARCH=x86_64 CC="${CC}" olddefconfig >/dev/null
}
want_y() {
  profile="$1"; shift
  for opt in "$@"; do
    grep -q "^CONFIG_${opt}=y$" .config || fail "${profile}: CONFIG_${opt} not =y after olddefconfig"
  done
}

case "${MODE}" in
  config)
    for profile in minimal desktop; do
      configure "${profile}"
      want_y "${profile}" SWAP BLK_DEV ZRAM BCACHEFS_FS
    done
    configure fast
    for opt in SWAP ZRAM BCACHEFS_FS; do
      ! grep -q "^CONFIG_${opt}=y$" .config || fail "fast: CONFIG_${opt} must stay off"
    done
    configure minimal
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC
    make ARCH=x86_64 CC="${CC}" olddefconfig >/dev/null
    make -j"${JOBS}" ARCH=x86_64 CC="${CC}" fs/bcachefs/ >/dev/null
    printf 'ci-kernel: config ok (bcachefs compiled for minimal)\n'
    ;;
  build)
    configure minimal
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC \
      --set-str INITRAMFS_SOURCE ""
    make ARCH=x86_64 CC="${CC}" olddefconfig >/dev/null
    want_y potato SWAP BLK_DEV ZRAM BCACHEFS_FS
    KBUILD_BUILD_TIMESTAMP=0 KBUILD_BUILD_USER=ci KBUILD_BUILD_HOST=ci \
      make -j"${JOBS}" ARCH=x86_64 CC="${CC}" bzImage >/dev/null
    printf 'ci-kernel: potato bzImage %s bytes\n' "$(stat -c%s arch/x86/boot/bzImage)"
    ;;
  *) fail "unknown mode: ${MODE}" ;;
esac
