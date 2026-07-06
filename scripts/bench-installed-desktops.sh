#!/bin/sh
set -eu

BASE="${BASE:-$PWD/build/installed-desktop-bench}"
ROOTS="${BASE}/roots"
IMAGES="${BASE}/images"
LOGS="${BASE}/logs"
MEMORY_MB="${MEMORY_MB:-4096}"

mkdir -p "${ROOTS}" "${IMAGES}" "${LOGS}"

docker_prepare() {
  name="$1"
  image="$2"
  install="$3"
  root="${ROOTS}/${name}"
  [ -d "${root}/boot" ] && return 0

  rm -rf "${root}"
  mkdir -p "${root}"
  cid="$(docker create "${image}" /bin/sh -c 'sleep 3600')"
  docker start "${cid}" >/dev/null
  docker exec "${cid}" /bin/sh -lc "${install}" >&2
  docker export "${cid}" | sudo tar -xpf - -C "${root}"
  docker rm -f "${cid}" >/dev/null

  sudo mkdir -p \
    "${root}/etc/systemd/system/getty.target.wants" \
    "${root}/etc/systemd/system/multi-user.target.wants"
  if [ -e "${root}/lib/systemd/system/serial-getty@.service" ]; then
    sudo ln -sf /lib/systemd/system/serial-getty@.service "${root}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
  elif [ -e "${root}/usr/lib/systemd/system/serial-getty@.service" ]; then
    sudo ln -sf /usr/lib/systemd/system/serial-getty@.service "${root}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
  fi
  sudo sh -c "cat > '${root}/etc/systemd/system/alpenglow-bench-report.service'" <<'UNIT'
[Unit]
Description=Alpenglow benchmark serial report

[Service]
Type=simple
ExecStart=/bin/sh -c 'while :; do echo BENCH_MEM >/dev/ttyS0; grep -E "MemTotal|MemFree" /proc/meminfo >/dev/ttyS0; sleep 0.2; done'

[Install]
WantedBy=multi-user.target
UNIT
  sudo ln -sf /etc/systemd/system/alpenglow-bench-report.service "${root}/etc/systemd/system/multi-user.target.wants/alpenglow-bench-report.service"
  sudo ln -sf /lib/systemd/system/graphical.target "${root}/etc/systemd/system/default.target" 2>/dev/null || \
    sudo ln -sf /usr/lib/systemd/system/graphical.target "${root}/etc/systemd/system/default.target" 2>/dev/null || true
  sudo truncate -s 0 "${root}/etc/machine-id" 2>/dev/null || true
  sudo chmod a+r "${root}"/boot/* "${root}"/usr/lib/modules/*/vmlinuz 2>/dev/null || true
}

make_image() {
  name="$1"
  size="${2:-18G}"
  root="${ROOTS}/${name}"
  img="${IMAGES}/${name}.img"
  [ -f "${img}" ] && return 0

  qemu-img create -f raw "${img}" "${size}" >/dev/null
  mkfs.ext4 -q -F "${img}"
  mnt="${BASE}/mnt-${name}"
  mkdir -p "${mnt}"
  sudo mount -o loop "${img}" "${mnt}"
  sudo cp -a "${root}/." "${mnt}/"
  sudo umount "${mnt}"
  rmdir "${mnt}"
}

latest_kernel() {
  ls "$1"/boot/vmlinuz-* "$1"/usr/lib/modules/*/vmlinuz 2>/dev/null | sort -V | tail -1
}

latest_initrd() {
  ls "$1"/boot/initrd.img "$1"/boot/initrd.img-* "$1"/boot/initramfs-*.img 2>/dev/null | sort -V | tail -1
}

measure() {
  label="$1"
  name="$2"
  root="${ROOTS}/${name}"
  img="${IMAGES}/${name}.img"
  kernel="$(latest_kernel "${root}")"
  initrd="$(latest_initrd "${root}")"
  serial="${LOGS}/${name}.serial.log"
  qlog="${LOGS}/${name}.qemu.log"
  rm -f "${serial}" "${qlog}"

  start="$(date +%s%N)"
  qemu-system-x86_64 \
    -machine q35,accel=kvm -cpu host \
    -m "${MEMORY_MB}" -smp 2 -display none -no-reboot \
    -device virtio-gpu-pci -drive file="${img}",format=raw,if=virtio \
    -serial file:"${serial}" -monitor none \
    -kernel "${kernel}" -initrd "${initrd}" \
    -append "root=/dev/vda rw quiet console=ttyS0 systemd.unit=graphical.target" \
    >"${qlog}" 2>&1 &
  pid="$!"

  found=0
  login_grace=50
  n=900
  while kill -0 "${pid}" 2>/dev/null; do
    if grep -q "Reached target .*graphical.target\\|Reached target .*Graphical Interface" "${serial}" 2>/dev/null; then
      found=1
      break
    fi
    if grep -q "login:" "${serial}" 2>/dev/null; then
      login_grace="$((login_grace - 1))"
      if [ "${login_grace}" -le 0 ]; then
        found=login
        break
      fi
    fi
    sleep 0.2
    n="$((n - 1))"
    [ "${n}" -le 0 ] && break
  done

  end="$(date +%s%N)"
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  ms="$(((end - start) / 1000000))"
  total="$(awk '/MemTotal:/ {value=$2} END {print value}' "${serial}" 2>/dev/null || true)"
  free="$(awk '/MemFree:/ {value=$2} END {print value}' "${serial}" 2>/dev/null || true)"
  used="?"
  [ -n "${total:-}" ] && [ -n "${free:-}" ] && used="$(((total - free) / 1024))"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${label}" "${found}" "${ms}" "$(du -h "${img}" | awk '{print $1}')" "${used}" "${kernel}"
}

ubuntu_install='export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y --no-install-recommends linux-generic initramfs-tools systemd-sysv dbus gdm3 gnome-shell gnome-session ubuntu-session xserver-xorg-core xserver-xorg-video-all xserver-xorg-input-all network-manager sudo ca-certificates; apt-get clean; rm -rf /var/lib/apt/lists/*'
fedora_install='dnf -y install kernel-core systemd dbus gdm gnome-shell gnome-session-wayland-session xorg-x11-server-Xorg xorg-x11-drv-libinput NetworkManager sudo; dnf clean all'
manjaro_install='pacman -Sy --noconfirm archlinux-keyring manjaro-keyring || true; pacman -Syu --noconfirm; pacman -S --noconfirm linux618 systemd dbus lightdm lightdm-gtk-greeter mkinitcpio exo garcon thunar thunar-volman tumbler xfce4-appfinder xfce4-panel xfce4-power-manager xfce4-session xfce4-settings xfce4-terminal xfconf xfdesktop xfwm4 xorg-server xf86-video-vesa xf86-input-libinput networkmanager sudo'

docker_prepare ubuntu ubuntu:24.04 "${ubuntu_install}"
docker_prepare fedora fedora:43 "${fedora_install}"
docker_prepare manjaro manjarolinux/base:latest "${manjaro_install}"
make_image ubuntu 18G
make_image fedora 18G
make_image manjaro 18G
measure "Ubuntu minimal GNOME" ubuntu
measure "Fedora minimal GNOME" fedora
measure "Manjaro minimal XFCE" manjaro
