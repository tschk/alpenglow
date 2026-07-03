#!/bin/sh
# Build a tiny x86_64 kernel with the FAST initramfs embedded.
# Usage: build-kernel-fast.sh <out-dir> <repo-root>
set -eu

OUT_DIR="${1:?out-dir}"
ROOT_DIR="${2:?repo-root}"
OUT_DIR="$(CDPATH='' cd -- "${OUT_DIR}" && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${ROOT_DIR}" && pwd)"
BACKEND="${ROOT_DIR}/system/backends/appliance"
BOOT_NATIVE="${ROOT_DIR}/scripts/boot-native.sh"
KERNEL_VERSION="${KERNEL_VERSION:-$(grep -E '^KERNEL_VERSION="\${KERNEL_VERSION:-' "${BOOT_NATIVE}" | sed -n 's/.*KERNEL_VERSION:-\([0-9.]*\).*/\1/p')}"
KERNEL_TAR="linux-${KERNEL_VERSION}"
VMLINUZ="${OUT_DIR}/vmlinuz"
INITRAMFS="${OUT_DIR}/initramfs.cpio.lz4"
STAMP="${OUT_DIR}/.kernel-fast.ok"

if [ -f "${STAMP}" ] && [ -f "${VMLINUZ}" ] && [ -f "${INITRAMFS}" ] && [ "${VMLINUZ}" -nt "${INITRAMFS}" ]; then
  echo "  kernel: ${VMLINUZ} (cached, newer than initramfs)"
  exit 0
fi

if [ ! -f "${INITRAMFS}" ]; then
  echo "ERROR: ${INITRAMFS} not found. Build the initramfs first." >&2
  exit 1
fi

echo "→ Building FAST kernel with embedded initramfs (Linux ${KERNEL_VERSION})..."

docker run --rm --platform linux/amd64 \
  -v "${OUT_DIR}:/out" \
  -v "${BACKEND}/kernel:/kcfg:ro" \
  debian:bookworm-slim sh -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev \
      libncurses-dev dwarves rsync kmod wget xz-utils ca-certificates lz4 >/dev/null
    cd /out
    if [ ! -d "'"${KERNEL_TAR}"'" ]; then
      wget -q "https://cdn.kernel.org/pub/linux/kernel/v7.x/'"${KERNEL_TAR}"'.tar.xz" -O k.tar.xz
      tar -xf k.tar.xz
    fi
    cd "'"${KERNEL_TAR}"'"
    cp /kcfg/alpenglow-qemu-minimal.config .config
    cat /kcfg/lz4.config >> .config 2>/dev/null || true
    cat /kcfg/virt.config >> .config 2>/dev/null || true
    cat /kcfg/fast.config >> .config 2>/dev/null || true
    make ARCH=x86_64 olddefconfig >/dev/null 2>&1
    ./scripts/config --disable OBJTOOL --disable STACK_VALIDATION --disable UNWINDER_ORC 2>/dev/null || true
    # Aggressive FAST-only disables that olddefconfig would otherwise re-enable
    ./scripts/config --disable DRM --disable DRM_BRIDGE --disable DRM_PANEL --disable DRM_PANEL_ORIENTATION_QUIRKS --disable DRM_VIRTIO_GPU \
      --disable SOUND --disable SND \
      --disable USB --disable USB_SUPPORT --disable USB_COMMON --disable USB_XHCI_HCD --disable USB_EHCI_HCD --disable USB_UHCI_HCD \
      --disable HID_SUPPORT --disable HID \
      --disable KALLSYMS --disable KALLSYMS_BASE_RELATIVE --disable KALLSYMS_SELFTEST \
      --disable PERF_EVENTS --disable PERF_EVENTS_INTEL_UNCORE --disable PERF_EVENTS_INTEL_RAPL --disable PERF_EVENTS_INTEL_CSTATE \
      --disable BPF --disable BPF_SYSCALL --disable BPF_JIT --disable BPF_LSM --disable BPF_EVENTS --disable BPF_STREAM_PARSER \
      --disable FTRACE --disable TRACING --disable KPROBES --disable UPROBES \
      --disable DEBUG_KERNEL --disable DEBUG_MISC --disable DEBUG_FS --disable DEBUG_BUGVERBOSE --disable DEBUG_LIST --disable DEBUG_SG --disable DEBUG_NOTIFIERS --disable DEBUG_CREDENTIALS --disable DEBUG_ATOMIC_SLEEP \
      --disable SLUB_DEBUG --disable SLUB_DEBUG_ON --disable MAGIC_SYSRQ --disable PRINTK_TIME --disable DYNAMIC_DEBUG --disable DYNAMIC_DEBUG_CORE \
      --disable HUGETLBFS --disable TRANSPARENT_HUGEPAGE --disable HUGETLB_PAGE \
      --disable IPV6 \
      --disable SCSI --disable SCSI_MOD --disable SCSI_COMMON --disable ATA --disable SATA_AHCI --disable PATA_MPIIX --disable PATA_NS87410 --disable PATA_AMD --disable PATA_ARTOP --disable PATA_ATIIXP --disable PATA_ATP867X --disable PATA_CMD64X --disable PATA_EFAR --disable PATA_HPT366 --disable PATA_HPT37X --disable PATA_HPT3X3 --disable PATA_IT8213 --disable PATA_IT821X --disable PATA_JMICRON --disable PATA_MARVELL --disable PATA_NETCELL --disable PATA_NINJA32 --disable PATA_NS87415 --disable PATA_OLDPIIX --disable PATA_OPTIDMA --disable PATA_PDC2027X --disable PATA_PDC_OLD --disable PATA_RADISYS --disable PATA_RDC --disable PATA_SC1200 --disable PATA_SCH --disable PATA_SERVERWORKS --disable PATA_SIL680 --disable PATA_SIS --disable PATA_TOSHIBA --disable PATA_TRIFLEX --disable PATA_VIA --disable PATA_WINBOND \
      --disable FUSE_FS --disable CUSE --disable VIRTIO_FS \
      --disable NVME_CORE --disable NVME_FABRICS --disable NVME_AUTH --disable NVME_MULTIPATH --disable NVME_HWMON \
      --disable NETFILTER --disable NETFILTER_ADVANCED --disable NF_CONNTRACK --disable NF_TABLES --disable IP_NF_IPTABLES --disable IP_NF_FILTER --disable IP_NF_NAT --disable IP_NF_MANGLE --disable IP_NF_RAW --disable BRIDGE_NF_EBTABLES \
      --disable NET_SCHED --disable NET_CLS --disable NET_EMATCH --disable NET_CLS_ACT --disable STP --disable LLC --disable BRIDGE \
      --disable WIRELESS --disable CFG80211 --disable MAC80211 \
      --disable CIFS --disable CIFS_SMB2 --disable CIFS_SMB311 --disable CIFS_DFS_UPCALL --disable CIFS_FSCACHE --disable CIFS_SWN_UPCALL \
      --disable NFS_FS --disable NFS_V2 --disable NFS_V3 --disable NFS_V4 --disable SUNRPC --disable SUNRPC_GSS --disable SUNRPC_BACKCHANNEL --disable SUNRPC_SWAP \
      --disable 9P_FS --disable 9P_FSCACHE --disable 9P_FS_POSIX_ACL --disable 9P_FS_SECURITY \
      --disable AFS_FS --disable OCFS2_FS --disable GFS2_FS --disable REISERFS_FS --disable JFS_FS --disable XFS_FS --disable BTRFS_FS --disable NILFS2_FS --disable F2FS_FS --disable NTFS_FS --disable NTFS3_FS --disable EXFAT_FS --disable VFAT_FS --disable MSDOS_FS --disable FAT_FS --disable ISO9660_FS --disable UDF_FS --disable ROMFS_FS --disable MINIX_FS --disable QNX4FS_FS --disable QNX6FS_FS \
      --disable INTEGRITY --disable INTEGRITY_SIGNATURE --disable IMA --disable IMA_MEASURE_PCR_IDX --disable IMA_NG_TEMPLATE --disable IMA_SIG_TEMPLATE --disable IMA_DEFAULT_HASH_SHA256 --disable IMA_DEFAULT_HASH_SHA512 --disable IMA_READ_POLICY --disable IMA_WRITE_POLICY --disable IMA_APPRAISE --disable IMA_APPRAISE_BOOTPARAM --disable IMA_APPRAISE_MODSIG --disable IMA_TRUSTED_KEYRING --disable IMA_KEYRINGS_PERMIT_SIGNED_BY_BUILTIN --disable IMA_MEASURE_ASYMMETRIC_KEYS --disable IMA_QUEUE_EARLY_BOOT_KEYS --disable IMA_SECURE_AND_OR_TRUSTED_BOOT --disable IMA_BLACKLIST_KEYRING --disable EVM --disable EVM_ATTR_FSUUID --disable EVM_ADD_XATTRS --disable EVM_LOAD_X509 --disable EVM_X509_PATH \
      --disable AUDIT --disable AUDITSYSCALL --disable AUDIT_WATCH --disable AUDIT_TREE \
      --disable SECURITY_SELINUX --disable SECURITY_SELINUX_DISABLE --disable SECURITY_SELINUX_BOOTPARAM --disable SECURITY_APPARMOR --disable SECURITY_SMACK --disable SECURITY_TOMOYO --disable SECURITY_LANDLOCK --disable SECURITY_LOCKDOWN_LSM --disable SECURITY_LOCKDOWN_LSM_EARLY \
      --disable KEYS --disable KEYS_REQUEST_CACHE --disable PERSISTENT_KEYRINGS --disable TRUSTED_KEYS --disable ENCRYPTED_KEYS --disable KEY_DH_OPERATIONS \
      --disable ASYMMETRIC_KEY_TYPE --disable ASYMMETRIC_PUBLIC_KEY_SUBTYPE --disable X509_CERTIFICATE_PARSER --disable PKCS7_MESSAGE_PARSER --disable PKCS8_PRIVATE_KEY_PARSER --disable SYSTEM_BLACKLIST_KEYRING --disable SYSTEM_DATA_VERIFICATION \
      --disable MODULE_SIG --disable MODULE_SIG_ALL --disable MODULE_SIG_SHA256 --disable MODULE_SIG_FORCE --disable MODULE_SIG_VERIFY \
      --disable CRYPTO_USER --disable CRYPTO_USER_API --disable CRYPTO_USER_API_HASH --disable CRYPTO_USER_API_SKCIPHER --disable CRYPTO_USER_API_RNG --disable CRYPTO_USER_API_AEAD --disable CRYPTO_STATS --disable CRYPTO_DH --disable CRYPTO_ECDH --disable CRYPTO_ECRDSA --disable CRYPTO_SM2 --disable CRYPTO_CURVE25519 --disable CRYPTO_MANAGER_DISABLE_TESTS --disable CRYPTO_GF128MUL --disable CRYPTO_NULL --disable CRYPTO_CRYPTD --disable CRYPTO_AUTHENC --disable CRYPTO_TEST --disable CRYPTO_RSA --disable CRYPTO_DH --disable CRYPTO_ECC --disable ECDH --disable CRYPTO_ECDSA --disable CRYPTO_ECRDSA --disable CRYPTO_SM2 --disable CRYPTO_CURVE25519 --disable CRYPTO_LIB_POLY1305_GENERIC --disable CRYPTO_LIB_CHACHA20POLY1305 --disable CRYPTO_CHACHA20POLY1305 --disable CRYPTO_AEGIS128 --disable CRYPTO_SEQIV --disable CRYPTO_ECHAINIV --disable CRYPTO_MD4 --disable CRYPTO_MD5 --disable CRYPTO_RMD160 --disable CRYPTO_SHA1 --disable CRYPTO_SHA512 --disable CRYPTO_SHA3 --disable CRYPTO_SM3 --disable CRYPTO_STREEBOG --disable CRYPTO_WP512 --disable CRYPTO_BLAKE2B --disable CRYPTO_BLAKE2S --disable CRYPTO_GHASH --disable CRYPTO_POLY1305 --disable CRYPTO_DEFLATE --disable CRYPTO_LZO --disable CRYPTO_LZ4 --disable CRYPTO_LZ4HC --disable CRYPTO_ZSTD --disable CRYPTO_ANUBIS --disable CRYPTO_ARC4 --disable CRYPTO_BLOWFISH --disable CRYPTO_CAMELLIA --disable CRYPTO_CAST5 --disable CRYPTO_CAST6 --disable CRYPTO_DES --disable CRYPTO_FCRYPT --disable CRYPTO_KHAZAD --disable CRYPTO_SALSA20 --disable CRYPTO_CHACHA20 --disable CRYPTO_SEED --disable CRYPTO_SERPENT --disable CRYPTO_SM4 --disable CRYPTO_TEA --disable CRYPTO_TWOFISH --disable CRYPTO_ADIANTUM --disable CRYPTO_ESSIV --disable CRYPTO_NHPOLY1305 --disable CRYPTO_USER_API_RNG --disable CRYPTO_USER_API_AEAD --disable CRYPTO_DEV_PADLOCK --disable CRYPTO_DEV_PADLOCK_AES --disable CRYPTO_DEV_PADLOCK_SHA --disable CRYPTO_DEV_CCP --disable CRYPTO_DEV_CCP_DD --disable CRYPTO_DEV_SP_CCP --disable CRYPTO_DEV_SP_PSP --disable CRYPTO_DEV_QAT --disable CRYPTO_DEV_QAT_DH895xCC --disable CRYPTO_DEV_QAT_C3XXX --disable CRYPTO_DEV_QAT_C62X --disable CRYPTO_DEV_QAT_4XXX --disable CRYPTO_DEV_QAT_C4XXX --disable CRYPTO_DEV_CHELSIO --disable CRYPTO_DEV_VIRTIO --disable CRYPTO_DEV_SAFEXCEL --disable CRYPTO_DEV_AMLOGIC_GXL --disable CRYPTO_DEV_KEEMBAY --disable CRYPTO_DEV_INTEL_IAA \
      --disable COREDUMP \
      2>/dev/null || true
    make ARCH=x86_64 olddefconfig >/dev/null 2>&1
    echo "→ compiling bzImage (this can take several minutes)..."
    make -j"$(nproc)" ARCH=x86_64 bzImage
    cp arch/x86/boot/bzImage /out/vmlinuz
    touch /out/.kernel-fast.ok
  '

echo "  kernel: ${VMLINUZ}"
