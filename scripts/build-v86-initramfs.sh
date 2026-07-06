#!/bin/sh
# Alpenglow v86 browser initramfs (i686 for v86 CPU): busybox + oil + docs
set -eu

if [ "${V86_SSH:-}" = 1 ] && [ -z "${V86_SKIP_SSH:-}" ]; then
  exec sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/build-v86-ssh.sh"
fi

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ALP_VERSION="0.1.$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 0)"
BUILD_DIR="${ROOT_DIR}/build/v86"
ROOTFS="${BUILD_DIR}/rootfs"
OUT="${ROOT_DIR}/public/v86/alpenglow-v86-initrd.cpio.gz"
KERNEL_OUT="${ROOT_DIR}/public/v86/alpenglow-v86-vmlinuz"
BUSYBOX="${BUILD_DIR}/busybox-i386"
OIL="${ROOT_DIR}/target/i686-unknown-linux-musl/release/oil"

need_docker() {
  command -v docker >/dev/null 2>&1 || {
    echo "docker required to build i686 busybox/oil (or run on ultramarine)" >&2
    exit 1
  }
}

if [ -d "${ROOTFS}" ] && [ ! -w "${ROOTFS}" ]; then
  sudo rm -rf "${ROOTFS}" 2>/dev/null || rm -rf "${ROOTFS}" 2>/dev/null || true
else
  rm -rf "${ROOTFS}"
fi
mkdir -p "${BUILD_DIR}" "${ROOTFS}/bin" "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" \
  "${ROOTFS}/run" "${ROOTFS}/tmp" "${ROOTFS}/usr/local/bin" "${ROOTFS}/usr/share/alpenglow/browser"

if [ ! -x "${BUSYBOX}" ] || [ "${FORCE_V86_BUSYBOX:-}" = 1 ]; then
  need_docker
  docker run --rm --platform linux/386 -v "${BUILD_DIR}:/out" alpine:3.20 sh -lc \
    'set -e
     apk add --no-cache build-base linux-headers musl-dev curl tar bzip2 >/dev/null
     cd /out
     BB_VERSION="1.36.1"
     if [ ! -d "busybox-${BB_VERSION}" ]; then
       curl -fsSL "https://busybox.net/downloads/busybox-${BB_VERSION}.tar.bz2" -o busybox.tar.bz2
       tar -xjf busybox.tar.bz2
     fi
     cd "busybox-${BB_VERSION}"
     make defconfig >/dev/null
     # Brand the binary as Alpenglow instead of the distro builder.
     sed -i "s|#define BB_EXTRA_VERSION \" (\"AUTOCONF_TIMESTAMP\")\"|#define BB_EXTRA_VERSION \" (Alpenglow)\"|" libbb/messages.c
     make CONFIG_STATIC=y -j"$(nproc)" >/dev/null
     cp busybox /out/busybox-i386
     chmod +x /out/busybox-i386'
fi

sh "${ROOT_DIR}/scripts/build-v86-kernel.sh"

if [ ! -x "${OIL}" ] || find "${ROOT_DIR}/system/oil/src" "${ROOT_DIR}/system/oil/Cargo.toml" "${ROOT_DIR}/Cargo.lock" -newer "${OIL}" 2>/dev/null | grep -q .; then
  need_docker
  docker run --rm -v "${ROOT_DIR}:/home/rust/src" -w /home/rust/src/system/oil messense/rust-musl-cross:i686-musl sh -lc \
    'cargo build --release --target i686-unknown-linux-musl --no-default-features'
fi

cp "${BUSYBOX}" "${ROOTFS}/bin/busybox"
chmod 755 "${ROOTFS}/bin/busybox"
for applet in sh ash mount mkdir mknod chmod cat ls pwd echo uname free dmesg clear hostname sleep stty setsid cttyhack; do
  ln -sf busybox "${ROOTFS}/bin/${applet}"
done
cp "${OIL}" "${ROOTFS}/bin/oil"
chmod 755 "${ROOTFS}/bin/oil"
ln -sf oil "${ROOTFS}/bin/wax"

need_docker
apk_root_install() {
  docker run --rm --platform linux/386 -v "${ROOTFS}:/rootfs" alpine:3.20 sh -lc '
    mkdir -p /rootfs/etc/apk/keys /rootfs/lib/apk/db /rootfs/var/cache/apk /rootfs/usr/lib
    cp -a /etc/apk/keys/* /rootfs/etc/apk/keys/ 2>/dev/null || true
    if [ ! -f /rootfs/etc/apk/repositories ]; then
      cat > /rootfs/etc/apk/repositories <<REPOS
https://dl-cdn.alpinelinux.org/alpine/v3.20/main
https://dl-cdn.alpinelinux.org/alpine/v3.20/community
REPOS
      apk add --root /rootfs --initdb --no-cache >/dev/null
    fi
    apk add --root /rootfs --no-cache "$@" >/dev/null
  ' sh "$@"
}

apk_root_install fastfetch oksh
FASTFETCH_VERSION="$(docker run --rm --platform linux/386 -v "${ROOTFS}:/rootfs" alpine:3.20 apk --root /rootfs info -e -v fastfetch 2>/dev/null | sed 's/^fastfetch-//')"
OKSH_VERSION="$(docker run --rm --platform linux/386 -v "${ROOTFS}:/rootfs" alpine:3.20 apk --root /rootfs info -e -v oksh 2>/dev/null | sed 's/^oksh-//')"
if [ -x "${ROOTFS}/usr/bin/oksh" ] && [ ! -e "${ROOTFS}/bin/oksh" ]; then
  ln -sf ../usr/bin/oksh "${ROOTFS}/bin/oksh"
fi
rm -f "${ROOTFS}/bin/bash" "${ROOTFS}/usr/bin/bash" 2>/dev/null || true
rm -rf "${ROOTFS}/usr/lib/bash" 2>/dev/null || true
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
  },
  "oksh": {
    "name": "oksh",
    "version": "${OKSH_VERSION}",
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

cat > "${ROOTFS}/etc/os-release" <<EOF
NAME="Alpenglow"
ID=alpenglow
VERSION_ID="${ALP_VERSION}"
VERSION="${ALP_VERSION}"
PRETTY_NAME="Alpenglow ${ALP_VERSION}"
BUILD_ID="browser-v86"
EOF
mkdir -p "${ROOTFS}/etc/fastfetch"
cat > "${ROOTFS}/etc/fastfetch/config.jsonc" <<EOF
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "type": "none" },
  "display": { "separator": ": " },
  "modules": [
    { "type": "custom", "format": "Alpenglow ${ALP_VERSION}" },
    { "type": "custom", "format": "Host: alpenglow (browser i686)" },
    { "type": "kernel" },
    { "type": "uptime" },
    { "type": "memory" },
    { "type": "shell" },
    { "type": "packages", "format": "{1} (oil/apk)" }
  ]
}
EOF

VRO_SRC="${ROOT_DIR}/../vro"
VRO_CACHE="${BUILD_DIR}/vro-i686"
build_vro_i686() {
  local ssh_host="${VRO_SSH_HOST:-undivisible@192.168.4.134}"
  local remote_src="/tmp/alpenglow-vro-build"
  local remote_c="${remote_src}/vro-headless.c"
  mkdir -p "${BUILD_DIR}"
  echo "Building vro i686 via ${ssh_host} ..."
  rsync -az --exclude='.git' "${VRO_SRC}/" "${ssh_host}:${remote_src}/"
  ssh "${ssh_host}" "cd ${remote_src} && v -gc none -os linux -d headless -o vro-headless.c ."
  scp "${ssh_host}:${remote_c}" "${BUILD_DIR}/vro-headless.c"
  need_docker
  docker run --rm --platform linux/386 -v "${BUILD_DIR}:/out" alpine:3.20 sh -lc '
    apk add --no-cache gcc musl-dev binutils >/dev/null
    sed -i "s/typedef u8 bool;/\/* typedef u8 bool; *\//" /out/vro-headless.c
    sed -i "1i #include <stdbool.h>\n\n/* Stubs for backtrace(3) symbols not provided by musl on i386. */\nint backtrace(void **buffer, int size) { (void)buffer; (void)size; return 0; }\nchar **backtrace_symbols(void *const *buffer, int size) { (void)buffer; (void)size; return 0; }\n" /out/vro-headless.c
    gcc -m32 -std=gnu99 -o /out/vro-i686 /out/vro-headless.c -lm -lpthread
    strip /out/vro-i686
    chmod +x /out/vro-i686
  '
}
if [ ! -x "${VRO_CACHE}" ]; then
  if [ -x "${VRO_SRC}/vro" ] && file "${VRO_SRC}/vro" 2>/dev/null | grep -q 'ELF.*386'; then
    cp "${VRO_SRC}/vro" "${VRO_CACHE}"
  elif [ -d "${VRO_SRC}" ] && ssh -o ConnectTimeout=5 "${VRO_SSH_HOST:-undivisible@192.168.4.134}" 'exit 0' 2>/dev/null; then
    build_vro_i686
  else
    echo "warning: no i686 vro source or SSH host available, falling back to busybox" >&2
  fi
fi
if [ "${V86_SKIP_VRO:-}" = 1 ]; then
  ln -sf /bin/busybox "${ROOTFS}/usr/local/bin/vro"
  echo "v86 initramfs: V86_SKIP_VRO=1 (smaller initrd, vro=busybox)" >&2
elif [ -x "${VRO_CACHE}" ]; then
  cp "${VRO_CACHE}" "${ROOTFS}/usr/local/bin/vro"
  chmod 755 "${ROOTFS}/usr/local/bin/vro"
else
  ln -sf /bin/busybox "${ROOTFS}/usr/local/bin/vro"
fi

cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/"
cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/usr/share/alpenglow/browser/"

mkdir -p "${ROOTFS}/etc/profile.d"
ln -sf oksh "${ROOTFS}/bin/login-shell" 2>/dev/null || true
cat > "${ROOTFS}/etc/profile" <<'PROF'
export PATH=/bin:/usr/bin:/usr/local/bin
export HOME=/
export SHELL=/bin/oksh
export TERM=xterm-256color
export COLORTERM=truecolor
export CLICOLOR=1
export FORCE_COLOR=1
for f in /etc/profile.d/*.sh; do
  [ -r "$f" ] && . "$f"
done
PROF
cat > "${ROOTFS}/etc/profile.d/colors.sh" <<'CLR'
# busybox ls honors LS_COLORS when set
export LS_COLORS='di=1;34:ln=1;36:so=1;35:pi=1;33:ex=1;32:*.md=0;33'
CLR
cat > "${ROOTFS}/etc/profile.d/serial-tty.sh" <<'TTY'
CON=/dev/ttyS0
[ -c "$CON" ] || CON=/dev/console
if /bin/stty -F "$CON" sane 2>/dev/null; then
  dims="$(/bin/stty -F "$CON" size 2>/dev/null)"
  set -- $dims
  [ -n "$2" ] && export LINES="$1" COLUMNS="$2"
fi
TTY
cat > "${ROOTFS}/etc/profile.d/prompt.sh" <<'PROMPT'
export PS1='alpenglow:\w# '
PROMPT

cat > "${ROOTFS}/init" <<'INIT'
#!/bin/sh
CON=/dev/ttyS0
export PATH=/bin:/usr/bin:/usr/local/bin
export HOME=/
export TERM=xterm-256color
export COLORTERM=truecolor
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
  esc=$(printf '\033')
  r="${esc}[0m"
  dim="${esc}[2m"
  title="${esc}[1;36m"
  stats="${esc}[0;32m"
  hint="${esc}[0;33m"
  boot_s=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
  mem_line=$(awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} END {
    if (t > 0) {
      u=t-a; printf "%.1f MiB / %.1f MiB (%d%%)", u/1024, t/1024, int(u*100/t+0.5)
    } else print "?"
  }' /proc/meminfo 2>/dev/null)
  . /etc/os-release 2>/dev/null
  printf '%sAlpenglow%s %s\n\n' "$title" "$r" "${VERSION_ID:-browser}"
  printf '%simmutable RAM root | bcachefs /state | oksh | Oil%s\n' "$dim" "$r"
  printf '%sboot: %ss  memory: %s%s\n' "$stats" "$boot_s" "$mem_line" "$r"
  printf '%s----------------------------------------%s\n' "$dim" "$r"
  printf '%sdocs:%s cat readme.md, ideology.md, benchmarks.md\n' "$hint" "$r"
  printf '%stry:%s fastfetch, vro readme.md, wax info oksh\n\n' "$hint" "$r"
  /usr/bin/fastfetch 2>/dev/null || /bin/fastfetch 2>/dev/null || true
  /bin/echo
  /bin/ls -1 --color=never *.md 2>/dev/null || /bin/ls -1 --color=never
  /bin/echo
} >"$CON" 2>&1
export ENV=/etc/profile
if [ -c "$CON" ]; then
  /bin/stty -F "$CON" sane 2>/dev/null || true
  # Use terminal size provided by the host via kernel cmdline if available.
  cols=80
  rows=24
  for arg in $(cat /proc/cmdline 2>/dev/null); do
    case "$arg" in
      alpenglow.cols=*) cols="${arg#*=}" ;;
      alpenglow.rows=*) rows="${arg#*=}" ;;
    esac
  done
  /bin/stty -F "$CON" rows "${rows}" cols "${cols}" 2>/dev/null || true
fi
printf '\n' >"$CON"
login_shell=/bin/oksh
[ -x "$login_shell" ] || login_shell=/usr/bin/oksh
if [ -x "$login_shell" ]; then
  exec /bin/setsid -c "$login_shell" -i <"$CON" >"$CON" 2>&1
fi
exec /bin/setsid -c /bin/sh -i <"$CON" >"$CON" 2>&1
INIT
chmod 755 "${ROOTFS}/init"
# Kernel must execute /init; script shebang needs /bin/sh -> busybox present.
ln -sf busybox "${ROOTFS}/bin/sh"
chmod 755 "${ROOTFS}/bin/sh" 2>/dev/null || true

# Ensure our custom Alpenglow-branded busybox survives any apk overwrites.
cp "${BUSYBOX}" "${ROOTFS}/bin/busybox"
chmod 755 "${ROOTFS}/bin/busybox"

BUILD_ID="$(date +%Y%m%d%H%M%S)"
echo "${BUILD_ID}" > "${ROOT_DIR}/public/v86/initrd-build-id.txt"

(cd "${ROOTFS}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT}")
echo "init in archive:"
gzip -dc "${OUT}" | cpio -t 2>/dev/null | grep -E '^(\./)?init$' || true
ls -lh "${KERNEL_OUT}"
ls -lh "${OUT}"