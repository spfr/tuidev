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

# 1b. footprint's phys_footprint, and the sample: footprint for the pids it
#     reads (yours), top only for the rest, both stubbed on PATH.
out="$(printf '%s\n' 'footprint: Unable to find pid for process matching '"'"'604'"'"'' \
    '======' 'com.apple.Virtualization.VirtualMachine [38526]: 64-bit    Footprint: 4502624760 B (16384 bytes per page)' '======' '' \
    'Auxiliary data:' '    phys_footprint: 4503624184 B' '    phys_footprint_peak: 4503689720 B' '' \
    'Odd [name] [4585]: 64-bit    Footprint: 256329600 B (16384 bytes per page)' '    phys_footprint: 256329600 B' \
    '======' 'Summary Footprint: 4758872440 B' | _agents_mem_parse_footprint)"
[[ "$out" == $'38526\t4398070\n4585\t250321' ]] || fail "footprint parse: $out"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/footprint" <<'EOF'
#!/bin/sh
echo "footprint $*" >> "$CALLS"
for a in "$@"; do
    case "$a" in
        700) printf '%s\n' 'Google Chrome [700]: 64-bit    Footprint: 6442450944 B' '    phys_footprint: 6442450944 B' ;;
        900) echo "footprint: Unable to find pid for process matching '900'" >&2 ;;
    esac
done
EOF
cat > "$tmp/bin/top" <<'EOF'
#!/bin/sh
echo "top $*" >> "$CALLS"
printf '%s\n' 'Processes: 2 total' 'PID    MEM' '900    6144M'
EOF
chmod +x "$tmp/bin/footprint" "$tmp/bin/top"
export CALLS="$tmp/calls"
out="$(PATH="$tmp/bin:$PATH" OSTYPE=darwin25 _agents_mem_fp 700 900)"
[[ "$out" == $'700\t6291456\n900\t6291456' ]] || fail "footprint, then top for the rest: $out"
[[ "$(cat "$CALLS")" == $'footprint --noCategories -f bytes 700 900\ntop -l 1 -stats pid,mem -pid 900' ]] || fail "calls: $(cat "$CALLS")"
rm -f "$CALLS"
out="$(PATH="$tmp/bin:$PATH" OSTYPE=darwin25 _agents_mem_fp 700)"
[[ "$out" == $'700\t6291456' && "$(cat "$CALLS")" == "footprint --noCategories -f bytes 700" ]] || fail "no top when footprint read them all: $(cat "$CALLS")"
rm -f "$CALLS"
out="$(PATH="$tmp/bin:$PATH" OSTYPE=linux-gnu _agents_mem_fp 700)"
[[ -z "$out" && ! -e "$CALLS" ]] || fail "off macOS nothing runs: $out"
pass "footprint's phys_footprint parses; a sample runs top only for the pids footprint can't read"

# 1c. A probe that hangs is cut off after _AGENTS_MEM_PROBE_WAIT: what it
#     printed is dropped, the pids it did not answer for have no reading, and
#     the sample fails with 124 (the stubs are this test's own processes).
mkdir -p "$tmp/hang"
printf '#!/bin/sh\necho "Google Chrome [700]: 64-bit    Footprint: 1024 B"\necho "    phys_footprint: 1024 B"\nexec sleep 30\n' > "$tmp/hang/footprint"
printf '#!/bin/sh\necho "PID MEM"\necho "900 1"\nexec sleep 30\n' > "$tmp/hang/top"
chmod +x "$tmp/hang/footprint" "$tmp/hang/top"
SECONDS=0
rc=0; out="$(PATH="$tmp/hang:$tmp/bin:$PATH" OSTYPE=darwin25 _AGENTS_MEM_PROBE_WAIT=1 _agents_mem_fp 700 900)" || rc=$?
[[ $rc == 124 && -z "$out" && $SECONDS -lt 10 ]] || fail "both probes hang: rc $rc, '$out', ${SECONDS}s"
rc=0; out="$(PATH="$tmp/bin:$PATH" OSTYPE=darwin25 _AGENTS_MEM_PROBE_WAIT=1 _agents_mem_top -stats pid,mem -pid 900)" || rc=$?
[[ $rc == 0 && "$out" == *"900    6144M"* ]] || fail "a top that answers is read as before: rc $rc"
cp "$tmp/bin/top" "$tmp/hang/top"
rc=0; out="$(PATH="$tmp/hang:$PATH" OSTYPE=darwin25 _AGENTS_MEM_PROBE_WAIT=1 _agents_mem_fp 700 900)" || rc=$?
[[ $rc == 124 && "$out" == $'900\t6291456' ]] || fail "footprint hangs, top answers for 900: rc $rc, '$out'"
rm -f "$CALLS"
pass "a hung footprint or top is cut off: its output dropped, 124, never a zero reading"

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
IFS=$'\t' read -r p st rss uid name label root kind tool tst tname <<<"$(printf '%s\n' "$cands" | head -1)"
[[ "$p $uid $name $label $root $kind" == "620 501 node clientFuelToday.test.js 600 claude" ]] || fail "node candidate: $p $uid $name $label $root $kind"
[[ "$st" == Wed_Oct_14_09:00:05_2026 && "$rss" == $((20 * G)) ]] || fail "node start/rss: $st $rss"
[[ "$tool|$tst|$tname" == "610|Wed_Oct_14_09:00:00_2026|zsh" ]] || fail "node's tool command, the agent's child: $tool|$tst|$tname"
IFS=$'\t' read -r p _ _ _ name label root kind tool tst tname <<<"$(printf '%s\n' "$cands" | sed -n 2p)"
[[ "$name|$label|$root|$kind|$tool|$tst|$tname" == "Google Chrome|-|-|-|-|-|-" ]] || fail "app candidate: $name|$label|$root|$kind|$tool|$tst|$tname"
# The tool command is the child of the nearest agent: a nested agent's own
# command, never an agent; an agent itself has none.
nested="$(printf '%s\n' "$psfix" | awk '$1 == 610 { $2 = 605 } { print }'; \
    echo "  605   600   501 me    0.0   300000   0:00.10 00:01:00 Wed Oct 14 08:59:00 2026     codex exec run-tests")"
out="$(printf '%s\n' "$nested" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v self=99999 -v screen=0 -v max=400 -v pids=" 620 605 600 ")"
[[ "$(printf '%s\n' "$out" | awk -F '\t' '{ print $1 ":" $7 ":" $9 }' | tr '\n' ' ')" == "620:600:610 600:600:- 605:600:- " ]] \
    || fail "tool commands under a nested agent: $out"
# A shell someone types in is never the tool command: the guard stops the
# process's own tree again instead.
bare="$(printf '%s\n' "$psfix" | sed 's|/bin/zsh -c node --test test/clientFuelToday.test.js|-zsh|')"
out="$(printf '%s\n' "$bare" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v self=99999 -v screen=0 -v max=400 -v pids=" 620 ")"
[[ "$(printf '%s\n' "$out" | awk -F '\t' '$1 == 620 { print $9 }')" == "-" ]] || fail "a bare shell as the tool command: $out"
pass "candidates carry the tool command: the nearest agent's child, never an agent"
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
# A footprint sample (macOS's path on every platform, MEASURED=0 for Linux's):
# each pid sampled is logged.
_agents_mem_measured() { [[ "${MEASURED:-1}" == 1 ]]; }
real_fp="$(declare -f _agents_mem_fp)"
# FP_RC=124: the sample was cut off (FPS is then what it did read).
_agents_mem_fp() { [[ $# -eq 0 ]] || echo "$*" >> "$tmp/sampled"; [[ -z "$FPS" ]] || printf '%s\n' "$FPS"; return "${FP_RC:-0}"; }
# Whether ps reads the process table (PS_OK=0: inside a sandbox).
_agents_mem_ps_ok() { [[ "${PS_OK:-1}" == 1 ]]; }
_agents_cwds() { local p; for p in "$@"; do printf '%s\t/Users/NAME/work/cairn\n' "$p"; done; }
agents_root_of() { return 1; }
_agents_kill_unattended() { echo "$*" >> "$tmp/killed"; agents_event "$_AGENTS_EV_KIND" memory "${1%%@*}" node cairn -; }
reset() { rm -rf "$AGENTS_RUN_DIR" "$AGENTS_DATA_DIR" "$tmp/killed" "$tmp/sampled"; unset _AGENTS_MEM_STATE _AGENTS_MEM_LEVEL _AGENTS_MEM_FREE _AGENTS_MEM_STOPS; }
# One look, in a subshell: each reads the state the last one saved.
tick() { ( AGENTS_NOW="$1" agents_mem_tick ); }

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

# 4b. How often the guard samples a footprint (top costs about half a second
#     of CPU): fix SIZE_620 SIZE_700 — the fixture with node (in claude's
#     tree) and Chrome (yours, in no tree) at those RSS KiB, plus a VM of
#     root's at 6 GB; samples PID — how many looks sampled PID.
vmline="  900     1     0 root    0.0 $((6 * G))   0:10.00 03:00:00 Wed Oct 14 06:00:00 2026     /System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"
fix() { printf '%s\n' "$psfix_small" | awk -v a="$1" -v b="$2" '$1 == 620 { $6 = a } $1 == 700 { $6 = b } { print }'; printf '%s\n' "$vmline"; }
samples() { tr ' ' '\n' < "$tmp/sampled" 2>/dev/null | grep -c "^$1\$" || true; }

# (a) Large processes the guard can never stop: sampled once, not every look;
#     again when RSS moves by an eighth (512 MB at least) or after 5 minutes.
reset
psfix="$(fix 1000 $((6 * G)))"; FPS=""
for t in 6000 6005 6010 6015 6020 6025 6030 6035 6040 6045 6050 6055; do tick "$t" >/dev/null; done
[[ "$(samples 700) $(samples 900)" == "1 1" ]] || fail "12 looks at an app and root's VM: $(samples 700) and $(samples 900) samples, want 1 and 1"
psfix="$(fix 1000 $((6 * G + 300000)))"
tick 6060 >/dev/null
[[ "$(samples 700)" == 1 ]] || fail "300 MB of RSS jitter is no reason to sample: $(samples 700)"
psfix="$(fix 1000 $((7 * G)))"
tick 6065 >/dev/null
[[ "$(samples 700) $(samples 900)" == "2 1" ]] || fail "1 GB more RSS samples it again: $(samples 700) $(samples 900)"
tick 6370 >/dev/null
[[ "$(samples 700) $(samples 900)" == "3 2" ]] || fail "after 5 minutes both are sampled again: $(samples 700) $(samples 900)"
pass "a large process the guard can't stop is sampled once, then on an RSS move or after 5 minutes, not every look"

# (b) In an agent tree: sampled every look while it grows, even with its RSS
#     flat (the compressor), and stopped past AGENTS_MEM_KILL as before.
reset
psfix="$(fix $((5 * G)) $((6 * G)))"
n=0
for gb in 6 10 14 18; do
    FPS=$'620\t'$((gb * G)); n=$((n + 1))
    AGENTS_MEM_KILL=20 tick $((7000 + n * 5)) >/dev/null
    [[ "$(samples 620)" == "$n" ]] || fail "node in claude's tree at ${gb} GB: $(samples 620) samples in $n looks"
done
[[ ! -s "$tmp/killed" ]] || fail "18 GB is under a 20 GB stop size"
FPS=$'620\t'$((22 * G))
out="$(AGENTS_MEM_KILL=20 tick 7025)"
[[ "$(samples 620)" == 5 ]] || fail "sampled on the fifth look too: $(samples 620)"
[[ "$(cat "$tmp/killed")" == "620@Wed_Oct_14_09:00:05_2026" ]] || fail "22 GB past AGENTS_MEM_KILL=20 stops it: $(cat "$tmp/killed" 2>/dev/null)"
[[ "$out" == *"Stopped node (clientFuelToday.test.js) in cairn: it held 22.0G past the 20.0G limit (claude:600)"* ]] || fail "stop text: $out"
[[ "$(samples 700)" == 1 ]] || fail "Chrome, beside it, sampled once: $(samples 700)"
pass "a process the guard could stop is sampled every look while large, and stopped past AGENTS_MEM_KILL"

# (c) One it can't stop that grows past the warning is still warned about,
#     once: at once when RSS shows it, at the 5-minute look when only the
#     footprint does.
reset
psfix="$(fix 1000 $((6 * G)))"; FPS=""
out="$(tick 8000)"
[[ "$out" != *"Google Chrome"* ]] || fail "6 GB is under the warning: $out"
psfix="$(fix 1000 $((9 * G)))"
out="$(tick 8005)"
[[ "$out" == *"Google Chrome in cairn holds 9.0G (not stopped by the guard)"* ]] || fail "past the warning by RSS: $out"
out="$(tick 8010)$(tick 8015)$(tick 8020)"
[[ "$out" != *"Google Chrome"* ]] || fail "warned once: $out"
grep -c $'\twarn\t700\t' "$AGENTS_DATA_DIR/memory.tsv" | grep -qx 1 || fail "one warn incident"
reset
psfix="$(fix 1000 $((6 * G)))"; FPS=""
tick 8100 >/dev/null
FPS=$'700\t'$((12 * G))
out="$(tick 8105)$(tick 8110)"
[[ "$out" != *"Google Chrome"* ]] || fail "not sampled again with RSS flat: $out"
out="$(tick 8400)"
[[ "$out" == *"Google Chrome in cairn holds 12.0G (not stopped by the guard)"* ]] || fail "the 5-minute look warns: $out"
out="$(tick 8405)"
[[ "$out" != *"Google Chrome"* ]] || fail "and only once: $out"
FPS=""
pass "one the guard can't stop is warned about once past the warning (by RSS at once, by footprint within 5 minutes)"

# (d) Under critical pressure every candidate is sampled, and the largest
#     agent-tree process past the warning is stopped; free memory falling
#     faster than AGENTS_MEM_RATE samples them all too.
reset
psfix="$(fix $((6 * G)) $((6 * G)))"
FPS=$'620\t'$((7 * G))
tick 9000 >/dev/null; tick 9005 >/dev/null
[[ "$(samples 700) $(samples 620)" == "1 2" ]] || fail "before the pressure: $(samples 700) $(samples 620)"
MACH=$'50331648\t3\tcritical\t2097152\t2097152'
FPS=$'620\t'$((10 * G))
out="$(tick 9010)"
[[ "$(samples 700) $(samples 900) $(samples 620)" == "2 2 3" ]] || fail "critical samples them all: $(samples 700) $(samples 900) $(samples 620)"
[[ "$(cat "$tmp/killed")" == "620@Wed_Oct_14_09:00:05_2026" ]] || fail "critical pressure stops node at a 10 GB footprint (6 GB RSS)"
[[ "$out" == *"while memory pressure is critical"* ]] || fail "critical stop text: $out"
reset
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
psfix="$(fix 1000 $((6 * G)))"; FPS=""
tick 9100 >/dev/null; tick 9105 >/dev/null
[[ "$(samples 700)" == 1 ]] || fail "steady: $(samples 700)"
MACH=$'50331648\t30\tnormal\t1048576\t2097152'   # 4.8 GB gone in 5 s
tick 9110 >/dev/null
[[ "$(samples 700) $(samples 900)" == "2 2" ]] || fail "free memory falling fast samples them all: $(samples 700) $(samples 900)"
tick 9115 >/dev/null
[[ "$(samples 700)" == 2 ]] || fail "and steady again: $(samples 700)"
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
pass "critical pressure or fast-falling free memory samples every candidate; the largest agent-tree one past the warning is stopped"

# Where RSS is the footprint (Linux), nothing is ever sampled; RSS decides.
reset
psfix="$(fix $((30 * G)) $((6 * G)))"
out="$(MEASURED=0 tick 9200)"
[[ ! -e "$tmp/sampled" ]] || fail "sampled off macOS: $(cat "$tmp/sampled")"
[[ "$(cat "$tmp/killed")" == "620@Wed_Oct_14_09:00:05_2026" ]] || fail "30 GB of RSS stops it off macOS"
psfix="$psfix_small"
pass "off macOS no footprint is sampled and RSS decides, every look"

# 4c. When the guard looks next (_AGENTS_MEM_NEXT): POLL while anything needs
#     watching, IDLE otherwise, a minute with no agent session; clamped.
next() { ( AGENTS_NOW="$1" agents_mem_tick >/dev/null; echo "$_AGENTS_MEM_NEXT" ); }
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
quiet="$(printf '%s\n' "$psfix_small" | awk '$1 == 620 || $1 == 700 { $6 = 1000 } { print }')"
reset; psfix="$psfix_small"; FPS=""
[[ "$(next 7000)" == 5 ]] || fail "a candidate past half the warning keeps the poll at 5 s"
reset; psfix="$quiet"
[[ "$(next 7100)" == 20 ]] || fail "nothing large, an agent running: the idle interval, 20 s"
[[ "$(AGENTS_MEM_IDLE=10 next 7100)" == 10 ]] || fail "AGENTS_MEM_IDLE is honoured"
[[ "$(AGENTS_MEM_IDLE=2 next 7100)" == 5 ]] || fail "idle is never below the poll"
reset; psfix="$(printf '%s\n' "$quiet" | awk '$1 != 600 && $1 != 620 { print }')"
MACH=$'134217728\t40\tnormal\t1048576\t2097152'
[[ "$(next 7200)" == 60 ]] || fail "no agent session at all (128 GB, a bound past the minute): 60 s"
[[ "$(AGENTS_MEM_IDLE=90 next 7205)" == 76 ]] || fail "no agent session (128 GB), AGENTS_MEM_IDLE=90: the safety bound, (64 - 4) GB at 800 MB/s, 76 s"
# ... never past the safety bound: 48 GB, (24 - 4) GB at 800 MB/s is 25 s; 16 GB
# (a 4.8 GB warning, 60 % of the 8 GB stop), (8 - 2.4) GB at 800 MB/s, 7 s.
MACH=$'16777216\t40\tnormal\t1048576\t2097152'
[[ "$(next 7210)" == 7 ]] || fail "no agent session on 16 GB: the minute exceeds the 7 s safety bound"
[[ "$(AGENTS_MEM_IDLE=90 next 7220)" == 7 ]] || fail "no agent session on 16 GB, AGENTS_MEM_IDLE=90: past the 7 s safety bound"
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
[[ "$(next 7230)" == 25 ]] || fail "no agent session on 48 GB: the minute exceeds the 25 s safety bound"
# Pressure, or free memory falling at half the rate, keep the poll.
reset; psfix="$quiet"; MACH=$'50331648\t40\twarn\t1048576\t2097152'
[[ "$(next 7300)" == 5 ]] || fail "memory pressure warn keeps the poll"
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
reset; psfix="$quiet"
tick 7400 >/dev/null                                      # saves free 40% at 7400
MACH=$'50331648\t39\tnormal\t1048576\t2097152'            # 1% of 48 GB in 4 s: ~125 MB/s, past half of 200
[[ "$(next 7404)" == 5 ]] || fail "free memory falling at half the rate keeps the poll"
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
# The clamp: a 16 GB machine stops at 8 GB and half its 4.8 GB warning is
# 2.4 GB; a runaway at 4 x 200 MB/s covers 5.6 GB in 7 s, so the interval
# cannot exceed 7.
reset; psfix="$quiet"; MACH=$'16777216\t40\tnormal\t1048576\t2097152'
[[ "$(AGENTS_MEM_IDLE=60 next 7500)" == 7 ]] || fail "idle clamped to the runaway's time to the stop size"
MACH=$'50331648\t40\tnormal\t1048576\t2097152'
[[ "$(AGENTS_MEM_IDLE=60 next 7600)" == 25 ]] || fail "48 GB: (24 - 4) GB at 800 MB/s is 25 s"
# A runaway still stops within one interval: an idle look, then it jumps past
# the stop size, and the very next look stops it.
reset; psfix="$quiet"
[[ "$(next 7700)" == 20 ]] || fail "idle before the runaway"
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 620 { $6 = g * 30 } { print }')"
FPS=""
tick 7720 >/dev/null
[[ "$(cat "$tmp/killed" 2>/dev/null)" == "620@Wed_Oct_14_09:00:05_2026" ]] || fail "the look after an idle interval stops a runaway past the stop size"
psfix="$psfix_small"; reset
pass "adaptive poll: poll while watching, idle otherwise, a minute without an agent; clamped; a runaway still stops at the next look"

# 4d. Thresholds by RAM: the warning is AGENTS_MEM_WARN (8 GB) or 60 % of the
#     stop size (half the RAM), the smaller; it always comes before the stop.
for gb in 8 16 32 64; do
    s="$(_agents_mem_kill_kib $((gb * G)))"; w="$(_agents_mem_warn_kib "$s")"
    case $gb in
        8)  want="$((4 * G)) 2516582" ;;    # stop 4 GB, warn 2.4 GB
        16) want="$((8 * G)) 5033164" ;;    # stop 8 GB, warn 4.8 GB
        32) want="$((16 * G)) $((8 * G))" ;;
        64) want="$((32 * G)) $((8 * G))" ;;
    esac
    [[ "$s $w" == "$want" ]] || fail "$gb GB: stop $s, warn $w; want $want"
    [[ $w -lt $s ]] || fail "$gb GB: the warning ($w) is not under the stop ($s)"
done
[[ "$(AGENTS_MEM_WARN=2 _agents_mem_warn_kib $((8 * G)))" == $((2 * G)) ]] || fail "a lower AGENTS_MEM_WARN wins"
[[ "$(AGENTS_MEM_KILL=6 _agents_mem_warn_kib "$(AGENTS_MEM_KILL=6 _agents_mem_kill_kib $((64 * G)))")" == 3774873 ]] || fail "AGENTS_MEM_KILL=6: warn at 3.6 GB"
# On 16 GB and 8 GB a runaway is warned about, then stopped, and screened
# (sampled) from half the warning.
for m in 16 8; do
    reset; MACH="$((m * G))"$'\t40\tnormal\t1048576\t2097152'
    small=$((m * G * 3 / 20))   # 15 % of the RAM: past half the warning, under it
    psfix="$(printf '%s\n' "$psfix_small" | awk -v k="$small" '$1 == 620 { $6 = k } $1 == 700 { $6 = 1000 } { print }')"
    FPS=""
    out="$(tick 11000)"
    [[ "$(samples 620)" == 1 && -z "$out" ]] || fail "$m GB: $small KiB is screened, not warned about: $(samples 620) '$out'"
    FPS=$'620\t'$((m * G * 2 / 5))   # 40 % of the RAM: past the warning, under the stop
    out="$(tick 11005)"
    [[ "$out" == *"holds"*"; stopped at $((m / 2)).0G"* && ! -s "$tmp/killed" ]] || fail "$m GB: warned first: $out"
    FPS=$'620\t'$((m * G * 11 / 20))
    out="$(tick 11010)"
    [[ "$out" == *"Stopped node"* && -s "$tmp/killed" ]] || fail "$m GB: then stopped: $out"
done
MACH=$'50331648\t40\tnormal\t1048576\t2097152'; FPS=""; psfix="$psfix_small"
pass "thresholds on 8, 16, 32 and 64 GB: a warning before the stop on each; screening from half the warning"

# 4e. A runner that starts the runaway again: the same script under the same
#     tool command stopped again within _AGENTS_MEM_RESPAWN stops that command
#     (pid 610, the agent's child), never the agent; outside the window, or
#     another script, stops only the process again.
# worker PID CLOCK SCRIPT — the fixture with node 620 replaced by PID (started
# at CLOCK) running SCRIPT at 30 GB.
worker() {
    printf '%s\n' "$psfix_small" | awk -v g="$G" -v p="$1" -v c="$2" -v js="$3" \
        '$1 == 620 { $1 = p; $6 = g * 30; $12 = c; gsub(/clientFuelToday\.test\.js/, js) } { print }'
}
killed() { tr '\n' ' ' < "$tmp/killed" 2>/dev/null; }
reset
psfix="$(worker 620 09:00:05 clientFuelToday.test.js)"
tick 12000 >/dev/null
psfix="$(worker 621 09:00:50 clientFuelToday.test.js)"
out="$(tick 12040)"
[[ "$(killed)" == "620@Wed_Oct_14_09:00:05_2026 610@Wed_Oct_14_09:00:00_2026 " ]] || fail "the respawn stops the tool command: $(killed)"
[[ "$out" == *"Stopped zsh in cairn, the command that keeps starting node (clientFuelToday.test.js): it held 30.0G past the 24.0G limit again 40s after the last stop (claude:600)"* ]] || fail "escalation text: $out"
line="$(grep $'\tescalate\t' "$AGENTS_DATA_DIR/memory.tsv")"
[[ "$line" == *$'\tescalate\t610\tzsh\tclientFuelToday.test.js\tcairn\tclaude:600\t'* \
    && "$line" == *$'\tnode (clientFuelToday.test.js) stopped again 40s after the guard stopped pid 620 under the same command' ]] || fail "escalate incident: $line"
grep -q $'\tguard\tmemory\t610\t' "$AGENTS_DATA_DIR/events.tsv" || fail "the escalation in events.tsv"
# Outside the window: only the process again.
reset
psfix="$(worker 620 09:00:05 clientFuelToday.test.js)"; tick 13000 >/dev/null
psfix="$(worker 621 09:02:10 clientFuelToday.test.js)"; tick 13121 >/dev/null
[[ "$(killed)" == "620@Wed_Oct_14_09:00:05_2026 621@Wed_Oct_14_09:02:10_2026 " ]] || fail "121 s later is a new runaway: $(killed)"
# Another script under the same command: only the process.
reset
psfix="$(worker 620 09:00:05 clientFuelToday.test.js)"; tick 14000 >/dev/null
psfix="$(worker 621 09:00:50 other.test.js)"; tick 14030 >/dev/null
[[ "$(killed)" == "620@Wed_Oct_14_09:00:05_2026 621@Wed_Oct_14_09:00:50_2026 " ]] || fail "another script is not a respawn: $(killed)"
# Node straight under the agent: its tool command is itself, so the agent is
# never the one stopped.
reset
psfix="$(worker 620 09:00:05 clientFuelToday.test.js | awk '$1 == 620 { $2 = 600 } { print }')"; tick 15000 >/dev/null
psfix="$(worker 621 09:00:50 clientFuelToday.test.js | awk '$1 == 621 { $2 = 600 } { print }')"; tick 15010 >/dev/null
[[ "$(killed)" == "620@Wed_Oct_14_09:00:05_2026 621@Wed_Oct_14_09:00:50_2026 " ]] || fail "under the agent itself: $(killed)"
# Under a nested agent (claude > codex > zsh > node): the nested agent's
# child, zsh, never codex or claude.
reset
nest() { worker "$@" | awk '$1 == 610 { $2 = 605 } { print }'; echo "  605   600   501 me    0.0   300000   0:00.10 00:01:00 Wed Oct 14 08:59:00 2026     codex exec run-tests"; }
psfix="$(nest 620 09:00:05 clientFuelToday.test.js)"; tick 16000 >/dev/null
psfix="$(nest 621 09:00:50 clientFuelToday.test.js)"; tick 16010 >/dev/null
[[ "$(killed)" == "620@Wed_Oct_14_09:00:05_2026 610@Wed_Oct_14_09:00:00_2026 " ]] || fail "nested agent: $(killed)"
# A dry run says what it would stop.
reset
psfix="$(worker 620 09:00:05 clientFuelToday.test.js)"; tick 17000 >/dev/null
psfix="$(worker 621 09:00:50 clientFuelToday.test.js)"; out="$(AGENTS_DRY_RUN=true tick 17020)"
[[ "$out" == "would stop zsh (pid 610), the command running node (clientFuelToday.test.js) in cairn (claude:600): node (clientFuelToday.test.js) stopped again 20s after the guard stopped pid 620 under the same command" ]] || fail "dry run escalation: $out"
[[ "$(killed)" == "620@Wed_Oct_14_09:00:05_2026 " ]] || fail "the dry run stopped something: $(killed)"
psfix="$psfix_small"
# Stops older than the window leave the state file and the loop's memory.
out="$( _AGENTS_MEM_STATE="" _AGENTS_MEM_LEVEL=normal _AGENTS_MEM_STOPS=$'1000\t610@x\tnode\t620\n1100\t610@x\tnode\t621\n'
    AGENTS_NOW=1150 _agents_mem_state_save; printf '%s|' "$_AGENTS_MEM_STOPS"; grep -c '^stop' "$AGENTS_RUN_DIR/memguard.state")"
[[ "$out" == $'1100\t610@x\tnode\t621\n|1' ]] || fail "stops pruned to the window: $out"
pass "a runaway started again under the same tool command within 120 s stops that command; never the agent; not outside the window or for another script"

# 4f. A probe cut off is no reading: no stop, no new warning, the last
#     footprint stands; the next good sample goes on from there.
reset
psfix="$(printf '%s\n' "$psfix_small" | awk -v g="$G" '$1 == 620 { $6 = g * 5 } { print }')"
FPS=$'620\t'$((20 * G))
out="$(tick 18000)"
[[ "$out" == *"holds 20.0G; stopped at 24.0G"* ]] || fail "warned at 20 GB: $out"
before="$(grep '^620@' "$AGENTS_RUN_DIR/memguard.state")"
FPS=""; out="$(FP_RC=124 tick 18005)"
[[ -z "$out" && ! -s "$tmp/killed" ]] || fail "a cut-off probe warned or stopped: $out"
[[ "$(grep '^620@' "$AGENTS_RUN_DIR/memguard.state")" == "$before" ]] || fail "the last footprint stands: $(grep '^620@' "$AGENTS_RUN_DIR/memguard.state") (was $before)"
FPS=$'620\t'$((20 * G)); out="$(tick 18010)"
[[ -z "$out" ]] || fail "no second warning for the same step after a cut-off look: $out"
# End to end, with the real sample and both probes hanging: the look ends
# within the cut-offs, stops nothing, and the heartbeat after it advances.
reset
SECONDS=0
(
    eval "$real_fp"
    # shellcheck disable=SC2329  # called by the real _agents_mem_fp
    _agents_mem_footprint() { _agents_timeout 1 sh -c 'exec sleep 30'; }
    # shellcheck disable=SC2329  # called by the real _agents_mem_fp
    _agents_mem_top() { _agents_timeout 1 sh -c 'exec sleep 30'; }
    OSTYPE=darwin25 AGENTS_NOW=18100 agents_mem_tick >/dev/null
    AGENTS_NOW=18100 _agents_mem_beat
)
[[ $SECONDS -lt 10 && ! -s "$tmp/killed" ]] || fail "hung probes: ${SECONDS}s, killed $(killed)"
[[ "$(cat "$AGENTS_RUN_DIR/memguard.beat")" == "18100 5" ]] || fail "heartbeat: $(cat "$AGENTS_RUN_DIR/memguard.beat" 2>/dev/null)"
grep -q '^620@' "$AGENTS_RUN_DIR/memguard.state" || fail "the look saved its state"
FPS=""; psfix="$psfix_small"
pass "a probe cut off: no stop, no warning, the last footprint stands; the look ends and the heartbeat advances"

# 4g. The guard's state from its lock and heartbeat: on, stalled past three
#     polls, unknown when ps can't read the process table (a sandbox).
reset
mkdir -p "$AGENTS_RUN_DIR/memguard.lock"
echo "4242 Wed_Oct_14_06:00:00_2026" > "$AGENTS_RUN_DIR/memguard.lock/holder"
# shellcheck disable=SC2329  # the stub is called by _agents_mem_guard_state
gstate() { ( _agents_holder_check() { return "${HOLDER_RC:-0}"; }; AGENTS_NOW="$1" _agents_mem_guard_state ); }
[[ "$(gstate 1000)" == "on 4242" ]] || fail "no heartbeat yet (a guard from before it had one): on"
echo "1000 5" > "$AGENTS_RUN_DIR/memguard.beat"
# Three polls, two probe cut-offs (5 s each) and the kill grace (3 s): 28 s.
[[ "$(gstate 1028)" == "on 4242" ]] || fail "a heartbeat three slow looks old is on"
[[ "$(gstate 1029)" == "stalled 4242 29" ]] || fail "past three slow looks: $(gstate 1029)"
echo "1000 60" > "$AGENTS_RUN_DIR/memguard.beat"
[[ "$(gstate 1193)" == "on 4242" ]] || fail "idle at a minute: three of those and a slow look"
[[ "$(gstate 1194)" == "stalled 4242 194" ]] || fail "idle, stalled: $(gstate 1194)"
# A stop in this same look is a sibling, not a respawn.
( _AGENTS_MEM_STOPS=$'500\tz@s\tnode (x.test.js)\t620'
  _agents_mem_respawned "z@s" "node (x.test.js)" 500 && exit 1
  _agents_mem_respawned "z@s" "node (x.test.js)" 540 ) || fail "respawned: the same look must not count, a later one must"
[[ "$(HOLDER_RC=2 gstate 1000)" == unknown ]] || fail "ps can't tell whose the holder is: unknown"
rm -rf "$AGENTS_RUN_DIR/memguard.lock"
[[ "$(PS_OK=0 gstate 1000)" == unknown ]] || fail "no holder, and ps reads nothing: unknown"
[[ "$(gstate 1000)" == none ]] || fail "no holder, ps fine, no LaunchAgent: none"
pass "guard state: on, stalled once the heartbeat is three polls old, unknown when the process table can't be read"

# 4h. `agents mem`: the stalled guard, the escalation (counted with the stops,
#     pointing at the log, its why under it), and in a sandbox, no "not running".
reset
# shellcheck disable=SC2329  # the stubs are called by _agents_mem_show
show() { ( _agents_mem_top() { return "${TOP_RC:-0}"; }; OSTYPE=darwin25; _agents_mem_guard_state() { echo "$GS"; }; AGENTS_NOW=12100 AGENTS_WIDTH=120 _agents_mem_show ); }
mkdir -p "$AGENTS_DATA_DIR"
printf '%s\n' $'12000\tstop\t620\tnode\tclientFuelToday.test.js\tcairn\tclaude:600\t31457280\t10485760\t3\t2097152' \
    $'12040\tescalate\t610\tzsh\tclientFuelToday.test.js\tcairn\tclaude:600\t31457280\t10485760\t3\t2097152\tnode (clientFuelToday.test.js) stopped again 40s after the guard stopped pid 620 under the same command' \
    > "$AGENTS_DATA_DIR/memory.tsv"
out="$(GS="stalled 42 125" show)"
[[ "$out" == *"GUARD   stalled (pid 42, no look for 2m; agents mem restart) · kill · 2 stops in 7 days, 1 escalated to the tool command (agents mem log)"* ]] || fail "stalled and escalation summary: $out"
[[ "$out" == *"escalate zsh (clientFuelToday.test.js)"*$'\n'*"node (clientFuelToday.test.js) stopped again 40s after the guard stopped pid 620 under the same command"* ]] || fail "the escalation and why in the incidents: $out"
out="$(GS=unknown MACH=$'50331648\t-\t-\t-\t-' show)"
[[ "$out" == *"GUARD   unknown: the process table can't be read from inside a sandbox"* ]] || fail "sandbox guard wording: $out"
[[ "$out" == *"MEMORY  unknown: can't be read from inside a sandbox"* ]] || fail "sandbox memory wording: $out"
[[ "$out" != *"not running"* && "$out" != *"pressure -"* ]] || fail "a sandbox reads as a guard that is down: $out"
out="$(GS=unknown MACH=$'50331648\t40\t-\t-\t-' show)"
[[ "$out" == *"60% used of 48.0G · pressure can't be read from inside a sandbox"* ]] || fail "free memory read, pressure not: $out"
out="$(GS="on 42" TOP_RC=124 show)"
[[ "$out" == *"top did not answer in 5 s: no footprints this time"* ]] || fail "a top cut off is said: $out"
pass "agents mem: stalled, escalations with why and the log, and a sandbox said as such"

# 5. The menu's memg row: the guard's state and the last incident.
reset
mkdir -p "$AGENTS_DATA_DIR" "$AGENTS_RUN_DIR"
printf '1000\tstop\t620\tnode\tclientFuelToday.test.js\tcairn\tclaude:600\t31457280\t10485760\t3\t2097152\n' > "$AGENTS_DATA_DIR/memory.tsv"
echo 50331648 > "$AGENTS_RUN_DIR/memtotal"
row="$(_agents_mem_tsv_row)"
[[ "$row" == $'memg\tnone\t-\t8388608\t25165824\t1000\tstop\tnode (clientFuelToday.test.js)\tcairn\t31457280' ]] || fail "memg row: $row"
# The LaunchAgent on macOS, the systemd user service on Linux.
unit="$(_agents_mem_unit)"; mkdir -p "${unit%/*}"; touch "$unit"
[[ "$(_agents_mem_guard_state)" == stopped ]] || fail "an installed guard service with no guard running is stopped"
[[ "$(OSTYPE=darwin25 _agents_mem_unit)" == "$HOME/Library/LaunchAgents/dev.tuidev.memguard.plist" ]] || fail "the guard's unit on macOS"
[[ "$(OSTYPE=linux-gnu XDG_CONFIG_HOME='' _agents_mem_unit)" == "$HOME/.config/systemd/user/tuidev-memguard.service" ]] || fail "the guard's unit on Linux"
[[ "$(AGENTS_MEM_GUARD=off _agents_mem_guard_state)" == off ]] || fail "off"
echo 16777216 > "$AGENTS_RUN_DIR/memtotal"
row="$(PS_OK=0 _agents_mem_tsv_row)"
[[ "$row" == $'memg\tunknown\t-\t5033164\t8388608\t'* ]] || fail "memg row in a sandbox on 16 GB: $row"
pass "memg row: guard state (none, stopped, off, unknown), warn and stop sizes, the last incident"

# 6. Settings: shapes are checked.
_agents_conf_valid AGENTS_MEM_GUARD kill  || fail "kill is valid"
! _agents_conf_valid AGENTS_MEM_GUARD nuke || fail "nuke is not"
_agents_conf_valid AGENTS_MEM_KILL 0      || fail "AGENTS_MEM_KILL=0 is valid (half the RAM)"
! _agents_conf_valid AGENTS_MEM_WARN 0    || fail "AGENTS_MEM_WARN=0 is not"
! _agents_conf_valid AGENTS_MEM_POLL 2s   || fail "AGENTS_MEM_POLL takes seconds as a number"
_agents_conf_valid AGENTS_MEM_IDLE 20     || fail "AGENTS_MEM_IDLE takes seconds"
! _agents_conf_valid AGENTS_MEM_IDLE 0    || fail "AGENTS_MEM_IDLE=0 is not valid"
pass "AGENTS_MEM_* values are validated"

# 7. Memory hogs lead the hogs, in any tree, by RSS.
hogs="$(printf '%s\n' "$psfix" | awk -v g="$G" '$1 == 620 { $6 = g * 9 } { print }' | agents_classify "" "" | awk -F '\t' '$1 == "hog" { print $2 }' | tr '\n' ' ')"
[[ "$hogs" == "620 "* ]] || fail "a 9 GB node in an agent tree leads the hogs: $hogs"
pass "memory hogs (RSS past AGENTS_MEM_WARN) lead the hogs, agent trees included"

echo
echo "All agents memory tests passed."
