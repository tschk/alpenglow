#!/bin/sh
# The glibc alpenglowed/greeter builds must not change the sibling checkout
# they read. Runs each build script against a fake alpenglowed tree (old-style
# path deps, so any manifest sed would match) with a stand-in `docker` that
# executes the container script on the host, mapping each -v mount to its host
# path. Fails if the tree differs afterwards. No Docker, network or cargo.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPTS="${REPO_ROOT}/system/backends/appliance/scripts"
tmp="$(mktemp -d)"
trap 'chmod -R u+w "${tmp}" 2>/dev/null; rm -rf "${tmp}"' EXIT INT TERM
fail() { printf 'test-alpenglowed-build-readonly: %s\n' "$1" >&2; exit 1; }

src="${tmp}/alpenglowed"
mkdir -p "${src}/src" "${src}/alpenglow-greeter" "${src}/.git" "${src}/target"
cat > "${src}/Cargo.toml" << 'EOF'
[package]
name = "alpenglowed"
[dependencies]
crepuscularity-core = { path = "../crepuscularity/crates/crepuscularity-core" }
EOF
cat > "${src}/alpenglow-greeter/Cargo.toml" << 'EOF'
crepuscularity-gpui = { path = "../../crepuscularity/crates/crepuscularity-gpui", features = ["wayland"] }
EOF
printf 'lock v1\n' > "${src}/Cargo.lock"
printf 'fn main() {}\n' > "${src}/src/main.rs"
printf 'host build cache\n' > "${src}/target/from-host"
printf 'host git metadata\n' > "${src}/.git/config"
snapshot() { (cd "${src}" && find . -type f -exec cksum {} + | sort; find . | sort); }
snapshot > "${tmp}/before"

bin="${tmp}/bin"
mkdir -p "${bin}"
for t in apt-get file; do printf '#!/bin/sh\nexit 0\n' > "${bin}/${t}"; chmod 755 "${bin}/${t}"; done
# cargo: refreshes the lockfile and writes the binary where cargo would.
cat > "${bin}/cargo" << 'EOF'
#!/bin/sh
set -eu
[ ! -e .git ] && [ ! -e target/from-host ] || exit 66
printf 'lock v2\n' > Cargo.lock
[ "${FAIL_CARGO:-0}" = 0 ] || exit 3
t=target/release
mkdir -p "${t}"
for n in alpenglowed alpenglow-greeter; do printf 'bin\n' > "${t}/${n}"; done
EOF
# The container has GNU sed; BSD sed needs an explicit empty -i suffix.
if ! sed --version > /dev/null 2>&1; then
  cat > "${bin}/sed" << 'EOF'
#!/bin/sh
if [ "${1:-}" = -i ]; then shift; exec /usr/bin/sed -i '' "$@"; fi
exec /usr/bin/sed "$@"
EOF
  chmod 755 "${bin}/sed"
fi
# docker run [--rm] [--platform P] [-e K=V] [-v H:C[:ro]]... IMAGE sh -c SCRIPT
cat > "${bin}/docker" << 'EOF'
#!/bin/sh
set -eu
root="${FAKE_DOCKER_ROOT}"
shift  # run
while [ $# -gt 0 ]; do
  case "$1" in
    --rm) shift ;;
    --platform) shift 2 ;;
    -e) export "$2"; shift 2 ;;
    -v)
      host="${2%%:*}"; rest="${2#*:}"; ctr="${rest%%:*}"
      mkdir -p "$(dirname "${root}${ctr}")"
      ln -s "${host}" "${root}${ctr}"
      case "${ctr}" in */alpenglowed) printf '%s\n' "${rest}" > "${root}/source-mount" ;; esac
      shift 2 ;;
    *) break ;;
  esac
done
shift  # image
[ "$1" = sh ] && [ "$2" = -c ] || { echo "fake docker: expected sh -c" >&2; exit 2; }
script="$3"
# Map every absolute container path (mounted or not) under the fake root.
script="$(printf '%s' "${script}" | sed -E "s#(^|[ \"'=])/(build|out|src|target|work|tmp)([/ \"']|\$)#\\1${root}/\\2\\3#g")"
mkdir -p "${root}/build" "${root}/work" "${root}/tmp"
exec sh -c "${script}"
EOF
chmod 755 "${bin}/cargo" "${bin}/docker"

run_build() {
  name="$1"; script="$2"; failure="${3:-0}"
  root="${tmp}/root-${name}"
  mkdir -p "${root}"
  out="${tmp}/out-${name}"
  status=0
  PATH="${bin}:${PATH}" FAKE_DOCKER_ROOT="${root}" FAIL_CARGO="${failure}" \
    sh "${script}" "${out}" "${src}" > "${tmp}/${name}.log" 2>&1 || status=$?
  snapshot > "${tmp}/after"
  if ! cmp -s "${tmp}/before" "${tmp}/after"; then
    diff "${tmp}/before" "${tmp}/after" >&2 || true
    fail "${name}: modified the alpenglowed checkout it builds from"
  fi
  if { [ "${failure}" = 0 ] && [ "${status}" != 0 ]; } ||
    { [ "${failure}" != 0 ] && [ "${status}" = 0 ]; }; then
    cat "${tmp}/${name}.log" >&2
    fail "${name}: unexpected build status ${status}"
  fi
  grep -q ':ro$' "${root}/source-mount" || fail "${name}: source mount is writable"
}

run_build shell "${SCRIPTS}/build-alpenglowed-glibc.sh"
[ -f "${tmp}/out-shell/alpenglowed-glibc/usr/bin/alpenglowed" ] || fail "shell: no binary produced"
run_build greeter "${SCRIPTS}/build-alpenglow-greeter-glibc.sh"
[ -f "${tmp}/out-greeter/alpenglow-greeter-glibc/usr/bin/alpenglow-greeter" ] || fail "greeter: no binary produced"
run_build shell-failure "${SCRIPTS}/build-alpenglowed-glibc.sh" 1
run_build greeter-failure "${SCRIPTS}/build-alpenglow-greeter-glibc.sh" 1

printf 'test-alpenglowed-build-readonly: ok\n'
