#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/cross/aarch64"
EDITION="${1:-${ALPENGLOW_EDITION:-desktop}}"
ROOTFS="${OUT_DIR}/rootfs-${EDITION}"
INITRAMFS="${OUT_DIR}/initramfs-${EDITION}.cpio.gz"
KERNEL="${OUT_DIR}/vmlinuz-${EDITION}"
CID=""

case "${EDITION}" in
  desktop) PACKAGES="dinit cage seatd foot font-dejavu mesa-dri-gallium mesa-vulkan-swrast libxkbcommon libxkbcommon-x11 wayland" ;;
  desktop-full) PACKAGES="dinit cage seatd foot font-dejavu mesa-dri-gallium mesa-vulkan-swrast libxkbcommon libxkbcommon-x11 wayland pipewire wireplumber alsa-lib alsa-utils iwd dropbear chrony dnsmasq curl ca-certificates" ;;
  *) echo "usage: $0 [desktop|desktop-full]" >&2; exit 1 ;;
esac

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }
}

cleanup() {
  [ -z "${CID}" ] || docker rm -f "${CID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_cmd cpio
require_cmd curl
require_cmd docker
require_cmd file
require_cmd gzip
require_cmd lz4
require_cmd tar

mkdir -p "${OUT_DIR}"
if [ ! -x "${OUT_DIR}/toybox-aarch64" ]; then
  curl -fsSL -o "${OUT_DIR}/toybox-aarch64" "https://landley.net/bin/toybox/latest/toybox-aarch64"
  chmod 755 "${OUT_DIR}/toybox-aarch64"
fi
file "${OUT_DIR}/toybox-aarch64" | grep -q 'aarch64' || { echo "not aarch64: ${OUT_DIR}/toybox-aarch64" >&2; exit 1; }
rm -rf "${ROOTFS}"
mkdir -p "${ROOTFS}"

CID="$(docker create --platform linux/arm64 alpine:3.21 sleep 600)"
docker start "${CID}" >/dev/null
docker exec "${CID}" sh -lc "apk add --no-cache ${PACKAGES} >/dev/null"
docker export "${CID}" | tar -C "${ROOTFS}" -xf -
cp "${OUT_DIR}/toybox-aarch64" "${ROOTFS}/usr/bin/toybox"

mkdir -p "${ROOTFS}/dev/pts" "${ROOTFS}/etc/dinit.d/boot.d" "${ROOTFS}/run/user/0" "${ROOTFS}/usr/local/bin"
cat > "${ROOTFS}/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /run
mkdir -p /run/user/0
chmod 700 /run/user/0
exec /sbin/dinit -d /etc/dinit.d -s -t boot
EOF
cat > "${ROOTFS}/etc/dinit.d/boot" <<'EOF'
type = internal
waits-for.d = boot.d
EOF
cat > "${ROOTFS}/etc/dinit.d/seatd" <<'EOF'
type = process
command = /usr/bin/seatd -g root -n 1
restart = yes
EOF
cat > "${ROOTFS}/etc/dinit.d/desktop" <<'EOF'
type = process
command = /usr/local/bin/start-desktop
depends-on = seatd
restart = no
EOF
if [ -n "${ALPENGLOWED_BIN:-}" ]; then
  require_cmd file
  test -x "${ALPENGLOWED_BIN}" || { echo "missing executable: ${ALPENGLOWED_BIN}" >&2; exit 1; }
  file "${ALPENGLOWED_BIN}" | grep -q 'aarch64' || { echo "not aarch64: ${ALPENGLOWED_BIN}" >&2; exit 1; }
  cp "${ALPENGLOWED_BIN}" "${ROOTFS}/usr/bin/alpenglowed"
  cat > "${ROOTFS}/usr/local/bin/start-desktop" <<'EOF'
#!/bin/sh
export XDG_RUNTIME_DIR=/run/user/0
export LIBSEAT_BACKEND=seatd
export WLR_RENDERER=pixman
export WLR_NO_HARDWARE_CURSORS=1
exec /usr/bin/alpenglowed --compositor
EOF
else
  cat > "${ROOTFS}/usr/local/bin/start-desktop" <<'EOF'
#!/bin/sh
export XDG_RUNTIME_DIR=/run/user/0
export LIBSEAT_BACKEND=seatd
export WLR_RENDERER=pixman
export WLR_NO_HARDWARE_CURSORS=1
exec /usr/bin/cage -d -- /usr/bin/foot
EOF
fi
ln -sf /etc/dinit.d/seatd "${ROOTFS}/etc/dinit.d/boot.d/seatd"
ln -sf /etc/dinit.d/desktop "${ROOTFS}/etc/dinit.d/boot.d/desktop"
cat > "${ROOTFS}/etc/os-release" <<EOF
NAME="Alpenglow"
ID=alpenglow
VERSION_ID="${EDITION}"
PRETTY_NAME="Alpenglow ${EDITION} aarch64"
EOF
chmod 755 "${ROOTFS}/init" "${ROOTFS}/usr/local/bin/start-desktop"

(cd "${ROOTFS}" && find . -print | cpio -o -H newc 2>/dev/null | gzip -1 > "${INITRAMFS}")
(cd "${ROOTFS}" && find . -print | cpio -o -H newc 2>/dev/null | lz4 -l -9 -c > "${OUT_DIR}/initramfs-proper.cpio.lz4")
rm -f "${OUT_DIR}/vmlinuz" "${OUT_DIR}/.kernel-aarch64-desktop.ok"
KERNEL_PROFILE=desktop sh "${ROOT_DIR}/system/backends/appliance/scripts/build-kernel-aarch64.sh" "${OUT_DIR}" "${ROOT_DIR}"
cp "${OUT_DIR}/vmlinuz" "${KERNEL}"

test -s "${INITRAMFS}"
test -s "${KERNEL}"
printf '%s\n%s\n' "${KERNEL}" "${INITRAMFS}"
