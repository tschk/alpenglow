#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "usage: $0 path/to/release-x86_64.img.zst" >&2
  exit 2
fi

echo 'NOTE: This boot gate does not verify the build host FAT assembly path.'
echo 'NOTE: Experimental FUSE FAT assembly is not verified for release reproducibility.'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
zstd -dc -- "$1" > "$tmp/disk.img"

python3 - "$tmp" <<'PY'
import os
import re
import secrets
import socket
import subprocess
import sys
import time

tmp = sys.argv[1]
firmware = '/usr/share/OVMF/OVMF_CODE.fd'
if not os.path.isfile(firmware):
    sys.exit('missing OVMF firmware: ' + firmware)

def run_boot(name, args, serial, command, token, boot):
    log = bytearray()
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    deadline = time.monotonic() + 240
    stage = 'connect serial'
    try:
        while True:
            if proc.poll() is not None:
                raise RuntimeError('QEMU exited before the check completed')
            if time.monotonic() >= deadline:
                raise RuntimeError('timed out waiting for ' + stage)
            try:
                conn.connect(serial)
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.1)
        conn.settimeout(0.5)
        stage = 'login prompt'
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise RuntimeError('QEMU exited while waiting for ' + stage)
            try:
                data = conn.recv(65536)
            except socket.timeout:
                continue
            if not data:
                raise RuntimeError('serial connection closed while waiting for ' + stage)
            log.extend(data)
            if stage == 'login prompt' and b'login:' in log and b'[  OK  ] boot' in log:
                conn.sendall(b'root\n')
                stage = 'root shell prompt'
                log.clear()
            elif stage == 'root shell prompt' and re.search(rb'(?m)(?:^|\n)[^\r\n]*[#$] $', log):
                conn.sendall(command.encode())
                stage = 'bcachefs mount and write verification'
                log.clear()
            elif stage == 'bcachefs mount and write verification' and token.encode() in log:
                if boot == 0:
                    print(name + ': writable bcachefs /state and marker verified; rebooting', flush=True)
                    conn.sendall(b'/bin/busybox reboot -f\n')
                    try:
                        status = proc.wait(timeout=120)
                    except subprocess.TimeoutExpired:
                        raise RuntimeError('timed out waiting for guest reboot')
                    if status != 0:
                        raise RuntimeError('QEMU exited with status ' + str(status) + ' during reboot')
                else:
                    print(name + ': marker persisted across reboot and was removed', flush=True)
                break
        else:
            raise RuntimeError('timed out waiting for ' + stage)
    except Exception as exc:
        print(name + ': ' + str(exc), file=sys.stderr)
        print(log.decode(errors='replace')[-20000:], file=sys.stderr)
        raise SystemExit(1)
    finally:
        conn.close()
        if proc.poll() is None:
            proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        errors = proc.stderr.read().decode(errors='replace')
        if errors:
            print(errors, file=sys.stderr)

for name in ('seabios', 'ovmf'):
    serial = os.path.join(tmp, name + '.sock')
    overlay = os.path.join(tmp, name + '.qcow2')
    subprocess.run(['qemu-img', 'create', '-q', '-f', 'qcow2', '-F', 'raw',
                    '-b', os.path.join(tmp, 'disk.img'), overlay], check=True)
    marker = 'ALPENGLOW_STATE_' + secrets.token_hex(16)
    path = '/state/.release-boot-test-' + secrets.token_hex(16)
    token = 'ALPENGLOW_RELEASE_OK_' + secrets.token_hex(16)
    mount_check = (
        "/bin/busybox awk '$2 == \"/state\" && $3 == \"bcachefs\" && "
        "$4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts && test -d /state"
    )
    success = " && printf '%s%s\\n' '" + token[:20] + "' '" + token[20:] + "'\n"
    commands = [
        mount_check + " && ( umask 077; printf '%s\\n' '" + marker + "' > '" + path + "' )"
        + " && test \"$(cat '" + path + "')\" = '" + marker + "' && /bin/busybox sync" + success,
        mount_check + " && test \"$(cat '" + path + "')\" = '" + marker + "'"
        + " && rm -f '" + path + "' && /bin/busybox sync" + success,
    ]
    args = [
        'qemu-system-x86_64', '-machine', 'q35', '-m', '768', '-smp', '2',
        '-display', 'none', '-monitor', 'none', '-no-reboot',
        '-serial', 'unix:' + serial + ',server=on,wait=off',
        '-drive', 'file=' + overlay + ',format=qcow2,if=virtio',
    ]
    if name == 'ovmf':
        args += ['-bios', firmware]
    for boot, command in enumerate(commands):
        print('Booting ' + name + (' (initial)' if boot == 0 else ' (after reboot)'), flush=True)
        if os.path.exists(serial):
            os.unlink(serial)
        run_boot(name, args, serial, command, token, boot)
PY
