#!/bin/bash
# shellcheck disable=SC2015  # "A && B || fail" fails on either, as meant
# Unit tests for scripts/lib/perf.sh, the performance audit.
# Run: bash scripts/lib/test_perf.sh  -> exit 0 on pass.
#
# Everything runs against a throwaway HOME, and the system commands the audit
# reads (mdfind, tmutil, pmset, defaults, pnpm, go, df, ps, sysctl) are stubs
# on PATH, so the real Spotlight index, Time Machine, process table and
# ~/.gitconfig are never touched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" TUIDEV_NO_COLOR=1 GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL TUIDEV_PERF_DIRS TUIDEV_PERF_INDEX_MIN BUN_INSTALL_CACHE_DIR CARGO_HOME \
    PNPM_HOME npm_config_store_dir XDG_DATA_HOME XDG_STATE_HOME GOPATH GOCACHE GOMODCACHE GOENV
mkdir -p "$HOME" "$tmp/bin" "$tmp/state"
TUIDEV_STATE_DIR="$HOME/.config/tuidev"
export TUIDEV_MANIFEST_FILE="$TUIDEV_STATE_DIR/manifest"

# Stubs. Each reads its answers from $tmp/state, so a test sets a file and
# runs the audit again. Their bodies are single-quoted on purpose: they expand
# when the stub runs.
# shellcheck disable=SC2016,SC2329
{
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
# pnpm and go are never run to read (both write when asked): the stores are
# their default folders. A call is recorded, and test 1 checks there is none.
stub pnpm    'echo "pnpm $*" >> "'"$tmp"'/state/calls"'
stub go      'echo "go $*" >> "'"$tmp"'/state/calls"'
stub uv      'exit 1'
stub npm     'exit 1'
stub mdfind  'dir="$2"; f="'"$tmp"'/state/indexed.$(basename "$dir")"; [[ -f "$f" ]] && cat "$f" || echo 0'
stub tmutil  'case "$1" in
  destinationinfo) cat "'"$tmp"'/state/tm.dest" 2>/dev/null || echo "tmutil: No destinations configured." ;;
  isexcluded) if grep -qxF "$2" "'"$tmp"'/state/tm.excluded" 2>/dev/null; then echo "[Excluded]  $2"; else echo "[Included]  $2"; fi ;;
  addexclusion) echo "$2" >> "'"$tmp"'/state/tm.excluded" ;;
  listlocalsnapshots) echo "Snapshots for disk /:"; cat "'"$tmp"'/state/snapshots" 2>/dev/null || true ;;
esac'
stub pmset   'if [[ "$2" == batt ]]; then echo "Now drawing from '"'"'AC Power'"'"'"; else echo " powermode            $(cat "'"$tmp"'/state/powermode" 2>/dev/null || echo 0)"; fi'
stub defaults '[[ "$3" == "FXICloudDriveDocuments" ]] && cat "'"$tmp"'/state/icloud" 2>/dev/null || echo 0'
stub df      'case "$2" in *pnpm*) dev="$(cat "'"$tmp"'/state/pnpm.dev" 2>/dev/null || echo /dev/disk1)";; *) dev=/dev/disk1;; esac; printf "Filesystem 1024-blocks Used Available Capacity Mounted\n%s %s /\n" "$dev" "$(cat "'"$tmp"'/state/df" 2>/dev/null || echo "1000000000 500000000 500000000 50%")"'
# The measured checks: ps's TIME and COMM, sysctl's boot time, memory and
# swap. The defaults are a healthy machine, 10 hours after boot.
stub ps      'cat "'"$tmp"'/state/ps" 2>/dev/null || printf "     TIME COMM\n  6:00.00 /System/Library/Metadata.framework/Support/mds_stores\n  0:36.00 /System/Library/FSEvents.framework/Support/fseventsd\n"'
stub sysctl  'case "$2" in
  kern.boottime) echo "{ sec = $(( $(date +%s) - $(cat "'"$tmp"'/state/uptime" 2>/dev/null || echo 36000) )), usec = 0 } Thu Nov 12 09:30:51 2026" ;;
  hw.memsize) echo 17179869184 ;;
  vm.swapusage) echo "total = 2048.00M  used = $(cat "'"$tmp"'/state/swap" 2>/dev/null || echo 512.00M)  free = 1536.00M  (encrypted)" ;;
  kern.memorystatus_vm_pressure_level) cat "'"$tmp"'/state/pressure" 2>/dev/null || echo 1 ;;
esac'
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
echo 270240 > "$tmp/state/indexed.store"
echo 98000 > "$tmp/state/indexed.workspace"
audit
[[ "$out" == *"Spotlight indexes 270240 files in ~/Library/pnpm/store"* ]] || fail "indexed store not flagged: $out"
[[ "$out" == *"Search Privacy > + > ~/Library/pnpm/store"* ]] || fail "no Settings path: $out"
[[ ! -s "$tmp/state/calls" ]] || fail "the audit ran pnpm or go: $(cat "$tmp/state/calls")"
[[ "$out" == *"ℹ Spotlight indexes 98000 files in ~/workspace"* ]] || fail "repos folder not a note: $out"
[[ "$out" != *"Spotlight indexes"*"go/pkg/mod"* ]] || fail "an unindexed store flagged: $out"
[[ "$out" != *"fix (--fix does this): System Settings"* ]] || fail "Spotlight offered as an automatic fix: $out"
pass "Spotlight: an indexed store is a warning, a repos folder a note, the fix is yours"

# 2. Below the threshold, and once excluded, it reads as fine.
echo 12 > "$tmp/state/indexed.store"; rm "$tmp/state/indexed.workspace"
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
[[ "$out" == *"how: tmutil destinationinfo, then tmutil isexcluded"* && "$out" == *"undo: tmutil removeexclusion $HOME/go/pkg/mod"* ]] \
    || fail "the check does not say how it measured, or the undo: $out"
DRY_RUN=true perf_apply > "$tmp/dry.txt"
[[ ! -f "$tmp/state/tm.excluded" && ! -f "$TUIDEV_STATE_DIR/disk.log" ]] || fail "DRY_RUN excluded a folder or logged"
grep -q "would log: .*	perf	tm	tmutil addexclusion" "$tmp/dry.txt" || fail "DRY_RUN did not print the log line: $(cat "$tmp/dry.txt")"
# The plan, with each undo, is printed before the first question.
# shellcheck disable=SC2317,SC2329  # called by perf_apply, by name
plan_first() { grep -q "Plan: the fixes --fix offers" "$tmp/apply.txt" && grep -q "undo: tmutil removeexclusion" "$tmp/apply.txt" || fail "asked before the plan"; }
perf_apply plan_first > "$tmp/apply.txt"
grep -qxF "$HOME/go/pkg/mod" "$tmp/state/tm.excluded" || fail "--fix did not exclude the store"
grep -qE "^[0-9TZ:-]+	perf	tm	tmutil addexclusion $HOME/go/pkg/mod	0	-	-	tmutil removeexclusion $HOME/go/pkg/mod\$" "$TUIDEV_STATE_DIR/disk.log" \
    || fail "the change was not logged with its undo: $(cat "$TUIDEV_STATE_DIR/disk.log")"
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
[[ "$out" != *"Spotlight indexes"* && "$out" != *"Spotlight: "* ]] || fail "a failing mdfind produced a Spotlight line: $out"
# shellcheck disable=SC2016
stub mdfind 'dir="$2"; f="'"$tmp"'/state/indexed.$(basename "$dir")"; [[ -f "$f" ]] && cat "$f" || echo 0'
pass "a failing tool is skipped, not fatal"

# 6c. ps's CPU time, in every form it prints: macOS MM:SS.ss (minutes past
#     59 included), procps HH:MM:SS and DD-HH:MM:SS, bare seconds.
for c in "1:45.99=105" "123:45.67=7425" "0:00.06=0" "01:02:03=3723" "2-01:02:03=176523" "45.5=45"; do
    [[ "$(_perf_cpu_seconds "${c%%=*}")" == "${c#*=}" ]] || fail "ps time ${c%%=*} read as $(_perf_cpu_seconds "${c%%=*}")"
done
pass "the ps time parser reads every format"

# 6d. Measured on a healthy machine: the numbers, as fine.
audit
[[ "$out" == *"✓ Background daemons, share of one core since boot (10 h 0 m): Spotlight 1.0%, fseventsd 0.1%"* ]] \
    || fail "daemon CPU not reported: $out"
[[ "$out" == *"✓ Memory: pressure normal, 512 MB of swap in use, 16 GB RAM"* ]] || fail "memory not reported: $out"
[[ "$out" == *"✓ Disk: 50% free on the volume your home is on (477 GB of 954 GB)"* ]] || fail "free disk not reported: $out"
[[ "$out" != *"Endpoint security"* ]] || fail "an endpoint agent reported where none runs: $out"
[[ "$out" == *"'make disk' lists what dev tools and agents left on disk"* ]] || fail "no pointer to make disk: $out"
pass "measured: daemons, memory and disk report their numbers when fine"

# 6e. A daemon past 15% of a core is a warning with its fix, but not within
#     an hour of boot; a corporate endpoint agent (a path with spaces) is a note.
printf '     TIME COMM\n120:00.00 /System/Library/Metadata.framework/Support/mds_stores\n  1:00.00 /System/Library/FSEvents.framework/Support/fseventsd\n  9:00.00 /Library/Application Support/CrowdStrike/falcond\n' > "$tmp/state/ps"
audit
[[ "$out" == *"⚠ Spotlight has used 20.0% of a core since boot (10 h 0 m ago)"* && "$out" == *"#1-spotlight"* ]] \
    || fail "a busy Spotlight not flagged: $out"
[[ "$out" != *"Background daemons, share"* ]] || fail "the summary claimed all is fine: $out"
[[ "$out" == *"ℹ Endpoint security: CrowdStrike Falcon is running"* && "$out" == *"ask IT for exclusions"* && "$out" != *"disable"* ]] \
    || fail "endpoint agent not noted: $out"
echo 1800 > "$tmp/state/uptime"; audit
[[ "$out" != *"Spotlight has used"* && "$out" == *"✓ Background daemons, share of one core since boot (30 m): Spotlight 400.0%"* ]] \
    || fail "judged within an hour of boot: $out"
rm "$tmp/state/uptime" "$tmp/state/ps"
stub ps 'exit 1'; audit
[[ "$out" != *"Background daemons"* && "$out" != *"Endpoint"* ]] || fail "a denied ps produced a line: $out"
rm "$tmp/bin/ps"
mv "$tmp/bin/sysctl" "$tmp/sysctl.keep"; stub sysctl 'exit 1'
mv "$tmp/bin/df" "$tmp/df.keep"; stub df 'echo "df: denied" >&2; exit 1'
( set -euo pipefail; audit ) || fail "a denied sysctl or df aborted the audit"
audit
[[ "$out" != *"Background daemons"* && "$out" != *"Memory:"* && "$out" != *"Disk:"*"free"* ]] || fail "a denied sysctl or df produced a line: $out"
mv "$tmp/sysctl.keep" "$tmp/bin/sysctl"; mv "$tmp/df.keep" "$tmp/bin/df"
pass "measured: a busy daemon warns after the first hour; an endpoint agent is a note; a denied ps, sysctl or df is silent"

# 6f. Memory pressure and swap past a quarter of RAM; a nearly full disk with
#     local snapshots points at make disk.
echo 4 > "$tmp/state/pressure"; audit
[[ "$out" == *"⚠ Memory: pressure is critical now"* && "$out" == *"agents mem"* ]] || fail "critical pressure not flagged: $out"
echo 1 > "$tmp/state/pressure"; echo 5120.00M > "$tmp/state/swap"; audit
[[ "$out" == *"ℹ Memory: 5.0 GB of swap in use, 16 GB RAM, a quarter of RAM or more"* ]] || fail "large swap not noted: $out"
rm "$tmp/state/pressure" "$tmp/state/swap"
echo "1000000000 950000000 50000000 95%" > "$tmp/state/df"
printf 'com.apple.TimeMachine.2026-11-12-101010.local\ncom.apple.TimeMachine.2026-11-12-111010.local\n' > "$tmp/state/snapshots"
audit
[[ "$out" == *"⚠ Disk: 5% free"*"2 local Time Machine snapshot(s)"*"Below 10% free"* && "$out" == *"fix: make disk"* ]] \
    || fail "a full disk not flagged: $out"
rm "$tmp/state/df" "$tmp/state/snapshots"
pass "measured: memory pressure, large swap and a full disk are flagged with the command"

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

# 9. A confirm function that says no applies nothing; the script without a
#    terminal and without --yes prints the plan and changes nothing.
git config --global --unset core.untrackedCache; audit
perf_apply false >/dev/null
[[ "$(get core.untrackedCache)" == "" ]] || fail "a declined fix was applied"
"$SCRIPT_DIR/../perf.sh" --fix < /dev/null > "$tmp/script.txt" 2>&1 || fail "perf.sh --fix failed: $(cat "$tmp/script.txt")"
grep -q "Plan: the fixes --fix offers" "$tmp/script.txt" && grep -q "Not a terminal and no --yes: nothing changed" "$tmp/script.txt" \
    || fail "perf.sh --fix without a terminal: $(cat "$tmp/script.txt")"
[[ "$(get core.untrackedCache)" == "" ]] || fail "perf.sh --fix without a terminal changed git"
pass "a declined fix is not applied; without a terminal nothing runs without --yes"

# 10. A store on another volume than home.
echo /dev/disk9 > "$tmp/state/pnpm.dev"; audit
[[ "$out" == *"~/Library/pnpm/store is on another volume"* ]] || fail "cross-volume store not flagged: $out"
rm "$tmp/state/pnpm.dev"
pass "a store on another volume is flagged"

# 11. --brief leaves out what is fine and says so when nothing is left.
git config --global core.untrackedCache true; audit --brief
[[ "$out" != *"✓ git"* && "$out" == *"Performance: nothing to change"* ]] || fail "--brief: $out"
[[ "$out" != *"Background daemons"* && "$out" != *"✓ Memory"* && "$out" != *"✓ Disk"* && "$out" != *"make disk"* ]] \
    || fail "--brief printed a measured line that is fine: $out"
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
echo 270240 > "$tmp/state/indexed.store"
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

# 13. Linux measured: load against cores, swap in use, /tmp in RAM.
printf '0.50 6.10 3.00 2/300 1234\n' > "$PERF_PROC/loadavg"
printf 'processor\t: 0\nprocessor\t: 1\nprocessor\t: 2\nprocessor\t: 3\n' > "$PERF_PROC/cpuinfo"
printf 'MemTotal:        8000000 kB\nSwapTotal:       2000000 kB\nSwapFree:        1000000 kB\n' > "$PERF_PROC/meminfo"
printf '/dev/sda1 / ext4 rw 0 0\ntmpfs /tmp tmpfs rw,nosuid,nodev,size=4000000k 0 0\n' > "$PERF_PROC/mounts"
audit
[[ "$out" == *"⚠ Load: 6.10 over 5 minutes on 4 cores"* && "$out" == *"agents hogs"* ]] || fail "high load not flagged: $out"
[[ "$out" == *"✓ Swap is present: 977 MB of swap in use, 7.6 GB RAM"* ]] || fail "swap use not reported: $out"
[[ "$out" == *"✓ /tmp is tmpfs, in RAM (up to 3.8 GB)"* ]] || fail "tmpfs /tmp not reported: $out"
[[ "$out" == *"✓ Disk: 50% free"* && "$out" != *"Background daemons"* && "$out" != *"Memory: pressure"* ]] || fail "wrong platform's checks: $out"
printf '1.00 1.20 1.00 2/300 1234\n' > "$PERF_PROC/loadavg"
printf 'MemTotal:        8000000 kB\nSwapTotal:       4000000 kB\nSwapFree:        0 kB\n' > "$PERF_PROC/meminfo"
printf 'tmpfs /tmp tmpfs rw 0 0\n' > "$PERF_PROC/mounts"
audit
[[ "$out" == *"✓ Load: 1.20 over 5 minutes on 4 cores"* ]] || fail "normal load not fine: $out"
[[ "$out" == *"ℹ Swap is present: 3.8 GB of swap in use, 7.6 GB RAM, a quarter of RAM or more"* ]] || fail "heavy swap not noted: $out"
[[ "$out" == *"/tmp is tmpfs, in RAM (up to half the RAM)"* ]] || fail "tmpfs default size: $out"
pass "Linux measured: load, swap in use and a tmpfs /tmp"

echo ""
echo "All perf lib tests passed."
