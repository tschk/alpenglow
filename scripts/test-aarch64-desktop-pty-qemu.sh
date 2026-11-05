#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/cross/aarch64"
EDITION="${1:-desktop}"
case "${EDITION}" in
  desktop|desktop-full) ;;
  *) echo "usage: $0 [desktop|desktop-full]" >&2; exit 1 ;;
esac

KERNEL="${KERNEL:-${OUT_DIR}/vmlinuz-${EDITION}}"
INITRAMFS="${INITRAMFS:-${OUT_DIR}/initramfs-${EDITION}.cpio.gz}"
TIMEOUT="${TIMEOUT:-120}"
CC="${AARCH64_CC:-aarch64-linux-gnu-gcc}"
for cmd in qemu-system-aarch64 cpio gzip timeout "${CC}"; do
  command -v "${cmd}" >/dev/null 2>&1 || { echo "missing: ${cmd}" >&2; exit 1; }
done
test -s "${KERNEL}" && test -s "${INITRAMFS}" || {
  echo "missing desktop kernel or initramfs: ${KERNEL}, ${INITRAMFS}" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT HUP INT TERM
mkdir -p "${TMP}/overlay/etc/dinit.d/boot.d" "${TMP}/overlay/usr/local/bin"
cat > "${TMP}/overlay/etc/dinit.d/pty-regression" <<'EOF'
type = scripted
command = /usr/local/bin/pty-regression
EOF
ln -s /etc/dinit.d/pty-regression "${TMP}/overlay/etc/dinit.d/boot.d/pty-regression"
cat > "${TMP}/probe.c" <<'EOF'
#define _XOPEN_SOURCE 600
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
    int serial = open("/dev/ttyAMA0", O_WRONLY);
    if (serial < 0) return 1;
    dup2(serial, 1);
    dup2(serial, 2);
    close(serial);
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) || unlockpt(master)) {
        perror("PTY allocation");
        return 1;
    }
    char *name = ptsname(master);
    if (!name) { perror("ptsname"); return 1; }
    int slave = open(name, O_RDWR | O_NOCTTY);
    if (slave < 0) { perror("open PTY slave"); return 1; }
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }
    if (pid == 0) {
        if (setsid() < 0) _exit(1);
        if (ioctl(slave, TIOCSCTTY, 0) < 0) _exit(1);
        for (int fd = 0; fd < 3; fd++) if (dup2(slave, fd) < 0) _exit(1);
        if (slave > 2) close(slave);
        close(master);
        execl("/bin/sh", "sh", "-c", "test -t 0 && test -t 1 && test -t 2 && printf 'ALPENGLOW_PTY_SHELL_OK\\n'", (char *)0);
        _exit(1);
    }
    close(slave);
    char buf[512];
    ssize_t n;
    while ((n = read(master, buf, sizeof(buf))) > 0) {
        for (ssize_t offset = 0; offset < n;) {
            ssize_t written = write(1, buf + offset, n - offset);
            if (written <= 0) return 1;
            offset += written;
        }
    }
    close(master);
    int status;
    if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status)) {
        fprintf(stderr, "PTY shell failed\n");
        return 1;
    }
    puts("ALPENGLOW_PTY_PROBE_OK");
    return 0;
}
EOF
"${CC}" -static -O2 -Wall -Wextra -o "${TMP}/overlay/usr/local/bin/pty-regression" "${TMP}/probe.c"

# Linux unpacks concatenated initramfs archives in order. This adds only a
# temporary dinit service; the image's init and devpts setup run unchanged.
cp "${INITRAMFS}" "${TMP}/initramfs.gz"
chmod u+w "${TMP}/initramfs.gz"
size=$(wc -c < "${TMP}/initramfs.gz")
padding=$(( (4 - size % 4) % 4 ))
if [ "${padding}" -ne 0 ]; then
  dd if=/dev/zero bs=1 count="${padding}" 2>/dev/null >> "${TMP}/initramfs.gz"
fi
(cd "${TMP}/overlay" && find . -print | cpio -o -H newc 2>/dev/null | gzip -c) >> "${TMP}/initramfs.gz"

status=0
timeout "${TIMEOUT}" qemu-system-aarch64 \
  -M virt -accel "${ACCEL:-tcg}" -cpu "${CPU:-max}" -m "${MEMORY_MB:-4096}" -smp "${SMP:-4}" \
  -display none -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci \
  -serial stdio -monitor none -no-reboot -kernel "${KERNEL}" -initrd "${TMP}/initramfs.gz" \
  -append 'console=tty0 console=ttyAMA0,115200 init=/init' > "${TMP}/qemu.log" 2>&1 || status=$?
cat "${TMP}/qemu.log"
if [ "${status}" -ne 124 ] || ! grep -q 'Alpenglow aarch64 root ready' "${TMP}/qemu.log" ||
   ! grep -q '^ALPENGLOW_PTY_SHELL_OK' "${TMP}/qemu.log" ||
   ! grep -q '^ALPENGLOW_PTY_PROBE_OK' "${TMP}/qemu.log"; then
  echo "FAIL: desktop PTY shell boot test (QEMU status ${status})" >&2
  exit 1
fi
echo "test-aarch64-desktop-pty-qemu: ok"
