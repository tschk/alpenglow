#!/bin/sh
# Compose each x86 edition's rootfs with the release assembler (the code
# boot-native.sh runs), using stub service binaries, and check it against
# editions.toml with check-release-rootfs.sh. No Docker, kernel or network.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
fail() { printf 'test-release-rootfs: %s\n' "$1" >&2; exit 1; }

stub() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; chmod 755 "$1"; }

# compose <edition> <out-dir>: rootfs at <out-dir>/rootfs, as boot-native.sh
# leaves it just before assemble_rootfs_config.
compose() (
  unset FAST GRAPHICAL BUILD_SERVICES WORLD_FILE KERNEL_POLICY ZIG_INIT SESSION
  ROOT_DIR="${REPO_ROOT}"
  ALPENGLOW_EDITION="$1"
  OUT_DIR="$2"
  export ALPENGLOW_EDITION
  set --  # edition-resolve.sh reads and resets the positional parameters
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  ROOTFS_DIR="${OUT_DIR}/rootfs"
  BACKEND_DIR="${REPO_ROOT}/system/backends/appliance"
  ALPENGLOW_MODULE="${OUT_DIR}/none.ko"
  mkdir -p "${ROOTFS_DIR}/bin" "${ROOTFS_DIR}/sbin" "${ROOTFS_DIR}/etc/alpenglow" "${ROOTFS_DIR}/dev"
  stub "${ROOTFS_DIR}/bin/toybox"
  stub "${ROOTFS_DIR}/sbin/dinit"
  if [ "${FAST}" != "1" ]; then
    stub "${ROOTFS_DIR}/usr/local/bin/alpenglow-kernelctl"
    stub "${ROOTFS_DIR}/usr/local/bin/alpenglow-zramctl-zig"
  fi
  [ "${KERNEL_POLICY}" = "none" ] ||
    cp "${BACKEND_DIR}/kernel-policy-${KERNEL_POLICY}.json" "${ROOTFS_DIR}/etc/alpenglow/kernel-policy.json"
  toybox_has() { return 1; }
  . "${REPO_ROOT}/scripts/lib/assemble-rootfs.sh"
  assemble_rootfs_config >/dev/null
)

check() (
  ROOT_DIR="${REPO_ROOT}"
  ALPENGLOW_EDITION="$1"
  export ALPENGLOW_EDITION
  unset ALPENGLOW_SKU
  sh "${REPO_ROOT}/scripts/check-release-rootfs.sh" "$2/rootfs"
)

payloads() {
  stub "$1/dropbear/usr/sbin/dropbear"
  stub "$1/chrony/usr/sbin/chronyd"
  stub "$1/dnsmasq/usr/sbin/dnsmasq"
  stub "$1/sdhcp/usr/sbin/sdhcp"
  stub "$1/oil"
}

if [ "${1:-}" = compose-only ]; then compose "$2" "$3"; exit; fi

for edition in potato internet desktop fast; do
  out="${tmp}/${edition}"
  payloads "${out}"
  compose "${edition}" "${out}"
  check "${edition}" "${out}" >/dev/null || fail "${edition}: release rootfs rejected"
done

# Lean editions: the units the checker accepted actually run the services.
lean="${tmp}/potato/rootfs/etc/dinit.d"
grep -q 'dropbear -F -R -s' "${lean}/dropbear" || fail "potato: dropbear unit"
grep -q 'waits-for = networking' "${lean}/chronyd" || fail "potato: chronyd must not block offline boot"
grep -q '/usr/sbin/sdhcp -d eth0 &' "${lean}/networking" || fail "potato: networking unit"
grep -q 'mount-state.sh' "${lean}/state-mount" || fail "potato: state-mount unit"
grep -qx 'nameserver 127.0.0.1' "${tmp}/potato/rootfs/etc/resolv.conf" || fail "potato: resolver"
grep -q '^chrony:' "${tmp}/potato/rootfs/etc/passwd" || fail "potato: chrony user"
[ -x "${tmp}/potato/rootfs/usr/local/bin/oil" ] || fail "potato: oil"
[ -L "${tmp}/potato/rootfs/lib/ld-musl-x86_64.so.1" ] || fail "potato: musl loader link for /opt/oil"
grep -qx '/opt/oil/lib' "${tmp}/potato/rootfs/etc/ld-musl-x86_64.path" || fail "potato: /opt/oil library path"
for edition in potato fast desktop; do
  grep -q '^root:!:' "${tmp}/${edition}/rootfs/etc/shadow" || fail "${edition}: root must ship locked"
  grep -q 'getty -L -l /usr/local/bin/alpenglow-login' "${tmp}/${edition}/rootfs/etc/dinit.d/shell-ttyS0" ||
    fail "${edition}: console login must set the first root password"
done
# configure-rootfs.sh service users survive the serial-login passwd step.
grep -q '^dnsmasq:' "${tmp}/desktop/rootfs/etc/passwd" || fail "desktop: service users dropped"
# The console waits for /state so the first password can be kept there.
grep -qx 'waits-for = state-mount' "${lean}/shell-ttyS0" || fail "potato: console must wait for state-mount"
# Missing optional payloads are a dev-boot condition, not an assembler failure.
# Run in its own shell: inside `||` the shell would ignore set -e.
sh "$0" compose-only potato "${tmp}/bare" ||
  fail "potato without payloads: assembler failed"
# fast stays zero-overhead.
! grep -q 'state-mount' "${tmp}/fast/rootfs/etc/dinit.d/shell-ttyS0" || fail "fast: console waits for state-mount"
[ ! -e "${tmp}/fast/rootfs/etc/dinit.d/boot.d/dropbear" ] || fail "fast: dropbear started"
[ ! -e "${tmp}/fast/rootfs/usr/local/bin/oil" ] || fail "fast: oil shipped"

# The checker catches what used to ship silently: a world service that was
# never built, and an empty root password.
out="${tmp}/broken"
payloads "${out}"
rm -rf "${out}/dropbear"
compose potato "${out}"
if check potato "${out}" 2>"${tmp}/err"; then fail "missing dropbear accepted"; fi
grep -q 'lists dropbear but dropbear is not in the image' "${tmp}/err" || fail "missing dropbear: wrong error"
sed 's/^root:!:/root::/' "${out}/rootfs/etc/shadow" > "${tmp}/shadow" && mv "${tmp}/shadow" "${out}/rootfs/etc/shadow"
if check potato "${out}" 2>"${tmp}/err"; then fail "empty root password accepted"; fi
grep -q 'empty password in /etc/shadow for: root' "${tmp}/err" || fail "empty password: wrong error"

printf 'test-release-rootfs: ok\n'
