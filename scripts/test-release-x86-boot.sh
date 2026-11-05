#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
  echo "usage: $0 path/to/release-x86_64.img.zst" >&2
  exit 2
fi

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

for name in ('seabios', 'ovmf'):
    serial = os.path.join(tmp, name + '.sock')
    log = bytearray()
    token = 'ALPENGLOW_RELEASE_OK_' + secrets.token_hex(16)
    command = (
        "/bin/busybox awk '$2 == \"/state\" && $3 == \"bcachefs\" && "
        "$4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts"
        " && test -d /state && f=/state/.release-boot-test-$$"
        " && ( umask 077; echo test > \"$f\" ) && test \"$(cat \"$f\")\" = test"
        " && rm -f \"$f\" && printf '%s%s\\n' '" + token[:20] + "' '" + token[20:] + "'\n"
    )
    args = [
        'qemu-system-x86_64', '-machine', 'q35', '-m', '2048', '-smp', '2',
        '-display', 'none', '-monitor', 'none', '-no-reboot', '-snapshot',
        '-serial', 'unix:' + serial + ',server=on,wait=off',
        '-drive', 'file=' + os.path.join(tmp, 'disk.img') + ',format=raw,if=virtio',
    ]
    if name == 'ovmf':
        args += ['-bios', firmware]
    print('Booting ' + name, flush=True)
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
                print(name + ': root shell and writable bcachefs /state verified', flush=True)
                break
        else:
            raise RuntimeError('timed out waiting for ' + stage)
    except Exception as exc:
        print(name + ': ' + str(exc), file=sys.stderr)
        print(log.decode(errors='replace')[-20000:], file=sys.stderr)
        raise SystemExit(1)
    finally:
        conn.close()
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        errors = proc.stderr.read().decode(errors='replace')
        if errors:
            print(errors, file=sys.stderr)
PY
