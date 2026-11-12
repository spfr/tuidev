#!/bin/bash
# shellcheck disable=SC2015,SC2034  # "A && B || fail" fails on either; the names here are used by the tests that source this
# The throwaway machine the disk audit's tests run against: sourced by
# test_disk.sh (what a read finds and says) and test_disk_fix.sh (what --fix
# does), never run. The caller sets SCRIPT_DIR to scripts/lib first.
#
# Everything is a throwaway HOME with made-up caches, runtimes, transcripts
# and git repos. The tools the audit asks (go, npm, pnpm, uv, pip3, brew, fnm,
# podman, docker), du, ps and readlink are stubs on a PATH of their own, so
# sizes and processes are exact and no real cache is touched. Sizes live in a
# table beside the stubs ($tmp/state/sizes), never as files in the folders.
# Each stub that would change something only appends its command line to
# $tmp/state/calls; a read must leave that file empty.
# Portable to BSD, GNU and BusyBox userlands (the Alpine test image).

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
