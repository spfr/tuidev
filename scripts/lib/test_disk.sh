#!/bin/bash
# shellcheck disable=SC2015,SC2034,SC2154  # "A && B || fail" fails on either; DISK_* are read by the lib; the rest is set in disk_fixture.sh
# Unit tests for scripts/lib/disk.sh and scripts/disk.sh, the disk audit:
# what a read finds, says and leaves untouched (the --fix side is in
# test_disk_fix.sh).
# Run: bash scripts/lib/test_disk.sh  -> exit 0 on pass.
#
# The machine they run against is disk_fixture.sh: a throwaway HOME and stub
# tools, so no real cache is touched. The two test files are separate so they
# run at the same time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./disk_fixture.sh disable=SC1091
. "$SCRIPT_DIR/disk_fixture.sh"

# --- tests ----------------------------------------------------------------------

# 1. A read writes nothing under $HOME and runs no tool that writes when
#    asked (go, pnpm, fnm, uv with its cache, npm with its debug log). fnm's
#    aliases folder is not created where it is missing.
mkdir -p "$HOME/fnm2/node-versions/v1.0.0"
before="$(snapshot)"
DISK_FD="" disk_collect; out="$(disk_report)"; json="$(disk_json)"
DISK_FD="" disk_collect --quick; disk_report >/dev/null
FNM_DIR="$HOME/fnm2" DISK_FD="" disk_collect --quick
[[ "$(snapshot)" == "$before" ]] || fail "a read changed \$HOME: $(diff <(echo "$before") <(snapshot) | head -5)"
[[ ! -e "$HOME/fnm2/aliases" ]] || fail "a read created fnm's aliases folder"
[[ ! -s "$tmp/state/calls" ]] || fail "a read ran a tool that writes: $(cat "$tmp/state/calls")"
[[ "$(cat "$tmp/state/npm.logsmax")" == 0 ]] || fail "npm ran with its debug log on"
pass "a read writes nothing under \$HOME and runs nothing that writes (go, pnpm, fnm, uv's cache, npm's log)"

# 2. Each verdict, each item explained: what, why, cost, and the command.
DISK_FD="" audit
[[ "$out" == *"regenerable: caches a tool rebuilds"* && "$out" == *"stale: superseded or unused"* \
    && "$out" == *"managed: another tool owns the cleanup"* && "$out" == *"yours: never offered for deletion"* ]] \
    || fail "a verdict group is missing: $out"
[[ "$out" == *"400 MB  Go build cache   ~/Library/Caches/go-build"*"what: Compiled Go packages"*"why:  a cache go owns and rebuilds; nothing in it written to in 3 months"*"cost: the next build recompiles"*"run (--fix offers this): go clean -cache"* ]] \
    || fail "the Go build cache is not explained with its command: $out"
[[ "$out" == *"Go module cache"*"toolchains"*"by hand (--fix never runs this): go clean -modcache"* ]] || fail "the Go module cache is not report-only: $out"
[[ "$out" == *"bun cache   ~/.bun/install/cache"*"bun is not installed any more"*"by hand (--fix never runs this): rm -rf ~/.bun/install/cache"* ]] \
    || fail "a cache whose tool is gone is not stale and report-only: $out"
[[ "$out" == *"3.0 GB  pnpm store   ~/Library/pnpm/store"*"run (--fix offers this): pnpm store prune"* ]] || fail "pnpm's default store not found: $out"
[[ "$out" == *"Homebrew downloads"*"removed from Homebrew's prefix (outside your home)"*"by hand (--fix never runs this): HOMEBREW_NO_AUTOREMOVE=1 brew cleanup -s --prune=all"* ]] \
    || fail "Homebrew is not report-only with its exact cost: $out"
[[ "$out" == *"Simulators"*"its tool: xcrun simctl delete unavailable"* ]] || fail "CoreSimulator not managed: $out"
[[ "$out" == *"Podman storage"*"1.1 GB of the images and containers in it is reclaimable"*"its tool: podman image prune -a"* ]] \
    || fail "podman's reclaimable size not read: $out"
[[ "$out" == *"Docker storage"*"954 MB of it is reclaimable"* ]] || fail "docker system df not read: $out"
[[ "$out" == *"Claude Code transcripts"*"2 of them"*"4.0 KB is in files older than 90 days"* ]] || fail "transcripts: $out"
[[ "$out" != *"Codex sessions"* && "$out" != *"tuidev backups"* ]] || fail "a small 'yours' item was listed: $out"
pass "regenerable, stale, managed and yours each say what, why, the cost and the command"

# 3. Runtimes, read from fnm's folders: superseded patches are stale; a Node
#    version with global npm packages is held back and names them; the
#    default is never listed; an alias is named.
[[ "$out" == *"Node v22.0.0 (fnm)"*"alias lts-latest points at it"*"run (--fix offers this): fnm uninstall v22.0.0"* ]] \
    || fail "superseded Node not offered: $out"
[[ "$out" == *"Node v18.0.0 (fnm)"*"--fix skips it now: global npm packages installed with it would go too: firebase-tools, @acme/devtools-mcp"*"run (--fix skips it now): fnm uninstall v18.0.0"* ]] \
    || fail "a Node with global packages was offered: $out"
[[ "$out" != *"Node v20.1.0"* && "$out" != *"Node v20.3.0"* && "$out" != *"Node v22.2.0"* ]] || fail "the default or a newest Node was listed: $out"
[[ "$out" == *"Python cpython-3.14.9-macos-aarch64-none (uv)"*"run (--fix offers this): uv python uninstall cpython-3.14.9"* ]] \
    || fail "a superseded Python with no venv on it not offered: $out"
[[ "$out" != *"cpython-3.15.0a1"* && "$out" != *"Python cpython-3.14.10"* ]] || fail "a current Python was listed: $out"
pass "runtimes: read from fnm's folders; superseded patches are stale; global npm packages block fnm uninstall"

# 4. Repos: an untouched repo's untracked build output is stale and report
#    only; tracked dist is not output; a repo in use is counted once, though
#    its folder is reachable twice; depth is bounded; node_modules is never
#    searched; a symlinked code folder is followed.
[[ "$out" == *"old app/node_modules   ~/workspace/old app/node_modules"*"by hand (--fix never runs this): rm -rf ~/workspace/old\\ app/node_modules"* ]] \
    || fail "stale build output: $out"
[[ "$out" == *"old app/.venv"* && "$out" != *"old app/dist"* ]] || fail "tracked dist or untracked .venv wrong: $out"
[[ "$out" != *"fresh/node_modules"* && "$out" == *"In use: 800 MB of build output and worktrees in 1 repo(s)"* ]] \
    || fail "a repo in use was listed, or counted twice: $out"
[[ "$(grep -c "fresh worktree wip" <<< "$out")" == 1 ]] || fail "the same repo was scanned twice: $out"
[[ "$out" != *"deep"* && "$out" != *"dep/"* ]] || fail "the repo search went too deep or into node_modules: $out"
[[ "$out" == *"~/code-link/fresh"* ]] || fail "find did not follow the symlinked code folder: $out"
pass "repos: build output of an untouched repo is report-only; one repo is scanned once"

# 5. Worktrees are report-only, with the command git itself refuses untracked
#    files with. The verdict is still right: only build folders may be
#    ignored in one (the last path component, compared literally: not "old
#    dist", not "*"), nothing untracked, nothing changed, and a detached HEAD
#    must be on some ref. A folder git does not list is compared by inode,
#    and one with its own .git is yours.
all="$(DISK_MIN_KB=0 DISK_YOURS_MIN_KB=0 disk_report)"
[[ "$out" == *"fresh worktree done"*"cost: the folder goes, with its build folders"*"and everything inside them"*"branch done stays in the repo with all its commits"*"by hand (--fix never runs this): git -c status.showUntrackedFiles=all -C ~/code-link/fresh worktree remove ~/my\\ code/fresh/.claude/worktrees/done"* ]] \
    || fail "a clean merged worktree not report-only with its exact cost: $out"
[[ "$out" == *"fresh worktree wip"*"untracked files git worktree remove would delete: notes.txt"* ]] || fail "an untracked file hidden by showUntrackedFiles=no: $out"
[[ "$out" == *"fresh worktree dbwt"*"ignored files that are not build output"*"naïve.db"* ]] || fail "an ignored non-ASCII file not protected: $out"
[[ "$out" == *"fresh worktree odd"*"ignored files that are not build output"*"old dist/"* ]] || fail "'old dist/' counted as build output: $out"
[[ "$out" == *"fresh worktree star"*"ignored files that are not build output"*"*/"* ]] || fail "a folder named * counted as build output: $out"
[[ "$all" == *"fresh worktree lost"*"a detached HEAD with commits no branch, tag or remote contains"* ]] || fail "an unreachable detached HEAD not protected"
[[ "$out" == *"fresh worktree atmain"*"its commit stays reachable from "*"by hand (--fix never runs this)"* ]] || fail "a reachable detached worktree: $out"
[[ "$out" != *"worktree busy"* ]] || fail "a busy worktree was listed: $out"
[[ "$out" != *"leftover wip"* && "$out" != *"leftover done"* && "$out" != *"leftover busy"* ]] || fail "a live worktree reported as leftover: $out"
[[ "$out" == *"fresh leftover ghost"*"by hand (--fix never runs this): rm -rf"* ]] || fail "a leftover folder: $out"
[[ "$all" == *"fresh folder ghost2"*"has a .git entry"* ]] || fail "a folder with its own .git not yours"
before="$(_disk_mtime "$repo/.git/worktrees/wip/index")"
audit
[[ "$(_disk_mtime "$repo/.git/worktrees/wip/index")" == "$before" ]] || fail "looking rewrote a worktree's index"
pass "worktrees: report-only; only clean ones on a ref are stale; 'old dist', '*' and non-ASCII names classify right"

# 6. fd and find find the same repos.
if [[ -n "$real_fd" ]]; then
    a="$(DISK_FD="" _disk_find_repos "$HOME/workspace" | sort)"
    b="$(DISK_FD="$real_fd" _disk_find_repos "$HOME/workspace" | sort)"
    [[ -n "$a" && "$a" == "$b" ]] || fail "fd and find disagree: [$a] [$b]"
    pass "fd and find find the same repos"
else
    echo "SKIP: fd not installed (find fallback covered above)"
fi

# 7. --quick leaves the repos and the venv search out (so no Python is
#    offered); progress goes to stderr and ends with what was not looked at.
DISK_PROGRESS=true disk_collect --quick 2> "$tmp/progress.txt"; out="$(disk_report)"
[[ "$out" != *"old app"* && "$out" != *"worktree"* && "$out" == *"Go module cache"* ]] || fail "--quick still scanned repos: $out"
[[ "$out" == *"Python cpython-3.14.9"*"--fix skips it now: venvs were not searched (--quick)"* ]] || fail "--quick offered a Python: $out"
grep -q "Go build cache: found with GOCACHE" "$tmp/progress.txt" && grep -q "du -sk ~/Library/Caches/go-build" "$tmp/progress.txt" \
    && grep -q "repos: skipped (--quick)" "$tmp/progress.txt" && grep -q "Not looked at: the rest of your home folder" "$tmp/progress.txt" \
    && grep -q "fnm is not run" "$tmp/progress.txt" || fail "progress does not say what and how: $(cat "$tmp/progress.txt")"
! grep -q "not present" "$tmp/progress.txt" || fail "'not present' without --verbose"
DISK_PROGRESS=true DISK_VERBOSE=true disk_collect --quick 2> "$tmp/progress.txt"
grep -q "not present: Gradle caches" "$tmp/progress.txt" || fail "--verbose does not say what is not there"
pass "--quick skips repos and offers no Python; stderr says what is looked at, how, and what is not"

# 8. --min, and the code-folder lists never fail when the last folder is missing.
DISK_FD="" disk_collect
DISK_MIN_KB=0 DISK_YOURS_MIN_KB=0 disk_report > "$tmp/all.txt"
{ grep -q "Codex sessions" "$tmp/all.txt" && grep -q "Copies tuidev took of your files before changing them: 2 of them" "$tmp/all.txt"; } \
    || fail "--min 0 did not list small yours items"
[[ "$(disk_parse_size 100M) $(disk_parse_size 1G) $(disk_parse_size 1.5G) $(disk_parse_size 500MB) $(disk_parse_size 1GiB) $(disk_parse_size 0) $(disk_parse_size 2048)" \
    == "102400 1048576 1572864 512000 1048576 0 2" ]] || fail "disk_parse_size"
! disk_parse_size bogus >/dev/null || fail "disk_parse_size accepted bogus"
( set -e; TUIDEV_PERF_DIRS="$HOME/nope" perf_code_dirs >/dev/null; perf_store_dirs >/dev/null ) || fail "a missing last folder made a list fail"
[[ "$(TUIDEV_PERF_DIRS="$HOME/code-link:$HOME/my code" perf_code_dirs | grep -c 'code')" == 1 ]] || fail "one folder reached twice was listed twice"
pass "--min sizes parse; code folders are listed once each and the lists never fail"

# 9. pnpm's store: store-dir from pnpm's rc file, then PNPM_HOME, then the
#    default; ~/.npmrc is never read, and when it exists prune is not offered.
mkdir -p "$L/Preferences/pnpm"; printf 'store-dir = ~/elsewhere/store\n' > "$L/Preferences/pnpm/rc"
[[ "$(perf_pnpm_store)" == "$HOME/elsewhere/store" ]] || fail "store-dir in pnpm's rc not read: $(perf_pnpm_store)"
rm "$L/Preferences/pnpm/rc"
[[ "$(PNPM_HOME="$HOME/ph" perf_pnpm_store)" == "$HOME/ph/store" ]] || fail "PNPM_HOME not honoured"
[[ "$(perf_pnpm_store)" == "$L/pnpm/store" ]] || fail "pnpm's macOS default: $(perf_pnpm_store)"
DISK_FD="" disk_collect --quick; json="$(disk_json)"
[[ "$(PNPM_HOME="$HOME/nowhere" disk_collect --quick; disk_json)" != *'"id":"pnpm"'* ]] || fail "a store folder that does not exist was listed"
# ~/.npmrc is a credential path: never read, and its presence holds prune back.
echo "store-dir=$HOME/elsewhere/store" > "$HOME/.npmrc"
[[ "$(perf_pnpm_store)" == "$L/pnpm/store" ]] || fail ".npmrc was read for store-dir: $(perf_pnpm_store)"
DISK_FD="" disk_collect --quick; out="$(disk_report)"
[[ "$out" == *"pnpm store"*"--fix skips it now: pnpm's store could not be confirmed: ~/.npmrc may name another one"* ]] || fail ".npmrc did not hold pnpm back: $out"
out="$(npm_config_store_dir="$L/pnpm/store" disk_collect --quick; disk_report)"
[[ "$out" != *"pnpm's store could not be confirmed"* ]] || fail "npm_config_store_dir did not confirm the store: $out"
rm "$HOME/.npmrc"
mkdir -p "$L/Preferences/pnpm"; echo "store-dir=$L/pnpm/store" > "$L/Preferences/pnpm/rc"; chmod 000 "$L/Preferences/pnpm/rc"
if ! cat "$L/Preferences/pnpm/rc" >/dev/null 2>&1; then
    DISK_FD="" disk_collect --quick; out="$(disk_report)"
    [[ "$out" == *"pnpm store"*"--fix skips it now: pnpm's store could not be confirmed: ~/Library/Preferences/pnpm/rc could not be read"* ]] || fail "an unreadable pnpm rc did not hold pnpm back: $out"
else
    echo "SKIP: running as root, an unreadable file cannot be made"
fi
chmod 600 "$L/Preferences/pnpm/rc"; rm "$L/Preferences/pnpm/rc"
pass "pnpm's store comes from its rc file, PNPM_HOME or the default; ~/.npmrc is never read and holds prune back"

# 10. JSON: one valid object, strings escaped, without jq to build it;
#     fix_offered is the same decision --fix makes.
export PLAYWRIGHT_BROWSERS_PATH="$HOME/we\"ird\\pw"
kb "$PLAYWRIGHT_BROWSERS_PATH" 204800
DISK_FD="" disk_collect
json="$(DISK_MIN_KB=0 DISK_YOURS_MIN_KB=0 disk_json)"
[[ "$json" == '{"generated_at":"'*'","free_bytes":'*',"items":[{"id":'*'],"reclaimable_bytes":'*',"in_use":{"bytes":'*'}}' ]] \
    || fail "JSON shape: $json"
[[ "$(printf '%s' "$json" | wc -l | tr -d ' ')" == 0 ]] || fail "JSON is not one line"
[[ "$(_disk_json_str "a\"b\\c$(printf '\t')d$(printf '\001')e")" == '"a\"b\\c\td e"' ]] || fail "JSON escaping"
[[ "$json" == *'"path":"'"$HOME"'/we\"ird\\pw"'* ]] || fail "a quote and a backslash in a path not escaped: $json"
n_items="$(printf '%s' "$json" | grep -o '"id":' | wc -l | tr -d ' ')"
[[ "$n_items" == "$(DISK_MIN_KB=0 DISK_YOURS_MIN_KB=0 _disk_order | wc -l | tr -d ' ')" ]] || fail "JSON items do not match the listed items"
pass "JSON is one object, escaped by hand"
if [[ -n "$real_jq" ]]; then
    jq -e . <<< "$json" >/dev/null || fail "jq rejects the JSON: $json"
    [[ "$(item playwright path)" == "$PLAYWRIGHT_BROWSERS_PATH" ]] || fail "the path did not survive JSON"
    [[ "$(item go-build verdict) $(item go-build safe) $(item go-build bytes) $(item go-build fix_offered)" == "regenerable true 419430400 true" ]] \
        || fail "go-build in JSON: $json"
    [[ -n "$(item go-build what)" && -n "$(item go-build why)" && -n "$(item go-build cost)" && "$(item go-build reclaim)" == "go clean -cache" ]] \
        || fail "what, why, cost or reclaim missing in JSON"
    [[ "$(item go-mod fix_offered) $(item brew fix_offered) $(item claude fix_offered) $(item coresimulator fix_offered) $(item node:v18.0.0 fix_offered)" == "false false false false false" ]] \
        || fail "a report-only, yours, managed or blocked item is fix_offered"
    [[ "$(jq -r '[.items[] | select(.id | startswith("worktree:")) | .fix_offered] | unique | join(",")' <<< "$json")" == false ]] || fail "a worktree is fix_offered"
    [[ "$(item node:v18.0.0 fix_reason)" == *"firebase-tools"* ]] || fail "fix_reason missing"
    printf '    1 /sbin/launchd\n 4242 go test ./...\n' > "$tmp/state/ps"
    DISK_FD="" disk_collect; json="$(disk_json)"
    [[ "$(item go-build fix_offered)" == false && "$(item go-build fix_reason)" == *"pid 4242"* ]] || fail "fix_offered ignores what is in use"
    : > "$tmp/state/ps"
    DISK_FD="" disk_collect; json="$(disk_json)"
    [[ "$(item go-build fix_offered)" == false && "$(item go-build fix_reason)" == *"process table could not be read"* ]] \
        || fail "fix_offered true without a process table"
    printf '    1 /sbin/launchd\n  321 -zsh\n' > "$tmp/state/ps"
    pass "JSON is valid (jq) and fix_offered is the decision --fix makes, in use and without ps included"
else
    echo "SKIP: jq not installed (structural checks above passed)"
fi
unset PLAYWRIGHT_BROWSERS_PATH

echo ""
echo "All disk lib tests passed."
