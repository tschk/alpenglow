# Design Inspirations

Ideas borrowed from other systems for Alpenglow.

## Plan 9 / 9front

Plan 9 was Bell Labs' attempt to replace Unix, designed at the Computing Science Research Center (CSRC) starting in the mid-1980s by Rob Pike, Ken Thompson, Dave Presotto, Phil Winterbottom, with contributions from Dennis Ritchie, Brian Kernighan, Tom Duff, and Doug McIlroy. The final official release was in early 2015. 9front is the actively maintained fork.

**Core principles:**

- **Everything is a file, taken seriously.** Not a metaphor. Every resource (network, graphics, auth, hardware) appears as files in a hierarchical namespace. You cat a network connection, echo to a window. This extends Unix's original idea to its logical endpoint.
- **Distributed computing built in.** The system is designed as a network of heterogeneous machines: terminals (user workstations), CPU servers (computation), and file servers (storage). All communicate over a unified protocol.
- **Per-process namespaces.** Every process has its own view of the filesystem. A process can construct its own /
  by binding directories, mounting remote resources, or hiding files. This replaces environment variables like PATH and chroot with a single, unified mechanism.
- **9P protocol.** All programs that provide services-as-files speak 9P, a generic, transport-agnostic byte-oriented protocol. It replaces sockets, ioctls, X resources, and bespoke APIs with one thing: read and write.
- **Union directories.** Directories from different trees can be layered into a single view. Bind mounts create union directories: `bind -a /usr/bin /bin` appends, `bind -b /usr/local/bin /bin` prepends. No recursive merging — just flat concatenation with top-down resolution.
- **UTF-8 invented here.** Ken Thompson designed UTF-8 in a Plan 9 terminal in 1992. The entire system uses Unicode throughout.
- **Graphical system through files.** The window system (8½, then rio) serves each window as files: /dev/cons, /dev/mouse, /dev/bitblt. Programs don't know if they're talking to hardware or a window manager.
- **Factotum.** Central authentication and key management. One daemon handles all auth so secret keys and implementation details stay in one place.
- **procfs and netfs.** /proc and /net are filesystems. Process management and networking are done with ls, cat, echo, not ioctls or syscalls.
- **Fossil + Venti.** Fossil provides snapshots and versioned file histories. Venti is a content-addressable archival store. Together they give every file a history.
- **No Unix compatibility as goal.** Plan 9 was never intended to run Unix software. It has APE (ANSI/POSIX Environment) for ports, and a Linux binary emulator, but these are secondary. The point is a clean design.

**Ideas that later appeared in Linux/Unix:**

- UTF-8 (now universal)
- Mount namespaces (containers, Docker)
- Union mounts (overlayfs, Docker layers)
- procfs (Linux /proc, inspired by Plan 9)
- Plumber-style IPC (D-Bus, Portal)
- Wayland compositor concepts (rio's per-window files)

**What Alpenglow takes from Plan 9:**

| Idea | Application |
|------|-------------|
| **Everything is a file** | `sold` exposes system state as file operations over 9P. Settings, auth, services readable/writable via filesystem. |
| **Per-process namespaces** | Each dinit service sees a private /net, /dev, /tmp via Linux mount namespaces + bind mounts. |
| **Union directories** | GlowFS immutable root + per-process writable overlay. Union mounts instead of overlayfs. |
| **9P protocol** | `sold` speaks 9P instead of Axum/REST. Uniform access local + remote. Lighter than HTTP. |
| **No /etc** | Configuration per-process in the namespace. No global mutable config files. |
| **Factotum** | Single auth daemon for `sold`. One secret unlocks all system services. |
| **UTF-8 everywhere** | Already standard. Enforced at OS boundary. |
| **procfs + netfs pattern** | System resources exposed as filesystem. Not ioctl soup. |

---

## Sortix

Sortix is a modern Unix-like OS written from scratch by Jonas 'Sortie' Linds (development started February 2011). It has its own kernel, own libc, own userspace. Not Linux. Not BSD.

**What it is:**

- Written entirely from scratch. Clean implementation with no legacy baggage.
- Self-hosting since Sortix 1.0 (March 2016). Sortix builds Sortix. The website runs on Sortix.
- Aims to be POSIX.1-2024 compatible while free to innovate.
- ISC licensed (permissive, functionally equivalent to MIT).
- Ships /src with every release — the entire source tree is available on disk.
- Currently missing: SMP support, USB. Still young but production-focused.
- Lightweight: runs in ~1400MB RAM.
- Rolling release with nightly stable builds.
- Clean upgrade path between nightly builds.
- Funded by NLnet's NGI0 Commons Fund.

**Why it matters (especially for compiler/runtime work):**

A single person can still understand the whole system. The kernel, libc, toolchain — it's all there, consistent, and not buried under decades of accumulation. For someone working on compilers and runtimes, Sortix is more interesting than most Linux distros because the whole stack is comprehensible.

**What Alpenglow takes from Sortix:**

| Idea | Application |
|------|-------------|
| **Self-hosting** | Oil should eventually build Oil. The appliance builds its own packages. Cross-compile optional, not required. |
| **/src shipped** | Rootfs includes /src with kernel source, Oil source, all build manifests. |
| **Clean, understandable codebase** | Keep dependency chain minimal. Prefer in-tree code. Every layer of the stack should be graspable by one person. |
| **Nightly builds + clean upgrade** | Generation model already supports upgrade + rollback. |
| **Permissive license (ISC)** | Prefer MIT, BSD, Apache, ISC. toybox (BSD-2), musl (MIT), dinit (Apache-2.0). |
| **POSIX + room to innovate** | toybox gives POSIX base. Deviate where the appliance model improves things. |
| **Lightweight RAM target** | ~2GB for diskless appliance. |
| **Production-focused, not a hobby** | Nightly builds, upgrade path, real use. |

---

## Oasis (~mcf)

> Oasis is a small Linux system closer to BSD than typical Linux. Everything is statically linked,
> packages are composed from spec files, no package manager, minimal /etc, BearSSL, cproc.

| Idea | Applied |
|------|---------|
| **Static linking** | Packages in the appliance are statically linked where practical. |
| **Spec-based composition** | `packages-runtime.txt` is the spec. Generation store is git-backed. |
| **BearSSL** | Default crypto. Tiny, well-audited. |
| **toybox** | Replaces GNU coreutils. |
| **No package manager** | Oil IS the package manager, but follows the spec → git → rootfs philosophy. |
| **cproc** | Not yet. Inauguration is the future compiler. LLVM for now. |

Also: Oasis does not use Oil. Oil is a separate project.

---

## Chimera

> Chimera uses dinit, LLVM/Clang as the default system compiler, FreeBSD userland, and apk.

| Idea | Applied |
|------|---------|
| **dinit** | Chosen as init system. |
| **LLVM/Clang** | Default system compiler. |
| **apk** | Not used as bootstrap. Oil reads apk repos as one data source. |
| **FreeBSD userland** | Not using — toybox instead. Single binary, simpler. |

---

## Combined synthesis

**Core insight for Alpenglow:** Everything is a file in a per-process namespace, composed from specs, with the source always available on disk. The initramfs loads the GlowFS spec layer, the kernel sets up per-service namespaces, and `sold` exposes the system as a 9P filesystem.

The result is an OS that is:
- **Understandable** — like Sortix, the whole stack is graspable
- **Philosophically clean** — like Plan 9, the model is consistent (everything is a file)
- **Minimal** — like Oasis, no wasted code paths
- **Practical** — like Chimera, using real tooling (dinit, LLVM) not hobby experiments
