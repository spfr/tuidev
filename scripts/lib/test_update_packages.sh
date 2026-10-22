#!/bin/bash
# End-to-end test of `update.sh --packages` on a native package manager (apt):
# per-pack reporting, one batched upgrade across packs, "status unknown" on a
# failed probe, and Node patch releases through fnm. apt, dpkg, sudo and fnm
# are stubs; nothing is installed and the real HOME is never touched.
# Run: bash scripts/lib/test_update_packages.sh  -> exit 0 on pass.
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE="$LIB_DIR/../update.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/state" TUIDEV_NO_COLOR=1
unset XDG_CONFIG_HOME
# A checkout without an upstream: repo sync stops before any git fetch.
export TUIDEV_REPO="$tmp/repo"
git init -q "$TUIDEV_REPO"
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
# pkg_manager only looks for apt on Linux, so a Mac run must report Linux too.
printf '#!/bin/bash\necho Linux\n' > "$tmp/bin/uname"; chmod +x "$tmp/bin/uname"
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

# A recorded repo path that no longer exists falls back to this checkout
# (only checkable when this tree is one: synced copies and tarballs aren't).
if [[ -e "$LIB_DIR/../../.git" ]]; then
    out="$(TUIDEV_REPO="$tmp/moved-away" GIT_ALLOW_PROTOCOL=none run_update --check)" || fail "--check with a stale repo path"
    [[ "$out" == *"Recorded repo $tmp/moved-away is not a git checkout; using"* ]] || fail "stale repo fallback: $out"
    pass "a stale recorded repo path falls back to the running checkout"
else
    echo "SKIP: not a git checkout — stale repo fallback not checked"
fi

# Node through fnm: installed v24.16.0 (behind), v24.22.1 and v26.8.2 (behind),
# default v26.8.2. The stub keeps its state in files, like fnm's own dir.
sed -i.bak 's/^extra_packs=.*/extra_packs=tmux vim fnm/' "$TUIDEV_STATE_DIR/profile"
fnm_dir="$tmp/fnm"; mkdir -p "$fnm_dir"
printf 'v24.16.0\nv24.22.1\nv26.8.2\n' > "$fnm_dir/installed"
echo v26.8.2 > "$fnm_dir/default"
# shellcheck disable=SC2016
stub fnm 'd='"$fnm_dir"'
case "$1" in
    ls) while read -r v; do
            [[ "$v" == "$(cat "$d/default")" ]] && echo "* $v default" || echo "* $v"
        done < "$d/installed"; echo "* system" ;;
    ls-remote) [[ -n "${FNM_REMOTE_FAIL:-}" ]] && exit 1
        printf "v22.23.4\nv24.9.0\nv24.22.1 (Krypton)\nv26.8.2\nv26.12.1\nv27.0.0\n" ;;
    install) echo "$2" >> "$d/installed" ;;
    default) echo "$2" > "$d/default" ;;
esac'

: > "$log"
out="$(run_update --check)" || fail "--check with fnm exited non-zero: $out"
[[ "$out" == *"Node via fnm (1 major(s) behind)"* ]] || fail "fnm group: $out"
[[ "$out" == *"Node 26: v26.8.2 → v26.12.1"* ]] || fail "stale major: $out"
[[ "$out" != *"Node 24:"* && "$out" != *"Node 27"* && "$out" != *"Node 22"* ]] \
    || fail "only installed majors that are behind: $out"
[[ "$out" == *"older patches still installed: v24.16.0;"* ]] || fail "superseded hint: $out"
grep -qE '^fnm (install|default) ' "$log" && fail "--check changed fnm state"
pass "--check: fnm majors behind nodejs.org, no installs"

out="$(run_update --packages --yes)" || fail "--packages with fnm exited non-zero: $out"
grep -q '^fnm install v26.12.1$' "$log" || fail "did not install v26.12.1: $(cat "$log")"
[[ "$(cat "$fnm_dir/default")" == v26.12.1 ]] || fail "default not moved: $out"
grep -qE '^fnm install v2[27]' "$log" && fail "installed a major that wasn't there"
grep -q 'v24.16.0' "$fnm_dir/installed" || fail "removed an old patch"
pass "--packages: latest patch per installed major, default follows within its major"

out="$(FNM_REMOTE_FAIL=1 run_update --check)" || fail "--check with nodejs.org down exited non-zero"
[[ "$out" == *"Node via fnm (status unknown)"* ]] || fail "unreachable remote: $out"
pass "an unreachable nodejs.org is status unknown"

: > "$fnm_dir/installed"; : > "$fnm_dir/default"
out="$(run_update --packages --yes)" || fail "--packages with fnm managing no Node exited non-zero: $out"
[[ "$out" == *"Node via fnm (0 major(s) behind)"* ]] || fail "empty fnm: $out"
pass "fnm with no Node installed and no default is not an error"

# uv from the standalone installer (its receipt), 0.12.5 behind 0.13.5, and a
# managed CPython 3.14.7 whose minor has 3.14.8. The 3.15 release candidate is
# a minor that isn't installed, so it is no update.
mkdir -p "$HOME/.config/uv"; echo '{}' > "$HOME/.config/uv/uv-receipt.json"
# shellcheck disable=SC2016
stub uv 'case "$1 $2" in
    "self update") [[ -n "${UV_SELF_FAIL:-}" ]] && exit 2
        [[ "$3" == --dry-run ]] && echo "Would update uv from v0.12.5 to v0.13.5" ;;
    "python list") cat <<EOF
cpython-3.15.0rc1-macos-aarch64-none   <download available>
cpython-3.14.8-macos-aarch64-none      <download available>
cpython-3.14.7-macos-aarch64-none      /h/.local/bin/python3 -> /h/py/bin/python3.14
cpython-3.14.7-macos-aarch64-none      /h/py/bin/python3.14
cpython-3.13.15-macos-aarch64-none     /h/py313/bin/python3.13
EOF
;;
esac'

: > "$log"
out="$(run_update --check)" || fail "--check with uv exited non-zero: $out"
[[ "$out" == *"uv v0.12.5 → v0.13.5"* ]] || fail "uv self check: $out"
[[ "$out" == *"uv-managed Python (1 behind"* ]] || fail "python group: $out"
[[ "$out" == *"cpython-3.14.7-macos-aarch64-none → cpython-3.14.8-macos-aarch64-none"* ]] || fail "stale python: $out"
[[ "$out" != *"3.15.0rc1"* && "$out" != *"3.13.15 →"* ]] || fail "only installed minors that are behind: $out"
grep -qE '^uv (self update$|python upgrade)' "$log" && fail "--check updated uv"
pass "--check: standalone uv and its managed Pythons behind, no changes"

: > "$log"
out="$(run_update --packages --yes)" || fail "--packages with uv exited non-zero: $out"
grep -q '^uv self update$' "$log" || fail "uv not updated: $(cat "$log")"
[[ "$(grep -E '^uv (self update|python upgrade)$' "$log" | tr '\n' ,)" == "uv self update,uv python upgrade," ]] \
    || fail "uv must update before its Pythons: $(cat "$log")"
pass "--packages: uv self update, then uv python upgrade"

out="$(UV_SELF_FAIL=1 run_update --check)" || fail "--check with a failing uv self check exited non-zero"
[[ "$out" == *"uv"*"status unknown"* ]] || fail "failed self check: $out"
pass "a failed uv self check is status unknown"

echo "All update --packages tests passed."
