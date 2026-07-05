#!/bin/sh
# Alpenglow v86 demo initramfs — toybox + dinit + oil (not an Alpine rootfs).
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
BUILD_DIR="${ROOT_DIR}/build/v86"
OUT_DIR="${BUILD_DIR}/native"
ROOTFS="${BUILD_DIR}/rootfs"
OUT="${ROOT_DIR}/public/v86/alpenglow-v86-initrd.cpio.gz"
KERNEL_OUT="${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz"
ISO="${BUILD_DIR}/alpine-virt-x86.iso"
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86/alpine-virt-3.20.10-x86.iso"

TOYBOX_VERSION="0.8.11"
DINIT_VERSION="0.19.2"

export BUILD_PROFILE=minimal
export GRAPHICAL=1
export FAST=1
export EFI=0
export BOOT_MODE=diskless
export KERNEL_BUILD=0
export BUILD_SERVICES=0
export ZIG_INIT=0

rm -rf "${ROOTFS}" "${OUT_DIR}"
mkdir -p "${BUILD_DIR}" "${OUT_DIR}" "${ROOTFS}"

compose_v86_rootfs() {
  require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

  [ -f "${OUT_DIR}/toybox" ] || {
    require_cmd docker
    echo "→ Building toybox ${TOYBOX_VERSION}..."
    docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
      apk add --no-cache make gcc musl-dev curl tar xz bash linux-headers >/dev/null
      curl -fsSL https://github.com/landley/toybox/archive/refs/tags/'"${TOYBOX_VERSION}"'.tar.gz -o /tmp/toybox.tar.gz
      tar -xzf /tmp/toybox.tar.gz -C /tmp
      cd /tmp/toybox-'"${TOYBOX_VERSION}"'
      make defconfig >/dev/null 2>&1
      sed -i "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/" .config
      sed -i "s/# CONFIG_SH is not set/CONFIG_SH=y/" .config
      make -j$(nproc) LDFLAGS="-static" >/dev/null 2>&1
      cp toybox /out/toybox
    '
  }

  [ -f "${OUT_DIR}/dinit" ] || {
    echo "→ Building dinit ${DINIT_VERSION}..."
    docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
      apk add --no-cache g++ make curl tar xz musl-dev bash >/dev/null
      curl -fsSL https://github.com/davmac314/dinit/releases/download/v'"${DINIT_VERSION}"'/dinit-'"${DINIT_VERSION}"'.tar.xz -o /tmp/dinit.tar.xz
      tar -xf /tmp/dinit.tar.xz -C /tmp
      cd /tmp/dinit-'"${DINIT_VERSION}"'
      ./configure --static >/dev/null 2>&1
      make -j$(nproc) CXXFLAGS="-static" LDFLAGS="-static" >/dev/null 2>&1
      make install DESTDIR=/out/dinit-install >/dev/null 2>&1
      cp /out/dinit-install/sbin/dinit /out/dinit
    '
  }

  OIL_BIN="${OUT_DIR}/oil"
  if [ ! -x "${OIL_BIN}" ]; then
    echo "→ Building oil (i686 musl)..."
    docker run --rm -v "${ROOT_DIR}:/home/rust/src" -w /home/rust/src/system/oil messense/rust-musl-cross:i686-musl sh -lc \
      'cargo build --release --target i686-unknown-linux-musl'
    cp "${ROOT_DIR}/target/i686-unknown-linux-musl/release/oil" "${OIL_BIN}"
  fi

  if [ "${GRAPHICAL}" = "1" ] && [ ! -x "${OUT_DIR}/cage/usr/bin/cage" ]; then
    echo "→ Fetching cage stack (i686, demo compositor only)..."
    docker run --rm --platform linux/386 -v "${OUT_DIR}/cage:/out" alpine:3.20 sh -c '
      set -e
      apk add --no-cache cage seatd foot mesa-dri-gallium fastfetch >/dev/null
      mkdir -p /out/usr/bin /out/usr/local/bin /out/usr/lib /out/lib /out/usr/lib/dri /out/usr/lib/gbm
      cp /usr/bin/cage /usr/bin/seatd /usr/bin/foot /out/usr/bin/ 2>/dev/null || true
      cp /usr/bin/fastfetch /out/usr/local/bin/ 2>/dev/null || true
      copy_deps() {
        for bin in "$@"; do
          [ -e "$bin" ] || continue
          ldd "$bin" 2>/dev/null | awk "{print \$3}" | grep "^/" | while read -r dep; do
            cp -a "$dep" /out/usr/lib/ 2>/dev/null || true
          done
        done
      }
      copy_deps /usr/bin/cage /usr/bin/seatd /usr/bin/foot /usr/bin/fastfetch
      cp /usr/lib/dri/*_dri.so /out/usr/lib/dri/ 2>/dev/null || true
      cp /lib/ld-musl-i386.so.1 /out/lib/ 2>/dev/null || cp /lib/ld-musl-x86.so.1 /out/lib/ 2>/dev/null || true
    '
  fi

  echo "→ Composing Alpenglow demo rootfs..."
  rm -rf "${ROOTFS}"
  mkdir -p "${ROOTFS}"/{bin,sbin,etc,dev,proc,sys,tmp,run,usr/local/bin,usr/share/alpenglow/browser,root}

  cp "${OUT_DIR}/toybox" "${ROOTFS}/bin/toybox"
  for applet in sh ls cat echo clear hostname sleep mount umount mkdir chmod kill dmesg free uname getty login; do
    ln -sf /bin/toybox "${ROOTFS}/bin/${applet}" 2>/dev/null || true
  done
  ln -sf /bin/toybox "${ROOTFS}/sbin/init"
  cp "${OUT_DIR}/dinit" "${ROOTFS}/sbin/dinit"
  chmod 755 "${ROOTFS}/sbin/dinit"
  cp "${OIL_BIN}" "${ROOTFS}/usr/local/bin/oil"
  chmod 755 "${ROOTFS}/usr/local/bin/oil"

  if [ -d "${OUT_DIR}/cage" ]; then
    cp -a "${OUT_DIR}/cage/usr" "${OUT_DIR}/cage/lib" "${ROOTFS}/" 2>/dev/null || true
    [ -d "${OUT_DIR}/cage/lib" ] && cp -a "${OUT_DIR}/cage/lib/." "${ROOTFS}/lib/" 2>/dev/null || true
  fi

  mkdir -p "${ROOTFS}/etc/dinit.d/boot.d"

  cat > "${ROOTFS}/etc/dinit.d/mount-filesystems" <<'MOUNT'
type = scripted
command = /bin/toybox sh -c "/bin/toybox mount -t proc proc /proc; /bin/toybox mount -t sysfs sysfs /sys; /bin/toybox mount -t devtmpfs devtmpfs /dev; /bin/toybox mount -t tmpfs tmpfs /run; /bin/toybox mount -t tmpfs tmpfs /tmp"
restart = no
MOUNT

  cat > "${ROOTFS}/etc/dinit.d/demo-seatd" <<'SEATD'
type = process
command = /usr/bin/seatd
restart = yes
depends-on = mount-filesystems
SEATD

  cat > "${ROOTFS}/etc/dinit.d/demo-compositor" <<'COMP'
type = process
command = /bin/toybox sh -c "export XDG_RUNTIME_DIR=/run/user/0 WLR_RENDERER=pixman WLR_BACKENDS=drm,fbdev LIBGL_ALWAYS_SOFTWARE=1; /bin/toybox mkdir -p /run/user/0; /bin/toybox chmod 700 /run/user/0; exec /usr/bin/cage -s -- /usr/bin/foot -H localhost -T Alpenglow"
restart = yes
depends-on = demo-seatd
waits-for = demo-seatd
COMP

  cat > "${ROOTFS}/etc/dinit.d/shell-ttyS0" <<'SERIAL'
type = process
command = /bin/toybox sh -c "/usr/local/bin/fastfetch 2>/dev/null; exec /bin/toybox getty -L 115200 ttyS0 vt100"
restart = yes
depends-on = mount-filesystems
SERIAL

  for svc in mount-filesystems demo-seatd demo-compositor shell-ttyS0; do
    ln -sf "/etc/dinit.d/${svc}" "${ROOTFS}/etc/dinit.d/boot.d/${svc}"
  done

  cat > "${ROOTFS}/etc/dinit.d/boot" <<'BOOT'
type = scripted
command = /bin/true
restart = no
depends-on = mount-filesystems
depends-on = demo-seatd
depends-on = demo-compositor
depends-on = shell-ttyS0
BOOT

  cat > "${ROOTFS}/etc/os-release" <<'OSR'
NAME="Alpenglow"
ID=alpenglow
VERSION_ID="0.1"
PRETTY_NAME="Alpenglow browser demo"
OSR

  cat > "${ROOTFS}/etc/passwd" <<'PASS'
root:x:0:0:root:/root:/bin/toybox sh
PASS
  cat > "${ROOTFS}/etc/shadow" <<'SHAD'
root::19999:0:99999:7:::
SHAD
  cat > "${ROOTFS}/etc/group" <<'GRP'
root:x:0:
seatd:x:772:
video:x:44:seatd
GRP
  echo alpenglow-demo > "${ROOTFS}/etc/hostname"
  mkdir -p "${ROOTFS}/root"
  cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/usr/share/alpenglow/browser/"

  FF_VER="2.7.0-r0"
  if [ -x "${ROOTFS}/usr/local/bin/fastfetch" ]; then
    FF_VER="$(docker run --rm --platform linux/386 alpine:3.20 sh -c 'apk search -x fastfetch 2>/dev/null | sed "s/^fastfetch-//"' | head -1)"
    FF_VER="${FF_VER:-2.7.0-r0}"
  fi
  mkdir -p "${ROOTFS}/root/.oil" "${ROOTFS}/root/.oil/cache/system"
  cat > "${ROOTFS}/root/.oil/installed.json" <<EOF
{
  "fastfetch": {
    "name": "fastfetch",
    "version": "${FF_VER}",
    "install_date": 0,
    "pinned": false
  }
}
EOF

  cat > "${ROOTFS}/init" <<'INIT'
#!/bin/toybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/local/bin
exec </dev/ttyS0 >/dev/ttyS0 2>&1
exec /sbin/dinit -d /etc/dinit.d -s -t boot
INIT
  chmod 755 "${ROOTFS}/init"

  for dev in "console c 5 1" "null c 1 3" "tty0 c 4 0" "ttyS0 c 4 64"; do
    set -- $dev
    mknod -m 666 "${ROOTFS}/dev/$1" "$2" "$3" "$4" 2>/dev/null || true
  done
}

compose_v86_rootfs

if [ ! -f "${KERNEL_OUT}" ]; then
  [ -f "${ISO}" ] || curl -L --fail -o "${ISO}" "${ISO_URL}"
  rm -rf "${BUILD_DIR}/iso"
  mkdir -p "${BUILD_DIR}/iso"
  bsdtar -xf "${ISO}" -C "${BUILD_DIR}/iso" boot/vmlinuz-virt
  cp "${BUILD_DIR}/iso/boot/vmlinuz-virt" "${KERNEL_OUT}"
fi

(cd "${ROOTFS}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT}")
ls -lh "${KERNEL_OUT}"
ls -lh "${OUT}"