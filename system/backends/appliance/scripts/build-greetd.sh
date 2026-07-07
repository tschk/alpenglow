#!/bin/sh
# Build greetd as static musl binary
set -eu

OUT_DIR="${1:?OUT_DIR must be specified}"
VERSION="${2:-0.10.3}"

echo "→ Building greetd ${VERSION}..."

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf -- "$BUILD_DIR"' EXIT
cd "$BUILD_DIR"
curl -fsSL "https://gitlab.com/mobian1/greetd/-/archive/v${VERSION}/greetd-v${VERSION}.tar.gz" -o greetd.tar.gz
tar -xf greetd.tar.gz
cd "greetd-v${VERSION}"

# Build greetd with musl
RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=yes" \
cargo build --release --target x86_64-unknown-linux-musl

mkdir -p "${OUT_DIR}/greetd/usr/bin"
cp target/x86_64-unknown-linux-musl/release/greetd "${OUT_DIR}/greetd/usr/bin/"
cp target/x86_64-unknown-linux-musl/release/agreety "${OUT_DIR}/greetd/usr/bin/" 2>/dev/null || true

echo "Done: ${OUT_DIR}/greetd"
