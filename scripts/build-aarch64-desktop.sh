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
  desktop|desktop-full) PACKAGES="dinit cage seatd foot xwayland font-dejavu mesa-dri-gallium mesa-vulkan-swrast libxkbcommon libxkbcommon-x11 wayland pipewire wireplumber alsa-lib alsa-utils iwd dropbear chrony dnsmasq curl ca-certificates zstd" ;;
  *) echo "usage: $0 [desktop]" >&2; exit 1 ;;
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

EXPECTED_SHA256="223b5ff5929371225d0bc62fb3b99a148692295fb6f85ad86bb924f689a55ea4"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "missing sha256sum or shasum" >&2
    exit 1
  fi
}

mkdir -p "${OUT_DIR}"
if [ ! -s "${KERNEL}" ]; then
  KERNEL_PROFILE=desktop sh "${ROOT_DIR}/system/backends/appliance/scripts/build-kernel-aarch64.sh" "${OUT_DIR}" "${ROOT_DIR}"
  cp "${OUT_DIR}/vmlinuz" "${KERNEL}"
fi

TOYBOX_BIN="${OUT_DIR}/toybox-aarch64"

if [ ! -x "${TOYBOX_BIN}" ]; then
  curl -fsSL -o "${TOYBOX_BIN}" "https://landley.net/bin/toybox/0.8.14/toybox-aarch64"
  chmod 755 "${TOYBOX_BIN}"
fi

if [ "$(sha256_of "${TOYBOX_BIN}")" != "${EXPECTED_SHA256}" ]; then
  echo "Checksum mismatch for toybox-aarch64; re-downloading..." >&2
  rm -f "${TOYBOX_BIN}"
  curl -fsSL -o "${TOYBOX_BIN}" "https://landley.net/bin/toybox/0.8.14/toybox-aarch64"
  chmod 755 "${TOYBOX_BIN}"
  if [ "$(sha256_of "${TOYBOX_BIN}")" != "${EXPECTED_SHA256}" ]; then
    echo "ERROR: Checksum validation failed for toybox-aarch64" >&2
    rm -f "${TOYBOX_BIN}"
    exit 1
  fi
fi
file "${OUT_DIR}/toybox-aarch64" | grep -q 'aarch64' || { echo "not aarch64: ${OUT_DIR}/toybox-aarch64" >&2; exit 1; }
rm -rf "${ROOTFS}"
mkdir -p "${ROOTFS}"

CID="$(docker create --platform linux/arm64 alpine:3.21 sleep 600)"
docker start "${CID}" >/dev/null
docker exec "${CID}" sh -lc 'apk add --no-cache "$@" >/dev/null' -- ${PACKAGES}
docker export "${CID}" | tar -C "${ROOTFS}" -xf -
cp "${OUT_DIR}/toybox-aarch64" "${ROOTFS}/usr/bin/toybox"

mkdir -p "${ROOTFS}/dev/pts" "${ROOTFS}/etc/dinit.d/boot.d" "${ROOTFS}/run/user/0" "${ROOTFS}/usr/local/bin"
cat > "${ROOTFS}/init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t devpts devpts /dev/pts
[ -e /dev/ptmx ] || ln -s pts/ptmx /dev/ptmx
mount -t tmpfs -o nosuid,nodev,mode=0755 tmpfs /run
printf 'Alpenglow aarch64 root ready\n' > /dev/console
mkdir -p /state /home
mount -L alpenglow-state /state 2>/dev/null || true
[ -d /state/home ] && mount --bind /state/home /home 2>/dev/null || true
mkdir -p /run/user/0
chmod 700 /run/user/0
exec /usr/sbin/dinit -d /etc/dinit.d -s -t boot
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
exec /usr/bin/cage -- /usr/bin/alpenglowed --role=desktop
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
rm -rf "${ROOTFS}"

test -s "${INITRAMFS}"
test -s "${KERNEL}"
printf '%s\n%s\n' "${KERNEL}" "${INITRAMFS}"
