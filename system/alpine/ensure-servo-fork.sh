#!/bin/bash
# Ensure Soliloquy Rust binaries are built (placeholder for Rust build)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Ensuring Soliloquy Rust binaries are built..."

cd "${PROJECT_ROOT}"

# Build Rust binaries for musl target
echo "Building soliloquy_shell..."
cargo build --release --target x86_64-unknown-linux-musl --bin soliloquy_shell

echo "Building sold..."
cargo build --release --target x86_64-unknown-linux-musl --bin sold

echo "Rust binaries built successfully."
