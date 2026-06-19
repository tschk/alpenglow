# GlowFS

GlowFS is the planned Alpenglow general-purpose filesystem. It is under development, not a production filesystem today. Its job is to provide a normal writable filesystem for Alpenglow systems while learning from ext4, ZFS, Btrfs, XFS, NTFS, APFS, EROFS, and SquashFS without inheriting all of their complexity.

Alpenglow separates the filesystem family into two formats:

- GlowFS is the planned normal writable filesystem track. It is for persistent state, package state, profiles, downloads, and general POSIX workloads where allocation, fsync, recovery, and long-lived mutation matter.
- GlowIFS is the planned immutable-first image format, sealed at build time and optimized for appliance roots, system generations, rollback, verification, and segmented editable areas such as `/home`.

The split is intentional. GlowIFS should not grow into a half-mutable general filesystem. GlowFS can learn from ext4, ZFS, NTFS, APFS, and other writable filesystems without forcing those concerns into the sealed boot image.

Current status: the repository still contains a prototype `glowfs` kernel module and `glowfsctl` image tool for the immutable image experiment. The naming and implementation have not caught up with this design split yet. Treat this document as direction, not a claim that GlowFS or GlowIFS are ready for real data.

## Why GlowFS Exists

General filesystems optimize for broad POSIX workloads. GlowFS should keep that contract but narrow the implementation around Alpenglow's needs:

- Browser cache is disposable and should not be treated like durable user state.
- Browser profiles, downloads, terminal state, and Oil state are explicit persistent data, not accidental writes into an opaque root.
- Recovery must be boring: after power loss, the filesystem either replays cleanly or reports a concrete repair path.
- Integrity should be native to the format instead of bolted on after mount.
- Layout should make the common appliance and desktop paths fast without needing a large policy engine in the kernel.

GlowFS should start as a small, journaled extent filesystem rather than a broad ZFS clone. The early design should learn from ext4's block groups, extents, journaled metadata commits, orphan recovery, fsck support, and fast mount behavior. The ZFS lessons to carry over are end-to-end checksums, transaction boundaries, scrub support, explicit datasets or volumes, send/receive as an update primitive, and avoiding silent corruption as a design premise.

GlowFS should avoid ZFS's weight at first: no pooled multi-device manager in v0, no deduplication, no ARC-sized memory assumptions, no general snapshot graph, and no policy engine in the kernel. Snapshots can come later as read-only roots or generation checkpoints once allocation, recovery, and verification are correct.

GlowFS should also learn from NTFS and APFS. NTFS shows why extensible metadata, durable file identity, recoverable journals, reparse-like indirection, and rich attributes matter. APFS shows why snapshots, clones, copy-on-write metadata, space sharing, and per-volume encryption are useful on SSDs. GlowFS should take those ideas selectively: extensible metadata and durable IDs early, snapshots and clones later, and encryption as a volume/layer decision rather than a mandatory v0 feature.

## GlowIFS

GlowIFS is the immutable-first format for appliance roots. It should take the best parts of immutable filesystems: EROFS-style read-only discipline, SquashFS-style packed images, dm-verity-style verification, OSTree-style generation thinking, and ZFS-style distrust of silent corruption. It leaves behind the parts Alpenglow does not need in the sealed image: online allocation, block reuse, write ordering for arbitrary mutation, quota policy, and repair tools.

GlowIFS is not purely static. It should support segmented editability by design:

- `/` is sealed and generation-verified.
- `/usr`, `/bin`, `/sbin`, `/lib`, and most of `/etc` come from the immutable image.
- `/home`, `/var/lib`, `/var/cache`, and selected `/etc` overlays can be editable segments backed by the current writable state filesystem.
- Segment boundaries are explicit in the image manifest and mount policy.
- Rollback switches the sealed image generation without destroying writable segments.

This gives Alpenglow an appliance-style root without pretending user data is immutable.

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
- `2`: reserved

Immutable images keep digest verification in tooling and mount read-only in the kernel. Creating files, unlinking files, renaming files, shrinking files, reusable free space, multi-extent files, and directory mutation are outside GlowIFS. Those are GlowFS responsibilities.

The root entry is inode `1`, parent `1`, directory kind, and empty name. Symlinks store their target path as inline payload data so Alpine rootfs layouts can be represented without requiring host path resolution during image build.

## Format V2

GlowIFS v2 should keep the v1 immutable image contract and improve lookup, verification, compression, and generation metadata without adding normal writes:

- directory child ranges or directory hash tables for fast lookup,
- optional compression blocks with independent verification,
- a manifest digest for whole-generation verification,
- per-file digests for lazy or eager verification,
- build IDs, generation IDs, rollback metadata, and policy metadata.

GlowFS is the place for mutable allocation metadata:

- allocation bitmap: one bit per filesystem block,
- extent table: records inode, logical block, physical block, block count, and flags,
- journal region: fixed-size intent and commit records for bitmap, extent, and inode-size updates,
- data region: block-aligned file blocks.

GlowFS should keep mutable allocation separate from GlowIFS images. GlowIFS can mount editable segments, but those segments should be separate writable filesystems rather than hidden mutable areas inside the sealed image.
