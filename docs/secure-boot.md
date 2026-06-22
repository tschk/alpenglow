# Secure Boot Implementation Guide

## Overview

Alpenglow implements secure boot to ensure the integrity and authenticity of the boot chain from firmware to kernel. This prevents unauthorized code execution and maintains system security.

## Threat Model

Alpenglow's threat model follows standard operating system security principles:

- **Boot chain integrity**: Ensure each component is signed and verified
- **Kernel module verification**: Only signed kernel modules can be loaded
- **Root filesystem protection**: Immutable GlowFS prevents runtime modification
- **Package authenticity**: APK signature verification via Oil package manager

## Implementation Requirements

### 1. UEFI Secure Boot

Alpenglow uses UEFI Secure Boot with custom keys:

```bash
# Generate Secure Boot keys
openssl genrsa -out alpenglow-db.key 2048
openssl req -new -x509 -key alpenglow-db.key -out alpenglow-db.crt -days 3650
openssl genrsa -out alpenglow-kek.key 2048
openssl req -new -x509 -key alpenglow-kek.key -out alpenglow-kek.crt -days 3650

# Sign EFI binaries
sbsign --key alpenglow-db.key --cert alpenglow-db.crt --output limine-signed.efi limine.efi
```

### 2. Kernel Module Signing

All kernel modules must be signed:

```bash
# Generate module signing key
openssl genrsa -out module-signing.key 2048
openssl req -new -x509 -key module-signing.key -out module-signing.x509 -days 3650

# Sign kernel modules during build
scripts/sign-module alpenglow_core.ko module-signing.key module-signing.x509
scripts/sign-module glowfs.ko module-signing.key module-signing.x509
```

### 3. Kernel Configuration

Enable kernel module signing verification:

```bash
# System/backends/appliance/kernel/alpenglow-internet-appliance.config
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_SHA512=y
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
CONFIG_MODULE_SIG_HASH=y
CONFIG_DM_VERITY=y
CONFIG_DM_VERITY_FEC=y
```

### 4. Kernel Command Line

Secure boot kernel parameters:

```
BOOT_IMAGE=/boot/vmlinuz
initrd=/boot/initramfs
alpenglow.secure_boot=1
module.sig_enforce=1
root=UUID=<disk-uuid>
ro
```

## Build Integration

### Module Signing Script

Create `scripts/sign-modules.sh`:

```bash
#!/bin/bash
set -e

SIGNING_KEY="$1"
SIGNING_CERT="$2"
MODULE_DIR="$3"

for module in "$MODULE_DIR"/*.ko; do
    if [ -f "$module" ]; then
        echo "Signing $module"
        /usr/src/kernels/$(uname -r)/scripts/sign-file sha512 \
            "$SIGNING_KEY" "$SIGNING_CERT" "$module"
    fi
done
```

### Build Process Integration

Add to build scripts:

```bash
# After kernel module compilation
make modules
./scripts/sign-modules.sh module-signing.key module-signing.x509 system/glowfs/kernel
./scripts/sign-modules.sh module-signing.key module-signing.x509 system/kernel-modules
```

## Verification

### Verify Secure Boot Status

```bash
# Check if secure boot is enabled
mokutil --sb-state

# Verify kernel module signatures
modinfo alpenglow_core | grep Signer
modinfo glowfs | grep Signer

# Check kernel config
zcat /proc/config.gz | grep MODULE_SIG
```

### Verification Script

Create `scripts/verify-secure-boot.sh`:

```bash
#!/bin/bash
echo "Secure Boot Status:"
mokutil --sb-state

echo -e "\nKernel Module Signatures:"
for module in /lib/modules/$(uname -r)/extra/*.ko; do
    if [ -f "$module" ]; then
        modinfo "$module" | grep -q "Signer" && echo "✓ $module signed" || echo "✗ $module unsigned"
    fi
done
```

## Platform-Specific Notes

### UEFI vs BIOS

- **UEFI**: Full secure boot support with custom keys
- **BIOS**: Limited verification, recommend UEFI systems for production

### Cross-Compilation

When cross-compiling for different architectures:

```bash
# ARM64 secure boot
sbsign --key alpenglow-db.key --cert alpenglow-db.crt \
       --output limine-arm64-signed.efi limine-arm64.efi

# Verify signature across architectures
sbverify --cert alpenglow-db.crt limine-arm64-signed.efi
```

## Troubleshooting

### Module Loading Failures

If signed modules fail to load:

```bash
# Check dmesg for verification errors
dmesg | grep -i signature

# Verify module signature
modinfo --sigdump <module.ko> | openssl x509 -noout -pubkey

# Check kernel keyring
keyctl show %:.system_keyring
```

### Secure Boot Override

For development/testing only:

```bash
# Disable secure boot (requires physical access)
mokutil --disable-validation

# Re-enroll keys
mokutil --import alpenglow-db.crt
```

## Security Considerations

### Key Management

- Store private keys securely (HSM, TPM, or secure filesystem)
- Rotate keys annually or after key compromise
- Use separate keys for development vs production

### Chain of Trust

1. **UEFI firmware** → verifies bootloader signature
2. **Bootloader** → verifies kernel signature  
3. **Kernel** → verifies module signatures
4. **Kernel modules** → enforce system policies

### Revocation

Implement key revocation mechanism:

```bash
# Revoke compromised key
mokutil --revoke alpenglow-compromised.crt

# Update dbx (revocation list)
efi-updatevar -v dbx -c -d alpenglow-revoked.crt
```

## References

- [Linux Kernel Module Signing Documentation](https://www.kernel.org/doc/html/latest/admin-guide/module-signing.html)
- [UEFI Secure Boot Specification](https://uefi.org/specifications)
- [sbsign Tool Documentation](https://github.com/rhboot/sbsigntools)

## Status

- [ ] Generate secure boot keys
- [ ] Configure kernel for module signing
- [ ] Implement signing in build pipeline
- [ ] Add EFI binary signing
- [ ] Test secure boot chain
- [ ] Document key rotation procedure