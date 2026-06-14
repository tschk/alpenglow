# Readiness

Alpenglow is not bootable as a complete usable OS yet.

## Proven

- `./scripts/ci-os-appliance.sh` validates the backend contract, rootfs manifests, service graph, kernel config policy, GlowFS source layout, and staging scripts.
- `./scripts/ci-rust-core.sh` passes for `sold`, `alpenglow-kernelctl`, `alpenglow-netd`, `glowfsctl`, and `alpenglow-drivers`.
- GlowFS tooling and the out-of-tree GlowFS kernel module compile in the CI kernel-module path.
- The Void musl/runit backend can configure a rootfs tree and records Oil as the package manager with XBPS only as bootstrap fetcher.
- The Alpine reference path can build local Linux helper binaries for `sold`, `alpenglow-kernelctl`, and `alpenglow-netd`.

## Not Proven

- No full QEMU boot has passed in the current Alpenglow-only shape.
- No target-board boot has been validated on Radxa Cubie A5E hardware.
- The Void backend does not yet have its own QEMU boot path; Alpine remains the reference image flow.
- Oil is the Alpenglow package-manager identity, but Oil still emits the current `wax` binary name.

## Next Work

2. Make the Void musl/runit backend produce the same QEMU artifacts as the Alpine reference path.
3. Add a single `./install.sh --doctor` command that reports missing engine checkout, missing Oil checkout, Docker/QEMU availability, rootfs backend readiness, and board-flash prerequisites.
4. Add a real image artifact command that emits kernel, initramfs, GlowFS root image, state image, checksums, and install metadata under `build/alpenglow/release`.
5. Add a board install path for Radxa Cubie A5E with an explicit dry-run mode and a destructive flash confirmation gate.
6. Replace the remaining OpenRC reference flow once the Void/runit path reaches parity.
