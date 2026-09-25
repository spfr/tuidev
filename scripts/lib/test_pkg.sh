#!/bin/bash
# Unit tests for scripts/lib/pkg.sh (package-manager dispatch) and
# scripts/lib/packs.sh (pack discovery). Package managers are stub binaries on
# a throwaway PATH; nothing is installed and the real HOME is never touched.
# Run: bash scripts/lib/test_pkg.sh  -> exit 0 on pass.
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
export TUIDEV_NO_COLOR=1
export TUIDEV_MANIFEST_FILE="$tmp/manifest"

# shellcheck source=pkg.sh disable=SC1091
. "$LIB_DIR/pkg.sh"
# shellcheck source=packs.sh disable=SC1091
. "$LIB_DIR/packs.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Only the stub dir plus the handful of real tools the libs use — CI runners
# ship real apt-get/dpkg in /usr/bin, which must not leak into these tests.
mkdir -p "$tmp/bin" "$tmp/sys"
for t in awk grep tr cat mkdir dirname; do
    ln -s "$(command -v "$t")" "$tmp/sys/$t"
done
SYS_PATH="$tmp/sys"
log="$tmp/calls.log"; installed="$tmp/installed"; : > "$installed"

stub() {  # stub NAME [BODY] — records "name args", then runs BODY
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$log" "${2:-}" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}
unstub() { rm -f "$tmp/bin/$1"; }

# shellcheck disable=SC2329,SC2317  # invoked indirectly by the libs
uname() { echo Linux; }
# shellcheck disable=SC2329,SC2317
id() { echo 0; }   # root: no sudo needed
_TUIDEV_PKG_REFRESHED=1   # skip `apt-get update` noise in the log

# --- pkg_manager ------------------------------------------------------------
mgr() { PATH="$tmp/bin:$SYS_PATH" pkg_manager; }
mgr >/dev/null && fail "no manager should return 1"
stub pacman; [[ "$(mgr)" == pacman ]] || fail "pacman alone"
stub dnf;    [[ "$(mgr)" == dnf ]]    || fail "dnf beats pacman"
stub apt-get; [[ "$(mgr)" == apt ]]   || fail "apt beats dnf"
stub brew;   [[ "$(mgr)" == brew ]]   || fail "brew beats apt"
unstub brew; unstub dnf; unstub pacman
pass "pkg_manager order: brew > apt-get > dnf > pacman"

# --- apt: probe, one batched install, record what landed --------------------
# apt-cache: fd-find, mosh and yq have candidates; nosuch does not.
# shellcheck disable=SC2016  # stub bodies expand in the stub, not here
stub apt-cache 'case "$2" in nosuch) echo "  Candidate: (none)" ;; *) echo "  Candidate: 1.0" ;; esac'
stub dpkg "grep -qx \"\$2\" '$installed'"
stub apt-get "shift 2; printf '%s\n' \"\$@\" >> '$installed'"
tuidev_manifest_enable
: > "$log"
rc=0; PATH="$tmp/bin:$SYS_PATH" pkg_install fd yq mosh nosuch >/dev/null || rc=$?
[[ $rc == 1 ]] || fail "unavailable packages should return 1, got $rc"
grep -qx 'apt-get install -y fd-find mosh' "$log" || fail "batched install: $(cat "$log")"
[[ "${PKG_UNAVAILABLE[*]}" == "yq nosuch" ]] || fail "unavailable: ${PKG_UNAVAILABLE[*]}"
tuidev_manifest_has apt fd-find || fail "fd-find not recorded"
tuidev_manifest_has apt yq && fail "Debian's different yq must never be taken"
pass "apt: renames, refuses Debian yq, batches, records what landed"

: > "$log"
PATH="$tmp/bin:$SYS_PATH" pkg_install fd mosh >/dev/null || fail "already-present packages are success"
grep -q 'apt-get install' "$log" && fail "reinstalled present packages"
pass "apt: already-present packages are skipped"

: > "$log"
DRY_RUN=true PATH="$tmp/bin:$SYS_PATH" pkg_install jq >/dev/null || true
grep -q 'apt-get install' "$log" && fail "DRY_RUN ran apt-get"
tuidev_manifest_has apt jq && fail "DRY_RUN recorded"
pass "apt: DRY_RUN changes nothing"

# Not root and no passwordless sudo: print the commands, never prompt.
# shellcheck disable=SC2329,SC2317
id() { echo 1000; }
: > "$log"
out="$(PATH="$tmp/bin:$SYS_PATH" pkg_install jq 2>&1)" && fail "no-sudo path should return 1"
grep -q 'apt-get install' "$log" && fail "ran apt-get without privileges"
[[ "$out" == *"sudo apt-get install -y jq"* ]] || fail "no-sudo hint missing: $out"
# shellcheck disable=SC2329,SC2317
id() { echo 0; }
pass "apt: without root or sudo -n, prints the command instead"

unstub apt-get
PATH="$tmp/bin:$SYS_PATH" pkg_install mosh >/dev/null 2>&1 && fail "no manager should return 1"
[[ "${PKG_UNAVAILABLE[*]}" == mosh ]] || fail "no-manager unavailable list"
pass "no package manager: warns, returns 1, never dies"

# --- packs.sh ---------------------------------------------------------------
got="$(pack_array core formulae | tr '\n' ' ')"
[[ "$got" == *" ripgrep "* && "$got" == *" git-delta "* ]] || fail "core formulae: $got"
[[ "$(pack_array core casks)" == ghostty ]] || fail "core casks"
[[ "$(pack_array sandbox-container formulae)" == podman ]] || fail "hyphenated pack array"
[[ -z "$(pack_array ai-clis formulae)" ]] || fail "a config-only pack should declare nothing"
[[ -z "$(pack_array no-such-pack formulae)" ]] || fail "unknown pack should print nothing"
pass "pack_array reads <PACK>_FORMULAE / <PACK>_CASKS, hyphens included"

[[ "$(pack_script core)" == */scripts/install/core.sh ]] || fail "built-in pack path"
[[ "$(pack_script herdr)" == */scripts/install/packs/herdr.sh ]] || fail "optional pack path"
pack_script no-such-pack >/dev/null && fail "unknown pack should have no script"
[[ "$(pack_entrypoint sandbox-container)" == sandbox_container_install ]] || fail "entrypoint"
pass "pack_script / pack_entrypoint"

got="$(pack_binaries extras | tr '\n' ' ')"
[[ "$got" == *" tldr "* && "$got" != *tealdeer* ]] || fail "extras binaries: $got"
[[ "$(pack_binaries core | grep -c zsh-)" == 0 ]] || fail "zsh plugins have no binary"
[[ "$(tuidev_cask_app hiddenbar)" == "Hidden Bar" && "$(tuidev_cask_app rectangle)" == Rectangle ]] \
    || fail "cask app names"
pass "formula → binary and cask → app mapping"

echo "All pkg + packs lib tests passed."
