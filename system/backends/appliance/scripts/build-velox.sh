#!/bin/sh
# Build velox (Wayland compositor) from source as static musl binary
set -eu

OUT_DIR="${1:-/tmp/out}"

echo "→ Building velox..."

cd /tmp
git clone --depth=1 https://github.com/velox-rs/velox.git velox-src
cd velox-src

RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=yes" \
cargo build --release --target x86_64-unknown-linux-musl

mkdir -p "${OUT_DIR}/velox/usr/bin"
cp target/x86_64-unknown-linux-musl/release/velox "${OUT_DIR}/velox/usr/bin/"

echo "Done: ${OUT_DIR}/velox"
