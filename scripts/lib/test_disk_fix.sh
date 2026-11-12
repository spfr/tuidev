#!/bin/bash
# shellcheck disable=SC2015,SC2034,SC2154  # "A && B || fail" fails on either; DISK_* are read by the lib; the rest is set in disk_fixture.sh
# Unit tests for scripts/lib/disk.sh and scripts/disk.sh, the disk audit:
# what --fix runs, refuses, rechecks and logs, and the script itself (the
# read side is in test_disk.sh).
# Run: bash scripts/lib/test_disk_fix.sh  -> exit 0 on pass.
#
# The machine they run against is disk_fixture.sh: a throwaway HOME and stub
# tools, so no real cache is touched. The two test files are separate so they
# run at the same time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./disk_fixture.sh disable=SC1091
. "$SCRIPT_DIR/disk_fixture.sh"

# --- tests ----------------------------------------------------------------------

# 11. The answer is No unless y or yes is typed at a terminal, or --yes.
DISK_INTERACTIVE=true
for a in "" "n" "x" "yy" "no"; do
    ! disk_confirm q <<< "$a" >/dev/null || fail "'$a' counted as yes"
done
disk_confirm q <<< "y" >/dev/null && disk_confirm q <<< "yes" >/dev/null || fail "y or yes was not yes"
! disk_confirm q < /dev/null >/dev/null || fail "no input counted as yes"
DISK_INTERACTIVE=false
! disk_confirm q <<< "y" >/dev/null || fail "a yes without a terminal counted"
DISK_ASSUME_YES=true; disk_confirm q </dev/null >/dev/null || fail "--yes was not yes"; DISK_ASSUME_YES=false
pass "the default answer is No; only y or yes at a terminal, or --yes, is yes"

# 12. --fix: a dry run prints the plan and log lines and runs nothing; no
#     changes nothing; without a terminal or --yes nothing runs; yes runs
#     only the tools' own commands, after the whole plan, and logs each.
#     Worktrees and Homebrew never run, and are not even in the plan.
DISK_FD="" disk_collect
_disk_add sneaky-managed "x" "$HOME/.claude/projects/-w-app" managed "e" "e" "e" "touchme" "go clean -cache" 999999
_disk_add sneaky-yours "y" "$HOME/.codex/sessions" yours "e" "e" "e" "touchme" "go clean -cache" 9999999
_disk_add sneaky-rm "z" "$L/Developer/Xcode/DerivedData/x" regenerable "e" "e" "e" "rm" "rm -rf $HOME" 999999
_disk_add sneaky-wt "w" "$W/done/pkg" stale "e" "e" "e" "git worktree remove" "git worktree remove" 999999
_disk_add sneaky-brew "b" "$L/Caches" regenerable "e" "e" "e" "brew" "env HOMEBREW_NO_AUTOREMOVE=1 brew cleanup -s --prune=all" 999999
_disk_add sneaky-home "h" "$HOME" regenerable "e" "e" "e" "go clean -cache" "go clean -cache" 999999
mkdir -p "$tmp/outside"; ln -s "$tmp/outside" "$HOME/link-out"
_disk_add sneaky-link "l" "$HOME/link-out" regenerable "e" "e" "e" "go clean -cache" "go clean -cache" 999999
DRY_RUN=true disk_apply yes_fn > "$tmp/dry.txt"
[[ ! -s "$tmp/state/calls" && ! -f "$TUIDEV_STATE_DIR/disk.log" ]] || fail "--dry-run ran or logged something: $(cat "$tmp/state/calls")"
grep -q '\[DRY RUN\] go clean -cache' "$tmp/dry.txt" && grep -q 'would log: .*	disk	go-build	go clean -cache	dry-run' "$tmp/dry.txt" \
    || fail "dry run did not print the commands and log lines: $(cat "$tmp/dry.txt")"
! grep -q "brew\|worktree remove" "$tmp/dry.txt" || fail "brew or a worktree reached the plan: $(cat "$tmp/dry.txt")"
disk_apply no_fn > /dev/null
[[ ! -s "$tmp/state/calls" ]] || fail "a declined fix ran: $(cat "$tmp/state/calls")"
disk_apply > "$tmp/noterm.txt"
[[ ! -s "$tmp/state/calls" ]] && grep -q "Not a terminal and no --yes: nothing ran" "$tmp/noterm.txt" \
    || fail "without a terminal or --yes something ran: $(cat "$tmp/noterm.txt")"
disk_apply yes_fn > "$tmp/fix.txt"
for c in "go clean -cache" "pnpm store prune" "npm cache clean --force" "uv cache prune" \
    "fnm uninstall v22.0.0" "uv python uninstall cpython-3.14.9-macos-aarch64-none"; do
    grep -qxF "$c" "$tmp/state/calls" || fail "--fix did not run '$c': $(cat "$tmp/state/calls")"
done
[[ -d "$W/done" && -d "$W/atmain" && -f "$W/odd/old dist/notes.txt" && -f "$W/wip/notes.txt" ]] || fail "--fix removed a worktree"
! grep -Eq 'touchme|brew|podman|docker|xcrun|fnm uninstall v(18|20)|go clean -modcache|rm |worktree' "$tmp/state/calls" || fail "--fix ran something it must not: $(cat "$tmp/state/calls")"
[[ "$(grep -c 'go clean -cache' "$tmp/state/calls")" == 1 ]] || fail "a yours, managed, home or symlinked item reached a fix"
grep -q "l ($(_perf_tilde "$HOME/link-out")): it is a symlink" "$tmp/fix.txt" || fail "a symlink was not refused: $(cat "$tmp/fix.txt")"
grep -q "h ($HOME): it resolves to" "$tmp/fix.txt" || fail "\$HOME was not refused: $(cat "$tmp/fix.txt")"
grep -q "freed 400 MB: go clean -cache" "$tmp/fix.txt" && grep -q "Freed .* in all (re-measured with du -sk)" "$tmp/fix.txt" \
    || fail "freed bytes not re-measured: $(cat "$tmp/fix.txt")"
[[ -d "$oldrepo/node_modules" && -d "$HOME/.claude/projects" && -d "$HOME/.codex/sessions" ]] || fail "--fix deleted a folder it must not"
pass "--fix: dry run, no, and no terminal change nothing; yes runs only allowed commands; worktrees and brew never"

# 13. The log: one tab-separated line per command run, with bytes before and
#     after: TIME SOURCE ITEM COMMAND EXIT BEFORE AFTER UNDO.
logf="$TUIDEV_STATE_DIR/disk.log"
grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z	disk	go-build	go clean -cache	0	419430400	0	-$' "$logf" \
    || fail "log line format: $(cat "$logf")"
grep -qE '	pip	pip3 cache purge	126	' "$logf" || fail "a failed command was not logged"
! grep -q "brew\|worktree" "$logf" || fail "brew or a worktree was logged as run"
pass "every command run is logged with its exit code and bytes before and after"
: > "$tmp/state/calls"

# 14. In use: skipped with the reason, never run. A go process, a running
#     shell whose fnm link points at a version, a venv deep in a code folder,
#     an unreadable process table.
mkdir -p "$HOME/.local/state/fnm_multishells"
ln -s "$NV/v22.0.0/installation" "$HOME/.local/state/fnm_multishells/5151_1700000000"
ln -s "$NV/v22.2.0/installation" "$HOME/.local/state/fnm_multishells/9999_1700000000"   # its shell is gone
kb "$NV/v22.0.0" 225280
kb "$P/cpython-3.14.9-macos-aarch64-none" 153600
mkdir -p "$repo/services/api/.venv"
printf 'home = %s/cpython-3.14.9-macos-aarch64-none/bin\n' "$P" > "$repo/services/api/.venv/pyvenv.cfg"
printf '    1 /sbin/launchd\n 4242 go test ./...\n 5151 -zsh\n' > "$tmp/state/ps"
kb "$L/Caches/go-build" 409600
DISK_FD="" disk_collect
disk_apply yes_fn > "$tmp/busy.txt"
grep -q "Go build cache (~/Library/Caches/go-build): in use: pid 4242: go test ./..." "$tmp/busy.txt" || fail "a running go not seen: $(cat "$tmp/busy.txt")"
grep -q "Node v22.0.0 (fnm).*in use: pid 5151: a shell whose fnm use points at it" "$tmp/busy.txt" || fail "a shell after fnm use not seen: $(cat "$tmp/busy.txt")"
grep -q "Python cpython-3.14.9.*a venv uses it: ~/code-link/fresh/services/api/.venv\|Python cpython-3.14.9.*a venv uses it: ~/my code/fresh/services/api/.venv" "$tmp/busy.txt" \
    || fail "a venv deep in a code folder not seen: $(cat "$tmp/busy.txt")"
! grep -Eq '^go |fnm uninstall|uv python uninstall' "$tmp/state/calls" || fail "an item in use was run: $(cat "$tmp/state/calls")"
: > "$tmp/state/calls"; : > "$tmp/state/ps"
DISK_FD="" disk_collect; disk_apply yes_fn > "$tmp/busy.txt"
[[ ! -s "$tmp/state/calls" ]] && grep -q "the process table could not be read" "$tmp/busy.txt" || fail "ran without a process table: $(cat "$tmp/busy.txt")"
pass "items in use are skipped with the reason; without ps nothing runs"

# 15. fnm's per-shell links: thousands of links of ended shells cost one pass
#     (readlink only for the running shell's), and are listed as a stale,
#     report-only item with a command that keeps running shells' links.
for i in $(seq 1 3000); do ln -s "$NV/v18.2.0/installation" "$HOME/.local/state/fnm_multishells/$((100000 + i))_1700000000"; done
printf '    1 /sbin/launchd\n 5151 -zsh\n' > "$tmp/state/ps"
: > "$tmp/state/readlinks"
start=$(date +%s)
DISK_FD="" disk_collect --quick; out="$(disk_report)"
took=$(( $(date +%s) - start ))
n_readlink="$(wc -l < "$tmp/state/readlinks" | tr -d ' ')"
(( n_readlink <= 6 )) || fail "readlink ran $n_readlink times for 3002 links: it must read only running shells' links"
(( took < 60 )) || fail "3000 dead links took $took s"
[[ "$out" == *"fnm links of ended shells"*"3001 of them belong to shells that are no longer running"*"by hand (--fix never runs this): for l in"*"kill -0"* ]] \
    || fail "the dead links are not reported: $out"
[[ "$(DISK_FD="" disk_collect --quick; disk_json)" == *'"id":"fnm-links"'*'"fix_offered":false'* ]] || fail "the dead links are offered"
pass "fnm links: one pass, readlink only for running shells ($n_readlink calls, $took s); 3001 dead ones reported by hand"
rm -rf "$HOME/.local/state/fnm_multishells"

# 16. Right before each command, after the yes, it looks again: a tool that
#     started meanwhile, a global npm package installed meanwhile, a venv
#     made meanwhile: each skips its item.
: > "$tmp/state/calls"
rm -rf "$repo/services"
kb "$L/pnpm/store" 3145728; kb "$NV/v22.0.0" 225280
printf '    1 /sbin/launchd\n  321 -zsh\n' > "$tmp/state/ps"
# shellcheck disable=SC2317,SC2329  # called by disk_apply, by name
meanwhile() {
    case "$1" in
        *"pnpm store prune"*) printf '    1 /sbin/launchd\n 4343 node /x/pnpm.cjs install\n' > "$tmp/state/ps" ;;
        *"fnm uninstall v22.0.0"*) mkdir -p "$NV/v22.0.0/installation/lib/node_modules/typescript" ;;
        *"uv python uninstall"*) mkdir -p "$repo/tools/.venv"
            printf 'home = %s/cpython-3.14.9-macos-aarch64-none/bin\n' "$P" > "$repo/tools/.venv/pyvenv.cfg" ;;
    esac
    return 0
}
DISK_FD="" disk_collect
disk_apply meanwhile > "$tmp/recheck.txt"
grep -q "skipped, changed since the plan: pnpm store prune: in use: pid 4343" "$tmp/recheck.txt" || fail "pnpm starting after the plan not seen: $(cat "$tmp/recheck.txt")"
grep -q "skipped, changed since the plan: fnm uninstall v22.0.0: global npm packages installed with it would go too: typescript" "$tmp/recheck.txt" \
    || fail "a global package installed after the plan not seen: $(cat "$tmp/recheck.txt")"
grep -q "skipped, changed since the plan: uv python uninstall .*: a venv uses it" "$tmp/recheck.txt" || fail "a venv made after the plan not seen: $(cat "$tmp/recheck.txt")"
! grep -q "pnpm store prune\|fnm uninstall\|uv python uninstall" "$tmp/state/calls" || fail "ran after something changed: $(cat "$tmp/state/calls")"
printf '    1 /sbin/launchd\n  321 -zsh\n' > "$tmp/state/ps"
pass "after each yes it checks again: a process, a global package or a venv that appeared skips the item"

# 17. A command that fails stops that item only, shows its output, and
#     nothing bigger is tried.
: > "$tmp/state/calls"; touch "$tmp/state/uv.fail"
kb "$HOME/.cache/uv" 204800
DISK_FD="" disk_collect; disk_apply yes_fn > "$tmp/fail.txt"
grep -q "failed (exit 2): uv cache prune. Nothing else is tried" "$tmp/fail.txt" && grep -q "the cache is locked by another uv" "$tmp/fail.txt" \
    || fail "a failure not reported with its output: $(cat "$tmp/fail.txt")"
[[ "$(grep -c '^uv cache' "$tmp/state/calls")" == 1 ]] || fail "a failure was retried"
grep -qE '	uv	uv cache prune	2	' "$TUIDEV_STATE_DIR/disk.log" || fail "a failure was not logged"
rm "$tmp/state/uv.fail"
pass "a failed command stops that item only, with its output, and is logged"

# 18. A tool that fails, hangs up or is missing never aborts the audit, which
#     runs under set -euo pipefail.
for t in go npm pnpm uv brew fnm podman docker; do
    stub "$t" 'echo "error: broken" >&2; exit 3'
done
( set -euo pipefail; DISK_FD="" disk_collect; disk_report >/dev/null; disk_json >/dev/null ) || fail "a failing tool aborted the audit"
for t in go npm pnpm uv brew fnm podman docker pip3; do rm -f "$tmp/bin/$t"; done
( set -euo pipefail; DISK_FD="" disk_collect; disk_report >/dev/null ) || fail "missing tools aborted the audit"
DISK_FD="" disk_collect; out="$(disk_report)"
# The stubs are gone; a go the system itself ships (/usr/bin/go) is still there.
if command -v go >/dev/null 2>&1; then
    echo "SKIP: a system go is on PATH, so a missing go cannot be staged"
else
    [[ "$out" == *"Go module cache"*"go is not installed any more"* ]] || fail "a missing go's cache not stale: $out"
fi
pass "failing and missing tools are skipped or judged, never fatal"

# 19. The script: --json on stdout with progress on stderr, --explain, a
#     non-interactive --fix without --yes changes nothing, a dry run, bad
#     options exit 2.
# shellcheck disable=SC2016
stub go "$log"
kb "$L/Caches/go-build" 409600
# The script asks uname, not as_macos: name the cache so Linux finds it too.
export GOCACHE="$L/Caches/go-build"
: > "$tmp/state/calls"
"$SCRIPT_DIR/../disk.sh" --json --quick --min 0 > "$tmp/script.json" 2> "$tmp/script.err" || fail "disk.sh --json failed"
[[ -z "$real_jq" ]] || jq -e '.items | length > 0' "$tmp/script.json" >/dev/null || fail "disk.sh --json: $(cat "$tmp/script.json")"
grep -q "du -sk" "$tmp/script.err" && ! grep -q "du -sk" "$tmp/script.json" || fail "progress is not on stderr only"
"$SCRIPT_DIR/../disk.sh" --quick --explain go-build > "$tmp/explain.txt" 2>/dev/null || fail "--explain failed"
grep -q "what:    Compiled Go packages" "$tmp/explain.txt" && grep -q "cost:    the next build recompiles" "$tmp/explain.txt" \
    && grep -q "command: go clean -cache" "$tmp/explain.txt" && grep -q -- "--fix:   would ask" "$tmp/explain.txt" \
    || fail "--explain: $(cat "$tmp/explain.txt")"
"$SCRIPT_DIR/../disk.sh" --quick --explain go-mod > "$tmp/explain.txt" 2>/dev/null
grep -q -- "--fix:   never: no tool has a cleanup command for it that --fix runs" "$tmp/explain.txt" || fail "--explain of a report-only item: $(cat "$tmp/explain.txt")"
rc=0; "$SCRIPT_DIR/../disk.sh" --quick --explain nope >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--explain of an unknown ID exit $rc"
"$SCRIPT_DIR/../disk.sh" --fix --quick < /dev/null > "$tmp/script.txt" 2>/dev/null || fail "disk.sh --fix without a terminal failed"
[[ ! -s "$tmp/state/calls" ]] && grep -q "Plan:" "$tmp/script.txt" && grep -q "Not a terminal and no --yes: nothing ran" "$tmp/script.txt" \
    || fail "non-interactive --fix without --yes: $(cat "$tmp/script.txt") $(cat "$tmp/state/calls")"
"$SCRIPT_DIR/../disk.sh" --fix --yes --dry-run --quick < /dev/null > "$tmp/script.txt" 2>/dev/null || fail "disk.sh --fix --dry-run failed"
[[ ! -s "$tmp/state/calls" ]] && grep -q "Dry run: nothing changed" "$tmp/script.txt" || fail "disk.sh dry run: $(cat "$tmp/script.txt")"
for bad in "--json --fix" "--min lots" "--explain"; do
    rc=0
    # shellcheck disable=SC2086  # the options are split on purpose
    "$SCRIPT_DIR/../disk.sh" $bad >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 2 ]] || fail "'$bad' exit $rc"
done
pass "disk.sh: --json, --explain, --fix without a terminal, a dry run, and bad options"

echo ""
echo "All disk fix tests passed."
