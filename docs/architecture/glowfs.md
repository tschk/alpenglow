# GlowFS

GlowFS is the Alpenglow root filesystem for internet-appliance images. Its job is narrower than ext4, Btrfs, XFS, EROFS, or SquashFS: boot a verified browser operating system quickly, expose immutable system generations, and keep mutable browser state out of the root image.

## Why GlowFS Exists

General filesystems optimize for broad POSIX workloads. Alpenglow has a smaller contract:

- `/usr`, `/etc`, OpenRC service graphs, UI bundles, Servo launchers, `sold`, and policy files are immutable generation content.
- Browser cache is disposable and should not be treated like durable user state.
- Browser profiles, downloads, terminal state, and Oil state are explicit persistent mounts outside the root image.
- OS rollback should be a filesystem generation operation rather than a package-manager repair operation.
- Image verification should be native to the root format instead of bolted on after mount.

GlowFS v0 therefore uses a compact image with a fixed header, fixed entries, a packed name table, aligned file payloads, and SHA-256 content digests. The kernel mounts valid GlowFS images, exposes directory lookup, directory iteration, page-cache-backed reads, readahead, mmap, splice reads, and fixed-extent writes for explicitly mutable images. The root image remains immutable by default; mutable GlowFS is for state volumes where existing extents can be overwritten without allocation or directory mutation.

## Kernel Boundary

The kernel driver is Rust-first with a small C VFS shim:

- C owns `register_filesystem`, `mount_bdev`, `super_block`, root inode creation, and Linux VFS ABI details.
- Rust owns GlowFS format validation and will own metadata lookup, digest policy, and read planning as the Rust side grows.
- The C shim is replaceable when upstream Rust VFS filesystem abstractions cover the required mount, inode, dentry, directory, and page-cache operations.

V is not used inside the kernel. V remains suitable for generated manifests and userspace policy helpers, but generated C is not a good Linux-kernel boundary because the kernel is a constrained environment rather than a normal libc target.

## Format V0

Header:

- magic: `GLWFSV01`
- version: `1`
- entry count
- entries offset
- names offset
- data offset
- image size
- flags

Entry:

- inode
- parent inode
- name offset and length
- kind: directory, file, or symlink
- mode, uid, gid
- file or symlink data offset and size
- SHA-256 digest

Flags:

- `1`: immutable verified image
- `2`: mutable fixed-extent image

Immutable images keep digest verification in tooling and mount read-only in the kernel. Mutable images allow overwrites and append-growth of existing files by relocating the file to a new aligned extent at the end of the image, updating the entry table, and advancing `image_size`. Creating files, unlinking files, renaming files, shrinking files, reusable free space, multi-extent files, and directory mutation are outside v0; those require the v2 bitmap, extent table, and journal format.

The root entry is inode `1`, parent `1`, directory kind, and empty name. Symlinks store their target path as inline payload data so Alpine rootfs layouts can be represented without requiring host path resolution during image build.

## Format V2

GlowFS v2 keeps the v1 immutable image contract but adds mutable allocation metadata after the v1 image body:

- allocation bitmap: one bit per filesystem block,
- extent table: records inode, logical block, physical block, block count, and flags,
- journal region: fixed-size intent and commit records for bitmap, extent, and inode-size updates,
- data region: block-aligned file blocks.

`glowfsctl plan-v2 <image> <target-size>` computes the concrete v2 layout for an existing mutable image. The v2 kernel mount path is not enabled until bitmap replay, extent validation, and journal commit handling are present.

`glowfsctl upgrade-v2 <image> <target-size>` writes the v2 superblock, allocation bitmap, extent table, empty journal region, and block-aligned extent payload copies into an existing mutable image. The kernel validates the v2 metadata and reports v2 capacity through `statfs`, but forces v2 mounts read-only until journal replay and bitmap-backed allocation are implemented.
