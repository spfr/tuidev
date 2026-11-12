#!/bin/bash
# shellcheck disable=SC2015,SC2034  # "A && B || fail" fails on either; DISK_* settings are read by the lib
# Unit tests for scripts/lib/disk.sh and scripts/disk.sh, the disk audit.
# Run: bash scripts/lib/test_disk.sh  -> exit 0 on pass.
#
# Everything runs against a throwaway HOME with made-up caches, runtimes,
# transcripts and git repos. The tools the audit asks (go, npm, pnpm, uv,
# pip3, brew, fnm, podman, docker), du, ps and readlink are stubs on a PATH
# of their own, so sizes and processes are exact and no real cache is
# touched. Sizes live in a table beside the stubs ($tmp/state/sizes), never as
# files in the folders. Each stub that would change something only appends
# its command line to $tmp/state/calls; a read must leave that file empty.
# Portable to BSD, GNU and BusyBox userlands (the Alpine test image).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export HOME="$tmp/home" TUIDEV_NO_COLOR=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR TUIDEV_PERF_DIRS CARGO_HOME \
    BUN_INSTALL_CACHE_DIR GOPATH GOCACHE GOMODCACHE GOENV npm_config_store_dir PNPM_HOME CLAUDE_CONFIG_DIR CODEX_HOME \
    PLAYWRIGHT_BROWSERS_PATH CYPRESS_CACHE_FOLDER TUIDEV_DISK_STALE_DAYS TUIDEV_DISK_DEPTH TUIDEV_DISK_JOBS DISK_FD
mkdir -p "$HOME" "$tmp/bin" "$tmp/state"
: > "$tmp/state/calls"; : > "$tmp/state/sizes"; : > "$tmp/state/readlinks"
git config --global init.defaultBranch main
git config --global advice.detachedHead false
printf 'node_modules/\ndist/\n*.db\nold dist/\n\\*/\n' > "$tmp/ignore"; git config --global core.excludesFile "$tmp/ignore"

# The real tools the audit needs beside the stubs; nothing else from the
# caller's PATH (a real bun, cargo or docker would change the answers).
real_fd="$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)"
real_jq="$(command -v jq 2>/dev/null || true)"
real_readlink="$(command -v readlink)"
ln -s "$(command -v git)" "$tmp/bin/git"
[[ -z "$real_jq" ]] || ln -s "$real_jq" "$tmp/bin/jq"
export PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Stubs. Their bodies are single-quoted on purpose: they expand when the stub
# runs. kb DIR N makes DIR and gives it N KB for the du stub; ps prints
# $tmp/state/ps; readlink counts its calls and asks the real one.
# shellcheck disable=SC2016,SC2329
{
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
log='echo "$(basename "$0") $*" >> "'"$tmp"'/state/calls"'
stub du 'for a in "$@"; do case "$a" in -*) continue ;; esac
  r="$(cd "$a" 2>/dev/null && pwd -P || printf "%s" "$a")"
  kb="$(R="$r" awk -F"\t" "\$2 == ENVIRON[\"R\"] { k = \$1 } END { print k }" "'"$tmp"'/state/sizes")"
  if [[ -z "$kb" && -f "$a" ]]; then kb=$(( ($(wc -c < "$a") + 1023) / 1024 )); fi
  printf "%s\t%s\n" "${kb:-0}" "$a"; done'
stub ps 'cat "'"$tmp"'/state/ps"'
stub readlink 'echo x >> "'"$tmp"'/state/readlinks"; exec "'"$real_readlink"'" "$@"'
stub go "$log"'; if [[ "$1 $2" == "clean -cache" ]]; then printf "0\t%s\n" "$(cd "$HOME/Library/Caches/go-build" && pwd -P)" >> "'"$tmp"'/state/sizes"; fi'
stub npm 'echo "${npm_config_logs_max:-unset}" > "'"$tmp"'/state/npm.logsmax"
  case "$1 $2" in "config get") echo "$HOME/.npm" ;; *) '"$log"' ;; esac'
stub pnpm "$log"
stub uv 'nc=""; if [[ "$1" == --no-cache ]]; then nc=1; shift; fi
  case "$1 $2" in
  "cache dir") echo "$HOME/.cache/uv" ;;
  "python dir") echo "$HOME/.local/share/uv/python" ;;
  "tool dir") echo "$HOME/.local/share/uv/tools" ;;
  "python list") if [[ -z "$nc" ]]; then echo "uv python list with the cache on" >> "'"$tmp"'/state/calls"; fi; cat "'"$tmp"'/state/uv.list" ;;
  "cache prune") '"$log"'; if [[ -f "'"$tmp"'/state/uv.fail" ]]; then echo "error: the cache is locked by another uv"; exit 2; fi ;;
  *) '"$log"' ;; esac'
stub pip3 'echo "bad interpreter: no such file or directory" >&2; exit 126'
stub brew 'case "$1" in --cache) echo "$HOME/Library/Caches/Homebrew" ;; --prefix) exit 1 ;; *) '"$log"' ;; esac'
stub fnm 'mkdir -p "$FNM_DIR/aliases"; '"$log"
stub podman 'case "$1 $2" in "system df") printf "1.5GB|1.2GB (80%%)\n0B|0B (0%%)\n120MB|0B (0%%)\n" ;; *) '"$log"' ;; esac'
stub docker 'case "$1" in --version) echo "Docker version 27.0.0" ;; system) printf "2GB|1GB (50%%)\n" ;; *) '"$log"' ;; esac'
stub touchme "$log"
}
kb() { mkdir -p "$1"; printf '%s\t%s\n' "$2" "$(cd "$1" && pwd -P)" >> "$tmp/state/sizes"; }
printf '    1 /sbin/launchd\n  321 -zsh\n' > "$tmp/state/ps"

# shellcheck source=./ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"
# shellcheck source=./disk.sh disable=SC1091
. "$SCRIPT_DIR/disk.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
# shellcheck disable=SC2317,SC2329  # redefined on purpose, called by the lib
as_macos() { is_macos() { return 0; }; is_linux() { return 1; }; }
as_macos
out=""
audit() { disk_collect; out="$(disk_report)"; }
json=""
# item ID FIELD — FIELD of the first item whose id is ID, from $json (jq).
item() { jq -r --arg id "$1" "[.items[] | select(.id == \$id)][0].$2 | if . == null then \"\" else . end" <<< "$json"; }
# yes_fn says yes, and fails the test if any command ran before the plan was
# printed in full (the plan's last line is in the file by the first question).
# shellcheck disable=SC2317,SC2329  # called by disk_apply, by name
yes_fn() {
    [[ -s "$tmp/state/calls" ]] || grep -q "Plan:" "$tmp/fix.txt" || fail "asked before the plan was printed"
    return 0
}
# shellcheck disable=SC2317,SC2329
no_fn() { return 1; }
# when EPOCH FORMAT — a date, portably: BSD date -r, GNU and BusyBox date -d @.
when() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2"; }
old() { touch -t 202001010000 "$@"; }
e2d=$(( $(date +%s) - 2 * 86400 ))
ago2d="$(when "$e2d" %Y%m%d%H%M)"
day2="$(when "$e2d" %Y-%m-%dT%H:%M:%S)"
# snapshot — every path under $HOME with its mtime.
snapshot() { find "$HOME" -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(_disk_mtime "$f")"; done; }
# quiet WT — make worktree WT look untouched for two days.
quiet() { touch -t "$ago2d" "$repo/.git/worktrees/$(basename "$1")/index" "$1"; }
# wt NAME [ARGS] — a worktree of $repo at main, merged and quiet.
wt() { git -C "$repo" worktree add -q "${@:2}" "$W/$1" main; }

# --- the machine --------------------------------------------------------------
L="$HOME/Library"
kb "$L/Caches/go-build" 409600                  # 400 MB
kb "$HOME/go/pkg/mod" 2097152                   # 2 GB
kb "$HOME/.npm/_cacache" 153600
kb "$L/pnpm/store" 3145728
kb "$HOME/.cache/uv" 204800
kb "$L/Caches/pip" 102400
kb "$L/Caches/Homebrew" 512000
kb "$HOME/.bun/install/cache" 307200            # bun is not installed: stale
kb "$L/Developer/Xcode/DerivedData" 716800
kb "$L/Developer/Xcode/iOS DeviceSupport" 1048576
mkdir -p "$L/Developer/Xcode/iOS DeviceSupport/17.0 (21A329)"
kb "$L/Developer/CoreSimulator" 4194304
kb "$L/Application Support/com.apple.container" 5242880
kb "$HOME/.local/share/containers/podman/machine" 8388608
# fnm, read from its folders: v20.1.0 is the default, v22.0.0 has an alias,
# v18.0.0 has global npm packages.
export FNM_DIR="$HOME/.local/share/fnm"
NV="$FNM_DIR/node-versions"
for v in v18.0.0 v18.2.0 v20.1.0 v20.3.0 v22.0.0 v22.2.0; do kb "$NV/$v" 225280; mkdir -p "$NV/$v/installation/lib/node_modules/npm"; done
mkdir -p "$NV/v18.0.0/installation/lib/node_modules/corepack" "$NV/v18.0.0/installation/lib/node_modules/firebase-tools" \
    "$NV/v18.0.0/installation/lib/node_modules/@acme/devtools-mcp" "$FNM_DIR/aliases"
ln -s "$NV/v20.1.0/installation" "$FNM_DIR/aliases/default"
ln -s "$NV/v22.0.0/installation" "$FNM_DIR/aliases/lts-latest"
P="$HOME/.local/share/uv/python"
kb "$P/cpython-3.14.9-macos-aarch64-none" 153600
kb "$P/cpython-3.14.10-macos-aarch64-none" 153600
kb "$P/cpython-3.15.0a1-macos-aarch64-none" 153600
cat > "$tmp/state/uv.list" <<EOF
cpython-3.15.0a1-macos-aarch64-none    $P/cpython-3.15.0a1-macos-aarch64-none/bin/python3.15
cpython-3.14.10-macos-aarch64-none     $P/cpython-3.14.10-macos-aarch64-none/bin/python3.14
cpython-3.14.10+freethreaded-macos-aarch64-none    <download available>
cpython-3.14.9-macos-aarch64-none      $P/cpython-3.14.9-macos-aarch64-none/bin/python3.14
EOF
kb "$HOME/.claude/projects" 2097152
mkdir -p "$HOME/.claude/projects/-w-app"
printf '{"a":1}\n' > "$HOME/.claude/projects/-w-app/new.jsonl"
head -c 4096 /dev/zero > "$HOME/.claude/projects/-w-app/old.jsonl"
kb "$HOME/.codex/sessions" 10240
mkdir -p "$TUIDEV_STATE_DIR/backups"
echo a > "$TUIDEV_STATE_DIR/backups/zshrc.1"; echo b > "$TUIDEV_STATE_DIR/backups/zshrc.2"
# Nothing was written to the caches lately: the in-use check looks at that.
find "$HOME" -exec touch -t 202001010000 {} \; 2>/dev/null || true
touch "$HOME/.claude/projects/-w-app/new.jsonl"

# Repos: one untouched for years, with a space in its path; one in use, in a
# code folder named twice (through a symlink, as ~/projects and ~/Projects
# are one folder on a case-insensitive disk), with worktrees in every state.
oldrepo="$HOME/workspace/old app"
mkdir -p "$oldrepo/dist"; echo x > "$oldrepo/dist/keep.js"
git -C "$oldrepo" init -q
git -C "$oldrepo" add -f -A
GIT_AUTHOR_DATE=2020-01-01T00:00:00 GIT_COMMITTER_DATE=2020-01-01T00:00:00 git -C "$oldrepo" commit -qm old
printf '%s\t%s\n' 51200 "$(cd "$oldrepo/dist" && pwd -P)" >> "$tmp/state/sizes"   # tracked: never build output
kb "$oldrepo/node_modules" 307200
kb "$oldrepo/.venv" 204800
mkdir -p "$oldrepo/node_modules/dep/.git"      # a repo inside node_modules: never searched
old "$oldrepo/.git/index" "$oldrepo"

mkdir -p "$HOME/my code"; ln -s "$HOME/my code" "$HOME/code-link"
export TUIDEV_PERF_DIRS="$HOME/code-link:$HOME/my code"
repo="$HOME/my code/fresh"
W="$repo/.claude/worktrees"
mkdir -p "$repo"; git -C "$repo" init -q
echo a > "$repo/a"; git -C "$repo" add a
GIT_AUTHOR_DATE="$day2" GIT_COMMITTER_DATE="$day2" git -C "$repo" commit -qm one
kb "$repo/node_modules" 512000
git -C "$repo" config status.showUntrackedFiles no      # git status alone would hide untracked files
# done: merged, quiet, ignored build folders only (one nested): stale.
wt "done" -b "done"; kb "$W/done" 204800; mkdir -p "$W/done/node_modules/x" "$W/done/pkg/dist/js"
echo x > "$W/done/pkg/dist/js/a.js"; quiet "$W/done"
# wip: an untracked file, hidden from plain git status by the repo's config.
wt wip -b wip; kb "$W/wip" 1048576; echo draft > "$W/wip/notes.txt"; quiet "$W/wip"
# dbwt: an ignored file that is not build output, with a non-ASCII name.
wt dbwt -b dbwt; kb "$W/dbwt" 1048576; echo data > "$W/dbwt/naïve.db"; quiet "$W/dbwt"
# odd: an ignored folder whose name ends in a build name, "old dist".
wt odd -b odd; kb "$W/odd" 1048576; mkdir -p "$W/odd/old dist"; echo keep > "$W/odd/old dist/notes.txt"; quiet "$W/odd"
# star: an ignored folder named *, beside a real dist.
wt star -b star; kb "$W/star" 1048576; mkdir -p "$W/star/*" "$W/star/dist"; echo keep > "$W/star/*/f"; quiet "$W/star"
# lost: a detached HEAD with a commit no ref has.
wt lost --detach
echo l > "$W/lost/l"; git -C "$W/lost" add l
GIT_AUTHOR_DATE=2020-01-01T00:00:00 GIT_COMMITTER_DATE=2020-01-01T00:00:00 git -C "$W/lost" commit -qm lost
kb "$W/lost" 204800; old "$repo/.git/worktrees/lost/index" "$W/lost"
# atmain: detached at main's commit: reachable, merged, quiet.
wt atmain --detach; kb "$W/atmain" 204800; quiet "$W/atmain"
# busy: a new commit today: in use.
wt busy -b busy; echo c > "$W/busy/c"; git -C "$W/busy" add c; git -C "$W/busy" commit -qm busy
kb "$W/busy" 307200
# ghost: no .git, git does not list it. ghost2: a .git of its own.
kb "$W/ghost" 102400
kb "$W/ghost2" 102400; echo "gitdir: /elsewhere" > "$W/ghost2/.git"
mkdir -p "$HOME/workspace/a/b/c/d/deep/.git"   # deeper than TUIDEV_DISK_DEPTH

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
[[ "$out" == *"Go module cache"*"go is not installed any more"* ]] || fail "a missing go's cache not stale: $out"
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
echo "All disk lib tests passed."
