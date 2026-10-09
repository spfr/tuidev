#!/bin/bash
# End-to-end test of `update.sh --packages` on a native package manager (apt):
# per-pack reporting, one batched upgrade across packs, "status unknown" on a
# failed probe. apt, dpkg and sudo are stubs; nothing is installed and the real
# HOME is never touched.
# Run: bash scripts/lib/test_update_packages.sh  -> exit 0 on pass.
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$LIB_DIR/../update.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/state" TUIDEV_NO_COLOR=1
unset XDG_CONFIG_HOME
export TUIDEV_REPO="$tmp/no-repo"   # repo sync skips: no git fetch in tests
mkdir -p "$HOME" "$TUIDEV_STATE_DIR" "$tmp/bin"
cat > "$TUIDEV_STATE_DIR/profile" <<'EOF'
profile=test
core=true
remote=false
sandbox=false
ui=false
extras=false
extra_packs=tmux vim
EOF

log="$tmp/calls.log"
stub() {  # stub NAME BODY — records "name args", then runs BODY
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$log" "$2" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}
# Installed: jq (core, current), tmux (outdated), vim (outdated).
# shellcheck disable=SC2016  # stub bodies expand in the stub, not here
stub dpkg 'case "$1" in
    --compare-versions) [[ "$2" < "$4" ]] ;;
    -s) case "$2" in jq|tmux|vim) echo "Status: install ok installed" ;; *) exit 1 ;; esac ;;
esac'
# shellcheck disable=SC2016
stub apt-cache '[[ -n "${APT_FAIL:-}" ]] && exit 1
case "$2" in
    jq)       printf "  Installed: 1.7\n  Candidate: 1.7\n" ;;
    tmux|vim) printf "  Installed: 1.0\n  Candidate: 2.0\n" ;;
    *)        printf "  Installed: (none)\n  Candidate: (none)\n" ;;
esac'
stub apt-get 'exit 0'
stub apt-mark 'exit 0'
stub sudo 'exit 1'   # no passwordless sudo
# No Homebrew: only the stubs and the system basics (not /opt/homebrew).
run_update() { PATH="$tmp/bin:/usr/bin:/bin" bash "$UPDATE" "$@" < /dev/null 2>&1; }

out="$(run_update --check)" || fail "--check exited non-zero: $out"
[[ "$out" == *"core updates (1 tracked via apt, 0 outdated)"* ]] || fail "core group: $out"
[[ "$out" == *"tmux updates (1 tracked via apt, 1 outdated)"* ]] || fail "tmux group: $out"
[[ "$out" == *"2 package(s) have updates available"* ]] || fail "check summary: $out"
grep -q '^apt-get' "$log" && fail "--check ran apt-get"
pass "--check: per-pack apt groups, counts and summary, no changes"

: > "$log"
out="$(run_update --packages --yes)" || fail "--packages exited non-zero: $out"
[[ "$out" == *"sudo apt-get install --only-upgrade -y tmux vim"* ]] || fail "one batched hint: $out"
[[ "$(grep -c 'sudo apt-get update' <<<"$out")" == 1 ]] || fail "apt-get update hint should appear once: $out"
grep -q '^apt-get' "$log" && fail "upgraded without root"
pass "--packages without sudo: one batched command across packs, printed once"

out="$(APT_FAIL=1 run_update --check)" || fail "--check with a failing probe exited non-zero"
[[ "$out" == *"status unknown"* ]] || fail "failed probe should be status unknown: $out"
[[ "$out" != *"All pack-tracked packages up to date"* ]] || fail "failed probe reported up to date: $out"
pass "a failed apt probe is status unknown, never up to date"

echo "All update --packages tests passed."
