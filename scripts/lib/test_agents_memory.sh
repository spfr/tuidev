#!/bin/bash
# Unit tests for the memory guard (lib/agents/memory.sh, awk/memory.awk) and
# memory hogs: top parsing, candidates from a fixture `ps`, and the guard's
# decisions with every probe and the kill stubbed. Nothing is signalled and
# no real process is read.
# Run: bash scripts/lib/test_agents_memory.sh  -> exit 0 on pass.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 AGENTS_TESTING=1
export TUIDEV_TERMINAL_NOTIFIER=""
export AGENTS_CONF="$tmp/none.conf" AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data"
export AGENTS_UID=501 AGENTS_SELF=99999 AGENTS_MEM_QUIET=1
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

G=1048576   # KiB in a GB

# 1. top's MEM column, in every unit it prints.
out="$(printf '%s\n' 'Processes: 3 total' 'PID    MEM   ' '607    840M  ' '74922  2.5G+ ' '12     512K- ' '13     0B    ' | _agents_mem_parse_top)"
[[ "$out" == $'607\t860160\n74922\t2621440\n12\t512\n13\t0' ]] || fail "top MEM parse: $out"
pass "top's MEM column parses (M, G, K, B, with a trailing + or -)"

# 2. Candidates: biggest first, the script an interpreter runs, the agent
#    tree's root and kind; an app's bundle path is no label; small ones out.
psfix="$(cat <<EOF
  510   500   501 me    0.0     3000   0:00.10 01:42:53 Wed Oct 14 07:31:08 2026     -zsh
  600   510   501 me    0.3   700000   4:30.13 01:42:53 Wed Oct 14 07:31:08 2026     claude --continue
  610   600   501 me    0.0     2000   0:00.01 00:01:00 Wed Oct 14 09:00:00 2026     /bin/zsh -c node --test test/clientFuelToday.test.js
  620   610   501 me   99.0 $((20 * G))   0:50.00 00:00:55 Wed Oct 14 09:00:05 2026     /usr/local/bin/node --heap-prof-interval=524288 --test test/clientFuelToday.test.js
  700     1   501 me    5.0 $((5 * G))   1:00.00 03:00:00 Wed Oct 14 06:00:00 2026     /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --type=renderer
  800     1   501 me    0.0   200000   0:00.10 03:00:00 Wed Oct 14 06:00:00 2026     /usr/bin/python3 small.py
EOF
)"
cands="$(printf '%s\n' "$psfix" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v self=99999 -v screen=$((4 * G)) -v floor=0 -v max=8)"
[[ "$(printf '%s\n' "$cands" | cut -f1 | tr '\n' ' ')" == "620 700 " ]] || fail "candidates by size: $cands"
IFS=$'\t' read -r p st rss uid name label root kind <<<"$(printf '%s\n' "$cands" | head -1)"
[[ "$p $uid $name $label $root $kind" == "620 501 node clientFuelToday.test.js 600 claude" ]] || fail "node candidate: $p $uid $name $label $root $kind"
[[ "$st" == Wed_Oct_14_09:00:05_2026 && "$rss" == $((20 * G)) ]] || fail "node start/rss: $st $rss"
IFS=$'\t' read -r p _ _ _ name label root kind <<<"$(printf '%s\n' "$cands" | sed -n 2p)"
[[ "$name|$label|$root|$kind" == "Google Chrome|-|-|-" ]] || fail "app candidate: $name|$label|$root|$kind"
cands="$(printf '%s\n' "$psfix" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v self=99999 -v screen=$((4 * G)) -v floor=100000 -v max=8)"
[[ "$(printf '%s\n' "$cands" | cut -f1 | tr '\n' ' ')" == "620 700 600 800 " ]] || fail "the floor lets the largest few in under pressure: $cands"
cands="$(printf '%s\n' "$psfix" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v self=620 -v screen=$((4 * G)) -v floor=0 -v max=8)"
[[ "$(printf '%s\n' "$cands" | cut -f1 | tr '\n' ' ')" == "700 " ]] || fail "never this process or its ancestors: $cands"
cands="$(printf '%s\n' "$psfix" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v self=99999 -v screen=0 -v max=400 -v pids=" 800 600 ")"
[[ "$(printf '%s\n' "$cands" | cut -f1 | tr '\n' ' ')" == "600 800 " ]] || fail "pids picks exactly those: $cands"
pass "candidates: biggest first, label, agent root and kind, the pressure floor, never ourselves, a pid list"

# 3. Warning steps: one per doubling.
[[ "$(_agents_mem_step $((7 * G)) $((8 * G)))" == 0 ]] || fail "step under the warning"
[[ "$(_agents_mem_step $((8 * G)) $((8 * G)))" == 1 ]] || fail "step at the warning"
[[ "$(_agents_mem_step $((17 * G)) $((8 * G)))" == 2 ]] || fail "step past twice the warning"
[[ "$(_agents_mem_step $((40 * G)) $((8 * G)))" == 3 ]] || fail "step past four times the warning"
pass "warning steps: one per doubling of AGENTS_MEM_WARN"

# 4. The guard's decisions, every probe stubbed: a ps fixture, the machine,
#    top's footprints, the kill (which records the token), cwds, root-of.
MACH=$'50331648\t40\tnormal\t1048576\t2097152'   # 48 GB, 40% free
FPS=""
agents_snapshot() { printf '%s\n' "$psfix"; }
agents_mem_machine() { printf '%s\n' "$MACH"; }
_agents_mem_fp() { [[ -z "$FPS" ]] || printf '%s\n' "$FPS"; }
_agents_cwds() { local p; for p in "$@"; do printf '%s\t/Users/NAME/work/cairn\n' "$p"; done; }
agents_root_of() { return 1; }
_agents_kill_unattended() { echo "$*" >> "$tmp/killed"; agents_event "$_AGENTS_EV_KIND" memory "${1%%@*}" node cairn -; }
reset() { rm -rf "$AGENTS_RUN_DIR" "$AGENTS_DATA_DIR" "$tmp/killed"; unset _AGENTS_MEM_STATE _AGENTS_MEM_LEVEL; }
tick() { AGENTS_NOW="$1" agents_mem_tick; }

reset
out="$(tick 1000)"
[[ "$(cat "$tmp/killed" 2>/dev/null)" == "" ]] || fail "20 GB is under the 24 GB stop size: nothing stopped"
[[ "$out" == *"node (clientFuelToday.test.js) in cairn holds 20.0G; stopped at 24.0G"* ]] || fail "warning text: $out"
[[ "$out" == *"Google Chrome in cairn holds 5.0G"* ]] && fail "5 GB is under the 8 GB warning"
grep -q $'\twarn\t620\tnode\tclientFuelToday.test.js\tcairn\tclaude:600\t' "$AGENTS_DATA_DIR/memory.tsv" || fail "warn incident: $(cat "$AGENTS_DATA_DIR/memory.tsv")"
pass "past the warning: notified with process, script, project and stop size, recorded in memory.tsv"

out="$(tick 1005)"
[[ -z "$out" ]] || fail "the same step warns once: $out"
FPS=$'620\t'$((30 * G))
out="$(tick 1010)"
[[ "$(cat "$tmp/killed")" == "620@Wed_Oct_14_09:00:05_2026" ]] || fail "a footprint past 24 GB stops it by PID@START: $(cat "$tmp/killed" 2>/dev/null)"
[[ "$out" == *"Stopped node (clientFuelToday.test.js) in cairn: it held 30.0G past the 24.0G limit (claude:600)"* ]] || fail "stop text: $out"
grep -q $'\tstop\t620\t' "$AGENTS_DATA_DIR/memory.tsv" || fail "stop incident"
grep -q $'\tguard\tmemory\t620\t' "$AGENTS_DATA_DIR/events.tsv" || fail "stop event in events.tsv"
pass "the footprint (top) past half the RAM stops it, tree and all, once warned; recorded in memory.tsv and events.tsv"

# Growth: 9 GB to 12 GB in 5 s is 614 MB/s (under a 16 GB warning).
reset
psfix_small="$psfix"
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 620 { $6 = g * 9 } { print }')"
FPS=$'620\t'$((9 * G))
out="$(AGENTS_MEM_WARN=16 tick 2000)"
FPS=$'620\t'$((12 * G))
out="$(AGENTS_MEM_WARN=16 tick 2005)"
[[ "$out" == *"is growing 614 MB/s (12.0G now)"* ]] || fail "growth warning: $out"
out="$(AGENTS_MEM_WARN=16 tick 2010)"
[[ "$out" != *growing* ]] || fail "one growth warning per process: $out"
psfix="$psfix_small"
pass "growing faster than AGENTS_MEM_RATE: one warning"

# An agent itself, an app, and warn mode: warned about, never stopped.
reset
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 600 { $6 = g * 30 } $1 == 620 { $6 = 1000 } $1 == 700 { $6 = g * 30 } { print }')"
FPS=""
out="$(tick 3000)"
[[ ! -s "$tmp/killed" ]] || fail "an agent or an app past the stop size was stopped: $(cat "$tmp/killed")"
[[ "$out" == *"claude in cairn holds 30.0G (not stopped by the guard)"* ]] || fail "agent warning: $out"
[[ "$out" == *"Google Chrome in cairn holds 30.0G (not stopped by the guard)"* ]] || fail "app warning: $out"
reset
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 620 { $6 = g * 30 } { print }')"
out="$(AGENTS_MEM_GUARD=warn tick 3100)"
[[ ! -s "$tmp/killed" ]] || fail "AGENTS_MEM_GUARD=warn stopped something"
[[ "$out" == *"(not stopped by the guard)"* ]] || fail "warn mode says it does not stop: $out"
out="$(AGENTS_MEM_GUARD=off tick 3200)"
[[ "$out" == *"off"* && ! -s "$tmp/killed" ]] || fail "off does nothing: $out"
pass "an agent itself and apps are only warned about; warn mode never stops; off does nothing"

# Critical pressure: the largest agent-tree process past the warning goes,
# even under the stop size; the turn to critical is recorded once.
reset
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 620 { $6 = g * 10 } { print }')"
MACH=$'50331648\t3\tcritical\t2097152\t2097152'
out="$(tick 4000)"
[[ "$(cat "$tmp/killed")" == "620@Wed_Oct_14_09:00:05_2026" ]] || fail "critical pressure stops the largest past the warning"
[[ "$out" == *"while memory pressure is critical"* ]] || fail "critical stop text: $out"
grep -q $'\tpressure\t620\t' "$AGENTS_DATA_DIR/memory.tsv" || fail "pressure incident"
rm -f "$tmp/killed"
psfix="$psfix_small"
out="$(tick 4005)"
[[ "$(grep -c $'\tpressure\t' "$AGENTS_DATA_DIR/memory.tsv")" == 1 ]] || fail "the turn to critical is recorded once"
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
pass "critical pressure: the largest agent-tree process past the warning is stopped; the turn recorded once"

# Dry run: says what it would do, records and stops nothing.
reset
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 620 { $6 = g * 30 } { print }')"
out="$(AGENTS_DRY_RUN=true tick 5000)"
[[ "$out" == *"would stop node (clientFuelToday.test.js) in cairn (claude:600): 30.0G past the 24.0G limit"* ]] || fail "dry run text: $out"
[[ ! -s "$tmp/killed" && ! -e "$AGENTS_DATA_DIR/memory.tsv" && ! -e "$AGENTS_RUN_DIR/memguard.state" ]] || fail "dry run wrote or stopped something"
psfix="$psfix_small"
pass "dry run: says what it would stop; records, saves and stops nothing"

# AGENTS_MEM_KILL in GB wins over half the RAM.
[[ "$(AGENTS_MEM_KILL=12 _agents_mem_kill_kib 50331648)" == $((12 * G)) ]] || fail "AGENTS_MEM_KILL=12"
[[ "$(_agents_mem_kill_kib 50331648)" == $((24 * G)) ]] || fail "default: half the RAM"
pass "the stop size: AGENTS_MEM_KILL GB, else half the RAM"

# 5. The menu's memg row: the guard's state and the last incident.
reset
mkdir -p "$AGENTS_DATA_DIR" "$AGENTS_RUN_DIR"
printf '1000\tstop\t620\tnode\tclientFuelToday.test.js\tcairn\tclaude:600\t31457280\t10485760\t3\t2097152\n' > "$AGENTS_DATA_DIR/memory.tsv"
echo 50331648 > "$AGENTS_RUN_DIR/memtotal"
row="$(_agents_mem_tsv_row)"
[[ "$row" == $'memg\tnone\t-\t8388608\t25165824\t1000\tstop\tnode (clientFuelToday.test.js)\tcairn\t31457280' ]] || fail "memg row: $row"
mkdir -p "$HOME/Library/LaunchAgents"; touch "$HOME/Library/LaunchAgents/dev.tuidev.memguard.plist"
[[ "$(_agents_mem_guard_state)" == stopped ]] || fail "an installed LaunchAgent with no guard running is stopped"
[[ "$(AGENTS_MEM_GUARD=off _agents_mem_guard_state)" == off ]] || fail "off"
pass "memg row: guard state (none, stopped, off), warn and stop sizes, the last incident"

# 6. Settings: shapes are checked.
_agents_conf_valid AGENTS_MEM_GUARD kill  || fail "kill is valid"
! _agents_conf_valid AGENTS_MEM_GUARD nuke || fail "nuke is not"
_agents_conf_valid AGENTS_MEM_KILL 0      || fail "AGENTS_MEM_KILL=0 is valid (half the RAM)"
! _agents_conf_valid AGENTS_MEM_WARN 0    || fail "AGENTS_MEM_WARN=0 is not"
! _agents_conf_valid AGENTS_MEM_POLL 2s   || fail "AGENTS_MEM_POLL takes seconds as a number"
pass "AGENTS_MEM_* values are validated"

# 7. Memory hogs lead the hogs, in any tree, by RSS.
hogs="$(printf '%s\n' "$psfix" | awk -v g="$G" '$1 == 620 { $6 = g * 9 } { print }' | agents_classify "" "" | awk -F '\t' '$1 == "hog" { print $2 }' | tr '\n' ' ')"
[[ "$hogs" == "620 "* ]] || fail "a 9 GB node in an agent tree leads the hogs: $hogs"
pass "memory hogs (RSS past AGENTS_MEM_WARN) lead the hogs, agent trees included"

echo
echo "All agents memory tests passed."
