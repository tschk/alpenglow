#!/bin/sh
# QEMU x86_64 boot for boot-native.sh / build/native artifacts.
# Expects KERNEL_IMAGE, INITRAMFS, OUT_DIR, and boot-native env (EFI, GRAPHICAL, FAST, …).
set -eu

qemu_boot_x86_64() {
  require_cmd qemu-system-x86_64
  echo "→ Booting Alpenglow..."
  echo "  kernel:    ${KERNEL_IMAGE}"
  echo "  initramfs: ${INITRAMFS}"
  echo "  mode:      ${BOOT_MODE}"
  echo "  efi:       ${EFI}"
  if [ "${GRAPHICAL}" = "1" ]; then
    echo "  display:   graphical (virtio-gpu)"
  fi
  echo "  (Ctrl-A X to quit)"
  echo ""

  if [ "${GRAPHICAL}" = "1" ]; then
  # Pick a display backend available on this host
    QEMU_DISPLAY="${QEMU_DISPLAY:-}"
    if [ -z "${QEMU_DISPLAY}" ]; then
      for backend in gtk sdl cocoa; do
        if timeout 2 qemu-system-x86_64 -display ${backend},show-cursor=off -M none </dev/null >/dev/null 2>&1; then
          QEMU_DISPLAY="${backend}"
          break
        fi
      done
    fi
    QEMU_DISPLAY="${QEMU_DISPLAY:-none}"
    QEMU_OPTS="-machine ${QEMU_MACHINE},accel=${ACCEL} -m ${MEMORY_MB} -smp 2 -no-reboot"
    if [ "${QEMU_DISPLAY}" = "none" ]; then
      QEMU_OPTS="${QEMU_OPTS} -display none"
    else
      QEMU_OPTS="${QEMU_OPTS} -display ${QEMU_DISPLAY}"
    fi
    if [ -f "${KERNEL_VIRT_STAMP}" ]; then
      QEMU_OPTS="${QEMU_OPTS} -device virtio-gpu-pci"
    else
      QEMU_OPTS="${QEMU_OPTS} -vga std"
    fi
    QEMU_OPTS="${QEMU_OPTS} -chardev stdio,id=char0,mux=on,signal=off -serial chardev:char0 -mon chardev=char0 -boot order=n -device e1000,romfile=,netdev=net0 -netdev user,id=net0"
    KERNEL_CMDLINE="console=ttyS0 console=tty0 init=/init"
  else
    QEMU_OPTS="-machine ${QEMU_MACHINE},accel=${ACCEL} -m ${MEMORY_MB} -smp 2 -nographic -no-reboot"
    if [ -z "${QEMU_CPU}" ] && [ "${ACCEL}" = "kvm" ]; then
      QEMU_OPTS="${QEMU_OPTS} -cpu host"
    elif [ -n "${QEMU_CPU}" ]; then
      QEMU_OPTS="${QEMU_OPTS} -cpu ${QEMU_CPU}"
    fi
    QEMU_OPTS="${QEMU_OPTS} -boot order=n -device e1000,romfile=,netdev=net0 -netdev user,id=net0"
    KERNEL_CMDLINE="quiet console=ttyS0 init=/init"
  fi

  EMBEDDED_INITRAMFS=""
  if [ "${FAST}" = "1" ] && [ -f "${OUT_DIR}/.kernel-fast.ok" ] && [ "${KERNEL_IMAGE}" = "${OUT_DIR}/vmlinuz" ]; then
    EMBEDDED_INITRAMFS="1"
  fi

  if [ "${EFI}" = "1" ]; then
  # UEFI boot via OVMF pflash (available, but measured slower than SeaBIOS)
    OVMF_CODE=""
    for p in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/local/share/qemu/edk2-x86_64-code.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd /opt/homebrew/Cellar/qemu/*/share/qemu/edk2-x86_64-code.fd; do
      [ -f "$p" ] && { OVMF_CODE="$p"; break; }
    done
    if [ -n "${OVMF_CODE}" ]; then
      OVMF_VARS="${OUT_DIR}/ovmf-vars.fd"
      OVMF_VARS_TEMPLATE=""
      for p in \
        "${OVMF_CODE%CODE.fd}VARS.fd" \
        "${OVMF_CODE%CODE.4m.fd}VARS.4m.fd" \
        "$(dirname "${OVMF_CODE}")/edk2-x86_64-vars.fd" \
        /opt/homebrew/share/qemu/edk2-x86_64-vars.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/edk2/x64/OVMF_VARS.4m.fd; do
        [ -f "$p" ] && { OVMF_VARS_TEMPLATE="$p"; break; }
      done
      if [ -n "${OVMF_VARS_TEMPLATE}" ]; then
        cp "${OVMF_VARS_TEMPLATE}" "${OVMF_VARS}"
      elif [ ! -f "${OVMF_VARS}" ]; then
        cp "${OVMF_CODE}" "${OVMF_VARS}" 2>/dev/null || true
      fi
      if [ -n "${EMBEDDED_INITRAMFS}" ]; then
        exec qemu-system-x86_64 \
          ${QEMU_OPTS} \
          -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
          -drive if=pflash,format=raw,file="${OVMF_VARS}" \
          -kernel "${KERNEL_IMAGE}" \
          -append "${KERNEL_CMDLINE}"
      else
        exec qemu-system-x86_64 \
          ${QEMU_OPTS} \
          -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
          -drive if=pflash,format=raw,file="${OVMF_VARS}" \
          -kernel "${KERNEL_IMAGE}" \
          -initrd "${INITRAMFS}" \
          -append "${KERNEL_CMDLINE}"
      fi
    fi
    echo "  → OVMF not found, falling back to SeaBIOS"
  fi

  # Legacy BIOS boot
  if [ -n "${EMBEDDED_INITRAMFS}" ]; then
    exec qemu-system-x86_64 \
      ${QEMU_OPTS} \
      -kernel "${KERNEL_IMAGE}" \
      -append "${KERNEL_CMDLINE}"
  else
    exec qemu-system-x86_64 \
      ${QEMU_OPTS} \
      -kernel "${KERNEL_IMAGE}" \
      -initrd "${INITRAMFS}" \
      -append "${KERNEL_CMDLINE}"
  fi
}
