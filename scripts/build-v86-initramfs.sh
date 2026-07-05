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
    'apk add --no-cache busybox-static >/dev/null && cp /bin/busybox.static /out/busybox-i386 && chmod +x /out/busybox-i386'
fi

sh "${ROOT_DIR}/scripts/build-v86-kernel.sh"

if [ ! -x "${OIL}" ] || find "${ROOT_DIR}/system/oil/src" "${ROOT_DIR}/system/oil/Cargo.toml" "${ROOT_DIR}/Cargo.lock" -newer "${OIL}" 2>/dev/null | grep -q .; then
  need_docker
  docker run --rm -v "${ROOT_DIR}:/home/rust/src" -w /home/rust/src/system/oil messense/rust-musl-cross:i686-musl sh -lc \
    'cargo build --release --target i686-unknown-linux-musl'
fi

cp "${BUSYBOX}" "${ROOTFS}/bin/busybox"
chmod 755 "${ROOTFS}/bin/busybox"
for applet in sh ash mount mkdir mknod chmod cat ls pwd echo uname free dmesg clear hostname sleep stty; do
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

apk_root_install fastfetch bash
FASTFETCH_VERSION="$(docker run --rm --platform linux/386 -v "${ROOTFS}:/rootfs" alpine:3.20 apk --root /rootfs info -e -v fastfetch 2>/dev/null | sed 's/^fastfetch-//')"
BASH_VERSION="$(docker run --rm --platform linux/386 -v "${ROOTFS}:/rootfs" alpine:3.20 apk --root /rootfs info -e -v bash 2>/dev/null | sed 's/^bash-//')"
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
  "bash": {
    "name": "bash",
    "version": "${BASH_VERSION}",
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
  "display": { "separator": ": ", "key": { "width": 14 } },
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

VRO_SRC="${ROOT_DIR}/../vro/vro"
VRO_CACHE="${BUILD_DIR}/vro-i686"
if [ ! -x "${VRO_CACHE}" ]; then
  mkdir -p "${BUILD_DIR}"
  if [ -x "${VRO_SRC}" ] && file "${VRO_SRC}" 2>/dev/null | grep -q 'ELF.*386'; then
    cp "${VRO_SRC}" "${VRO_CACHE}"
  else
    need_docker
    docker run --rm --platform linux/386 -v "${BUILD_DIR}:/out" alpine:3.20 sh -lc '
      apk add --no-cache curl tar >/dev/null
      tag="$(curl -fsSL https://api.github.com/repos/undivisible/vro/releases/latest | sed -n "s/.*\"tag_name\": \"\([^\"]*\)\".*/\1/p" | head -1)"
      [ -n "$tag" ] || exit 1
      url="https://github.com/undivisible/vro/releases/download/${tag}/vro-linux-x86_64"
      if ! curl -fsSL -o /out/vro-i686 "$url"; then
        url="https://github.com/undivisible/vro/releases/download/${tag}/vro-linux-x86"
        curl -fsSL -o /out/vro-i686 "$url" || exit 1
      fi
      chmod +x /out/vro-i686
    ' || true
  fi
fi
if [ -x "${VRO_CACHE}" ]; then
  cp "${VRO_CACHE}" "${ROOTFS}/usr/local/bin/vro"
  chmod 755 "${ROOTFS}/usr/local/bin/vro"
  ln -sf vro "${ROOTFS}/usr/local/bin/vi" 2>/dev/null || true
fi

cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/"
cp "${ROOT_DIR}/docs/browser/"*.md "${ROOTFS}/usr/share/alpenglow/browser/"
if [ -f "${ROOTFS}/README.md" ]; then
  ln -sf README.md "${ROOTFS}/readme.md"
fi

mkdir -p "${ROOTFS}/etc/profile.d"
ln -sf bash "${ROOTFS}/bin/login-shell" 2>/dev/null || true
cat > "${ROOTFS}/etc/profile" <<'PROF'
export PATH=/bin:/usr/bin:/usr/local/bin
export HOME=/
export SHELL=/bin/bash
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
if [ -n "${BASH_VERSION}" ]; then
  export PS1='\[\033[1;36m\]alpenglow\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]# '
else
  export PS1='alpenglow:~# '
fi
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
  /bin/echo "Alpenglow"
  /bin/echo
  /bin/echo "Alpenglow: headless appliance or full desktop (Alpenglowed); immutable RAM root + disk /state."
  /bin/echo "Docs (case-sensitive): cat README.md  cat ideology.md  cat root-model.md  cat desktop.md"
  /bin/echo "Try: fastfetch   wax info vro   wax tap undivisible/tap   oil search firefox"
  /bin/echo "     wax tap undivisible/tap - third-party tap; vro via wax on real hosts."
  /bin/echo
  /usr/bin/fastfetch 2>/dev/null || /bin/fastfetch 2>/dev/null || true
  /bin/echo
  /bin/ls -1 --color=never *.md 2>/dev/null || /bin/ls -1 --color=never
  /bin/echo
} >"$CON" 2>&1
export ENV=/etc/profile
if [ -c "$CON" ]; then
  /bin/stty -F "$CON" sane 2>/dev/null || true
  /bin/stty -F "$CON" columns 100 rows 30 2>/dev/null || true
fi
printf '\n' >"$CON"
if [ -x /bin/bash ]; then
  exec /bin/bash --login -i 0<"$CON" 1>"$CON" 2>&1
fi
exec /bin/sh -i 0<"$CON" 1>"$CON" 2>&1
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