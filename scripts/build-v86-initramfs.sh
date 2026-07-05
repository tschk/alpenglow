#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/v86"
ROOTFS="${BUILD_DIR}/rootfs"
OUT="${ROOT_DIR}/public/v86/alpenglow-v86-initrd.cpio.gz"
KERNEL_OUT="${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz"
BUSYBOX="${BUILD_DIR}/busybox-i386"
ISO="${BUILD_DIR}/alpine-virt-x86.iso"
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86/alpine-virt-3.20.10-x86.iso"

rm -rf "${ROOTFS}"
mkdir -p "${BUILD_DIR}" "${ROOTFS}/bin" "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/run" "${ROOTFS}/tmp" "${ROOTFS}/usr/share/alpenglow/browser"

if [ ! -x "${BUSYBOX}" ]; then
  docker run --rm --platform linux/386 -v "${BUILD_DIR}:/out" alpine:3.20 sh -lc 'apk add --no-cache busybox-static >/dev/null && cp /bin/busybox.static /out/busybox-i386 && chmod +x /out/busybox-i386'
fi

if [ ! -f "${KERNEL_OUT}" ]; then
  [ -f "${ISO}" ] || curl -L --fail -o "${ISO}" "${ISO_URL}"
  rm -rf "${BUILD_DIR}/iso"
  mkdir -p "${BUILD_DIR}/iso"
  bsdtar -xf "${ISO}" -C "${BUILD_DIR}/iso" boot/vmlinuz-virt
  cp "${BUILD_DIR}/iso/boot/vmlinuz-virt" "${KERNEL_OUT}"
fi

cp "${BUSYBOX}" "${ROOTFS}/bin/busybox"
for applet in sh mount mkdir mknod chmod cat ls pwd echo uname free dmesg clear hostname sleep; do
  ln -sf busybox "${ROOTFS}/bin/${applet}"
done

cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/"
cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/usr/share/alpenglow/browser/"
cat > "${ROOTFS}/alpenglowed.sh" <<'ALPENGLOWED'
#!/bin/sh
cat <<'EOF'
Alpenglowed

Alpenglowed is the desktop environment for Alpenglow. It layers the Wayland
and Smithay desktop path onto the same immutable RAM-root system model.

Source:
https://github.com/tschk/alpenglowed

Build target:
  BUILD_PROFILE=desktop KERNEL_PROFILE=desktop
EOF
ALPENGLOWED
chmod +x "${ROOTFS}/alpenglowed.sh"

cat > "${ROOTFS}/bin/fastfetch" <<'FASTFETCH'
#!/bin/sh
cat <<'EOF'
       /\        Alpenglow
      /  \       immutable RAM-root Linux
     /____\      root: in memory
    /      \     state: bcachefs-backed /state
   /        \    init: dinit in full images

profile: browser shell
package manager: Oil
desktop: Alpenglowed
targets: x86_64, aarch64
hardware tested: Orange Pi 3B, Mac mini 2012
EOF
FASTFETCH
chmod +x "${ROOTFS}/bin/fastfetch"

cat > "${ROOTFS}/bin/oil" <<'OIL'
#!/bin/sh
set -eu

cmd="${1:-help}"
pkg="${2:-}"

case "${cmd}" in
  help|--help|-h)
    cat <<'EOF'
Oil - Alpenglow package manager

Commands:
  oil search <query>
  oil info <package>
  oil install <package>
  oil list

Browser catalog:
  fastfetch
  alpenglow-docs
EOF
    ;;
  search)
    case "${pkg}" in
      ""|fast*|*fetch*) echo "fastfetch  installed  system information";;
      *doc*|alpenglow*) echo "alpenglow-docs  installed  browser shell documentation";;
    esac
    ;;
  info)
    case "${pkg}" in
      fastfetch)
        echo "Name: fastfetch"
        echo "Status: installed"
        echo "Description: Alpenglow system summary"
        ;;
      alpenglow-docs)
        echo "Name: alpenglow-docs"
        echo "Status: installed"
        echo "Files: README.md root-model.md profiles.md packages.md desktop.md"
        ;;
      *) echo "oil: package not found: ${pkg}" >&2; exit 1;;
    esac
    ;;
  install)
    case "${pkg}" in
      fastfetch|alpenglow-docs) echo "${pkg} is already installed";;
      "") echo "oil: install needs a package name" >&2; exit 1;;
      *) echo "oil: ${pkg} is not in the browser catalog" >&2; exit 1;;
    esac
    ;;
  list)
    echo "fastfetch"
    echo "alpenglow-docs"
    ;;
  *) echo "oil: unknown command: ${cmd}" >&2; exit 1;;
esac
OIL
chmod +x "${ROOTFS}/bin/oil"

cat > "${ROOTFS}/init" <<'INIT'
#!/bin/busybox sh
export PATH=/bin
export HOME=/
export PS1='# '
export TERM=dumb
export NO_COLOR=1
export LS_COLORS=
/bin/mount -t proc proc /proc 2>/dev/null
/bin/mount -t sysfs sysfs /sys 2>/dev/null
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || {
  /bin/mknod /dev/console c 5 1 2>/dev/null
  /bin/mknod /dev/ttyS0 c 4 64 2>/dev/null
  /bin/mknod /dev/null c 1 3 2>/dev/null
}
/bin/mount -t tmpfs tmpfs /run 2>/dev/null
/bin/hostname alpenglow-v86 2>/dev/null
cd /
{
  /bin/echo "Alpenglow browser shell"
  /bin/echo
  /bin/echo "Immutable RAM-root Linux with persistent bcachefs-backed state."
  /bin/echo "Explore the docs, run fastfetch, or try oil list."
  /bin/echo
  /bin/ls -1 --color=never
  /bin/echo
  /bin/echo "Read: cat README.md"
  /bin/echo "Desktop: ./alpenglowed.sh"
  /bin/echo "Packages: oil list"
  /bin/echo
} >/dev/console 2>&1
exec /bin/sh </dev/console >/dev/console 2>&1
INIT
chmod +x "${ROOTFS}/init"

(cd "${ROOTFS}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT}")
ls -lh "${KERNEL_OUT}"
ls -lh "${OUT}"
