#!/bin/bash
# Unit tests for scripts/lib/perf.sh, the performance audit.
# Run: bash scripts/lib/test_perf.sh  -> exit 0 on pass.
#
# Everything runs against a throwaway HOME, and the system commands the audit
# reads (mdfind, tmutil, pmset, defaults, pnpm, go, df) are stubs on PATH, so
# the real Spotlight index, Time Machine and ~/.gitconfig are never touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" TUIDEV_NO_COLOR=1 GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL TUIDEV_PERF_DIRS TUIDEV_PERF_INDEX_MIN BUN_INSTALL_CACHE_DIR CARGO_HOME
mkdir -p "$HOME" "$tmp/bin" "$tmp/state"
TUIDEV_STATE_DIR="$HOME/.config/tuidev"
export TUIDEV_MANIFEST_FILE="$TUIDEV_STATE_DIR/manifest"

# Stubs. Each reads its answers from $tmp/state, so a test sets a file and
# runs the audit again. Their bodies are single-quoted on purpose: they expand
# when the stub runs.
# shellcheck disable=SC2016,SC2329
{
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
stub pnpm    '[[ "$1 $2" == "store path" ]] && echo "$HOME/Library/pnpm/store/v11"'
stub go      '[[ "$1 $2" == "env GOMODCACHE" ]] && echo "$HOME/go/pkg/mod"'
stub uv      'exit 1'
stub npm     'exit 1'
stub mdfind  'dir="$2"; f="'"$tmp"'/state/indexed.$(basename "$dir")"; [[ -f "$f" ]] && cat "$f" || echo 0'
stub tmutil  'case "$1" in
  destinationinfo) cat "'"$tmp"'/state/tm.dest" 2>/dev/null || echo "tmutil: No destinations configured." ;;
  isexcluded) if grep -qxF "$2" "'"$tmp"'/state/tm.excluded" 2>/dev/null; then echo "[Excluded]  $2"; else echo "[Included]  $2"; fi ;;
  addexclusion) echo "$2" >> "'"$tmp"'/state/tm.excluded" ;;
esac'
stub pmset   'if [[ "$2" == batt ]]; then echo "Now drawing from '"'"'AC Power'"'"'"; else echo " powermode            $(cat "'"$tmp"'/state/powermode" 2>/dev/null || echo 0)"; fi'
stub defaults '[[ "$3" == "FXICloudDriveDocuments" ]] && cat "'"$tmp"'/state/icloud" 2>/dev/null || echo 0'
stub df      'case "$2" in *pnpm*) dev="$(cat "'"$tmp"'/state/pnpm.dev" 2>/dev/null || echo /dev/disk1)";; *) dev=/dev/disk1;; esac; printf "Filesystem 512-blocks Used Available Capacity Mounted\n%s 1 1 1 1%% /\n" "$dev"'
}
export PATH="$tmp/bin:$PATH"

# shellcheck source=./ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"
# shellcheck source=./manifest.sh disable=SC1091
. "$SCRIPT_DIR/manifest.sh"
# shellcheck source=./gitconfig.sh disable=SC1091
. "$SCRIPT_DIR/gitconfig.sh"
# shellcheck source=./perf.sh disable=SC1091
. "$SCRIPT_DIR/perf.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
get() { git config --global --includes --get "$1" 2>/dev/null || true; }
out=""
audit() { perf_collect; out="$(perf_report "$@")"; }
# shellcheck disable=SC2317,SC2329  # redefined on purpose, called by the lib
as_macos() { is_macos() { return 0; }; is_linux() { return 1; }; }
# shellcheck disable=SC2317,SC2329
as_linux() { is_macos() { return 1; }; is_linux() { return 0; }; }

mkdir -p "$HOME/Library/pnpm/store/v11" "$HOME/go/pkg/mod" "$HOME/workspace" "$HOME/Documents"

# --- macOS ------------------------------------------------------------------
as_macos

# 1. A package store in the Spotlight index is flagged with its count and the
#    Settings path; a repos folder is a note, not a warning; neither has a fix
#    the tool runs, because macOS has no command for the list.
echo 270240 > "$tmp/state/indexed.v11"
echo 98000 > "$tmp/state/indexed.workspace"
audit
[[ "$out" == *"Spotlight indexes 270240 files in ~/Library/pnpm/store/v11"* ]] || fail "indexed store not flagged: $out"
[[ "$out" == *"Search Privacy > + > ~/Library/pnpm/store/v11"* ]] || fail "no Settings path: $out"
[[ "$out" == *"ℹ Spotlight indexes 98000 files in ~/workspace"* ]] || fail "repos folder not a note: $out"
[[ "$out" != *"Spotlight indexes"*"go/pkg/mod"* ]] || fail "an unindexed store flagged: $out"
[[ "$out" != *"fix (--fix does this): System Settings"* ]] || fail "Spotlight offered as an automatic fix: $out"
pass "Spotlight: an indexed store is a warning, a repos folder a note, the fix is yours"

# 2. Below the threshold, and once excluded, it reads as fine.
echo 12 > "$tmp/state/indexed.v11"; rm "$tmp/state/indexed.workspace"
audit
[[ "$out" == *"✓ Spotlight: package stores and repo folders are out of the index"* ]] || fail "clean index not reported: $out"
pass "Spotlight: nothing indexed reads as fine"

# 3. TUIDEV_PERF_DIRS adds a folder of your own.
mkdir -p "$HOME/clients"; echo 5000 > "$tmp/state/indexed.clients"
TUIDEV_PERF_DIRS="$HOME/clients" audit
[[ "$out" == *"Spotlight indexes 5000 files in ~/clients"* ]] || fail "TUIDEV_PERF_DIRS ignored: $out"
rm "$tmp/state/indexed.clients"
pass "Spotlight: TUIDEV_PERF_DIRS is checked too"

# 4. Time Machine: silent with no destination; with one, each included store
#    is flagged and --fix excludes it.
audit
[[ "$out" != *"Time Machine"* ]] || fail "Time Machine reported with no destination: $out"
echo "Name : Backup" > "$tmp/state/tm.dest"
audit
[[ "$out" == *"Time Machine backs up ~/go/pkg/mod"* && "$out" == *"fix (--fix does this): tmutil addexclusion $HOME/go/pkg/mod"* ]] \
    || fail "included store not flagged: $out"
DRY_RUN=true perf_apply >/dev/null
[[ ! -f "$tmp/state/tm.excluded" ]] || fail "DRY_RUN excluded a folder"
perf_apply >/dev/null
grep -qxF "$HOME/go/pkg/mod" "$tmp/state/tm.excluded" || fail "--fix did not exclude the store"
audit
[[ "$out" == *"✓ Time Machine: package stores are excluded"* ]] || fail "excluded stores not fine: $out"
pass "Time Machine: only with a destination; --fix excludes the stores; dry run changes nothing"

# 5. Low Power Mode on the charger.
echo 1 > "$tmp/state/powermode"; audit
[[ "$out" == *"Low Power Mode is on while plugged in"* ]] || fail "low power mode not flagged: $out"
echo 0 > "$tmp/state/powermode"; audit
[[ "$out" == *"✓ Power: Low Power Mode is off"* ]] || fail "normal power not fine: $out"
pass "Low Power Mode on the charger is flagged"

# 6. Repos under a folder iCloud Drive syncs.
mkdir -p "$HOME/Documents/app/.git"; echo 1 > "$tmp/state/icloud"; audit
[[ "$out" == *"1 git repo(s) under ~/Documents, which iCloud Drive syncs"* ]] || fail "iCloud repo not flagged: $out"
mkdir -p "$HOME/Documents/code.nosync/app2/.git"; audit
[[ "$out" == *"1 git repo(s) under ~/Documents"* ]] || fail "a repo in a .nosync folder was counted: $out"
echo 0 > "$tmp/state/icloud"; audit
[[ "$out" != *"iCloud"* ]] || fail "iCloud flagged while sync is off: $out"
pass "a repo in an iCloud-synced folder is flagged, only while sync is on"

# 6b. A tool that fails (a sandbox, a folder macOS will not let us read) never
#     aborts the caller, which runs under set -euo pipefail.
stub mdfind 'exit 1'
audit
[[ "$out" != *"Spotlight"* ]] || fail "a failing mdfind produced a Spotlight line: $out"
# shellcheck disable=SC2016
stub mdfind 'dir="$2"; f="'"$tmp"'/state/indexed.$(basename "$dir")"; [[ -f "$f" ]] && cat "$f" || echo 0'
pass "a failing tool is skipped, not fatal"

# --- shared -----------------------------------------------------------------

# 7. Open files: flagged until a shell profile raises the limit; a commented
#    line does not count.
audit
[[ "$out" == *"⚠ Open files"* ]] || fail "missing ulimit not flagged: $out"
echo '# ulimit -n 65536' > "$HOME/.zshrc"; audit
[[ "$out" == *"⚠ Open files"* ]] || fail "a commented ulimit counted: $out"
grep 'ulimit -n' "$SCRIPT_DIR/../../configs/zsh/.zshrc" | grep -v '^#' > "$HOME/.zshrc" || fail "the shipped .zshrc has no ulimit line"
audit
[[ "$out" == *"✓ Open files: your shell raises the limit (~/.zshrc)"* ]] || fail "the shipped ulimit line not recognized: $out"
pass "open files: the shipped .zshrc line satisfies the check"

# 8. git: untrackedCache is offered, applied through the git-defaults lib (so
#    it is recorded for uninstall), and a global fsmonitor is flagged.
git config --global --unset core.untrackedCache   # test 4's --fix set it too
audit
[[ "$out" == *"fix (--fix does this): git config --global core.untrackedCache true"* ]] || fail "untrackedCache not offered: $out"
tuidev_manifest_enable
perf_apply >/dev/null
[[ "$(get core.untrackedCache)" == true ]] || fail "--fix did not set core.untrackedCache"
tuidev_manifest_values gitconfig | grep -q '^core.untrackedCache true$' || fail "the fix was not recorded"
git config --global core.fsmonitor true; audit
[[ "$out" == *"core.fsmonitor is on globally"* && "$out" == *"✓ git: core.untrackedCache is set"* ]] || fail "fsmonitor not flagged: $out"
git config --global --unset core.fsmonitor
pass "git: untrackedCache is set and recorded by --fix; a global fsmonitor is flagged"

# 9. A confirm function that says no applies nothing.
git config --global --unset core.untrackedCache; audit
perf_apply false >/dev/null
[[ "$(get core.untrackedCache)" == "" ]] || fail "a declined fix was applied"
pass "a declined fix is not applied"

# 10. A store on another volume than home.
echo /dev/disk9 > "$tmp/state/pnpm.dev"; audit
[[ "$out" == *"~/Library/pnpm/store/v11 is on another volume"* ]] || fail "cross-volume store not flagged: $out"
rm "$tmp/state/pnpm.dev"
pass "a store on another volume is flagged"

# 11. --brief leaves out what is fine and says so when nothing is left.
git config --global core.untrackedCache true; audit --brief
[[ "$out" != *"✓ git"* && "$out" == *"Performance: nothing to change"* ]] || fail "--brief: $out"
pass "--brief prints only what to change"

# --- Linux ------------------------------------------------------------------
as_linux
export PERF_PROC="$tmp/proc" PERF_ETC="$tmp/etc"
mkdir -p "$PERF_PROC/sys/fs/inotify" "$PERF_ETC"

# 12. inotify: the kernel's 128 instances are flagged with the drop-in; raised
#     limits are fine. No macOS check runs.
echo 128 > "$PERF_PROC/sys/fs/inotify/max_user_instances"
echo 65536 > "$PERF_PROC/sys/fs/inotify/max_user_watches"
printf 'Filename Type Size Used Priority\n' > "$PERF_PROC/swaps"
printf '# PRUNENAMES=".git .bzr .hg .svn"\n' > "$PERF_ETC/updatedb.conf"
echo 270240 > "$tmp/state/indexed.v11"
audit
[[ "$out" == *"inotify: 128 instances and 65536 watches"* && "$out" == *"sysctl.d/60-inotify.conf"* ]] || fail "inotify not flagged: $out"
[[ "$out" == *"⚠ No swap"* ]] || fail "missing swap not flagged: $out"
[[ "$out" == *"ℹ locate: the nightly updatedb walks node_modules"* ]] || fail "updatedb not noted: $out"
[[ "$out" != *"Spotlight"* && "$out" != *"Time Machine"* ]] || fail "a macOS check ran on Linux: $out"
echo 1048576 > "$PERF_PROC/sys/fs/inotify/max_user_watches"; audit
[[ "$out" == *"max_user_instances = 1024"* && "$out" != *"max_user_watches = "* ]] || fail "the drop-in would lower a raised watch limit: $out"
echo 1024 > "$PERF_PROC/sys/fs/inotify/max_user_instances"
echo 524288 > "$PERF_PROC/sys/fs/inotify/max_user_watches"
printf 'Filename Type Size Used Priority\n/dev/zram0 partition 1 0 100\n' > "$PERF_PROC/swaps"
printf 'PRUNENAMES=".git node_modules target"\n' > "$PERF_ETC/updatedb.conf"
audit
[[ "$out" == *"✓ inotify: 1024 instances, 524288 watches"* && "$out" == *"✓ Swap is present"* && "$out" == *"✓ locate: updatedb skips node_modules"* ]] \
    || fail "tuned Linux not fine: $out"
pass "Linux: inotify, swap and updatedb are checked, and no macOS check runs"

echo ""
echo "All perf lib tests passed."
