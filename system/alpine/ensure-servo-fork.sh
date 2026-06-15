#!/bin/bash
# Ensure Alpenglow Rust binaries are built (placeholder for Rust build)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Ensuring Alpenglow Rust binaries are built..."

cd "${PROJECT_ROOT}"

# Build Rust binaries for musl target
echo "Building alpenglow_shell..."
cargo build --release --target x86_64-unknown-linux-musl --bin alpenglow_shell

echo "Rust binaries built successfully."
