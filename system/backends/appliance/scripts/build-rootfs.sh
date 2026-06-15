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
GLOWFS_IMAGE="${OUT_DIR}/alpenglow-root.glowfs"

ALPENGLOW_ARCH="${ALPENGLOW_ARCH:-$(uname -m)}"
ALPENGLOW_PROFILE="${ALPENGLOW_PROFILE:-standard}"
OIL_CMD="${OIL_CMD:-wax}"

case "${ALPENGLOW_PROFILE}" in
  minimal) PKG_LIST="${BACKEND_DIR}/packages-minimal.txt" ;;
  standard) PKG_LIST="${BACKEND_DIR}/packages-runtime.txt" ;;
  *) echo "Unknown profile: ${ALPENGLOW_PROFILE}. Use minimal or standard." >&2; exit 1 ;;
esac

mkdir -p "${OUT_DIR}" "${GENERATION_DIR}"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

echo "Alpenglow native appliance build"
echo "  arch:   ${ALPENGLOW_ARCH}"
echo "  oil:    ${OIL_CMD}"
echo "  profile: ${ALPENGLOW_PROFILE}"
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

# ── Phase 2: Configure rootfs ───────────────────────────────────────
"${BACKEND_DIR}/scripts/configure-rootfs.sh" "${ROOTFS_DIR}"

# ── Phase 3: Compose GlowFS image ───────────────────────────────────
echo "→ Composing GlowFS image..."
GLOWFSCTL="${ROOT_DIR}/target/release/glowfsctl"
if [ -f "${GLOWFSCTL}" ]; then
  "${GLOWFSCTL}" create \
    --input "${ROOTFS_DIR}" \
    --output "${GLOWFS_IMAGE}" \
    --label "alpenglow-$(date +%Y%m%d-%H%M%S)" \
    --compression zstd
  echo "  GlowFS image: ${GLOWFS_IMAGE}"
fi

# ── Phase 4: Register generation ────────────────────────────────────
GEN_ID="alpenglow-$(date +%Y%m%d-%H%M%S)"
GENERATION_FILE="${GENERATION_DIR}/${GEN_ID}.json"
cat > "${GENERATION_FILE}" <<EOF
{
  "id": "${GEN_ID}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "arch": "${ALPENGLOW_ARCH}",
  "backend": "alpenglow-native",
  "image": "${GLOWFS_IMAGE}",
  "packages": $(wc -l < "${PKG_LIST}")
}
EOF
ln -sf "${GLOWFS_IMAGE}" "${OUT_DIR}/current.glowfs"
ln -sf "${GENERATION_FILE}" "${OUT_DIR}/current.json"

echo "✓ Alpenglow native appliance built:"
echo "  rootfs:  ${ROOTFS_DIR}"
echo "  image:   ${GLOWFS_IMAGE}"
echo "  gen:     ${GEN_ID}"
echo ""
echo "To boot:"
echo "  qemu-system-x86_64 -kernel /boot/vmlinuz -initrd initramfs -append \"alpenglow.ram_root alpine.image=${GLOWFS_IMAGE}\""
