#!/bin/bash
# The menu bar refreshes when it is needed: `agents bar poke` (lib/agents/bar.sh)
# and the plugin's own decisions (configs/swiftbar/agents.10s.sh): who may
# poke, the 2 s debounce and its trailing poke, the next-refresh table, the
# one pending early refresh, the idle fast path and what defeats it, bar.alive,
# the Herdr label sync from the menu, and the once-a-minute jobs on a 60 s timer.
# Run: bash scripts/lib/test_agents_bar.sh  -> exit 0 on pass.
#
# `open` is a stub on PATH, and so are `agents` (for the plugin) and `ps`
# (SwiftBar's pid): nothing here ever asks the real SwiftBar for anything.

# Tests change variables inside ( … ) on purpose; the stubs are called by the
# sourced functions.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN="$REPO_DIR/configs/swiftbar/agents.10s.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
bgpids=""
cleanup() { local p; for p in $bgpids; do kill "$p" 2>/dev/null || true; done; rm -rf "$tmp"; }
trap cleanup EXIT
for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR SWIFTBAR SWIFTBAR_PLUGIN_REFRESH_REASON; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 AGENTS_CONF="$tmp/none.conf" AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data"
mkdir -p "$HOME" "$AGENTS_RUN_DIR" "$AGENTS_DATA_DIR" "$tmp/bin"
# The stub `open`: what a poke would have asked SwiftBar.
printf '#!/bin/sh\necho "$*" >> "%s/opened"\n' "$tmp" > "$tmp/bin/open"; chmod +x "$tmp/bin/open"
export PATH="$tmp/bin:$PATH"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
opened() { if [[ -f "$tmp/opened" ]]; then grep -c . "$tmp/opened"; else echo 0; fi; }
R="$AGENTS_RUN_DIR"
# A stand-in SwiftBar: a process that lives while the test needs it.
sleep 600 & SB=$!; bgpids="$SB"; disown "$SB" 2>/dev/null || true
alive() { printf '%s %s %s -\n' "${2:-$(date +%s)}" "${1:-$SB}" "${3:-agents}" > "$R/bar.alive"; }
settle() { local i; for i in $(seq 1 "${1:-30}"); do [[ -e "$R/bar.busy" ]] || return 0; sleep 0.1; done; }
OSTYPE=darwin25   # the poke is for macOS; this runs on Linux CI too

# --- 1. Who may poke --------------------------------------------------------------------
_AGENTS_BAR_GAP=1
rm -f "$R"/bar.* "$tmp/opened"
agents_bar_poke; sleep 0.2
[[ "$(opened)" == 0 && ! -e "$R/bar.dirty" && ! -e "$R/bar.busy" ]] || fail "a poke with no plugin run under SwiftBar went out: $(ls -A "$R")"
alive 99999999; agents_bar_poke; sleep 0.2
[[ "$(opened)" == 0 && ! -e "$R/bar.dirty" ]] || fail "a poke went out to a SwiftBar that is not running (open would launch it)"
alive "$SB" "$(( $(date +%s) - 181 ))"; agents_bar_poke; sleep 0.2
[[ "$(opened)" == 0 ]] || fail "a poke went out on a bar.alive older than two backstops"
alive "$SB" "" 'bad;name'; agents_bar_poke; sleep 0.2
[[ "$(opened)" == 0 ]] || fail "a poke went out for a plugin name it should not put in a URL"
alive; ( OSTYPE=linux-gnu; agents_bar_poke ); sleep 0.2
[[ "$(opened)" == 0 ]] || fail "a poke went out off macOS"
: > "$R/bar.alive"; agents_bar_poke; sleep 0.2
[[ "$(opened)" == 0 ]] || fail "a poke went out on an empty bar.alive"
alive; AGENTS_BAR_REFRESH=10m; agents_bar_poke; settle
[[ "$(cat "$tmp/opened")" == "-g swiftbar://refreshplugin?name=agents" ]] || fail "the poke: $(cat "$tmp/opened" 2>/dev/null)"
[[ -s "$R/bar.poked" ]] || fail "no bar.poked after a poke"
AGENTS_BAR_REFRESH=1m
pass "a poke goes out only under SwiftBar here (bar.alive: a live pid, fresh, a plain name, macOS); else nothing, and no file"

# --- 2. Debounce: one per window, the last of a burst kept -------------------------------
rm -f "$R"/bar.busy "$R"/bar.dirty "$tmp/opened"; alive
for i in 1 2 3 4 5; do agents_bar_poke; done
sleep 0.3
[[ "$(opened)" == 1 && -e "$R/bar.busy" && -e "$R/bar.dirty" ]] || fail "a burst of 5: $(opened) pokes now, $(ls -A "$R")"
settle 40
[[ "$(opened)" == 2 && ! -e "$R/bar.dirty" ]] || fail "a burst of 5: $(opened) pokes in all (want 2: the first, then one at the window's end)"
# A single poke: one, and the window closes without another.
rm -f "$tmp/opened"; agents_bar_poke; settle 40
[[ "$(opened)" == 1 && ! -e "$R/bar.busy" ]] || fail "a single poke: $(opened)"
# --settle: once more at the window's end.
rm -f "$tmp/opened"; agents_bar_poke --settle; settle 40
[[ "$(opened)" == 2 ]] || fail "--settle: $(opened) pokes (want 2)"
# A storm: a Stop every 0.1 s for 3 s costs one poke per window, plus the last.
rm -f "$tmp/opened"
SECONDS=0; while [[ $SECONDS -lt 3 ]]; do agents_bar_poke; sleep 0.1; done
settle 40
n="$(opened)"
[[ $n -ge 3 && $n -le 5 ]] || fail "a 3 s storm with a 1 s window: $n pokes (want 3 to 5)"
# A keeper that died (a bar.busy 10 s old) is taken over; a fresh one is not.
rm -f "$tmp/opened"; printf '%s\n' "$(( $(date +%s) - 3 ))" > "$R/bar.busy"
agents_bar_poke; sleep 0.2
[[ "$(opened)" == 0 && -e "$R/bar.dirty" ]] || fail "a poke inside a live window went out"
printf '%s\n' "$(( $(date +%s) - 11 ))" > "$R/bar.busy"; rm -f "$R/bar.dirty"
agents_bar_poke; settle 40
[[ "$(opened)" == 1 ]] || fail "a bar.busy whose keeper is gone was not taken over: $(opened)"
# SwiftBar quits inside a window: the trailing poke does not launch it.
rm -f "$tmp/opened"; agents_bar_poke; agents_bar_poke
sleep 0.2; alive 99999999
settle 40
[[ "$(opened)" == 1 && ! -e "$R/bar.busy" ]] || fail "the trailing poke went to a SwiftBar that quit: $(opened)"
alive
pass "debounce: one poke per window, a burst's last one at the window's end, a storm costs one per window; --settle; a dead keeper's window is taken over"

# --- 3. The next refresh: bar_next_in, from the plugin ----------------------------------------
eval "$(awk '/^BAR_FAST=/ { print } /^bar_next_in\(\) \{/, /^\}/ { print } /^bar_secs\(\) \{/, /^\}/ { print }' "$PLUGIN")"
[[ "$BAR_FAST" == 10 ]] || fail "BAR_FAST is $BAR_FAST"
# TOOLS UNHOOKED ENDS_IN BACKSTOP -> SECONDS   what
while IFS='|' read -r args want what; do
    [[ -n "$args" ]] || continue
    # shellcheck disable=SC2086  # four numbers
    bar_next_in $args
    [[ "$REPLY" == "$want" ]] || fail "bar_next_in $args ($what): $REPLY, want $want"
done <<'EOF'
0 0 -1 60|0|nothing going on: the backstop
0 0 -1 60|0|a hog candidate short of its sustain time: the backstop (read every 30 s at best)
1 0 -1 60|10|a live command (and its run, with history on)
3 0 -1 60|10|several live commands
0 1 -1 60|10|a working session nothing reports on (codex outside Herdr)
0 0 30 60|31|a keep-awake that ends in 30 s: just after it
0 0 0 60|2|a countdown ending now: 2 s at the soonest
0 0 59 60|0|a countdown that ends with the backstop: the backstop
0 0 300 60|0|a countdown past the backstop: the backstop
1 0 3 60|4|a countdown before the next fast refresh
1 0 30 60|10|a live command with a countdown later
1 1 -1 10|0|a 10 s backstop is already as fast
1 0 -1 5|0|a backstop faster than that
0 1 -1 3600|10|an hour's backstop, a session working
EOF
while IFS='|' read -r v want; do
    [[ -n "$v" ]] || continue
    bar_secs "$v"; [[ "$REPLY" == "$want" ]] || fail "bar_secs $v: $REPLY, want $want"
    _agents_bar_secs got "$v"; [[ "$got" == "$want" ]] || fail "_agents_bar_secs $v: $got, want $want"
done <<'EOF'
10s|10
1m|60
2h|7200
1d|86400
30|60
x|60
EOF
pass "the next-refresh table: 10 s while a command runs or an unreported session works, a countdown's end, else the backstop; the interval read alike in the plugin and agents"

# --- 4. The plugin: idle fast path, early refresh, bar.alive, Herdr sync ---------------------
M="$tmp/m"; mkdir -p "$M/cache"; ln -s "$PLUGIN" "$M/agents.1m.sh"   # SwiftBar's name for it
# shellcheck disable=SC2016  # the stubs' own variables
printf '#!/bin/bash\necho "$*" >> "%s/calls"\n[[ "$1" != tsv ]] || cat "%s/tsv"\n' "$M" "$M" > "$M/agents"
chmod +x "$M/agents"
# ps: the plugin's parent is SwiftBar (a run under SwiftBar), unless PSCOMM says otherwise.
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$*" in *ppid=,comm=*) echo "1 ${PSCOMM:-/Applications/SwiftBar.app/Contents/MacOS/SwiftBar}" ;; *comm=*) echo "${PSPARENT:-launchd}" ;; esac\n' > "$tmp/bin/ps"
chmod +x "$tmp/bin/ps"
idle_tsv() { printf 'sys\t5\t1.0\t8\t60\tnormal\t-\t-\nhist\tok\t0\t-\t0\nconf\tAGENTS_BAR_REFRESH\t1m\n' > "$M/tsv"; }
calls() { if [[ -f "$M/calls" ]]; then grep -c '^tsv' "$M/calls"; else echo 0; fi; }
# mbar [VAR=VALUE...] — one run as SwiftBar makes it (a timed one unless the
# caller says otherwise); the output in $M/out.
mbar() {
    env PATH="$tmp/bin:$PATH" AGENTS_BIN="$M/agents" SWIFTBAR=1 SWIFTBAR_PLUGIN_CACHE_PATH="$M/cache" \
        SWIFTBAR_PLUGIN_PATH="$M/agents.1m.sh" SWIFTBAR_PLUGIN_REFRESH_REASON=Schedule "$@" bash "$PLUGIN" > "$M/out"
}
rm -f "$R"/bar.*
idle_tsv; rm -f "$M/calls"
mbar
[[ "$(calls)" == 1 && -s "$M/cache/last" && -s "$M/cache/last.idle" ]] || fail "an idle full run: $(calls) tsv calls, $(ls "$M/cache")"
read -r t pid name launch < "$R/bar.alive"
[[ "$t" =~ ^[0-9]+$ && "$pid" =~ ^[0-9]+$ && "$name" == agents && "$launch" == - ]] || fail "bar.alive: $(cat "$R/bar.alive")"
kept="$(cat "$M/out")"
mbar
[[ "$(calls)" == 1 && "$(cat "$M/out")" == "$kept" ]] || fail "the idle fast path asked agents ($(calls) tsv calls) or printed something else"
pass "idle: a timed run after an idle full run prints the kept output and asks agents nothing; bar.alive names SwiftBar's pid and the plugin"
# What defeats it, each alone.
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; [[ "$(calls)" == 2 ]] || fail "a poke's run took the idle fast path"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=MenuAction; [[ "$(calls)" == 3 ]] || fail "a manual refresh took the idle fast path"
mbar; [[ "$(calls)" == 3 ]] || fail "the fast path did not come back"
: > "$R/bar.dirty"; mbar; [[ "$(calls)" == 4 ]] || fail "a pending poke (bar.dirty) did not defeat the fast path"
rm -f "$R/bar.dirty"; mbar; [[ "$(calls)" == 4 ]] || fail "the fast path did not come back after bar.dirty"
: > "$R/bar.poked"; mbar; [[ "$(calls)" == 5 ]] || fail "a poke since the idle run did not defeat the fast path"
touch -t 202001010000 "$R/bar.poked"; mbar; [[ "$(calls)" == 5 ]] || fail "an old poke defeated the fast path"
printf '%s\n' "$(( $(date +%s) - 301 ))" > "$M/cache/last.idle"; mbar; [[ "$(calls)" == 6 ]] || fail "an idle mark 5 minutes old did not defeat the fast path"
mbar; [[ "$(calls)" == 6 ]] || fail "a full idle run did not renew the mark"
# Opening the menu prints the kept output and refreshes (open-load: agents bar poke).
rm -f "$M/calls"; mbar SWIFTBAR_PLUGIN_REFRESH_REASON=MenuOpen
for _ in $(seq 20); do grep -q 'bar poke' "$M/calls" 2>/dev/null && break; sleep 0.1; done
[[ "$(cat "$M/out")" == "$kept" && "$(calls)" == 0 && "$(grep -c '^bar poke$' "$M/calls")" == 1 ]] || fail "opening the menu: $(cat "$M/calls" 2>/dev/null)"
# Something going on clears the mark: the next timed run is a full one.
for row in $'agent\t300\tclaude\t60\t1.0\t0.1\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\tme\t-\t/w\tclaude\tw' \
           $'stale\t400\tmcp\t60\t0.0\t0.0\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\tme\t-\t/w\tnpm exec x\tw' \
           $'hog\t500\tWindowServer\t60\t90.0\t80.0\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\tme\t-\t/\tWindowServer\t-' \
           $'sys\t5\t1.0\t8\t60\twarn\t-\t-'; do
    idle_tsv; printf '%s\n' "$row" >> "$M/tsv"; rm -f "$M/calls"
    mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
    [[ ! -e "$M/cache/last.idle" ]] || fail "a full run with ${row%%$'\t'*} left the idle mark"
    mbar; [[ "$(calls)" == 2 ]] || fail "a timed run took the fast path after a ${row%%$'\t'*} row"
done
idle_tsv; mbar; [[ -e "$M/cache/last.idle" ]] || fail "back to idle, no mark"
: > "$R/hog.state.tmp"; printf 'hot\t1\n' > "$R/hog.state"; rm -f "$M/calls"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; [[ ! -e "$M/cache/last.idle" ]] || fail "a hot streak (hog.state) left the idle mark"
rm -f "$R/hog.state" "$R/hog.state.tmp"
mkdir -p "$R/runs.feed"; : > "$R/runs.feed/1.1"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; [[ ! -e "$M/cache/last.idle" ]] || fail "a run reading waiting for the sample left the idle mark"
rm -rf "$R/runs.feed"
printf 'run\tx\n' > "$AGENTS_DATA_DIR/runs.state"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; [[ ! -e "$M/cache/last.idle" ]] || fail "an open run in the ledger left the idle mark"
rm -f "$AGENTS_DATA_DIR/runs.state"
pass "idle fast path: a poke's run, a manual refresh, a pending or newer poke, an old mark, and anything going on (session, stale, hog, hot streak, warning, a run open or unsampled) take the full path"

# The early refresh: one pending (bar.next), its sleeper pokes once, the
# plugin's output does not wait for it, and a superseded one does nothing.
idle_tsv; now="$(date +%s)"
printf 'awake\ttimed\t123\t%s\n' "$((now + 2))" >> "$M/tsv"
rm -f "$M/calls" "$R/bar.next"
SECONDS=0; out="$(env PATH="$tmp/bin:$PATH" AGENTS_BIN="$M/agents" SWIFTBAR=1 SWIFTBAR_PLUGIN_CACHE_PATH="$M/cache" SWIFTBAR_PLUGIN_PATH="$M/agents.1m.sh" bash "$PLUGIN")"
[[ -n "$out" && $SECONDS -lt 2 ]] || fail "the run's output waited ${SECONDS}s for its early refresh"
read -r due tok < "$R/bar.next" || fail "no bar.next for a keep-awake ending in a second"
[[ $((due - now)) -ge 2 && $((due - now)) -le 4 ]] || fail "bar.next due in $((due - now)) s"
[[ ! -e "$M/cache/last.idle" ]] || fail "an idle mark while a refresh is due"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
[[ "$(cat "$R/bar.next")" == "$due $tok" ]] || fail "a second run replaced the pending early refresh: $(cat "$R/bar.next")"
for _ in $(seq 40); do grep -q '^bar poke$' "$M/calls" 2>/dev/null && break; sleep 0.1; done
[[ "$(grep -c '^bar poke$' "$M/calls")" == 1 && ! -e "$R/bar.next" ]] || fail "the early refresh: $(grep -c '^bar poke$' "$M/calls") pokes, bar.next $(cat "$R/bar.next" 2>/dev/null)"
# A live command: 10 s; then a sooner one replaces it, and the later sleeper stays quiet.
idle_tsv; printf 'act\t700\ttool\t5\t1.0\t1.0\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\t300\t-\t/w\tgo test ./...\t-\t-\t1\n' >> "$M/tsv"
rm -f "$M/calls"; mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; now="$(date +%s)"
read -r due tok < "$R/bar.next"; [[ $((due - now)) -ge 9 && $((due - now)) -le 10 ]] || fail "a live command: early refresh in $((due - now)) s"
idle_tsv; printf 'awake\ttimed\t123\t%s\n' "$((now + 2))" >> "$M/tsv"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
read -r due2 tok2 < "$R/bar.next"; [[ $due2 -lt $due && "$tok2" != "$tok" ]] || fail "a sooner early refresh did not replace a later one"
for _ in $(seq 40); do grep -q '^bar poke$' "$M/calls" 2>/dev/null && break; sleep 0.1; done
[[ "$(grep -c '^bar poke$' "$M/calls")" == 1 ]] || fail "the sooner early refresh did not poke"
printf '%s %s\n' "$((now + 100))" other > "$R/bar.next"   # what the 10 s sleeper finds when it wakes
pass "early refresh: one pending at a time (bar.next), a sooner one replaces a later one, its sleeper pokes once and never holds the menu's output"

# bar.alive: SwiftBar's pid, found through a shell wrapper too; nothing by hand.
rm -f "$R/bar.alive"
mbar PSCOMM=/bin/zsh PSPARENT=/Applications/SwiftBar.app/Contents/MacOS/SwiftBar SWIFTBAR_LAUNCH_TIME=2026-11-17T10:00:00Z SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
read -r t pid name launch < "$R/bar.alive"
[[ "$pid" == 1 && "$launch" == 2026-11-17T10:00:00Z ]] || fail "bar.alive through a shell: $(cat "$R/bar.alive")"
rm -f "$R/bar.alive"; mbar PSCOMM=/bin/zsh PSPARENT=launchd SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
[[ ! -e "$R/bar.alive" ]] || fail "bar.alive with no SwiftBar above the plugin"
rm -f "$R/bar.next"; idle_tsv; printf 'act\t700\ttool\t5\t1.0\t1.0\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\t300\t-\t/w\tgo test ./...\t-\t-\t1\n' >> "$M/tsv"
env PATH="$tmp/bin:$PATH" AGENTS_BIN="$M/agents" bash "$PLUGIN" > /dev/null
[[ ! -e "$R/bar.alive" && ! -e "$R/bar.next" ]] || fail "a run by hand (no SWIFTBAR) wrote bar files: $(ls -A "$R")"
# A window whose keeper is gone: the next full run lets it go.
printf '%s\n' "$(( $(date +%s) - 30 ))" > "$R/bar.busy"; : > "$R/bar.dirty"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
[[ ! -e "$R/bar.busy" && ! -e "$R/bar.dirty" ]] || fail "a dead keeper's bar.busy outlived a full run"
pass "bar.alive: SwiftBar's pid (the parent, or above a shell wrapper), only under SwiftBar; a dead keeper's window is let go"

# Herdr's labels from the menu: while an agent runs in a Herdr pane, at most
# every 30 s (the stamp read in the plugin), never on the idle fast path.
idle_tsv
printf 'agent\t300\tcodex\t60\t1.0\t0.1\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\tme\tworking\t/w\tcodex\tw\n' >> "$M/tsv"
rm -f "$M/calls" "$R/herdr-labels.stamp"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme
for _ in $(seq 20); do grep -q '^herdr' "$M/calls" 2>/dev/null && break; sleep 0.1; done
grep -qx 'herdr sync --throttle -q' "$M/calls" || fail "no Herdr sync with an agent in Herdr: $(cat "$M/calls")"
date +%s > "$R/herdr-labels.stamp"; rm -f "$M/calls"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; sleep 0.3
! grep -q '^herdr' "$M/calls" || fail "a Herdr sync within 30 s of the last"
idle_tsv; rm -f "$R/herdr-labels.stamp" "$M/calls"
mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; sleep 0.3
! grep -q '^herdr' "$M/calls" || fail "a Herdr sync with no agent in Herdr"
pass "the menu starts agents herdr sync --throttle only with an agent in Herdr and its stamp 30 s old"

# Who is unreported: Codex working outside Herdr, 10 s; the same in a Herdr
# pane (Herdr's events) or Claude Code (its hooks), and Codex not working,
# the backstop.
date +%s > "$R/herdr-labels.stamp"
while IFS='|' read -r kind hcol state want; do
    [[ -n "$kind" ]] || continue
    idle_tsv; rm -f "$R/bar.next"
    printf 'triage\t300\t%s\t60\tx\nagent\t300\t%s\t60\t1.0\t0.1\t1000\t0\tWed_Oct_14_08:00:00_2026\t-\tme\t%s\t/w\t%s\tw\n' "$state" "$kind" "$hcol" "$kind" >> "$M/tsv"
    mbar SWIFTBAR_PLUGIN_REFRESH_REASON=URLScheme; now="$(date +%s)"
    got=none; [[ ! -r "$R/bar.next" ]] || { read -r due _ < "$R/bar.next"; got=$(( (due - now + 1) / 10 * 10 )); }
    [[ "$got" == "$want" ]] || fail "$kind ($state, Herdr: $hcol): early refresh $got, want $want"
done <<'EOF'
codex|-|run|10
agy|-|run|10
codex|working|run|none
claude|-|run|none
codex|-|unknown|none
codex|-|parked|none
EOF
printf '%s %s\n' 0 stale > "$R/bar.next"
pass "a working session nothing reports on (Codex or agy outside Herdr) brings the next refresh to 10 s; in Herdr, Claude Code, or not working: the backstop"

# --- 5. Once a minute on a 60 s timer ---------------------------------------------------------
(
    export AGENTS_TESTING=1 AGENTS_HISTORY=1
    now=1760400000
    for age in 54 55 59 60 61; do
        printf '%s\n' "$((now - age))" > "$AGENTS_DATA_DIR/sample.stamp"
        if _agents_sample_due "$now"; then got=due; else got=no; fi
        want=due; [[ $age -ge 55 ]] || want=no
        [[ "$got" == "$want" ]] || fail "a sample $age s after the last: $got"
    done
    # auto-reap's throttle: the same 55 s.
    FAKE_NOW="$now"; date() { echo "$FAKE_NOW"; }
    printf '%s\n' "$((now - 56))" > "$AGENTS_RUN_DIR/auto-reap"
    _agents_auto_due || fail "auto-reap not due 56 s after the last"
    _agents_auto_due && fail "auto-reap due twice"
    true
) || exit 1
pass "agents sample and auto-reap are due 55 s after the last: a 60 s timer whose clock reads land a second early runs them every minute, not every other"

echo "All agents bar tests passed."
