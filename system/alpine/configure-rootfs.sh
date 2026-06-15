#!/bin/bash
# Configure rootfs with Alpenglow overlay
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK_DIR="${PROJECT_ROOT}/build/alpine"
ROOTFS_DIR="${WORK_DIR}/rootfs"

echo "Configuring rootfs with Alpenglow overlay..."

cd "${ROOTFS_DIR}"

# Create Alpenglow directories
mkdir -p var/lib/alpenglow
mkdir -p var/log/alpenglow
mkdir -p tmp

# Configure OpenRC
echo "Configuring OpenRC..."

# Disable unnecessary services
rc-update del hwdrivers default || true
rc-update del acpid default || true
rc-update del crond default || true

# Add Alpenglow services
cp "${SCRIPT_DIR}/openrc/seatd" etc/init.d/

chmod +x etc/init.d/seatd

rc-update add seatd default

# Configure networking (static)
cat > etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
EOF

# Disable getty
sed -i 's/^tty/#tty/' etc/inittab

# Set init to OpenRC
echo "openrc" > etc/init

# Configure kernel cmdline for direct boot
cat > etc/kernel/cmdline << 'EOF'
console=ttyS0 root=/dev/vda ro init=/sbin/openrc-init
EOF

# Security hardening
echo "Applying security hardening..."

# Disable VT switching
echo "vt.global_cursor_default=1" >> etc/sysctl.conf
echo "kernel.vt_switch=0" >> etc/sysctl.conf

# Mount options
cat > etc/fstab << 'EOF'
/dev/vda / squashfs ro,noexec,nosuid,nodev 0 0
tmpfs /tmp tmpfs rw,nosuid,nodev,size=100M 0 0
tmpfs /var/log tmpfs rw,nosuid,nodev,size=50M 0 0
EOF

echo "Rootfs configured."
