# Oil recipe format

Oil (`system/oil/`) is an APK-only native package manager. Historically its
only source of package data was Alpine's `APKINDEX` (parsed in
`system/oil/src/system/registry/apk.rs`) into an in-memory
`PackageMetadata` struct, which `install_package()` in `main.rs` then
downloads and extracts.

Recipes (`*.yml`) are a second, declarative way to describe a package for
Oil to install — modeled loosely on Solus's ypkg `package.yml` shape
(name / version / source / build steps / install path), but trimmed down to
exactly what Oil's existing `PackageMetadata` type needs. There is no
`release` field (APK versions like `0.21.0-r0` already carry the revision),
no `builddeps` (Oil doesn't build from source), and no Vala/eopkg-specific
concepts — Oil only ever produces its existing APK-compatible install
output.

A recipe parses directly into `system::registry::PackageMetadata`, the same
struct the Alpine `APKINDEX` loader produces. `install_package()` doesn't
need to know whether a `PackageMetadata` came from the network registry or
from a recipe file.

## Schema

```yaml
name: <string, required>          # package name
version: <string, required>       # Alpine-style version, e.g. "0.21.0-r0"
description: <string, optional>   # defaults to ""

source:
  url: <string, required>         # URL of the prebuilt .apk to fetch
  sha256: <string, optional>      # expected sha256 of the downloaded .apk

build: [<string>, ...]            # optional list of shell steps, default []
                                   # (see "Build steps" below — not executed yet)

install: <string, optional>       # destination root to unpack into,
                                   # defaults to "/usr/local"

depends: [<string>, ...]          # optional, default []
provides: [<string>, ...]         # optional, default []
```

Parsing and validation live in `system/oil/src/recipe.rs` (`Recipe::parse`,
`Recipe::load`). `name`, `version`, and `source.url` must be non-empty;
everything else is optional with the defaults above.

## Example

```yaml
name: dinit
version: 0.21.0-r0
description: Service monitoring/init system

source:
  url: https://dl-cdn.alpinelinux.org/alpine/edge/community/x86_64/dinit-0.21.0-r0.apk
  sha256: 98bfaf584025c79233f100b594a1c95ea6c5dee5d38b199c610efa7f6070a1f3

build: []

install: /usr/local

depends:
  - so:libc.musl-x86_64.so.1
  - so:libgcc_s.so.1
  - so:libstdc++.so.6

provides:
  - cmd:dinit-check
  - cmd:dinit-monitor
  - cmd:dinit
  - cmd:dinitctl
```

See `system/oil/recipes/toybox.yml` and `system/oil/recipes/dinit.yml` for
two real, working recipes migrated from the plain package-name lists in
`system/backends/appliance/packages-runtime.txt`.

## Using a recipe

```sh
oil install-recipe system/oil/recipes/dinit.yml            # fetch + install
oil install-recipe system/oil/recipes/dinit.yml --dry-run   # preview only
```

`install-recipe` loads the `.yml` file, converts it to a `PackageMetadata`,
and runs it through the exact same download/verify/extract path
(`install_package()`) that `oil install <name>` uses for registry packages.
It also records the install in the same `~/.oil/installed.json` state file,
so `oil uninstall`/`oil upgrade`/`oil outdated` all see recipe-installed
packages too.

## Build steps: current scope

Oil doesn't build packages from source — it only fetches and extracts
prebuilt `.apk` payloads. The `build` field exists so the schema has
somewhere to grow into once/if that changes, but as of this writing it is
parsed and stored on the `Recipe` struct and never executed.

`// ponytail:` there is no sandboxing/chroot for build steps because
nothing runs them yet. Before wiring `build` steps up to actually execute
shell commands against untrusted recipe content, add sandboxing (e.g. an
unprivileged `bwrap`/chroot jail with no network access beyond the initial
source fetch) — do not `exec()` recipe-authored shell text directly against
the host.
