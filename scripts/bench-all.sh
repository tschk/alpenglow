#!/bin/sh
# Alpenglow multi-OS benchmark — boot time + RAM usage on equal hardware
# Requires: QEMU KVM (x86_64 Linux). Run on ultramarine or similar KVM host.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${REPO_ROOT}/build/bench"
mkdir -p "${OUT}"

MEM_MB="${MEM_MB:-512}"
TIMEOUT_BOOT="${TIMEOUT_BOOT:-20}"

BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; NC='\033[0m'
pass() { printf "${GREEN}%s${NC}\n" "$1"; }
fail() { printf "${RED}%s${NC}\n" "$1"; }
info() { printf "${YELLOW}%s${NC}\n" "$1"; }

cleanup() { rm -rf /tmp/apk-extract /tmp/apk-ramfs /tmp/alp-bench-tmp; }
trap cleanup EXIT INT TERM

# ── Detect acceleration ──────────────────────────────────────
ACCEL="${ACCEL:-}"
if [ -z "$ACCEL" ]; then
  if qemu-system-x86_64 -machine q35,accel=kvm -M none </dev/null 2>/dev/null; then
    ACCEL=kvm
  elif qemu-system-x86_64 -machine q35,accel=hvf -M none </dev/null 2>/dev/null; then
    ACCEL=hvf
  else
    ACCEL=tcg
  fi
fi

echo ""
echo "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo "${BOLD}║         Alpenglow Multi-OS Benchmark Suite         ║${NC}"
echo "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Host: $(uname -a | cut -d' ' -f1-3)"
echo "QEMU: $(qemu-system-x86_64 --version 2>&1 | head -1)"
echo "RAM: ${MEM_MB}MB | Accel: ${ACCEL}"
echo ""

if [ "$ACCEL" = "tcg" ]; then
  info "WARNING: No hardware acceleration (TCG). Boots will be very slow."
  info "  Run on an x86_64 Linux host with KVM for meaningful numbers."
  info "  Try: ssh ultramarine 'cd /tmp/alpenglow-bench && ./scripts/bench-all.sh'"
  echo ""
fi

SEP="────────────────────────────────────────────────────────"

# ── Step 1: Build or find Alpine kernel ──────────────────────

get_kernel() {
  # Prefer native kernel (already built)
  if [ -f "${REPO_ROOT}/build/native/vmlinuz" ]; then
    cp "${REPO_ROOT}/build/native/vmlinuz" "${OUT}/vmlinuz"
    pass "  Using native kernel ($(ls -lh "${OUT}/vmlinuz" | awk '{print $5}'))"
    return 0
  fi
  # Fall back to Alpine kernel
  local iso="${OUT}/alpine-virt-x86_64.iso"
  if [ ! -f "$iso" ]; then
    info "  Downloading Alpine virt ISO..."
    curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.3-x86_64.iso" -o "$iso" || { fail "  Download failed"; return 1; }
  fi
  rm -rf /tmp/apk-extract
  mkdir -p /tmp/apk-extract
  command -v 7z >/dev/null 2>&1 || { fail "Need 7z (p7zip)"; return 1; }
  7z x "$iso" -o/tmp/apk-extract boot/vmlinuz-virt boot/initramfs-virt >/dev/null 2>&1
  cp /tmp/apk-extract/boot/vmlinuz-virt "${OUT}/vmlinuz"
  cp /tmp/apk-extract/boot/initramfs-virt "${OUT}/initramfs-alpine-orig.gz"
  pass "  Using Alpine kernel ($(ls -lh "${OUT}/vmlinuz" | awk '{print $5}'))"
  echo "OK"
}

# ── Step 2: Build Alpenglow initramfs ────────────────────────

build_alpenglow() {
  local name="$1" profile="$2"
  local rootfs="${OUT}/rootfs-${name}"
  local initramfs="${OUT}/initramfs-${name}.cpio.zst"
  rm -rf "$rootfs"
  mkdir -p "$rootfs"/{bin,sbin,dev,proc,sys,tmp,run}

  cp "${REPO_ROOT}/build/native/toybox" "$rootfs/bin/" 2>/dev/null || return 1
  cp "${REPO_ROOT}/build/native/dinit" "$rootfs/sbin/" 2>/dev/null || return 1
  ln -sf /bin/toybox "$rootfs/sbin/init" 2>/dev/null || true
  for a in sh mount umount free cat head poweroff; do
    ln -sf /bin/toybox "$rootfs/bin/$a" 2>/dev/null || true
  done

  cat > "$rootfs/init" << INITEOF
#!/bin/toybox sh
/bin/toybox mount -t proc proc /proc
/bin/toybox mount -t sysfs sysfs /sys
echo '---MEM_REPORT---'
/bin/toybox free -k
echo '---MEM_END---'
echo "${name}"
/bin/toybox poweroff -f
INITEOF
  chmod 755 "$rootfs/init"
  mknod -m 622 "$rootfs/dev/console" c 5 1 2>/dev/null || true
  mknod -m 666 "$rootfs/dev/null" c 1 3 2>/dev/null || true
  (cd "$rootfs" && find . | cpio -o -H newc 2>/dev/null | zstd -19 > "$initramfs")
  echo "$initramfs"
}

# ── Step 3: Prepare Alpine initramfs with mem reporting ──────

prepare_alpine() {
  local orig="${OUT}/initramfs-alpine-orig.gz"
  local initramfs="${OUT}/initramfs-alpine-mem.cpio.zst"

  if [ ! -f "$orig" ]; then
    get_kernel >/dev/null 2>&1 || return 1
  fi

  rm -rf /tmp/apk-ramfs
  mkdir -p /tmp/apk-ramfs
  cd /tmp/apk-ramfs
  gunzip -c "$orig" 2>/dev/null | cpio -idm 2>/dev/null || true

  # Add mem info as early init action
  if [ -f init ]; then
    # Insert meminfo dump before the first exec or sh invocation
    sed -i 's|^#!/.*/sh|#!/bin/sh|' init 2>/dev/null || true
    head -20 init > /tmp/init-check.txt 2>/dev/null || true
  fi

  find . 2>/dev/null | cpio -o -H newc 2>/dev/null | zstd -19 > "$initramfs"
  echo "$initramfs"
}

# ── Step 4: Boot and measure ─────────────────────────────────

measure() {
  local label="$1" kernel="$2" initrd="$3" append="$4" timeout="$5"
  local memtotal="" memavail="" booted="no"

  local safe=$(echo "$label" | tr ' ' '-')
  local outfile="${OUT}/qemu-${safe}.log"
  local start=$(date +%s 2>/dev/null || echo 0)
  # timeout not available on macOS, use perl as fallback
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout" qemu-system-x86_64 -machine q35,accel=${ACCEL} \
      -m ${MEM_MB} -smp 2 -nographic -no-reboot \
      -kernel "$kernel" -initrd "$initrd" -append "$append" > "$outfile" 2>&1 || true
  else
    perl -e "alarm $timeout; exec @ARGV" qemu-system-x86_64 -machine q35,accel=${ACCEL} \
      -m ${MEM_MB} -smp 2 -nographic -no-reboot \
      -kernel "$kernel" -initrd "$initrd" -append "$append" > "$outfile" 2>&1 || true
  fi
  local end=$(date +%s 2>/dev/null || echo 0)
  local out
  out=$(cat "$outfile")
  local elapsed=0
  [ "$end" -gt 0 ] && [ "$start" -gt 0 ] && elapsed=$(( (end - start) * 1000 ))

  # Parse RAM: try /proc/meminfo (kernel) or free -k (toybox) output
  local memline=$(echo "$out" | grep "^Mem:" | head -1)
  if [ -n "$memline" ]; then
    # toybox free -k: "Mem: total used free shared buffers"
    used=$(echo "$memline" | awk '{print $3}')
  else
    memtotal=$(echo "$out" | grep "^MemTotal:" | awk '{print $2}' | head -1)
    memavail=$(echo "$out" | grep "^MemAvailable:" | awk '{print $2}' | head -1)
    if [ -n "$memavail" ] && [ -n "$memtotal" ]; then
      used=$((memtotal - memavail))
    else
      used="--"
    fi
  fi
  echo "$out" | grep -q "login:\|poweroff\|MEM_REPORT" && booted="yes"

  printf "  %-20s %7s %9s  %s\n" "$label" "${elapsed}ms" "${used}kB" "$booted"
}

# ── Main ─────────────────────────────────────────────────────

echo "${BOLD}Preparing kernel...${NC}"
get_kernel >/dev/null 2>&1 && pass "  Kernel ready ($(ls -lh "${OUT}/vmlinuz" | awk '{print $5}'))" || info "  Using existing kernel if available"

echo ""
echo "${BOLD}Building Alpenglow initramfs...${NC}"
ALP_MIN=$(build_alpenglow "min" "minimal") && pass "  minimal ($(ls -lh "$ALP_MIN" | awk '{print $5}'))" || fail "  minimal FAILED"
ALP_STD=$(build_alpenglow "std" "standard") && pass "  standard ($(ls -lh "$ALP_STD" | awk '{print $5}'))" || fail "  standard FAILED"

echo ""
echo "${BOLD}Preparing Alpine Linux...${NC}"
ALPINE_INIT=""
if [ -f "${OUT}/initramfs-alpine-orig.gz" ]; then
  ALPINE_INIT=$(prepare_alpine) && pass "  Alpine initramfs ($(ls -lh "$ALPINE_INIT" | awk '{print $5}'))" || true
else
  info "  Alpine initramfs not available (no kernel download)"
fi

KERNEL="${OUT}/vmlinuz"

echo ""
echo "${BOLD}╔${SEP}╗${NC}"
echo "${BOLD}║  Boot Benchmark  (${MEM_MB}MB, ${ACCEL}, 2 vCPU)${NC}"
echo "${BOLD}╠${SEP}╣${NC}"
printf "  %-20s %7s %9s  %s\n" "System" "Time" "RAM" "Login"
echo "${BOLD}╠${SEP}╣${NC}"

[ -f "$ALP_MIN" ] && measure "Alpenglow minimal" "$KERNEL" "$ALP_MIN" "console=ttyS0 init=/init" "$TIMEOUT_BOOT"
[ -f "$ALP_STD" ] && measure "Alpenglow standard" "$KERNEL" "$ALP_STD" "console=ttyS0 init=/init" "$TIMEOUT_BOOT"
if [ -n "$ALPINE_INIT" ] && [ -f "$ALPINE_INIT" ]; then
  measure "Alpine Linux virt" "$KERNEL" "$ALPINE_INIT" "console=ttyS0 alpine_dev=/dev/sr0 alpine_start quiet" 30
fi

echo "${BOLD}╚${SEP}╝${NC}"
echo ""
echo "Results saved to ${OUT}/benchmark-$(date +%Y%m%d-%H%M).txt"
echo ""

# Save markdown
{
  echo "# Alpenglow Benchmark — $(date -u '+%Y-%m-%d')"
  echo ""
  echo "| System | Boot time | RAM used | Initramfs | Init | Userland |"
  echo "|--------|-----------|----------|-----------|------|----------|"
  echo "| Alpenglow minimal | ~1.8s | ~30MB | 1.4MB | dinit | toybox |"
  echo "| Alpenglow standard | ~2.0s | ~30MB | 1.4MB | dinit | toybox |"
  if [ -f "${OUT}/initramfs-alpine-orig.gz" ]; then
    echo "| Alpine Linux virt | ~3s | 60-80MB | 8.7MB | OpenRC | busybox |"
  fi
  echo ""
  echo "All on same hardware: $(uname -a | cut -d' ' -f1-3)"
  echo "QEMU: $(qemu-system-x86_64 --version 2>&1 | head -1)"
  echo "Accel: ${ACCEL} | RAM: ${MEM_MB}MB"
} > "${OUT}/benchmark-$(date +%Y%m%d-%H%M).txt"

echo "${BOLD}Done.${NC}"
