#!/bin/bash
# Tests for who-needs-you and how it looks: the session states and what they
# rest on (triage.sh, awk/triage.awk, awk/waits_state.awk), the view at each
# width, the palette and its color depths (palette.sh), the gauges and limits'
# pace, the memory bars, the waits report's split and lanes, and the menu's rows,
# order, title and tints. Everything is fixtures: nothing real is read.
# Run: bash scripts/lib/test_agents_triage.sh  -> exit 0 on pass.

# Stubs are called by the sourced functions; settings change per case.
# shellcheck disable=SC1010,SC2016,SC2030,SC2031,SC2034,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR COLORTERM COLUMNS OS_APPEARANCE NO_COLOR TUIDEV_NO_COLOR; do unset "$v"; done
export HOME="$tmp/home" TERM=xterm AGENTS_TESTING=1 TZ=UTC
export AGENTS_CONF="$tmp/none.conf" AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data" AGENTS_UID=501 AGENTS_SELF=99999
mkdir -p "$HOME" "$AGENTS_DATA_DIR" "$AGENTS_RUN_DIR"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

NOW=1793800000
export AGENTS_NOW="$NOW"
date() {
    case "$*" in
        '+%s %Y-%m-%d') echo "$NOW 2026-11-04" ;;
        '+%s %z')       echo "$NOW +0000" ;;
        +%s)            echo "$NOW" ;;
        +%Y-%m-%d)      echo 2026-11-04 ;;
        *)              command date "$@" ;;
    esac
}
_agents_utf8() { return 0; }     # block glyphs, whatever locale runs this

# rec PID STATUS CPU RSS AGE PROJECT — one agent record, as agents_enrich writes it.
rec() { printf 'agent\t%s\tclaude\t%s\t%s\t0\t%s\t2\tS%s\t-\tme\t%s\t/w/%s\tclaude\t%s\n' "$1" "$5" "$3" "$4" "$1" "$2" "$6" "$6"; }
# st PID — the triage row's STATE AGE LABEL for a session.
st() { printf '%s\n' "$ROWS" | awk -F '\t' -v p="$1" '$2 == p { print $3 " " $4 " " $5 }'; }

# --- 1. The states -------------------------------------------------------------------
{
    printf '101@S101\tblocked\t%s\t%s\n' $((NOW - 360)) $((NOW - 30))
    printf '102@S102\tdone\t%s\t%s\n' $((NOW - 600)) $((NOW - 30))
    printf '103@S103\tdone\t%s\t%s\n' $((NOW - 7200)) $((NOW - 30))
    printf '105@S105\tidle\t%s\t%s\n' $((NOW - 90000)) $((NOW - 30))
    printf '106@S106\tworking\t%s\t%s\n' $((NOW - 90000)) $((NOW - 30))
} > "$AGENTS_DATA_DIR/waits.now"
mkdir -p "$AGENTS_DATA_DIR/waiting"
printf '%s\tdone\tapp\t111@S111\n' $((NOW - 300)) > "$AGENTS_DATA_DIR/waiting/s1"
printf '%s\tdone\tapp\t112@S112\n' $((NOW - 5400)) > "$AGENTS_DATA_DIR/waiting/s2"
printf '%s\tblocked\tapp\t113@S113\n' $((NOW - 120)) > "$AGENTS_DATA_DIR/waiting/s3"
printf '%s\t101@S101\tapi\tPermission\therdr\t-\n%s\t104@S104\tweb\tIdle\therdr\t-\n' $((NOW - 350)) $((NOW - 100)) > "$AGENTS_DATA_DIR/notify.tsv"
RECS="$(
    rec 101 blocked 2 100 5000 api      # Herdr blocked, its notification says why
    rec 102 done 0.5 100 5000 web       # done 10 m
    rec 103 done 0.5 100 9000 docs      # done past the hour
    rec 104 done 0.5 100 5000 fresh     # done, waits.now doesn't know it yet
    rec 105 idle 0.1 100 99000 old      # looked at and left: parked, however recent
    rec 106 idle 0.1 100 5000 flip      # idle since the last sample
    rec 107 working 800 100 5000 busy
    rec 108 working 1 100 5000 think
    rec 111 - 0.5 100 5000 hook1        # outside Herdr: the hook's wait, young
    rec 112 - 0.5 100 9000 hook2        # ...and past the hour
    rec 113 - 0.5 100 9000 hook3        # ...and blocked
    rec 114 - 0.1 100 9000 quiet        # nothing says, and nothing moves
    rec 115 - 50 100 9000 cpu           # nothing says, but it uses the CPU
    rec 116 - 0.1 100 9000 tool         # nothing says, but it runs a command
    printf 'agent\t117\tdaemon\t100\t0\t0\t100\t0\tS117\t-\tme\t-\t-\tcodex\t-\n'
    printf 'act\t700\ttool\t192\t90\t0\t100\t1\tSx\t-\t107\t-\t/w\tpnpm test\tmain\t-\t1\n'
    printf 'job\t107\ttest\t0\t90\t0\t100\t1\tSx\town\t700\tclaude\t/w\t-\tbusy\t-\n'
    printf 'act\t800\ttool\t30\t0\t0\t100\t1\tSx\t-\t116\t-\t/w\tmake thing\tmain\t-\t1\n'
)"
ROWS="$(_agents_triage_rows "$RECS")"
[[ "$(st 101)" == "need 360 permission" ]] || fail "blocked, with the notification's kind: $(st 101)"
[[ "$(st 102)" == "review 600 done" ]] || fail "done under the hour: $(st 102)"
[[ "$(st 103)" == "parked 7200 done" ]] || fail "done past the hour: $(st 103)"
[[ "$(st 104)" == "review - done" ]] || fail "done with no record: no age, still to review: $(st 104)"
[[ "$(st 105)" == "parked 90000 idle" ]] || fail "idle keeps how long it has sat: $(st 105)"
[[ "$(st 106)" == "parked 30 idle" ]] || fail "idle since the last sample: $(st 106)"
[[ "$(st 107)" == "run 5000 tests 3m12s" ]] || fail "working, its busiest command's job: $(st 107)"
[[ "$(st 108)" == "run 5000 working" ]] || fail "working with no command: $(st 108)"
[[ "$(st 111)" == "review 300 done" ]] || fail "outside Herdr, the hook's done: $(st 111)"
[[ "$(st 112)" == "parked 5400 done" ]] || fail "outside Herdr, past the hour: $(st 112)"
[[ "$(st 113)" == "need 120 blocked" ]] || fail "outside Herdr, the hook's blocked: $(st 113)"
[[ "$(st 114)" == "unknown - no signal" ]] || fail "no wait data, no activity: no signal, not parked: $(st 114)"
[[ "$(st 115)" == "run 9000 working" ]] || fail "no wait data, uses the CPU: running: $(st 115)"
[[ "$(st 116)" == "run 9000 working" ]] || fail "no wait data, runs a command: running: $(st 116)"
[[ -z "$(st 117)" ]] || fail "the Codex daemon has a state: $(st 117)"
pass "states: Herdr first, then the hooks, then what the process does; an age only when one is known"

ROWS="$(AGENTS_PARKED_MIN=6 _agents_triage_rows "$RECS")"
[[ "$(st 102)" == "parked 600 done" && "$(st 111)" == "review 300 done" ]] || fail "AGENTS_PARKED_MIN=6: $(st 102) / $(st 111)"
ROWS="$(AGENTS_PARKED_MIN=180 _agents_triage_rows "$RECS")"
[[ "$(st 103)" == "review 7200 done" ]] || fail "AGENTS_PARKED_MIN=180: $(st 103)"
_agents_conf_valid AGENTS_PARKED_MIN 60 || fail "60 refused"
! _agents_conf_valid AGENTS_PARKED_MIN 0 || fail "0 accepted"
! _agents_conf_valid AGENTS_PARKED_MIN abc || fail "abc accepted"
pass "AGENTS_PARKED_MIN moves the threshold"

# An age only from the latest stretch. rows RECORD HSTATE — the row of session 201,
# Herdr saying done, over one waits.now record.
D2="$tmp/stale"; mkdir -p "$D2"
age_of() {   # STATUS RECORD [HERDR_SEQ]
    printf '%s\n' "$2" > "$D2/waits.now"
    { rec 201 "$1" 0.5 100 90000 web; [[ -z "${3:-}" ]] || printf 'hstate\t201\t%s\n' "$3"; } > "$D2/recs"
    ROWS="$(AGENTS_DATA_DIR="$D2" _agents_triage_rows "$(cat "$D2/recs")")"
    st 201
}
T=$'\t'
# The last sample, 20 h ago, said done: the session worked and finished seconds ago.
[[ "$(age_of "done" "201@S201${T}done${T}$((NOW - 75600))${T}$((NOW - 72000))")" == "review - done" ]] || fail "a stale record aged a fresh done: $(st 201)"
[[ "$(age_of "done" "201@S201${T}done${T}$((NOW - 75600))${T}$((NOW - 72000))${T}10" 50)" == "review - done" ]] || fail "a stale record of another state change: $(st 201)"
# With the menu running: done two hours, you look, it finishes again within a minute.
[[ "$(age_of "done" "201@S201${T}done${T}$((NOW - 7200))${T}$((NOW - 30))${T}10" 14)" == "review 30 done" ]] || fail "a new stretch took the old one's age: $(st 201)"
# Herdr's number holds: the same stretch, however old the record.
[[ "$(age_of "done" "201@S201${T}done${T}$((NOW - 75600))${T}$((NOW - 72000))${T}10" 10)" == "parked 75600 done" ]] || fail "the same stretch across a gap: $(st 201)"
[[ "$(age_of blocked "201@S201${T}blocked${T}$((NOW - 7200))${T}$((NOW - 72000))${T}10" 12)" == "need - blocked" ]] || fail "a stale blocked: $(st 201)"
[[ "$(age_of idle "201@S201${T}done${T}$((NOW - 75600))${T}$((NOW - 72000))")" == "parked - idle" ]] || fail "a stale record aged an idle: $(st 201)"
# A lower bound ("~") shows only once that alone is past the threshold.
[[ "$(age_of "done" "201@S201${T}done${T}$((NOW - 300))${T}$((NOW - 30))${T}~")" == "review - done" ]] || fail "a lower bound shown as an age: $(st 201)"
[[ "$(age_of "done" "201@S201${T}done${T}$((NOW - 7200))${T}$((NOW - 30))${T}~")" == "parked 7200 done" ]] || fail "a lower bound past the threshold: $(st 201)"
pass "an age only from the latest stretch: Herdr's number decides, and a stale record ages nothing"

# --- 2. waits.now and waits.today, from the sample ----------------------------------------
D="$tmp/waitstate"; mkdir -p "$D"
day=2026-11-04
state() { AGENTS_DATA_DIR="$D" _agents_waits_state "$1" "$day" "$2" "$3"; }
row() { printf '%s\tapp\tclaude\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
now_field() { awk -F '\t' -v t="$1" '$1 == t { print $2 " " $3 }' "$D/waits.now"; }
# live PID START STATUS [HERDR_SEQ]
live() {
    printf 'agent\t%s\tclaude\t100\t0\t0\t1\t0\t%s\t-\tme\t%s\t/w\tclaude\tapp\n' "$1" "$2" "$3"
    [[ -z "${4:-}" ]] || printf 'hstate\t%s\t%s\n' "$1" "$4"
}
# The first sample reads all of waits.tsv: a stretch already past the hour is
# known as that, a row over a sample's cap apart starts a new one.
{
    row $((NOW - 9000)) done 7@A 60
    row $((NOW - 8940)) done 7@A 60
    i=$((NOW - 7000)); while [[ $i -lt $NOW ]]; do row "$i" done 7@A 60; i=$((i + 60)); done
    row $((NOW - 60)) blocked 8@B 60
} > "$D/waits.tsv"
state "$NOW" "" "$(live 7 A "done"; live 8 B blocked; live 9 C working)"
[[ "$(now_field 7@A)" == "done $((NOW - 7060))" ]] || fail "first run, the stretch: $(now_field 7@A)"
[[ "$(now_field 8@B)" == "blocked $((NOW - 120))" ]] || fail "first run, blocked: $(now_field 8@B)"
[[ -z "$(now_field 9@C)" ]] || fail "a working session in waits.now"
# Live, with Herdr's number: the number that holds keeps the start across a night
# asleep; one that changes is a new stretch, however fast it worked.
AT=$((NOW + 60))
state "$AT" "$(row "$AT" "done" 7@A 60)" "$(live 7 A "done" 10; live 8 B working 11)"
[[ "$(now_field 7@A)" == "done $((NOW - 7060))" ]] || fail "live: the stretch: $(now_field 7@A)"
[[ -z "$(now_field 8@B)" ]] || fail "blocked, then working, still in waits.now"
[[ "$(awk -F '\t' '$1 == "7@A" { print $5 }' "$D/waits.now")" == 10 ]] || fail "the number not kept: $(cat "$D/waits.now")"
AT=$((AT + 28800))
state "$AT" "$(row "$AT" "done" 7@A 300)" "$(live 7 A "done" 10)"
[[ "$(now_field 7@A)" == "done $((NOW - 7060))" ]] || fail "a night asleep restarted the stretch: $(now_field 7@A)"
AT=$((AT + 60))
state "$AT" "$(row "$AT" "done" 7@A 60)" "$(live 7 A "done" 14)"
[[ "$(now_field 7@A)" == "done $((AT - 60))" ]] || fail "done, looked at, done again within a sample: $(now_field 7@A)"
# You look at it: idle, and it has sat since it finished; working clears it.
SINCE=$((AT - 60))
AT=$((AT + 60)); state "$AT" "" "$(live 7 A idle 15)"
[[ "$(now_field 7@A)" == "idle $SINCE" ]] || fail "done to idle: $(now_field 7@A)"
AT=$((AT + 60)); state "$AT" "" "$(live 7 A working 16)"
[[ -z "$(now_field 7@A)" ]] || fail "working left it in waits.now"
AT=$((AT + 60)); state "$AT" "$(row "$AT" "done" 7@A 60)" "$(live 7 A "done" 17)"
[[ "$(now_field 7@A)" == "done $((AT - 60))" ]] || fail "done again: $(now_field 7@A)"
# No number: a gap past what a record can vouch for keeps only a lower bound.
AT=$((AT + 60)); state "$AT" "$(row "$AT" "done" 9@C 60)" "$(live 9 C "done")"
AT=$((AT + 72000)); state "$AT" "$(row "$AT" "done" 9@C 300)" "$(live 9 C "done")"
[[ "$(awk -F '\t' '$1 == "9@C" { print $3 " " $5 }' "$D/waits.now")" == "$AT ~" ]] || fail "a gap with no number: $(cat "$D/waits.now")"
AT=$((AT + 60)); state "$AT" "$(row "$AT" "done" 9@C 60)" "$(live 9 C "done"; live 7 A "done" 17)"
# A session gone leaves the file; a sample that sees no agent leaves it as it is.
AT=$((AT + 60)); state "$AT" "" "$(live 7 A "done")"
before="$(cat "$D/waits.now")"
AT=$((AT + 60)); state "$AT" "" ""
[[ "$(cat "$D/waits.now")" == "$before" ]] || fail "a sample that sees no agent wiped waits.now"
pass "waits.now: the first run reads the history; a status keeps its start until it changes"

# waits.today: by class, starting over with a new day.
D="$tmp/waitstate2"; mkdir -p "$D"
: > "$D/waits.now"; printf '1\tx\n' > "$D/waits.tsv"
mid=$(( NOW - NOW % 86400 ))
state "$mid" "$(row "$mid" blocked 7@A 120)" "$(live 7 A blocked)"
[[ "$(cat "$D/waits.today")" == "$day"$'\t120\t0\t0' ]] || fail "blocked: $(cat "$D/waits.today")"
state $((mid + 60)) "$(row $((mid + 60)) done 8@B 60)" "$(live 8 B "done" 5)"
[[ "$(cat "$D/waits.today")" == "$day"$'\t120\t60\t0' ]] || fail "fresh: $(cat "$D/waits.today")"
state $((mid + 3660)) "$(row $((mid + 3660)) done 8@B 300)" "$(live 8 B "done" 5)"
[[ "$(cat "$D/waits.today")" == "$day"$'\t120\t60\t300' ]] || fail "parked past the hour: $(cat "$D/waits.today")"
day=2026-11-05
state $((mid + 86400 + 10)) "$(row $((mid + 86400 + 10)) blocked 7@A 10)" "$(live 7 A blocked)"
[[ "$(cat "$D/waits.today")" == "$day"$'\t10\t0\t0' ]] || fail "a new day: $(cat "$D/waits.today")"
pass "waits.today counts blocked, fresh and parked; a new day starts over"

# The first run counts the history once, even with nobody running to leave a
# record: a sample a minute would otherwise add it all again.
D="$tmp/waitstate3"; mkdir -p "$D"
printf '%s\tapp\tclaude\tblocked\t7@A\t600\n' $((mid + 100)) > "$D/waits.tsv"
day=2026-11-04
for i in 1 2 3; do state $((mid + 1000 + i * 60)) "" ""; done
[[ "$(cat "$D/waits.today")" == "$day"$'\t600\t0\t0' ]] || fail "waits multiply with no one running: $(cat "$D/waits.today")"
[[ -f "$D/waits.now" ]] || fail "the first run left no waits.now"
# Yesterday's or an earlier run's file doesn't add to it either.
D="$tmp/waitstate4"; mkdir -p "$D"
printf '%s\tapp\tclaude\tblocked\t7@A\t600\n' $((mid + 100)) > "$D/waits.tsv"
printf '%s\t600\t0\t0\n' "$day" > "$D/waits.today"
state $((mid + 1000)) "" ""
[[ "$(cat "$D/waits.today")" == "$day"$'\t600\t0\t0' ]] || fail "the first run added to an old waits.today: $(cat "$D/waits.today")"
pass "the first run counts the history once"

# --- 3. The view ------------------------------------------------------------------------
agents_thermal_level() { echo 0; }
agents_thermal_name() { echo nominal; }
agents_system() { printf '3.84\t12\t59\tnormal\t86\tcharging\n'; }
_agents_cpu_pct() { echo 27; }
agents_awake_line() { echo "awake: while agents run (pid 1)"; }
_agents_lid_warning() { :; }
_agents_swap() { echo "${FAKE_SWAP:-1000 13000000}"; }
agents_assess() { :; }
VIEW="$(
    rec 66498 blocked 2 1363148 12180 api
    rec 23638 done 0.6 513024 720 web
    rec 90129 done 0.6 464896 2460 docs
    rec 55625 working 842 7969177 8460 billing-with-a-long-project-name
    rec 82771 working 20.4 301056 2820 infra
    rec 7001 idle 0.1 100 140400 old1
    rec 7002 idle 0.1 100 3600 old2
    printf 'herdr\t23638\tw1:p1\tFix the login flow\n'
    printf 'act\t700\ttool\t192\t90\t0\t100\t1\tSx\t-\t55625\t-\t/w\tpnpm test\tmain\t-\t1\n'
    printf 'job\t55625\ttest\t0\t90\t0\t100\t1\tSx\town\t700\tclaude\t/w\t-\tb\t-\n'
)"
D="$tmp/view"; mkdir -p "$D"
{
    printf '66498@S66498\tblocked\t%s\t%s\n23638@S23638\tdone\t%s\t%s\n90129@S90129\tdone\t%s\t%s\n7001@S7001\tidle\t%s\t%s\n' \
        $((NOW - 360)) "$NOW" $((NOW - 720)) "$NOW" $((NOW - 2460)) "$NOW" $((NOW - 140400)) "$NOW"
} > "$D/waits.now"
printf '%s\t66498@S66498\tapi\tPermission\therdr\t-\n' $((NOW - 350)) > "$D/notify.tsv"
# The verdict row of a stuck loop under infra, as agents_assess writes it.
NEED_ROW=$'need\t5010\tS\tstuck\tstop\thigh\tfinished\t0\t82771\tsafe to stop\tsafe to stop \342\200\224 what it waits for already finished (ok, 5h0m ago)\tclaude\tinfra\t18600\t0\t-\t-\t-\t-\t1'
render() { AGENTS_DATA_DIR="$D" AGENTS_WIDTH="$1" _agents_triage_render "$VIEW"$'\n'"$NEED_ROW"; }
# widest S — the widest line of S as a terminal counts it, colors left out.
widest() { printf '%s\n' "$1" | _agents_awk lib_fmt -f /dev/fd/3 3<<'EOF'
{ gsub(/\033\[[0-9;]*m/, ""); if (dw($0) > m) m = dw($0) }
END { print m + 0 }
EOF
}
_agents_colors
out="$(render 80)"
[[ "$out" == *" ▲ 1 needs you   ◆ 2 to review   ● 2 running   ○ 2 parked"* ]] || fail "summary line: $out"
[[ "$(printf '%s\n' "$out" | head -1)" == " ▲ 1 needs you"* ]] || fail "the summary comes first: $out"
pos() { printf '%s\n' "$out" | grep -n -m1 -e "$1" | cut -d: -f1; }
[[ $(pos 'NEEDS YOU') -lt $(pos 'TO REVIEW') && $(pos 'TO REVIEW') -lt $(pos 'RUNNING') && $(pos 'RUNNING') -lt $(pos '○ 2 parked,') && $(pos '○ 2 parked,') -lt $(pos '^cpu ') ]] \
    || fail "group order: $out"
[[ "$out" == *" ▲ api"*"permission"*"6m"*"agents show 66498"* ]] || fail "needs row: $out"
[[ "$out" == *" ◆ web"*"done"*"12m"*"Fix the login flow"* ]] || fail "review row with Herdr's title: $out"
[[ "$out" == *" ● billing-with-a-lo…"*"tests 3m12s"*"2h21m"*"8.4 cores  7.6G"* ]] || fail "running row: $out"
[[ "$out" == *" ● infra"*"working"*"47m"*"0.2 cores  294M"*$'\n'"   ! wait-loop stuck 5h10m · what it waits for already finished · safe to stop"* ]] || fail "a stuck loop under its session: $out"
[[ "$out" == *"○ 2 parked, oldest 39 h · no stale · no hogs"* ]] || fail "parked line: $out"
[[ "$out" == *$'\n'"cpu 27% · mem 59% free · thermal nominal · awake while agents run"* ]] || fail "system line: $out"
[[ "$out" != *old1* && "$out" != *66498$'\t'* ]] || fail "a parked session has a row"
[[ $(widest "$out") -le 80 ]] || fail "wider than 80 ($(widest "$out")): $out"
[[ "$out" != *$'\033'* ]] || fail "colors off a terminal"
# Columns line up by what the eye sees: glyphs are three bytes each.
cols="$(printf '%s\n' "$out" | grep -E '^ [▲◆●] ' | _agents_awk lib_fmt -f /dev/fd/3 3<<'EOF'
# Where the age column ends: the age is the token before the gap, or the end of the row.
# (No apostrophe in here: bash 3.2 misreads one inside a heredoc inside $(...).)
match($0, /[0-9]+[hm][0-9m]*( |$)/) { t = substr($0, RSTART, RLENGTH); sub(/ $/, "", t); print dw(substr($0, 1, RSTART - 1)) + length(t) }
EOF
)"
[[ "$(printf '%s\n' "$cols" | sort -u | wc -l | tr -d ' ')" == 1 ]] || fail "rows don't line up"
pass "agents at 80 columns: summary, Needs you, To review, Running, one parked line, one system line, in bounds"

narrow="$(render 52)"
[[ "$narrow" == *" ▲ 1  ◆ 2  ● 2  ○ 2"* ]] || fail "narrow summary: $narrow"
[[ "$narrow" != *"NEEDS YOU"* && "$narrow" != *"cpu 27%"* ]] || fail "narrow keeps headers or the system line: $narrow"
[[ "$narrow" == *"8.4c 7.6G"* && "$narrow" == *"! wait-loop stuck 5h10m · safe to stop"* && "$narrow" == *"○ 2 parked · oldest 39 h"* ]] || fail "narrow rows: $narrow"
[[ $(widest "$narrow") -le 52 ]] || fail "wider than 52 ($(widest "$narrow")): $narrow"
tight="$(render 40)"
[[ $(widest "$tight") -le 44 ]] || fail "a 40-column pane: $(widest "$tight"): $tight"
pass "agents narrows at about 52 columns: no headers, no system line, still in bounds"

# Empty groups disappear; high swap speaks up, right-aligned.
VIEW="$(rec 82771 working 20 301056 2820 infra)"
out="$(render 80)"
[[ "$out" != *"NEEDS YOU"* && "$out" != *"TO REVIEW"* && "$out" != *"needs you"* && "$out" != *parked* ]] || fail "empty groups shown: $out"
[[ "$out" == *"no stale · no hogs"* ]] || fail "stale and hogs quiet: $out"
FAKE_SWAP="11800000 13000000"
out="$(render 80)"
[[ "$(printf '%s\n' "$out" | head -1)" == *"! swap 90%" ]] || fail "high swap in the summary: $out"
[[ $(printf '%s\n' "$out" | head -1 | _agents_awk lib_fmt -f /dev/fd/3 3<<'EOF'
{ print dw($0) }
EOF
) -eq 80 ]] || fail "swap isn't right-aligned: $out"
unset FAKE_SWAP
_agents_swap_high && fail "1 GB of 13 counted as high"
VIEW=""
out="$(render 80)"
[[ -z "$out" ]] || [[ "$out" == *"no agent sessions"* ]] || fail "no sessions: $out"
pass "empty groups disappear; swap only when high"

# Stale and hogs: a word each; a flag under a parked session still shows.
VIEW="$(
    rec 7001 idle 0.1 100 140400 old1
    printf 'stale\t1\tmcp\t0\t0\t0\t0\t0\tS\t-\tme\t-\t-\targs\tx\n'
    printf 'hog\t2\tyes\t0\t0\t0\t0\t0\tS\t-\tme\t-\t-\targs\n'
)"
NEED_ROW="${NEED_ROW//82771/7001}"
out="$(render 80)"
[[ "$out" == *"! 1 stale: agents stale · ! 1 hog: agents hogs"* ]] || fail "stale and hogs counted: $out"
[[ "$out" == *" ! old1: wait-loop stuck 5h10m"* ]] || fail "a flag under a parked session: $out"
pass "stale and hogs get a word; a flagged command under a parked session still shows"

# No signal: a row of its own, at each width, and never in the parked count.
VIEW="$(
    rec 7001 - 0.1 301056 9000 codexapp
    rec 7002 idle 0.1 100 3600 old
    rec 7003 working 90 100 3600 busy
)"; NEED_ROW=""
out="$(render 80)"
[[ "$(printf '%s\n' "$out" | head -1)" == " ● 1 running   ? 1 no signal   ○ 1 parked" ]] || fail "summary with no signal: $out"
[[ "$out" == *$'\n'"NO SIGNAL"$'\n'" ? codexapp"*"no signal"*"0.0 cores  294M"* ]] || fail "a no-signal row: $out"
[[ "$out" == *"○ 1 parked"* && $(pos 'RUNNING') -lt $(pos 'NO SIGNAL') ]] || fail "no signal counted as parked, or before Running: $out"
narrow="$(render 52)"
[[ "$(printf '%s\n' "$narrow" | head -1)" == " ● 1  ? 1  ○ 1" && "$narrow" == *$'\n'" ? codexapp "*"no signal"*"0.0c 294M"* ]] || fail "narrow no signal: $narrow"
[[ $(widest "$narrow") -le 52 ]] || fail "narrow no signal, too wide: $narrow"
pass "no signal: a row of its own at 80 and 52 columns, not counted as parked"

# Under a locale with no such glyphs, shapes of their own and nothing else.
_agents_utf8() { return 1; }
VIEW="$(
    rec 66498 blocked 2 1363148 12180 api
    rec 23638 done 0.6 513024 720 a-very-long-project-name-indeed
    rec 55625 working 842 7969177 8460 billing
    rec 7001 - 0.1 100 9000 quiet
    rec 7002 idle 0.1 100 140400 old
)"
NEED_ROW=$'need\t5010\tS\tstuck\tstop\thigh\tfinished\t0\t55625\tsafe to stop\tsafe to stop \342\200\224 what it waits for already finished (ok, 5h0m ago)\tclaude\tinfra\t18600\t0\t-\t-\t-\t-\t1'
for width in 80 52; do
    out="$(render "$width")"
    bad="$(printf '%s\n' "$out" | LC_ALL=C grep -n '[^ -~]' || true)"
    [[ -z "$bad" ]] || fail "non-ASCII at $width columns under a non-UTF-8 locale: $bad"
done
out="$(render 80)"
[[ "$out" == " ^ 1 needs you   * 1 to review   o 1 running   ? 1 no signal   . 1 parked"* ]] || fail "ASCII summary: $out"
[[ "$out" == *" ^ api "* && "$out" == *" * a-very-long-proje~"* && "$out" == *" o billing "* && "$out" == *" ? quiet "* && "$out" == *". 1 parked - no stale - no hogs"* ]] || fail "ASCII rows: $out"
_agents_utf8() { return 0; }
# The locale is read as a C library would: LC_ALL, LC_CTYPE, then LANG.
real_utf8() { ( unset -f _agents_utf8; . "$REPO_DIR/lib/agents/palette.sh"; _agents_utf8 ); }
( unset LC_ALL LC_CTYPE; export LANG=en_GB.UTF-8; real_utf8 ) || fail "a Pi's LANG"
( unset LC_ALL LC_CTYPE; export LANG=en_GB.utf8; real_utf8 ) || fail "a glibc spelling"
( unset LC_ALL; export LC_CTYPE=UTF-8 LANG=C; real_utf8 ) || fail "a Mac's LC_CTYPE"
( export LC_ALL=C LANG=en_GB.UTF-8; real_utf8 ) && fail "LC_ALL=C over a UTF-8 LANG"
( unset LC_ALL LC_CTYPE; export LANG=POSIX; real_utf8 ) && fail "POSIX"
pass "a locale with no glyphs gets ASCII shapes, read from LC_ALL, LC_CTYPE, then LANG"

# --- 4. The palette ----------------------------------------------------------------------
mkdir -p "$HOME/.config/tuidev"
colors() { ( for kv in "$@"; do export "${kv?}"; done; _agents_colors --always; printf '%q ' "$C_NEED" "$C_DONE" "$C_RUN" "$C_WARN" "$C_DIM" "$C_ACC" "$C_TINT" ); }
esc=$'\033'
sgr() { printf '%q' "${esc}[$1m"; }
# Nothing applied, nothing set: the terminal's own 16 colors, at any depth.
want16="$(sgr 31) $(sgr 34) $(sgr 32) $(sgr 33) $(sgr 2) $(sgr 34) '' "
[[ "$(colors TERM=xterm)" == "$want16" ]] || fail "16 colors: $(colors TERM=xterm)"
[[ "$(colors COLORTERM=truecolor)" == "$want16" ]] || fail "truecolor, no palette: $(colors COLORTERM=truecolor)"
# Blocked is red, not the yellow it was.
[[ "$(colors TERM=xterm)" == "$(sgr 31)"* ]] || fail "need is not red"
# Applied by theme.sh: read from its state file.
echo tokyo-night > "$HOME/.config/tuidev/theme"
truec="$(colors COLORTERM=truecolor)"
[[ "$truec" == "$(sgr '38;2;247;118;142') $(sgr '38;2;122;162;247') $(sgr '38;2;158;206;106') $(sgr '38;2;224;175;104') $(sgr 2) $(sgr '38;2;122;162;247') $(sgr '48;2;56;39;52') " ]] \
    || fail "truecolor tokens: $truec"
c256="$(colors TERM=xterm-256color)"
[[ "$c256" == "$(sgr '38;5;210') $(sgr '38;5;111') $(sgr '38;5;149') $(sgr '38;5;179') $(sgr 2) $(sgr '38;5;111') '' " ]] || fail "256 tokens: $c256"
[[ "$(colors TERM=xterm)" == "$want16" ]] || fail "16 colors with a palette"
[[ "$(colors COLORTERM=truecolor NO_COLOR=1)" == "'' '' '' '' '' '' '' " ]] || fail "NO_COLOR"
[[ "$(colors COLORTERM=truecolor TUIDEV_NO_COLOR=1)" == "'' '' '' '' '' '' '' " ]] || fail "TUIDEV_NO_COLOR"
[[ "$(colors TERM=dumb)" == "'' '' '' '' '' '' '' " ]] || fail "a dumb terminal"
[[ "$(colors TERM=dumb COLORTERM=truecolor)" == "'' '' '' '' '' '' '' " ]] || fail "TERM=dumb under COLORTERM=truecolor"
_agents_rgb_256 128 128 128; [[ "$REPLY" == 244 ]] || fail "gray ramp: $REPLY"
_agents_rgb_256 255 0 0; [[ "$REPLY" == 196 ]] || fail "cube red: $REPLY"
_agents_rgb_256 0 0 0; [[ "$REPLY" == 16 ]] || fail "black: $REPLY"
_agents_rgb_256 255 255 255; [[ "$REPLY" == 231 ]] || fail "white: $REPLY"
# AGENTS_THEME: a name, ansi, none; a name with no file falls back quietly.
[[ "$(colors COLORTERM=truecolor AGENTS_THEME=catppuccin-mocha)" == "$(sgr '38;2;243;139;168')"* ]] || fail "a palette by name"
[[ "$(colors COLORTERM=truecolor AGENTS_THEME=ansi)" == "$want16" ]] || fail "AGENTS_THEME=ansi"
[[ "$(colors COLORTERM=truecolor AGENTS_THEME=none)" == "'' '' '' '' '' '' '' " ]] || fail "AGENTS_THEME=none"
[[ "$(colors COLORTERM=truecolor AGENTS_THEME=nosuch)" == "$want16" ]] || fail "an unknown palette"
# Overrides: a palette key or #rrggbb, on any token.
[[ "$(colors COLORTERM=truecolor AGENTS_COLOR_NEED=ansi_magenta)" == "$(sgr '38;2;187;154;247')"* ]] || fail "a palette key"
[[ "$(colors COLORTERM=truecolor AGENTS_COLOR_NEED=#010203)" == "$(sgr '38;2;1;2;3')"* ]] || fail "#rrggbb"
[[ "$(colors COLORTERM=truecolor AGENTS_COLOR_NEED=#010203)" == *"$(sgr '48;2;22;23;33') " ]] || fail "the tint follows need: $(colors COLORTERM=truecolor AGENTS_COLOR_NEED=#010203)"
[[ "$(colors TERM=xterm AGENTS_COLOR_NEED=ansi_bright_red)" == "$(sgr 91)"* ]] || fail "an ANSI slot at 16 colors"
[[ "$(colors COLORTERM=truecolor AGENTS_COLOR_DIM=fg_dim)" == *"$(sgr '38;2;169;177;214')"* ]] || fail "dim as a color"
for good in "AGENTS_THEME auto" "AGENTS_THEME catppuccin-latte" "AGENTS_COLOR_NEED ansi_red" "AGENTS_COLOR_DONE #A1b2C3"; do
    # shellcheck disable=SC2086  # KEY VALUE
    _agents_conf_valid $good || fail "refused: $good"
done
for bad in "AGENTS_THEME ../etc" "AGENTS_THEME A/B" "AGENTS_COLOR_NEED #12" "AGENTS_COLOR_RUN red;rm"; do
    # shellcheck disable=SC2086  # KEY VALUE
    ! _agents_conf_valid $bad || fail "accepted: $bad"
done
pass "tokens: truecolor, 256 and 16 colors, NO_COLOR; AGENTS_THEME and AGENTS_COLOR_* with the usual validation"

# The palette row: what the menu tints with.
palrow() { ( for kv in "$@"; do export "${kv?}"; done; unset _AGENTS_PALETTE_LOADED; _agents_palette_row ); }
[[ "$(palrow)" == $'palette\ttokyo-night\t#f7768e\t#7aa2f7\t#9ece6a\t#e0af68\t#7aa2f7\t#1a1b26' ]] || fail "palette row: $(palrow)"
[[ -z "$(palrow AGENTS_THEME=ansi)" && -z "$(palrow AGENTS_THEME=none)" ]] || fail "a palette row with no palette"
[[ "$(palrow AGENTS_THEME=ansi AGENTS_COLOR_NEED=#010203)" == $'palette\t-\t#010203\t-\t-\t-\t-\t-' ]] || fail "only an override: $(palrow AGENTS_THEME=ansi AGENTS_COLOR_NEED=#010203)"
rm -f "$HOME/.config/tuidev/theme"
[[ -z "$(palrow)" ]] || fail "a palette row with no theme applied"
pass "the palette row carries the tokens' hex; none without a palette"

# Colors in the view: the row tint needs truecolor and a palette.
VIEW="$(rec 66498 blocked 2 100 100 api)"; NEED_ROW=""
echo tokyo-night > "$HOME/.config/tuidev/theme"
out="$(COLORTERM=truecolor; export COLORTERM; unset _AGENTS_PALETTE_LOADED; _agents_colors --always; render 80)"
[[ "$out" == *$'\033[48;2;56;39;52m'* && "$out" == *$'\033[38;2;247;118;142m'*"▲"* ]] || fail "tint and need on a truecolor terminal: $(printf '%q' "$out")"
row_w="$(printf '%s\n' "$out" | grep '▲ api' | sed 's/\x1b\[[0-9;]*m//g' | _agents_awk lib_fmt -f /dev/fd/3 3<<'EOF'
{ print dw($0) }
EOF
)"
[[ "$row_w" == 80 ]] || fail "the tint stops short of the edge: $row_w"
out="$(TERM=xterm; export TERM; _agents_colors --always; render 80)"
[[ "$out" != *$'\033[48;'* && "$out" == *$'\033[31m'* ]] || fail "16 colors: no tint, ANSI red: $(printf '%q' "$out")"
_agents_colors
pass "the Needs-you row is tinted only on a truecolor terminal"

# --- 5. Gauges --------------------------------------------------------------------------
g() { _agents_awk_eval lib_fmt "BEGIN { printf \"%s\", gauge($1, $2, $3, \"\", \"\", \"\") }"; }
[[ "$(g 0 4 -1)" == "░░░░" ]] || fail "0%: $(g 0 4 -1)"
[[ "$(g 100 4 -1)" == "████" ]] || fail "100%: $(g 100 4 -1)"
[[ "$(g 50 4 -1)" == "██░░" ]] || fail "50%: $(g 50 4 -1)"
[[ "$(g 72 10 -1)" == "███████▎░░" ]] || fail "72% of 10: $(g 72 10 -1)"
[[ "$(g 23 12 41)" == "██▊░░│░░░░░░░" ]] || fail "marker: $(g 23 12 41)"
[[ "$(g 150 4 -1)" == "████" && "$(g -5 4 -1)" == "░░░░" ]] || fail "out of range"
[[ "$(g 100 4 100)" == "████│" && "$(g 0 4 0)" == "│░░░░" ]] || fail "marker at the ends"
[[ "$(AGENTS_ASCII=1 g 50 4 25)" == "#|#--" ]] || fail "ascii: $(AGENTS_ASCII=1 g 50 4 25)"
[[ "$(AGENTS_ASCII=1 g 72 10 -1)" == "#######---" ]] || fail "ascii rounds to a cell: $(AGENTS_ASCII=1 g 72 10 -1)"
colored="$(N=$'\033[0m' _agents_awk_eval lib_fmt 'BEGIN { printf "%s", gauge(50, 4, -1, "F", "D", "") }')"
[[ "$colored" == $'F██D░░\033[0m' ]] || fail "colors switch only when they change: $(printf '%q' "$colored")"
w() { _agents_awk_eval lib_fmt "BEGIN { printf \"%s\", $1 }"; }
[[ "$(w 'dw("▲ api")')" == 5 ]] || fail "dw counts glyphs as one"
[[ "$(w 'lc("▲", 3) "|"')" == "▲  |" && "$(w 'rc("▲", 3) "|"')" == "  ▲|" ]] || fail "padding by width, not bytes"
[[ "$(w 'dcut("mactui_setup", 6)')" == "mactu…" && "$(w 'dcut("▲▲▲▲", 3)')" == "▲▲…" && "$(w 'dcut("abc", 3)')" == "abc" ]] || fail "dcut"
[[ "$(w 'rough(600)')" == "10 m" && "$(w 'rough(3600)')" == "1 h" && "$(w 'rough(5400)')" == "90 m" && "$(w 'rough(39*3600)')" == "39 h" && "$(w 'rough(5*86400)')" == "5 d" ]] || fail "rough"
pass "gauge: eighths, the marker, ASCII; cells pad and cut by what the terminal shows"

# Under a locale with no blocks, the view of a limit falls back to ASCII.
( unset -f _agents_utf8; . "$REPO_DIR/lib/agents/palette.sh"; LC_ALL=C _agents_utf8 ) && fail "LC_ALL=C has block glyphs"
( unset -f _agents_utf8; . "$REPO_DIR/lib/agents/palette.sh"; LC_ALL=en_US.UTF-8 _agents_utf8 ) || fail "a UTF-8 locale has none"
( unset -f _agents_utf8; . "$REPO_DIR/lib/agents/palette.sh"; unset LC_ALL LC_CTYPE; LANG=C.UTF-8 _agents_utf8 ) || fail "LANG=C.UTF-8 has none"
pass "block glyphs follow the locale"

# --- 6. Pace ----------------------------------------------------------------------------
L="$tmp/pace"; mkdir -p "$L"
# 5h window, 2h gone (40% of it), 23% used; week, a day gone (14%), 41% used, 6h
# of 5h... each from limits.tsv's used, window and resets alone.
{
    printf '%s\tclaude\t23\t300\t%s\t-\n' "$NOW" $((NOW + 3 * 3600))                     # 40% gone, 23 used: under
    printf '%s\tcodex\t60\t300\t%s\t-\n' "$NOW" $((NOW + 3 * 3600))                      # 40% gone, 60 used: over
    printf '%s\tagy:x\t3\t10080\t%s\tModel\n' "$NOW" $((NOW + 10080 * 60 - 60))          # the window's first minute: too early
    printf '%s\tgrok\t2\t300\t0\t-\n' "$NOW"                                             # no reset: nothing to go by
    printf '%s\tother\t50\t300\t%s\t-\n' "$NOW" $((NOW + 150 * 60))                      # 50% gone, 50 used: on it, under
} > "$L/limits.tsv"
tsvout() { AGENTS_DATA_DIR="$L" _agents_limits_lines; }
p() { tsvout | awk -F '\t' -v c="$1" -v w="$2" '$1 == "limit" && $6 == c && $3 == w { getline; print $2 " " $3 " " $4; exit }'; }
[[ "$(p claude 5h)" == "40 under -" ]] || fail "under pace: $(p claude 5h)"
# 60% in 2h: 30%/h, so the rest takes 80 minutes.
[[ "$(p codex 5h)" == "40 over 4800" ]] || fail "over pace, time left: $(p codex 5h)"
[[ "$(p agy:x week)" == "0 - -" ]] || fail "too early to say: $(p agy:x week)"
[[ "$(p grok 5h)" == "-1 - -" ]] || fail "no reset, no pace: $(p grok 5h)"
[[ "$(p other 5h)" == "50 under -" ]] || fail "right on pace: $(p other 5h)"
[[ "$(tsvout | awk -F '\t' '$1 == "pace"' | cut -f5 | head -1)" == "██▊░░│░░░░░░░" ]] || fail "the row's gauge: $(tsvout | head -2)"
# A reading from an hour ago: the time left counts down from it.
printf '%s\tcodex\t60\t300\t%s\t-\n' $((NOW - 3600)) $((NOW + 2 * 3600)) > "$L/limits.tsv"
[[ "$(p codex 5h)" == "60 over 1200" ]] || fail "an older reading: $(p codex 5h)"
{
    printf '%s\tclaude\t23\t300\t%s\t-\n' "$NOW" $((NOW + 3 * 3600))
    printf '%s\tcodex\t60\t300\t%s\t-\n' "$NOW" $((NOW + 3 * 3600))
} > "$L/limits.tsv"
out="$(AGENTS_DATA_DIR="$L" agents_limits)"
[[ "$out" == *"Claude 5h"*"██████████"*"23%"* ]] || [[ "$out" == *"Claude 5h"*"│"*"23%"*"resets"*"under pace"* ]] || fail "view, under: $out"
[[ "$out" == *"Codex 5h"*"│"*"60%"*"resets"*"! over pace, 80 m left at this rate"* ]] || fail "view, over: $out"
# Every row fits, the projection shortening as the width does; the longest name too.
{
    cat "$L/limits.tsv"
    printf '%s\tagy:gemini-argon-wtu\t80\t300\t%s\tClaude and GPT and Gemini 4 Argon\n' "$NOW" $((NOW + 3 * 3600))
    printf '%s\tcodex\t100\t10080\t%s\t-\n' "$NOW" $((NOW + 5 * 86400))
    printf '%s\tgrok\t3\t300\t%s\t-\n' $((NOW - 9000)) $((NOW - 100))
} > "$L/limits.wide"; mv "$L/limits.wide" "$L/limits.tsv"
for width in 160 80 72 60 52 44; do
    v="$(AGENTS_DATA_DIR="$L" AGENTS_WIDTH="$width" agents_limits)"
    [[ $(widest "$v") -le $width ]] || fail "limits at $width columns is $(widest "$v") wide:"$'\n'"$v"
    [[ "$v" == *"Codex 5h"*"60%"*"! "* ]] || fail "limits at $width lost over pace:"$'\n'"$v"
done
v="$(AGENTS_DATA_DIR="$L" AGENTS_WIDTH=160 agents_limits)"
[[ "$v" == *"! over pace, 80 m left at this rate"* ]] || fail "wide: the whole projection: $v"
v="$(AGENTS_DATA_DIR="$L" AGENTS_WIDTH=52 agents_limits)"
[[ "$v" == *"60%   ! 80 m left"* ]] || fail "narrow: the time left stays: $v"
js="$(AGENTS_DATA_DIR="$L" agents_limits --json)"
[[ "$js" == *'"elapsed_percent":40,"pace":"under","left_s":null'* && "$js" == *'"pace":"over","left_s":4800'* ]] || fail "json pace: $js"
pass "pace: from limits.tsv's used, window and resets; a projection only when over; too early or no reset says nothing"

# --- 7. Status line ---------------------------------------------------------------------
sl() { printf '{"model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":%s},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":1},"seven_day":{"used_percentage":41,"resets_at":1}}}' "$1" "$2" \
    | AGENTS_HISTORY=0 agents_statusline; }
out="$(export NO_COLOR=1; sl 72 23)"
[[ "$out" == "Opus 5.5  ctx ███████▎░░ 72%  5h 23%  wk 41%" ]] || fail "status line: $out"
# Claude Code sets COLUMNS: the line keeps to it, the model first to go.
out="$(export NO_COLOR=1 COLUMNS=45; sl 72 23)"
[[ "$out" == "Opus 5.5  ctx"* ]] || fail "full at 45 columns: $out"
out="$(export NO_COLOR=1 COLUMNS=40; sl 72 23)"
[[ "$out" == "ctx ███████▎░░ 72%  5h 23%  wk 41%" ]] || fail "no room for the model: $out"
out="$(export NO_COLOR=1 COLUMNS=26; sl 72 23)"
[[ "$out" == "ctx ██▉░ 72  5h 23  wk 41" ]] || fail "narrow status line: $out"
# With no COLUMNS at all (a CLI that sets none), a long model name can't wrap it.
out="$(printf '{"model":{"display_name":"Claude Opus 5.5 (1M context, extended)"},"context_window":{"used_percentage":72}}' | NO_COLOR=1 AGENTS_HISTORY=0 agents_statusline)"
[[ "$out" == "Claude Opus 5.5…  ctx "* ]] || fail "a long model name, no COLUMNS: $out"
out="$(unset NO_COLOR; export TERM=xterm; sl 28 23)"
[[ "$out" == *$'\033[32m'*"░"*" 28%"* && "$out" != *$'\033[33m'* && "$out" != *$'\033[31m'* ]] || fail "ctx 28: run: $(printf '%q' "$out")"
out="$(unset NO_COLOR; export TERM=xterm; sl 72 23)"
[[ "$out" == *$'\033[33m72%'* ]] || fail "ctx 72: warn: $(printf '%q' "$out")"
out="$(unset NO_COLOR; export TERM=xterm; sl 92 78)"
[[ "$out" == *$'\033[31m92%'* && "$out" == *$'5h \033[33m78%'* ]] || fail "ctx 92: need; 5h 78: warn: $(printf '%q' "$out")"
_agents_utf8() { return 1; }
out="$(export NO_COLOR=1; sl 50 23)"
[[ "$out" == "Opus 5.5  ctx #####----- 50%  5h 23%  wk 41%" ]] || fail "ASCII status line: $out"
_agents_utf8() { return 0; }
out="$(unset NO_COLOR; export TERM=xterm AGENTS_STATUSLINE_CMD='printf mine'; sl 72 23)"
[[ "$out" == mine ]] || fail "a command of yours: $(printf '%q' "$out")"
pass "status line: a ctx gauge turning warn at 70%, need at 90%; narrow form; a command of yours untouched"

# --- 8. agents mem ----------------------------------------------------------------------
memv() { W="$1" _agents_awk_colored "lib_fmt mem_view" -F '\t' -v total=50331648 -v free=59 -v level=normal -v su="$2" -v stot="$3" \
    -v gstate=on -v gpid=42 -v gmode=kill -v stops="$4" -v warn=8388608 -v stop=25165824 -v high=80; }
out="$(printf '80913\t5767168\t100\tvm guest\t-\t-\n2141\t10485760\t2000\tnode\tbilling\tclaude:7\n99\t31457280\t10\tbig\t-\t-\n' | memv 80 12373196 13631488 2)"
[[ "$out" == "MEMORY  ████████████▎░░░░░░░░░░░░░░░░░  41% used of 48.0G · pressure normal"* ]] || fail "memory bar: $out"
[[ "$out" == *$'\n'"SWAP    ███████████████████████████▎░░  ! 11.8 of 13.0G"$'\n'* ]] || fail "swap bar: $out"
[[ "$out" == *$'\n'"GUARD   running (pid 42) · kill · 2 stops in 7 days"$'\n'* ]] || fail "guard line: $out"
[[ "$out" == *$'\n'"PID     FOOTPRINT    warn 8G        stop 24G  PROCESS"$'\n'* ]] || fail "the thresholds over the bars: $out"
[[ "$out" == *$'\n'"80913        5.5G  █████▌░░│░░░░░░░░░░░░░░░░  vm guest · rss 100K"$'\n'* ]] || fail "process bar with the warn mark: $out"
[[ "$out" == *$'\n'"2141        10.0G  ████████│██░░░░░░░░░░░░░░  node · billing · claude:7 · rss 1M"* ]] || fail "past the warning: $out"
[[ "$out" == *$'\n'"99          30.0G  ████████│████████████████  big · rss 10K"* ]] || fail "past the stop size: $out"
[[ $(widest "$out") -le 80 ]] || fail "too wide: $out"
out="$(printf '' | memv 80 1048576 13631488 0)"
[[ "$out" == *"SWAP    "*"  1.0 of 13.0G"* && "$out" != *"!"* && "$out" != *"stops in"* ]] || fail "low swap: $out"
out="$(printf '' | memv 80 - - 0)"
[[ "$out" != *SWAP* ]] || fail "no swap reading: $out"
_agents_swap_parse "total = 13312.00M  used = 11800.25M  free = 1511.75M  (encrypted)" || fail "swap parse"
[[ "$REPLY" == "12083456 13631488" ]] || fail "swap kib: $REPLY"
_agents_swap_parse "total = 2.00G  used = 512.50K  free = 2.00G" || fail "swap parse, other units"
[[ "$REPLY" == "512 2097152" ]] || fail "swap kib, other units: $REPLY"
! _agents_swap_parse "nonsense" || fail "nonsense parsed"
pass "agents mem: bars for memory, swap and processes, the guard's sizes drawn"

# --- 9. The waits report ----------------------------------------------------------------
W="$tmp/report"; mkdir -p "$W"
{
    # billing: done for two hours (one fresh, one parked), then a block of 30 minutes.
    t=$((NOW - 3 * 3600)); while [[ $t -lt $((NOW - 3600)) ]]; do printf '%s\tbilling\tclaude\tdone\t1@A\t60\n' "$t"; t=$((t + 60)); done
    t=$((NOW - 1800)); while [[ $t -lt $NOW ]]; do printf '%s\tbilling\tclaude\tblocked\t1@A\t60\n' "$t"; t=$((t + 60)); done
    # infra: a stretch that began before the window is parked inside it.
    t=$((NOW - 90000)); while [[ $t -lt $((NOW - 84000)) ]]; do printf '%s\tinfra\tcodex\tdone\t2@B\t60\t\n' "$t"; t=$((t + 60)); done
} > "$W/waits.tsv"
printf '%s\t1@A\tbilling\tIdle\therdr\t-\n%s\t1@A\tbilling\tPermission\therdr\t-\n%s\t1@A\tbilling\tIdle\therdr\t-\n' $((NOW - 300)) $((NOW - 200)) $((NOW - 100)) > "$W/notify.tsv"
out="$(AGENTS_DATA_DIR="$W" AGENTS_WIDTH=100 agents_report --view waits)"
[[ "$out" == *"▲ blocked 30 min   ◆ fresh 59 min   ○ parked 1.7 h      3 notifications, 2 idle"* ]] || fail "headline: $out"
lane="$(printf '%s\n' "$out" | grep '^billing ')"
[[ "$lane" == *"▒░█"* ]] || fail "lane cells, fresh then parked then blocked: $lane"
[[ "$(printf '%s\n' "$lane" | _agents_awk lib_fmt -f /dev/fd/3 3<<'EOF'
{ s = substr($0, 12); i = index(s, "    "); print dw(substr(s, 1, i - 1)) }
EOF
)" == 24 ]] || fail "a day is 24 cells: $lane"
[[ "$out" == *"  now"* && "$out" == *"█ blocked   ▒ done under 1 h   ░ parked   · working or closed"* ]] || fail "lane header and legend: $out"
[[ "$out" == *"Longest: billing blocked 30 min, 13:15 to 13:45."* ]] || fail "longest: $out"
row_out="$(printf '%s\n' "$out" | grep '^  billing' | tr -s ' ')"
[[ "$row_out" == " billing 30 min 59 min 61 min 3 0" ]] || fail "billing's row: $row_out"
js="$(AGENTS_DATA_DIR="$W" agents_report --view waits --json)"
[[ "$js" == *'"blocked_s":1800,"done_s":9600,"fresh_s":3540,"parked_s":6060'* ]] || fail "json split: $js"
[[ "$js" == *'"waited_s":'* ]] || fail "json keeps waited_s"
out="$(AGENTS_DATA_DIR="$W" AGENTS_WIDTH=100 agents_report --view waits --since 7d)"
[[ "$out" == *"▲ blocked"* && "$out" != *"█ blocked"* ]] || fail "a week has no lanes: $out"
out="$(AGENTS_DATA_DIR="$W" AGENTS_WIDTH=40 agents_report --view waits)"
[[ "$out" != *"█ blocked"* ]] || fail "no room for lanes: $out"
pass "waits report: blocked, fresh and parked apart; hourly lanes for a window that fits; the longest block"

# --- 10. The menu -----------------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\n[[ "$1" == tsv ]] && cat "%s"\n' "$tmp/tsv" > "$HOME/.local/bin/agents"
chmod +x "$HOME/.local/bin/agents"
: > "$tmp/conf"
sess() {   # PID STATE AGE LABEL STATUS CPU RSS PROJECT
    printf 'triage\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
    printf 'agent\t%s\tclaude\t9000\t%s\t0\t%s\t2\tS%s\t-\tme\t%s\t/w/%s\tclaude\t%s\n' "$1" "$6" "$7" "$1" "$5" "$8" "$8"
}
MENU_TSV="$(
    sess 1 need 360 permission blocked 2 1000 api
    sess 2 review 720 "done" "done" 0.6 1000 web
    sess 3 review 2460 "done" "done" 0.6 1000 docs
    sess 4 run 8460 "tests 3m12s" working 842 7969177 billing
    sess 5 run 2820 working working 20 301056 infra
    sess 6 parked 140400 idle idle 0.1 1000 old1
    sess 7 parked 7200 "done" "done" 0.1 1000 old2
    sess 8 parked - quiet - 0.1 1000 old3
    printf 'act\t50\ttool\t18600\t0.0\t0\t100\t1\tSt\t-\t5\t-\t/w\tuntil x; do sleep 5; done\tmain\twait,stuck\t1\n'
    printf 'need\t50\tSt\tstuck\tstop\thigh\tfinished\t0\t5\tsafe to stop\tsafe to stop \342\200\224 done\tclaude\tinfra\t18600\t0\t-\t-\t-\t-\t1\n'
    printf 'job\t4\ttest\t0\t130\t0\t461000\t1\tSx\town\t700\tclaude\t/w\t-\tbilling\t-\n'
    printf 'sys\t27\t3.84\t12\t41\tnormal\t86\tcharging\n'
    printf 'awake\tagents\t9\t0\nthermal\t0\tnominal\npower\tautomatic\n'
    printf 'hist\tok\t172800\ttest\t110592\n'
    printf 'waitsum\t12240\t100\t100\n'
    printf 'limit\tClaude\t5h\t23\t16:40\tclaude\t60\npace\t41\tunder\t-\t██▌░░│░░░░░░░\n'
    printf 'limit\tClaude\tweek\t41\tSun 17:26\tclaude\t60\npace\t60\tunder\t-\t████▏░░│░░░░░░\n'
    printf 'tokens\t2200000000\t98\ndenials\t15\t-\ncompacts\t17\n'
    printf 'swap\t91\t12373196\t13631488\t██████████▍░\n'
    printf 'memg\ton\t42\t8388608\t25165824\t0\t-\t-\t-\t0\n'
)"
plugin() { { printf '%s\n' "$1"; printf '%s\n' "${2:-}"; } > "$tmp/tsv"; PATH="$HOME/.local/bin:$PATH" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh"; }
menu="$(plugin "$MENU_TSV")"
top="$(printf '%s\n' "$menu" | awk '$0 == "---" || !/^--/' | sed 's/ | .*//')"
want=":exclamationmark.circle.fill: 1 :checkmark.circle: 2 :cup.and.saucer.fill:
---
Needs you (1)
api · permission · 6m
To review (2)
web · done 12m
docs · done 41m
Running (2)
billing · tests 3m12s · 8.4 cores · 7.5G
infra · wait-loop stuck 5h10m · safe to stop
Parked (3) · oldest 39 h
---
Limits and memory
Claude 5h ██▌░░│░░░░░░░  23%
Claude wk ████▏░░│░░░░░░  41%
Swap      ██████████▍░  91%
---
Today: 3.4 h blocked · 48.0 CPU-h · tests 64%
---
Awake: while agents run
CPU 27% · Mem 59% · Thermal nominal
---
Open agents watch
Refresh"
[[ "$top" == "$want" ]] || fail "the menu's rows and order:"$'\n'"$top"
rows="$(printf '%s\n' "$top" | grep -vcE '^(---|:)')"
[[ $rows -le 18 ]] || fail "more than about 17 rows: $rows"$'\n'"$top"
pass "menu: the mockup's rows, in its order, $rows rows"

title="$(printf '%s\n' "$menu" | head -1)"
[[ "$title" == ":exclamationmark.circle.fill: 1 :checkmark.circle: 2 :cup.and.saucer.fill: | sfcolor=#FF453A sfcolor1=#0A84FF sfcolor2=#1D1D1F,#F2F2F5" ]] || fail "title, each symbol its color: $title"
calm_tsv="$(sess 4 run 8460 working working 842 7969177 billing; sess 6 parked 7200 idle idle 0 1000 old1; printf 'awake\tagents\t9\t0\n')"
title="$(plugin "$calm_tsv" | head -1)"
[[ "$title" == ":terminal: :cup.and.saucer.fill:" ]] || fail "calm: the icon alone, no tint: $title"
# The machine in trouble, sessions fine: the icon speaks.
title="$(plugin "$calm_tsv" $'sys\t5\t1.0\t14\t3\tcritical\t-\t-' | head -1)"
[[ "$title" == ":terminal: :cup.and.saucer.fill: | sfcolor=#FF453A sfcolor1=#1D1D1F,#F2F2F5" ]] || fail "critical memory: $title"
title="$(plugin "$MENU_TSV" $'sys\t5\t1.0\t14\t3\tcritical\t-\t-' | head -1)"
[[ "$title" == ":terminal: :exclamationmark.circle.fill: 1 :checkmark.circle: 2 :cup.and.saucer.fill: | sfcolor=#FF453A sfcolor1=#FF453A sfcolor2=#0A84FF sfcolor3=#1D1D1F,#F2F2F5" ]] || fail "both: $title"
# Stale processes and hogs wait in the menu, untinted.
title="$(plugin "$calm_tsv"$'\n'$'stale\t1\tmcp\t0\t0\t0\t100\t0\tS\t-\tme\t-\t-\tnpm exec x\t-' | head -1)"
[[ "$title" == ":terminal: :cup.and.saucer.fill:" ]] || fail "stale tinted the title: $title"
# The old token still counts.
title="$(plugin "$calm_tsv" $'conf\tAGENTS_BAR_TITLE\tcount awake' | head -1)"
[[ "$title" == ":terminal: 2 :cup.and.saucer.fill:" ]] || fail "the count token: $title"
pass "menu title: what needs you with its tints, calm otherwise, the icon back for the machine; the count token works"

# Nothing is lost: what the old rows did is in a submenu.
parked="$(printf '%s\n' "$menu" | awk '/^Parked/ { on = 1; next } on && /^---$|^[^-]/ { exit } on')"
[[ "$parked" == "--old1 · idle · 39 h | sfimage=circle "*$'\n'* ]] || fail "parked sessions: $parked"
[[ "$parked" == *$'\n'"--old3 · quiet | "* ]] || fail "a parked session with no age: $parked"
[[ "$parked" == *$'\n'"----Jump to session | "* && "$parked" == *$'\n'"----Kill session… | "* && "$parked" == *$'\n'"----Copy path | "* && "$parked" == *$'\n'"----Details | "* ]] || fail "a parked session's actions: $parked"
run="$(printf '%s\n' "$menu" | awk '/^infra · wait-loop/ { on = 1; next } on && /^[^-]/ { exit } on')"
[[ "$run" == "--until x; do sleep 5; done | symbolize=false"$'\n'"--Jump to session"* || "$run" == "--until x; do sleep 5; done | symbolize=false"$'\n'* ]] || fail "the flagged row's submenu: $run"
[[ "$run" == *"--Stop command… | "* && "$run" == *"--Copy details | "* && "$run" == *"--Kill session… | "* ]] || fail "the flagged row keeps the verdict's and the session's actions: $run"
today="$(printf '%s\n' "$menu" | awk '/^Today:/ { on = 1; next } on && /^---$|^[^-]/ { exit } on')"
for w in "--Where the CPU goes" "--tests · 130% · " "--2.2B tokens · 98% read from the prompt cache" "--15 denials" "--17 context compactions" "--Open report"; do
    [[ "$today" == *"$w"* ]] || fail "Today's submenu has no '$w': $today"
done
system="$(printf '%s\n' "$menu" | awk '/^CPU / { on = 1; next } on && /^---$|^[^-]/ { exit } on')"
[[ "$system" == "--Load 3.84/12 | size=11"$'\n'* && "$system" == *"--Battery 86%"*"param1=battery-settings"* && "$system" == *"--Memory guard: on · stops agent runaways at 24.0G | "* && "$system" == *$'\n'"----Memory view (agents mem) | "* ]] \
    || fail "the system row's submenu: $system"
watch="$(printf '%s\n' "$menu" | awk '/^Open agents watch/ { on = 1; next } on && /^---$|^[^-]/ { exit } on')"
[[ "$watch" == *"--Full table (agents ls) | "* ]] || fail "Open agents watch's submenu: $watch"
: > "$tmp/conf-file"
menu2="$(plugin "$MENU_TSV" $'conf\tAGENTS_CONF\t'"$tmp/conf-file")"
[[ "$menu2" == *$'\n'"--Edit settings… | "*"param1=config param2=--edit "* ]] || fail "Edit settings"
pass "menu: every action is still there, one submenu down"

# Swap: only when high (agents sends the row only then).
# No signal: a row of its own after Running, out of the title and of Parked.
quiet_tsv="$(sess 4 run 8460 working working 842 7969177 billing; sess 9 unknown - "no signal" - 0.1 301056 codexapp; printf 'awake\tagents\t9\t0\n')"
menu="$(plugin "$quiet_tsv")"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: :cup.and.saucer.fill:" ]] || fail "no signal in the title: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *$'\n'"Running (1) | size=12"$'\n'"billing · working"*$'\n'"No signal (1) | size=12"$'\n'"codexapp · no signal · 0.0 cores · 294M | sfimage=questionmark.circle "* ]] || fail "no signal's rows: $menu"
[[ "$menu" != *"Parked ("* ]] || fail "no signal under Parked"
# From an older agents too: no triage row, no Herdr status.
menu="$(plugin "$(sess 9 unknown - x - 0.1 301056 codexapp | grep -v '^triage')")"
[[ "$menu" == *$'\n'"No signal (1) | size=12"$'\n'"codexapp · no signal"* ]] || fail "older agents, no status: $menu"
pass "menu: no signal is a row of its own, not parked and not in the title"

menu="$(plugin "$calm_tsv")"
[[ "$menu" != *"Swap "* && "$menu" != *"Limits and memory"* ]] || fail "swap when it isn't high: $menu"
menu="$(plugin "$calm_tsv" $'swap\t91\t12373196\t13631488\t██████████▍░')"
[[ "$menu" == *$'\n'"Limits and memory | size=12"$'\n'"Swap      ██████████▍░  91% | sfimage=memorychip "*"font=Menlo size=12"* ]] || fail "swap alone: $menu"
pass "menu: swap only when high"

# An older agents: no triage rows, Herdr's status alone; nothing breaks.
old="$(printf '%s\n' "$MENU_TSV" | grep -vE '^(triage|pace|waitsum|swap)'$'\t')"
menu="$(plugin "$old")"
[[ "$menu" == *$'\n'"Needs you (1) | size=12"$'\n'"api · blocked | "* ]] || fail "older agents, blocked: $menu"
[[ "$menu" == *$'\n'"To review (3) | size=12"$'\n'"web · done | "* ]] || fail "older agents, done: $menu"
[[ "$menu" == *$'\n'"Parked (1) | "* ]] || fail "older agents, idle: $menu"
[[ "$menu" == *$'\n'"Claude 5h 23% | "* ]] || fail "older agents, limits: $menu"
pass "menu with an older agents: Herdr's status and plain limits"

# Tints: the theme's, base64 and all, when it suits the appearance.
PAL=$'palette\ttokyo-night\t#f7768e\t#7aa2f7\t#9ece6a\t#e0af68\t#7aa2f7\t#1a1b26'
b64() { printf '{"renderingMode":"Palette","colors":["%s"]}' "$1" | base64 | tr -d '\n'; }
menu="$(OS_APPEARANCE=Dark plugin "$PAL"$'\n'"$MENU_TSV")"
[[ "$(printf '%s\n' "$menu" | head -1)" == *"sfcolor=#f7768e sfcolor1=#7aa2f7 "* ]] || fail "palette in the title: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *$'\n'"api · permission · 6m | sfimage=exclamationmark.circle.fill sfconfig=$(b64 '#f7768e') "* ]] || fail "palette in sfconfig: $(printf '%s\n' "$menu" | grep '^api')"
[[ "$menu" == *$'\n'"web · done 12m | sfimage=checkmark.circle sfconfig=$(b64 '#7aa2f7') "* ]] || fail "done tint"
[[ "$menu" == *"sfimage=circle.fill sfconfig=$(b64 '#9ece6a') "* ]] || fail "run tint"
[[ "$menu" == *"sfimage=hourglass sfconfig=$(b64 '#e0af68') "* ]] || fail "warn tint"
# A dark palette on a light menu keeps Apple's hues, for light.
menu="$(OS_APPEARANCE=Light plugin "$PAL"$'\n'"$MENU_TSV")"
[[ "$(printf '%s\n' "$menu" | head -1)" == *"sfcolor=#FF3B30 sfcolor1=#007AFF "* ]] || fail "dark palette, light menu: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *"sfconfig=$(b64 '#FF3B30') "* ]] || fail "light hue in sfconfig"
# A light palette suits it; on a dark menu it doesn't.
LAT=$'palette\tcatppuccin-latte\t#d20f39\t#1e66f5\t#40a02b\t#df8e1d\t#1e66f5\t#eff1f5'
[[ "$(OS_APPEARANCE=Light plugin "$LAT"$'\n'"$MENU_TSV" | head -1)" == *"sfcolor=#d20f39 "* ]] || fail "light palette, light menu"
[[ "$(OS_APPEARANCE=Dark plugin "$LAT"$'\n'"$MENU_TSV" | head -1)" == *"sfcolor=#FF453A "* ]] || fail "light palette, dark menu"
# No palette: Apple's hues; nonsense is ignored.
[[ "$(plugin "$MENU_TSV" | head -1)" == *"sfcolor=#FF453A sfcolor1=#0A84FF "* ]] || fail "no palette"
[[ "$(plugin $'palette\tx\tred\t-\t-\t-\t-\t-'$'\n'"$MENU_TSV" | head -1)" == *"sfcolor=#FF453A "* ]] || fail "a bad color used"
pass "menu tints: the palette through sfconfig and sfcolor where it suits the appearance, Apple's hues otherwise"

# --- 11. agents_tsv and json carry the new rows ---------------------------------------------
_agents_with_needs_out="$(_agents_with_needs "$(rec 101 blocked 2 100 5000 api)")"
[[ "$_agents_with_needs_out" == *$'triage\t101\tneed\t'* ]] || fail "with_needs has no triage row"
unk="$(_agents_with_needs "$(rec 301 - 0.1 100 5000 quiet)" | agents_json)"
[[ "$unk" == *'"triage":{"state":"unknown","age_s":null,"label":"no signal"}'* ]] || fail "json unknown: $unk"
js="$(printf '%s\n' "$_agents_with_needs_out" | agents_json)"
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$js" | jq -e '.schema_version == 1 and .agents[0].triage.state == "need" and .agents[0].triage.label == "permission"' >/dev/null || fail "json triage: $js"
else
    [[ "$js" == *'"triage":{"state":"need"'* ]] || fail "json triage: $js"
fi
pass "agents json: each session's triage, added to schema 1"

echo
echo "All agents triage tests passed."
