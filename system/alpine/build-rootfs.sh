#!/bin/bash
# Build minimal Alpine rootfs for Alpenglow appliance
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Building minimal Alpine rootfs for Alpenglow..."

# Create working directory
WORK_DIR="${PROJECT_ROOT}/build/alpine"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Download Alpine minirootfs if not exists
ALPINE_VERSION="3.19"
ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/alpine-minirootfs-${ALPINE_VERSION}.0-x86_64.tar.gz"
ROOTFS_TAR="alpine-minirootfs.tar.gz"
ROOTFS_DIR="rootfs"

if [[ ! -f "${ROOTFS_TAR}" ]]; then
    echo "Downloading Alpine minirootfs..."
    curl -L "${ROOTFS_URL}" -o "${ROOTFS_TAR}"
fi

# Extract rootfs
if [[ ! -d "${ROOTFS_DIR}" ]]; then
    echo "Extracting rootfs..."
    mkdir -p "${ROOTFS_DIR}"
    tar -xzf "${ROOTFS_TAR}" -C "${ROOTFS_DIR}"
fi

# Setup apk in rootfs
echo "Setting up apk in rootfs..."
cp /etc/resolv.conf "${ROOTFS_DIR}/etc/"
mount -t proc proc "${ROOTFS_DIR}/proc"
mount -t sysfs sys "${ROOTFS_DIR}/sys"
mount --bind /dev "${ROOTFS_DIR}/dev"

# Install minimal packages
chroot "${ROOTFS_DIR}" /bin/sh -c "
    apk update
    apk add --no-cache \
        busybox \
        openrc \
        seatd \
        wlroots \
        cage \
        iproute2 \
        squashfs-tools \
        e2fsprogs \
        linux-headers
"

# Cleanup
umount "${ROOTFS_DIR}/dev"
umount "${ROOTFS_DIR}/sys"
umount "${ROOTFS_DIR}/proc"
rm "${ROOTFS_DIR}/etc/resolv.conf"

echo "Minimal rootfs built at: ${WORK_DIR}/${ROOTFS_DIR}"