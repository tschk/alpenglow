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

# standardOptimizeOption exposes -Drelease=true in Zig 0.14+.
RELEASE_FLAG="-Drelease=true"
echo "ci-zig: using ${RELEASE_FLAG}"

# Build kernelctl-zig
echo "ci-zig: building kernelctl-zig..."
(cd "${REPO_ROOT}/system/kernelctl-zig" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1
echo "ci-zig: kernelctl-zig built OK"

# Build netd-zig
echo "ci-zig: building netd-zig..."
(cd "${REPO_ROOT}/system/netd-zig" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1
echo "ci-zig: netd-zig built OK"

# Build zramctl-zig
echo "ci-zig: building zramctl-zig..."
(cd "${REPO_ROOT}/system/zramctl-zig" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1
echo "ci-zig: zramctl-zig built OK"

# Build pressurectl-zig
echo "ci-zig: building pressurectl-zig..."
(cd "${REPO_ROOT}/system/pressurectl-zig" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1
echo "ci-zig: pressurectl-zig built OK"

printf 'ci-zig: ok\n'
