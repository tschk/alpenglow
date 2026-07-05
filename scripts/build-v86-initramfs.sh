#!/bin/sh
# Alpenglow v86 browser initramfs (i686): busybox + oil + docs at / for cat *.md
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/v86"
ROOTFS="${BUILD_DIR}/rootfs"
OUT="${ROOT_DIR}/public/v86/alpenglow-v86-initrd.cpio.gz"
KERNEL_OUT="${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz"
BUSYBOX="${BUILD_DIR}/busybox-i386"
OIL="${ROOT_DIR}/target/i686-unknown-linux-musl/release/oil"
ISO="${BUILD_DIR}/alpine-virt-x86.iso"
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86/alpine-virt-3.20.10-x86.iso"

need_docker() {
  command -v docker >/dev/null 2>&1 || {
    echo "docker required to build i686 busybox/oil/fastfetch (or run on ultramarine)" >&2
    exit 1
  }
}

if [ -d "${ROOTFS}" ] && [ ! -w "${ROOTFS}" ]; then
  sudo rm -rf "${ROOTFS}" 2>/dev/null || rm -rf "${ROOTFS}" 2>/dev/null || true
else
  rm -rf "${ROOTFS}"
fi
mkdir -p "${BUILD_DIR}" "${ROOTFS}/bin" "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" \
  "${ROOTFS}/run" "${ROOTFS}/tmp" "${ROOTFS}/usr/share/alpenglow/browser"

if [ ! -x "${BUSYBOX}" ]; then
  need_docker
  docker run --rm --platform linux/386 -v "${BUILD_DIR}:/out" alpine:3.20 sh -lc \
    'apk add --no-cache busybox-static >/dev/null && cp /bin/busybox.static /out/busybox-i386 && chmod +x /out/busybox-i386'
fi

if [ ! -f "${KERNEL_OUT}" ]; then
  [ -f "${ISO}" ] || curl -L --fail -o "${ISO}" "${ISO_URL}"
  rm -rf "${BUILD_DIR}/iso"
  mkdir -p "${BUILD_DIR}/iso"
  bsdtar -xf "${ISO}" -C "${BUILD_DIR}/iso" boot/vmlinuz-virt
  cp "${BUILD_DIR}/iso/boot/vmlinuz-virt" "${KERNEL_OUT}"
fi

if [ ! -x "${OIL}" ] || find "${ROOT_DIR}/system/oil/src" "${ROOT_DIR}/system/oil/Cargo.toml" "${ROOT_DIR}/Cargo.lock" -newer "${OIL}" 2>/dev/null | grep -q .; then
  need_docker
  docker run --rm -v "${ROOT_DIR}:/home/rust/src" -w /home/rust/src/system/oil messense/rust-musl-cross:i686-musl sh -lc \
    'cargo build --release --target i686-unknown-linux-musl'
fi

cp "${BUSYBOX}" "${ROOTFS}/bin/busybox"
chmod 755 "${ROOTFS}/bin/busybox"
for applet in sh mount mkdir mknod chmod cat ls pwd echo uname free dmesg clear hostname sleep; do
  ln -sf busybox "${ROOTFS}/bin/${applet}"
done
cp "${OIL}" "${ROOTFS}/bin/oil"
chmod 755 "${ROOTFS}/bin/oil"

need_docker
FASTFETCH_VERSION="$(docker run --rm --platform linux/386 -v "${ROOTFS}:/rootfs" alpine:3.20 sh -lc '
  mkdir -p /rootfs/etc/apk/keys /rootfs/lib/apk/db /rootfs/var/cache/apk /rootfs/usr/lib
  cp -a /etc/apk/keys/* /rootfs/etc/apk/keys/
  cat > /rootfs/etc/apk/repositories <<REPOS
https://dl-cdn.alpinelinux.org/alpine/v3.20/main
https://dl-cdn.alpinelinux.org/alpine/v3.20/community
REPOS
  apk add --root /rootfs --initdb --no-cache fastfetch >/dev/null
  apk --root /rootfs info -e -v fastfetch 2>/dev/null | sed "s/^fastfetch-//"
')"
if [ -d "${ROOTFS}/etc" ] && [ ! -w "${ROOTFS}/etc" ]; then
  if command -v sudo >/dev/null 2>&1; then
    sudo chown -R "$(id -u):$(id -g)" "${ROOTFS}"
  else
    chown -R "$(id -u):$(id -g)" "${ROOTFS}" 2>/dev/null || true
  fi
fi
mkdir -p "${ROOTFS}/.oil/cache/system" "${ROOTFS}/etc"
cat > "${ROOTFS}/.oil/installed.json" <<EOF
{
  "fastfetch": {
    "name": "fastfetch",
    "version": "${FASTFETCH_VERSION}",
    "install_date": 0,
    "pinned": false
  }
}
EOF
docker run --rm --platform linux/386 -v "${ROOTFS}/.oil/cache/system:/cache" alpine:3.20 sh -lc \
  'apk update >/dev/null && version="$(apk search -x fastfetch | sed "s/^fastfetch-//")" && cat > /cache/apk-https---dl-cdn-alpinelinux-org-alpine-v3-20-x86.json <<EOF
[{
  "name": "fastfetch",
  "version": "${version}",
  "description": "System information tool",
  "download_url": "https://dl-cdn.alpinelinux.org/alpine/v3.20/community/x86/fastfetch-${version}.apk",
  "installed_size": 3452928,
  "depends": ["hwdata-pci", "so:libc.musl-x86.so.1"],
  "provides": ["cmd:fastfetch=${version}", "cmd:flashfetch=${version}"]
}]
EOF'

cat > "${ROOTFS}/etc/os-release" <<'EOF'
NAME="Alpenglow"
ID=alpenglow
VERSION_ID="3.20"
PRETTY_NAME="Alpenglow"
EOF

cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/"
cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/usr/share/alpenglow/browser/"

cat > "${ROOTFS}/init" <<'INIT'
#!/bin/sh
export PATH=/bin:/usr/bin:/usr/local/bin
export HOME=/
export PS1='# '
export TERM=xterm-256color
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
/bin/hostname alpenglow 2>/dev/null
cd /
{
  /bin/echo "Alpenglow"
  /bin/echo
  /bin/echo "Immutable RAM-root Linux appliance (browser demo, i686)."
  /bin/echo "Docs: cat README.md  cat root-model.md  cat packages.md  cat desktop.md"
  /bin/echo "Try: fastfetch   oil search firefox   oil info alpenglowed   ls *.md"
  /bin/echo
  /usr/bin/fastfetch 2>/dev/null || /bin/fastfetch 2>/dev/null || true
  /bin/echo
  /bin/ls -1 --color=never *.md 2>/dev/null || /bin/ls -1 --color=never
  /bin/echo
} >/dev/console 2>&1
exec /bin/sh </dev/console >/dev/console 2>&1
INIT
chmod 755 "${ROOTFS}/init"
# Kernel must execute /init; script shebang needs /bin/sh -> busybox present.
ln -sf busybox "${ROOTFS}/bin/sh"
chmod 755 "${ROOTFS}/bin/sh" 2>/dev/null || true

BUILD_ID="$(date +%Y%m%d%H%M%S)"
echo "${BUILD_ID}" > "${ROOT_DIR}/public/v86/initrd-build-id.txt"

(cd "${ROOTFS}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT}")
echo "init in archive:"
gzip -dc "${OUT}" | cpio -t 2>/dev/null | grep -E '^(\./)?init$' || true
ls -lh "${KERNEL_OUT}"
ls -lh "${OUT}"