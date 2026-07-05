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
mkdir -p "${BUILD_DIR}" "${ROOTFS}/bin" "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/run" "${ROOTFS}/tmp"

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

cp "${ROOT_DIR}/public/root/"* "${ROOTFS}/"
chmod +x "${ROOTFS}/alpenglowed.sh"

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
  /bin/echo "v86-compatible demo image, not the full x86_64/aarch64 system build."
  /bin/echo "Model: immutable RAM root; real builds keep /home and state on bcachefs."
  /bin/echo
  /bin/ls -1 --color=never
  /bin/echo
  /bin/echo "Read: cat README.md"
  /bin/echo "Desktop: ./alpenglowed.sh"
  /bin/echo
} >/dev/console 2>&1
exec /bin/sh </dev/console >/dev/console 2>&1
INIT
chmod +x "${ROOTFS}/init"

(cd "${ROOTFS}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT}")
ls -lh "${KERNEL_OUT}"
ls -lh "${OUT}"
