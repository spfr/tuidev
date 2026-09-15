#!/bin/bash
# Unit tests for scripts/lib/container.sh — runtime preference order and the
# CLI-shape shims, run against stub binaries on a throwaway PATH.
# Run: bash scripts/lib/test_container.sh  -> exit 0 on pass.
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container.sh disable=SC1091
. "$LIB_DIR/container.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
log="$tmp/calls.log"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

stub() {  # stub NAME — records "name args" into the log
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$1" "$log" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}
mkdir -p "$tmp/bin"
unset TUIDEV_CONTAINER_RUNTIME

# Resolve with ONLY the stub dir on PATH — CI runners ship real docker and
# podman in /usr/bin, which would otherwise leak into the preference tests.
rt() { PATH="$tmp/bin" tuidev_container_runtime; }

# Force the Darwin branch so `container` is eligible regardless of host OS.
# shellcheck disable=SC2329,SC2317  # invoked indirectly by the lib
uname() { echo Darwin; }

[[ -z "$(rt || true)" ]] || fail "no runtimes should print nothing"
pass "no runtime → empty"

stub docker
[[ "$(rt)" == docker ]] || fail "docker alone"
stub podman
[[ "$(rt)" == podman ]] || fail "podman beats docker"
stub container
[[ "$(rt)" == container ]] || fail "container beats podman"
pass "preference order container > podman > docker"

export TUIDEV_CONTAINER_RUNTIME=docker
[[ "$(rt)" == docker ]] || fail "env override"
export TUIDEV_CONTAINER_RUNTIME=missing
rt >/dev/null && fail "override to a missing binary must fail"
unset TUIDEV_CONTAINER_RUNTIME
pass "TUIDEV_CONTAINER_RUNTIME override"

# shellcheck disable=SC2329,SC2317
uname() { echo Linux; }
[[ "$(rt)" == podman ]] || fail "Apple container skipped on Linux"
# shellcheck disable=SC2329,SC2317
uname() { echo Darwin; }
pass "container is macOS-only"

: > "$log"
export PATH="$tmp/bin:$PATH"   # shims: stubs must shadow any real runtime
tuidev_container_rmi container img
tuidev_container_rmi podman img
tuidev_container_pull container img
tuidev_container_build docker t Dockerfile .
tuidev_container_run podman img echo hi
grep -qx 'container image rm img' "$log"   || fail "apple rmi shape"
grep -qx 'podman rmi img' "$log"           || fail "podman rmi shape"
grep -qx 'container image pull img' "$log" || fail "apple pull shape"
grep -qx 'docker build -t t -f Dockerfile .' "$log" || fail "build shape"
grep -qx 'podman run --rm img echo hi' "$log" || fail "run shape"
pass "CLI shims"

echo "All container lib tests passed."
