#!/bin/sh
# Build the Alpenglow legacy initramfs from the shipped i686 v86 rootfs.
#
# The v86 image boots through bash, which was compiled with SSE2 and dies
# with SIGILL on anything older than a Pentium 4. The legacy image drops bash
# and fastfetch and uses busybox ash, which has no SSE2, so it reaches a shell
# on a Pentium, a Pentium II, and a 486.
#
# It stays i686: the kernel (site/public/v86/alpenglow-v86-vmlinuz) refuses to
# boot on an i586, so a Pentium still needs `-cpu pentium2` or newer.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SRC_INITRD="${REPO_ROOT}/site/public/v86/alpenglow-v86-initrd.cpio.gz"
OUT_DIR="${REPO_ROOT}/build/legacy"
OUT="${OUT_DIR}/initramfs.cpio.gz"

[ -f "${SRC_INITRD}" ] || { echo "missing ${SRC_INITRD}" >&2; exit 1; }
mkdir -p "${OUT_DIR}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

gzip -dc "${SRC_INITRD}" | (cd "${WORK}" && cpio -id 2>/dev/null)

# SSE2 userspace. busybox ash is the shell; fastfetch is cosmetic.
rm -f "${WORK}/bin/bash" "${WORK}/usr/bin/fastfetch" "${WORK}/usr/bin/flashfetch"
rm -rf "${WORK}/usr/lib/bash" "${WORK}/lib/ld-musl-i386.so.1" "${WORK}/usr/lib/libncursesw.so.6.4" \
  "${WORK}/usr/lib/libreadline.so.8.2"

cat > "${WORK}/init" <<'INIT'
#!/bin/sh
CON=/dev/ttyS0
export PATH=/bin:/usr/bin:/usr/local/bin
export HOME=/
export TERM=vt100
/bin/mount -t proc proc /proc 2>/dev/null
/bin/mount -t sysfs sysfs /sys 2>/dev/null
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || {
  /bin/mkdir -p /dev 2>/dev/null
  /bin/mknod /dev/console c 5 1 2>/dev/null
  /bin/mknod /dev/ttyS0 c 4 64 2>/dev/null
  /bin/mknod /dev/null c 1 3 2>/dev/null
}
/bin/mount -t tmpfs tmpfs /run 2>/dev/null
/bin/hostname alpenglow 2>/dev/null
[ -c "$CON" ] || CON=/dev/console
cd /
{
  /bin/echo "Alpenglow legacy"
  /bin/echo
  /bin/uname -a
  /bin/free
  /bin/echo
} >"$CON" 2>&1
exec /bin/setsid -c /bin/sh -i <"$CON" >"$CON" 2>&1
INIT
chmod 755 "${WORK}/init"

cat > "${WORK}/etc/profile" <<'PROFILE'
export PS1='alpenglow-legacy:\w# '
PROFILE

(cd "${WORK}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT}")
echo "${OUT}"
ls -lh "${OUT}"
