#!/bin/sh
# Alpenglow native appliance — build-rootfs
# Builds the rootfs image using Oil as the native package manager.
# No distro bootstrap fetcher — Oil fetches everything.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OUT_DIR="${ROOT_DIR}/build/appliance"
ROOTFS_DIR="${OUT_DIR}/rootfs"
GENERATION_DIR="${OUT_DIR}/generations"
ROOT_IMAGE="${OUT_DIR}/alpenglow-root.erofs"

ALPENGLOW_ARCH="${ALPENGLOW_ARCH:-$(uname -m)}"
BUILD_PROFILE="${BUILD_PROFILE:-standard}"
COMPILER="${COMPILER:-llvm}"
OIL_CMD="${OIL_CMD:-wax}"

case "${BUILD_PROFILE}" in
  minimal) PKG_LIST="${BACKEND_DIR}/packages-minimal.txt" ;;
  standard) PKG_LIST="${BACKEND_DIR}/packages-standard.txt" ;;
  desktop) PKG_LIST="${BACKEND_DIR}/packages-runtime.txt" ;;
  *) echo "Unknown profile: ${BUILD_PROFILE}. Use minimal, standard, or desktop." >&2; exit 1 ;;
esac

case "${COMPILER}" in
  llvm|inauguration) ;;
  *) echo "Unknown compiler: ${COMPILER}. Use llvm or inauguration." >&2; exit 1 ;;
esac

mkdir -p "${OUT_DIR}" "${GENERATION_DIR}"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

echo "Alpenglow native appliance build"
echo "  arch:   ${ALPENGLOW_ARCH}"
echo "  oil:    ${OIL_CMD}"
echo "  profile: ${BUILD_PROFILE}"
echo "  compiler: ${COMPILER}"
echo "  pkg:    ${PKG_LIST}"
echo ""

# ── Phase 1: Bootstrap rootfs via Oil ──────────────────────────────
# Oil installs all packages directly from its registries. No distro
# package manager is involved at any point.

if ! command -v "${OIL_CMD}" >/dev/null 2>&1; then
  echo "Oil (${OIL_CMD}) not found." >&2
  echo "Install Oil first: curl -fsSL https://oil.sh/install.sh | sh" >&2
  exit 1
fi

echo "→ Installing base system via Oil..."
# Read package list and install each via Oil system registry
while IFS= read -r pkg || [ -n "${pkg}" ]; do
  # Skip comments and blank lines
  case "${pkg}" in
    ''|'#'*) continue ;;
  esac
  echo "  + ${pkg}"
  "${OIL_CMD}" system add "${pkg}" --prefix "${ROOTFS_DIR}"
done < "${PKG_LIST}"

# ── Phase 1.5: Install Oil/Wax (standard/desktop only) ──────────────
if [ "${BUILD_PROFILE}" != "minimal" ]; then
  echo "→ Installing Oil (wax) package manager..."
  OIL_BIN="${ALPENGLOW_OIL_BIN:-}"
  if [ -z "${OIL_BIN}" ]; then
    OIL_BIN="${OUT_DIR}/oil"
    if [ ! -x "${OIL_BIN}" ]; then
      cargo build --release \
        --manifest-path "${ROOT_DIR}/system/oil/Cargo.toml" \
        --no-default-features --features system-apk,wax >/dev/null 2>&1
      cp "${ROOT_DIR}/system/oil/target/release/oil" "${OIL_BIN}"
    fi
  fi
  mkdir -p "${ROOTFS_DIR}/usr/local/bin"
  cp "${OIL_BIN}" "${ROOTFS_DIR}/usr/local/bin/oil"
  chmod 755 "${ROOTFS_DIR}/usr/local/bin/oil"
  ln -sf oil "${ROOTFS_DIR}/usr/local/bin/wax"
  echo "  + oil (wax) from ${OIL_BIN}"
fi

# ── Phase 2: Configure rootfs ───────────────────────────────────────
BUILD_PROFILE="${BUILD_PROFILE}" COMPILER="${COMPILER}" "${BACKEND_DIR}/scripts/configure-rootfs.sh" "${ROOTFS_DIR}"

# ── Phase 3: Compose immutable root image ──────────────────────────
echo "→ Composing immutable root image..."
if command -v mkfs.erofs >/dev/null 2>&1; then
  mkfs.erofs -zlz4hc "${ROOT_IMAGE}" "${ROOTFS_DIR}" >/dev/null
elif command -v mksquashfs >/dev/null 2>&1; then
  ROOT_IMAGE="${OUT_DIR}/alpenglow-root.squashfs"
  mksquashfs "${ROOTFS_DIR}" "${ROOT_IMAGE}" -noappend -comp zstd >/dev/null
else
  echo "missing mkfs.erofs or mksquashfs" >&2
  exit 1
fi
echo "  image: ${ROOT_IMAGE}"

# ── Phase 4: Register generation ────────────────────────────────────
GEN_ID="alpenglow-$(date +%Y%m%d-%H%M%S)"
GENERATION_FILE="${GENERATION_DIR}/${GEN_ID}.json"
cat > "${GENERATION_FILE}" <<EOF
{
  "id": "${GEN_ID}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "arch": "${ALPENGLOW_ARCH}",
  "backend": "alpenglow-native",
  "compiler": "${COMPILER}",
  "image": "${ROOT_IMAGE}",
  "packages": $(wc -l < "${PKG_LIST}")
}
EOF
ln -sf "${ROOT_IMAGE}" "${OUT_DIR}/current.${ROOT_IMAGE##*.}"
ln -sf "${GENERATION_FILE}" "${OUT_DIR}/current.json"

echo "✓ Alpenglow native appliance built:"
echo "  rootfs:  ${ROOTFS_DIR}"
echo "  image:   ${ROOT_IMAGE}"
echo "  gen:     ${GEN_ID}"
echo ""
echo "To boot:"
echo "  qemu-system-x86_64 -kernel /boot/vmlinuz -initrd initramfs -append \"alpenglow.ram_root alpenglow.image=${ROOT_IMAGE}\""
