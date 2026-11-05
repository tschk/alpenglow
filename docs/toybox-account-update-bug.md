# Toybox account-update file truncation

**Upstream report draft — not filed.** Do not run this reproduction against a real system or real account database.

## Summary

Toybox `passwd` can empty the entire credential file while reporting `Success`. In upstream 0.8.11, [`lib/password.c:133`](https://github.com/landley/toybox/blob/0.8.11/lib/password.c#L133) opens the existing file with `fopen(filename, "w+")` before locking or reading it. That open truncates the file immediately. The backup hard link is created afterward and therefore does not preserve the original contents. [`passwd.c`](https://github.com/landley/toybox/blob/0.8.11/toys/lsb/passwd.c#L107-L109) prints `Success` on the helper's failure return.

The truncating open was introduced in [0f51bfc](https://github.com/landley/toybox/commit/0f51bfc50c0ddf5dd44976672d43d9ffa8680459). Source inspection found it in every tag from 0.8.7 through 0.8.15 and in upstream revision [6a0c0ef](https://github.com/landley/toybox/blob/6a0c0ef5eeb2c43e4feef9781398c1718b8bddcb/lib/password.c#L132-L135); no later fix was found in the fetched history. Toybox 0.8.6 uses `r+` for this open; that is not an assessment of its other account handling.

In a disposable chroot using a statically linked glibc build of 0.8.11 with `CONFIG_PASSWD=y`, each operation below printed `Success` and reduced the two-account `/etc/shadow` to zero bytes:

| Operation | Process outcome |
| --- | --- |
| `passwd -l root` | Exit 1 |
| `passwd -u root` | SIGABRT |
| `passwd -d root` | SIGABRT |
| `passwd root` with matching new passwords | SIGABRT |

These outcomes are for that build and fixture, not a claim that all libc versions produce the same exit status. The operations must first pass their account, permission and input checks. The helper may instead truncate `/etc/passwd` when the account does not use a shadow entry. Other account applets also call the same helper; their runtime effects have not been separately reproduced.

## Reproduction

On a Linux host with a C toolchain, static libc development files, `make`, Python 3, Git, and root privileges, build Toybox 0.8.11 in a disposable directory. The following commands enable `passwd`; the default config does not.

```sh
git clone --depth 1 --branch 0.8.11 https://github.com/landley/toybox.git /tmp/toybox-repro
cd /tmp/toybox-repro
make defconfig
sed -i 's/^# CONFIG_PASSWD is not set$/CONFIG_PASSWD=y/' .config
make -j2 LDFLAGS=-static
```

Run the following as root, with `TOYBOX` set to that static binary. It creates and removes a fresh temporary chroot for each operation; it does not modify the host account database. The interactive case uses a pseudoterminal.

```sh
sudo TOYBOX="$PWD/toybox" python3 - <<'PY'
import os, pty, select, shutil, subprocess, tempfile, time

toybox = os.environ['TOYBOX']
for label, args in [('lock', ['-l']), ('unlock', ['-u']),
                    ('delete', ['-d']), ('change', [])]:
    with tempfile.TemporaryDirectory(prefix='toybox-passwd-') as root:
        os.mkdir(root + '/bin')
        os.mkdir(root + '/etc')
        shutil.copy2(toybox, root + '/bin/toybox')
        with open(root + '/etc/passwd', 'w') as f:
            f.write('root:x:0:0:root:/root:/bin/sh\nother:x:1000:1000:other:/home/other:/bin/sh\n')
        password = '!hash' if label == 'unlock' else 'hash'
        with open(root + '/etc/shadow', 'w') as f:
            f.write(f'root:{password}:19000:0:99999:7:::\nother:hash:19000:0:99999:7:::\n')
        os.chmod(root + '/etc/shadow', 0o600)
        if label != 'change':
            p = subprocess.run(['chroot', root, '/bin/toybox', 'passwd', *args, 'root'],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            output, status = p.stdout, p.returncode
        else:
            pid, fd = pty.fork()
            if pid == 0:
                os.chroot(root)
                os.execv('/bin/toybox', ['/bin/toybox', 'passwd', 'root'])
            output, sent, deadline = b'', 0, time.monotonic() + 10
            while time.monotonic() < deadline:
                if select.select([fd], [], [], 0.2)[0]:
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                    if sent == 0 and b'New password:' in output:
                        os.write(fd, b'example-passphrase\n'); sent = 1
                    if sent == 1 and b'Retype password:' in output:
                        os.write(fd, b'example-passphrase\n'); sent = 2
            else:
                os.kill(pid, 9)
                raise RuntimeError('interactive passwd timed out')
            os.close(fd)
            _, wait_status = os.waitpid(pid, 0)
            status = os.waitstatus_to_exitcode(wait_status)
        print(f'{label}: exit={status}, shadow bytes={os.path.getsize(root + "/etc/shadow")}')
        print(output.decode(errors='replace').strip())
PY
```

Python reports a signal termination as a negative exit value; `-6` is SIGABRT. The fixture is recreated for every command because the first operation destroys it.

## Alpenglow exposure and mitigation

The clean native build uses Toybox 0.8.11 `defconfig`, where `passwd` is disabled. It previously created a dangling applet symlink regardless. All 12 published v0.1.721 potato, internet and desktop disk images and ISOs for x86_64 and aarch64 were checksum-verified and their boot initramfs Toybox binaries extracted. Both distinct binaries (0.8.11 x86-64 and 0.8.14 aarch64) were executed, the latter under `qemu-aarch64 -0 toybox`; neither contains any of the six account applets named below. The checked-in v86 image uses BusyBox, not Toybox, and the published RISC-V v0.1.721 initramfs contains no Toybox. These checks do not establish the behavior of BusyBox, other releases, packages installed later, or arbitrary locally built images. Cached native binaries, host-provided binaries and the Oil-installed package can differ from the default.

The image builders check actual Toybox applet lists and reject `passwd` and the other known callers of the same helper (`chsh`, `useradd`, `userdel`, `groupadd`, and `groupdel`). Inspection failure is an error; cross-building an aarch64 binary requires executable binfmt support or `qemu-aarch64`. This guard does not inspect packages installed after image creation or independently built images.
