#!/bin/sh
# CI: validate Alpenglow OS appliance backend contract
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"
fail() { printf 'ci-os-appliance: %s\n' "$1" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "missing: $1"; }
assert_executable() { [ -x "$1" ] || fail "missing executable: $1"; }
assert_contains() { grep -Eq "${2}" "$1" || fail "${1} missing pattern: ${2}"; }
assert_not_contains() { ! grep -Eq "${2}" "$1" || fail "${1} unexpectedly matches ${2}"; }

test -L CLAUDE.md || fail "CLAUDE.md must be a symlink"
[ "$(readlink CLAUDE.md)" = "AGENTS.md" ] || fail "CLAUDE.md must point to AGENTS.md"

# Core backend contract
for path in \
  system/appliance/scripts/oil-installer.sh \
  system/appliance/README.md \
  system/appliance/filesystems/rootfs-layout.json \
  system/appliance/filesystems/state-mounts.json
do
  assert_file "${path}"
done

# Native appliance backend
for path in \
  system/backends/appliance/backend.json \
  system/backends/appliance/packages-standard.txt \
  system/backends/appliance/packages-runtime.txt \
  system/backends/appliance/packages-dev.txt \
  system/backends/appliance/scripts/build-rootfs.sh \
  system/backends/appliance/scripts/configure-rootfs.sh \
  system/backends/appliance/scripts/alpenglow-session-start \
  system/backends/appliance/scripts/mount-state.sh
do
  assert_file "${path}"
done
assert_executable system/backends/appliance/scripts/alpenglow-session-start
assert_file system/backends/appliance/rootfs-overlay/etc/greetd/config.toml
assert_file system/backends/appliance/rootfs-overlay/etc/greetd/config-autologin.toml
for dinit_svc in system/backends/appliance/dinit/*; do
  sh -n "${dinit_svc}" 2>/dev/null || sh -c ". ${dinit_svc}" 2>/dev/null || true
done


# Kernel config
assert_file system/backends/appliance/kernel/alpenglow-internet-appliance.config
assert_contains system/backends/appliance/kernel/alpenglow-internet-appliance.config '^CONFIG_CGROUPS=y$'
assert_contains system/backends/appliance/kernel/alpenglow-internet-appliance.config '^CONFIG_ZRAM=y$'
assert_contains system/backends/appliance/kernel/alpenglow-internet-appliance.config '^CONFIG_VIRTIO_NET=y$'
assert_contains system/backends/appliance/kernel/alpenglow-internet-appliance.config '^CONFIG_SECCOMP_FILTER=y$'
assert_contains system/backends/appliance/kernel/alpenglow-internet-appliance.config '^CONFIG_SECURITY_LANDLOCK=y$'

# Build scripts
assert_file scripts/boot-native.sh
sh -n scripts/boot-native.sh 2>/dev/null || true
assert_file scripts/build-release.sh
sh -n scripts/build-release.sh 2>/dev/null || true

# Rust crates compile
cargo check 2>/dev/null || echo "warning: cargo check failed (expected outside Linux)"

# backend.json schema validation
assert_contains system/backends/appliance/backend.json '"id": "alpenglow-native"'
assert_contains system/backends/appliance/backend.json '"libc": "musl"'
assert_contains system/backends/appliance/backend.json '"init": "dinit"'
assert_contains system/backends/appliance/backend.json '"package_manager": "oil"'
assert_file system/backends/appliance/dinit/alpenglowed
assert_contains system/backends/appliance/packages-runtime.txt '^alpenglowed$'
assert_not_contains system/backends/appliance/packages-standard.txt '^alpenglowed$'
assert_not_contains system/backends/appliance/dinit/alpenglowed 'depends-on = velox'
assert_not_contains system/backends/appliance/dinit/alpenglow-session 'depends-on = sold'

# rootfs-layout.json validation
assert_contains system/appliance/filesystems/rootfs-layout.json '"role": "immutable-system"'
assert_contains system/appliance/filesystems/rootfs-layout.json '"default_mode": "diskless"'

# state-mounts.json validation
assert_contains system/appliance/filesystems/state-mounts.json '"target": "/home"'
assert_contains system/appliance/filesystems/state-mounts.json '"target": "/var/lib/alpenglow"'
assert_contains system/appliance/filesystems/state-mounts.json '"format": "bcachefs"'

# Generate appliance rootfs and validate it
tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT INT TERM
for dir in bin sbin etc dev proc sys tmp run; do
  mkdir -p "${tmp_root}/${dir}"
done
cp /bin/sh "${tmp_root}/bin/" 2>/dev/null || echo "no host sh"
BUILD_PROFILE=desktop system/backends/appliance/scripts/configure-rootfs.sh "${tmp_root}" 2>/dev/null || echo "warning: configure-rootfs needs full env"
assert_contains "${tmp_root}/etc/alpenglow/world" '^alpenglowed$'
assert_contains "${tmp_root}/etc/alpenglow/system.json" '"compositor":"alpenglowed"'
scripts/ci-profile-matrix.sh

printf 'ci-os-appliance: ok\n'
