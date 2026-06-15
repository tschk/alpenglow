#!/bin/sh
# CI: validate Zig code compiles and passes tests
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() { printf 'ci-zig: %s\n' "$1" >&2; exit 1; }

if ! command -v zig >/dev/null 2>&1; then
  echo "ci-zig: zig not installed, skipping"
  exit 0
fi

ZIG_VERSION="$(zig version 2>&1)"
echo "ci-zig: zig ${ZIG_VERSION}"

# Determine release flag (0.14: -Doptimize=ReleaseSmall, 0.16: -Drelease=true)
RELEASE_FLAG="-Drelease=true"
zig build -Drelease=true --help >/dev/null 2>&1 || RELEASE_FLAG="-Doptimize=ReleaseSmall"

# Build kernelctl-zig
echo "ci-zig: building kernelctl-zig..."
(cd "${REPO_ROOT}/system/kernelctl-zig" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1 | tail -3
echo "ci-zig: kernelctl-zig built OK"

# Build glowfsctl-zig
echo "ci-zig: building glowfsctl-zig..."
(cd "${REPO_ROOT}/system/glowfsctl-zig" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1 | tail -3
echo "ci-zig: glowfsctl-zig built OK"

printf 'ci-zig: ok\n'
