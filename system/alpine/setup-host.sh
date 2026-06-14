#!/bin/bash
# Setup host dependencies for Alpenglow Alpine appliance build
set -euo pipefail

echo "Setting up host for Alpenglow Alpine appliance build..."

# Check if running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macOS detected, installing macOS-specific deps..."

    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "Homebrew not found. Install from https://brew.sh/"
        exit 1
    fi

    # Install QEMU
    brew install qemu

    # Install Servo's macOS framework dependencies
    echo "Installing Servo framework dependencies..."
    brew install gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly

    echo "macOS setup complete."

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Linux detected, installing Linux-specific deps..."

    # Assume Ubuntu/Debian for now
    sudo apt update
    sudo apt install -y qemu-system-x86 qemu-utils squashfs-tools

    echo "Linux setup complete."

else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

# Common setup
echo "Installing common dependencies..."

# Install Rust if not present
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Install cross-compilation targets
rustup target add x86_64-unknown-linux-musl
rustup target add aarch64-unknown-linux-musl

echo "Host setup complete!"
echo "You can now run: ./scripts/build-rootfs.sh"