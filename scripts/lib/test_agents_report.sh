#!/bin/bash
# Unit tests for `agents report`'s run-ledger views (runs, waste, trends,
# agents), the summary's top insights, insight.txt and the menu's insight line.
# Run: bash scripts/lib/test_agents_report.sh  -> exit 0 on pass.
#
# Everything runs against scripts/lib/testdata/agents-runs.tsv, a fixed clock
# and temp dirs. The fixture, in the 24h before "now" (15:00 UTC):
#   app   go      test  main     10 runs, 60..600 s, 400 CPU-s each; #9 exit 1,
#                                #10 unknown; #3-#5 duplicates (1200 CPU-s)
#   shop  pytest  test  Explore  5 runs of 200 s, 200 CPU-s; exits 1 1 0 2 0:
#                                the first two re-run at once (400 CPU-s), the
#                                third failure 800 s before the next run: no
#   shop  wait-loop     Explore  3 loops of 2520 s (2.1 h), cleaned up
#   app   wait-loop     main     2 loops of 3600 s, not cleaned up
#   api   make    build implementor-complex  5 runs, 100..500 s, 480 CPU-s each
#   -     node    other -        1 run
# and in the 24h before that: api's 5 builds (60 s, 160 CPU-s each) and 2 of
# app's tests (1500 CPU-s each); one row 10 days old, a header, a short row.

# Tests change variables inside ( … ) on purpose, for one call; the stubs
# (date) are called by the sourced bin/agents; backticks in single quotes are
# the insights' own, not command substitutions.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1 LC_ALL=C
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
has_jq() { command -v jq >/dev/null 2>&1; }
# jqt JSON FILTER WHAT — FILTER must hold for JSON (skipped without jq).
jqt() { ! has_jq || printf '%s' "$1" | jq -e "$2" >/dev/null || fail "$3: $(printf '%s' "$1" | jq -c "${4:-.}")"; }

# A fixed clock: 15:00 UTC on 2025-10-14.
FAKE_NOW=1760454000
# shellcheck disable=SC2317,SC2329  # called by the functions under test
date() {
    case "$*" in
        '+%s %z') echo "$FAKE_NOW +0000" ;;
        +%s)      echo "$FAKE_NOW" ;;
        *)        command date "$@" ;;
    esac
}

# ledger DIR — the fixture as DIR/runs.tsv, its times counted back from FAKE_NOW.
ledger() {
    mkdir -p "$1"
    awk -F '\t' -v OFS='\t' -v n="$FAKE_NOW" '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { $1 = n - $1; $2 = n - $2 } { print }' \
        "$SCRIPT_DIR/testdata/agents-runs.tsv" > "$1/runs.tsv"
}
d="$tmp/d"; ledger "$d"
rep() { AGENTS_DATA_DIR="$d" agents_report "$@"; }
# row TEXT LINE — LINE, with runs of spaces squeezed, is in TEXT.
row() { printf '%s\n' "$1" | tr -s ' ' | grep -qxF "$2"; }

# 1. runs: the most repeated commands, the slowest tests and builds.
out="$(rep --view runs)"
[[ "$out" == "agents report · runs · last 24h"$'\n\n'"RUNS 26 · 2.06 CPU-h · 18% failed"* ]] || fail "runs header:"$'\n'"$out"
row "$out" " app go test 10 1.11 5m30s 9m00s 11%" || fail "runs: go (median of 10 = mean of the middle two, p90 = 9th):"$'\n'"$out"
row "$out" " api make build 5 0.67 5m00s 8m20s 0%" || fail "runs: make:"$'\n'"$out"
row "$out" " shop pytest test 5 0.28 3m20s 3m20s 60%" || fail "runs: pytest:"$'\n'"$out"
row "$out" " shop wait-loop wait 3 0.00 42m00s 42m00s -" || fail "runs: cleaned runs count in no failure rate:"$'\n'"$out"
[[ "$(printf '%s\n' "$out" | grep -n ' make ' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n ' pytest ' | head -1 | cut -d: -f1)" ]] \
    || fail "runs: a tie in count goes to more CPU"
slow="$(printf '%s\n' "$out" | sed -n '/^SLOWEST/,$p')"
row "$slow" " app go test 10 5m30s 9m00s 10m00s" || fail "slowest: go:"$'\n'"$slow"
[[ "$slow" != *wait-loop* && "$slow" != *node* ]] || fail "slowest lists more than tests and builds:"$'\n'"$slow"
[[ "$out" != *old* && "$out" != *broken* ]] || fail "runs counts rows outside the window or short rows"
pass "runs: count, CPU-h, median, p90 and failure rate per command; slowest tests and builds"
json="$(rep --view runs --json)"
jqt "$json" '.schema_version == 1 and .view == "runs" and .window == "24h" and .ledger and .runs == 26 and .cpu_s == 7420 and .exit_known == 22 and .failed == 4' "runs json totals"
jqt "$json" '.commands[0] == {"project":"app","cmd":"go","job":"test","runs":10,"cpu_s":4000,"median_s":330,"p90_s":540,"max_s":600,"exit_known":9,"failed":1,"fail_pct":11.1,"dups":3,"dup_cpu_s":1200,"reruns":0,"rerun_cpu_s":0}' "runs json: go" '.commands[0]'
jqt "$json" '(.commands[] | select(.cmd == "wait-loop" and .project == "shop") | .fail_pct) == null' "runs json: no exit codes, no failure rate"
jqt "$json" '[.slowest[].cmd] == ["go","make","pytest"]' "runs json: slowest" '.slowest'
pass "runs --json: every command, with the same numbers"

# 2. waste: duplicates, leaks, polling loops, failed runs re-run at once.
out="$(rep --view waste)"
[[ "$out" == *"DUPLICATES  3 runs · 0.33 CPU-h (16% of the runs' CPU)"* ]] || fail "waste: duplicates:"$'\n'"$out"
row "$out" " app go test 3 0.33" || fail "waste: duplicate command:"$'\n'"$out"
[[ "$out" == *"LEFT RUNNING  3 runs, until a cleanup stopped them · 2.1 h · 0.00 CPU-h"* ]] || fail "waste: leaks:"$'\n'"$out"
[[ "$out" == *"  by agent    Explore 3 (2.1 h)"$'\n'"  by job      wait 3 (2.1 h)"* ]] || fail "waste: leaks by agent and job:"$'\n'"$out"
[[ "$out" == *"POLLING LOOPS  5 · 4.1 h waiting"$'\n'"  by agent    Explore 3 (2.1 h) · main 2 (2.0 h)"* ]] || fail "waste: polling:"$'\n'"$out"
[[ "$out" == *"FAILED, RE-RUN AT ONCE  2 runs · 0.11 CPU-h"* ]] || fail "waste: re-runs:"$'\n'"$out"
row "$out" " shop pytest test 2 0.11" || fail "waste: re-run command:"$'\n'"$out"
json="$(rep --view waste --json)"
jqt "$json" '.duplicates == {"runs":3,"cpu_s":1200,"commands":[{"project":"app","cmd":"go","job":"test","runs":3,"cpu_s":1200}]}' "waste json duplicates" '.duplicates'
jqt "$json" '.cleaned.runs == 3 and .cleaned.cpu_s == 15 and .cleaned.wall_s == 7560 and .cleaned.agents[0] == {"agent":"Explore","runs":3,"cpu_s":15,"wall_s":7560,"wait_runs":3}' "waste json cleaned" '.cleaned'
jqt "$json" '.wait.runs == 5 and .wait.wall_s == 14760 and .reruns.runs == 2 and .reruns.cpu_s == 400' "waste json wait and reruns"
pass "waste: duplicates and their CPU, leaks and their hours, polling, re-runs (only within 120s)"

# 3. trends: this window against the one before.
out="$(rep --view trends --since 24h)"
[[ "$out" == "agents report · trends · last 24h vs the 24h before"* ]] || fail "trends header:"$'\n'"$out"
row "$out" " api 0.67 0.22 ↑200% 5 0% 5m00s ↑400% more CPU, slower" || fail "trends: api regressed:"$'\n'"$out"
row "$out" " app 1.11 0.83 ↑33% 12 ↑500% 6m30s ↑30%" || fail "trends: app (more, under the thresholds):"$'\n'"$out"
row "$out" " shop 0.28 0.00 new 8 new 3m20s new" || fail "trends: shop is new:"$'\n'"$out"
row "$out" " test 1.39 0.83 ↑67% 15 ↑650% 3m20s ↓33% more CPU" || fail "trends: by job:"$'\n'"$out"
json="$(rep --view trends --since 24h --json)"
jqt "$json" '.previous == {"since":1760281200,"until":1760367600}' "trends json: the window before" '.previous'
jqt "$json" '(.projects[] | select(.project == "api")) == {"project":"api","cpu_s":2400,"prev_cpu_s":800,"runs":5,"prev_runs":5,"median_s":300,"prev_median_s":60,"more_cpu":true,"slower":true}' "trends json: api" '.projects'
json="$(rep --view trends --json)"
jqt "$json" '.window == "7d" and (.projects[] | select(.project == "old") | .prev_runs == 1 and .runs == 0)' "trends: 7d by default, the week before included" '.projects'
pass "trends: CPU-h, runs and median against the window before, with ↑/↓ and the regressions flagged"

# 4. agents: by agent type.
out="$(rep --view agents)"
row "$out" " main 12 1.11 54% 9% 3 0.33 0 0.0 2.0" || fail "agents: main:"$'\n'"$out"
row "$out" " Explore 8 0.28 14% 60% 0 0.00 3 2.1 2.1" || fail "agents: Explore:"$'\n'"$out"
row "$out" " (unknown) 1 0.00 0% 0% 0 0.00 0 0.0 0.0" || fail "agents: no agent type:"$'\n'"$out"
[[ "$out" == *"LEAKS MOST       Explore 3 (2.1 h)"$'\n'"DUPLICATES MOST  main 3 (0.33 CPU-h)" ]] || fail "agents: leaks and duplicates most:"$'\n'"$out"
json="$(rep --view agents --json)"
jqt "$json" '[.agents[].agent] == ["main","implementor-complex","Explore",null] and .agents[2].cleaned_s == 7560 and .agents[0].dup_cpu_s == 1200' "agents json" '.agents'
pass "agents: runs, CPU, failures, duplicates, leaks and polling per agent type"

# 5. The summary's top insights: ranked by impact, worded with what to do.
out="$(rep)"
ins="$(printf '%s\n' "$out" | sed -n '/^TOP INSIGHTS$/,/^$/p')"
want="TOP INSIGHTS
  1. api: 40 CPU-min in 24h, ↑200% on the 24h before (build +27 CPU-min) — see what changed: agents report --view trends
  2. app: \`go\` test runs ×10 in 24h, 5m30s median, 3 duplicates (20 CPU-min) — consider a shared test cache or serializing them
  3. Explore subagents left 3 polling loops running in 24h (2.1 h) — have them stop what they start, or set AGENTS_AUTO_REAP=1
  more: agents report --view runs|waste|trends|agents"
[[ "$ins" == "$want" ]] || fail "top insights:"$'\n'"$ins"
[[ "$out" == *"no CPU samples in this window"* ]] || fail "summary without history:"$'\n'"$out"
json="$(rep --json)"
jqt "$json" '.view == "summary" and .ledger and ([.insights[] | [.kind, .impact_s]] == [["regression",1600],["dup",1200],["leak",771]])' "summary json insights" '.insights'
jqt "$json" '.insights[1] | .project == "app" and .cmd == "go" and .job == "test" and .agent == null and .view == "waste"' "summary json: an insight's subject" '.insights[1]'
# Below 5 CPU-min nothing is worth a line: only the polling (720) and the
# re-runs (400) are left once the three above are gone.
awk -F '\t' '!($4 == "api" || ($7 == "go" && $4 == "app") || ($7 == "wait-loop" && $4 == "shop"))' "$d/runs.tsv" > "$tmp/r"
mkdir -p "$tmp/d2"; cp "$tmp/r" "$tmp/d2/runs.tsv"
out="$(AGENTS_DATA_DIR="$tmp/d2" agents_report)"
[[ "$out" == *"  1. Main sessions spent 2.0 h in 2 polling loops in 24h — wait on a background task's notification instead of a sleep loop"$'\n'"  2. shop: \`pytest\` test failed and was re-run at once ×2 in 24h (7 CPU-min) — find the flaky failure, or re-run only what failed"$'\n'"  more:"* ]] \
    || fail "insights: polling and re-runs:"$'\n'"$out"
awk -F '\t' -v OFS='\t' '$7 == "wait-loop" { next } $7 == "pytest" { $9 = 20 } { print }' "$tmp/r" > "$tmp/d2/runs.tsv"
out="$(AGENTS_DATA_DIR="$tmp/d2" agents_report)"
[[ "$out" == *"TOP INSIGHTS"$'\n'"  nothing stands out (agents report --view runs|waste|trends|agents)"* ]] || fail "insights below 5 CPU-min:"$'\n'"$out"
pass "summary: the top 3 insights, ranked by CPU at stake; none below 5 CPU-min"

# 6. Without a ledger, or nothing in the window: no invented numbers.
e="$tmp/empty"; mkdir -p "$e"
printf '%s\ttest\tapp\tclaude\t600\t100\t1\n' "$((FAKE_NOW - 600))" > "$e/history.tsv"
note="no runs recorded yet (runs.tsv): insights and the runs, waste, trends and agents views start with the first finished run"
out="$(AGENTS_DATA_DIR="$e" agents_report)"
[[ "$out" == *$'\n'"$note"$'\n'* && "$out" == *"CPU 10.00 CPU-min of agent work"* && "$out" != *"TOP INSIGHTS"* ]] || fail "summary without a ledger:"$'\n'"$out"
for v in runs waste trends agents; do
    out="$(AGENTS_DATA_DIR="$e" agents_report --view "$v")"
    [[ "$out" == "agents report · last "*"$note"*"CPU 10.00 CPU-min"* ]] || fail "--view $v without a ledger falls back to the summary:"$'\n'"$out"
    json="$(AGENTS_DATA_DIR="$e" agents_report --view "$v" --json)"
    [[ "$json" == '{"schema_version":1,"view":"'"$v"'",'*'"ledger":false'* ]] || fail "--view $v --json without a ledger: $json"
    jqt "$json" '.ledger == false' "--view $v --json"
done
jqt "$(AGENTS_DATA_DIR="$e" agents_report --json)" '.ledger == false and .insights == []' "summary json without a ledger"
jqt "$(AGENTS_DATA_DIR="$e" agents_report --view runs --json)" '.runs == 0 and .commands == [] and .slowest == []' "runs json without a ledger"
jqt "$(AGENTS_DATA_DIR="$e" agents_report --view waste --json)" '.duplicates.runs == 0 and .cleaned.agents == [] and .reruns.commands == []' "waste json without a ledger"
grep old "$d/runs.tsv" > "$e/runs.tsv"
for v in runs waste agents; do
    [[ "$(AGENTS_DATA_DIR="$e" agents_report --view "$v")" == *$'\n\n'"no runs in this window" ]] || fail "--view $v with nothing in the window"
done
[[ "$(AGENTS_DATA_DIR="$e" agents_report --view trends --since 1h)" == *"no runs in this window or the one before" ]] || fail "trends with nothing in either window"
[[ "$(AGENTS_DATA_DIR="$e" agents_report)" == *"TOP INSIGHTS"$'\n'"  nothing stands out"* ]] || fail "insights with nothing in the window"
[[ "$(AGENTS_DATA_DIR="$tmp/none" agents_report --view runs)" == *"no history yet"* ]] || fail "no data at all"
pass "no ledger: the history report and a one-line note (JSON: ledger false, empty lists); nothing in the window says so"

# 7. Options.
for bad in "--view" "--view bogus" "--view insight" "--view=" "--since 3x --view runs"; do
    rc=0
    # shellcheck disable=SC2086  # one argument per word
    rep $bad >/dev/null 2>&1 || rc=$?
    [[ $rc == 2 ]] || fail "agents report $bad: rc $rc"
done
[[ "$(rep --view=waste)" == "agents report · waste"* ]] || fail "--view=waste"
[[ "$(rep --view trends --since today)" == "agents report · trends · today vs yesterday by this hour"* ]] || fail "trends today"
pass "report: --view and --view=, bad views refused (rc 2)"

# 8. insight.txt and the tsv's insight row.
w="$tmp/w"; ledger "$w"
AGENTS_DATA_DIR="$w" agents_insight_write
IFS=$'\t' read -r was until view text < "$w/insight.txt"
[[ "$was" == "$FAKE_NOW" && "$until" == $((FAKE_NOW + 3600)) && "$view" == trends ]] || fail "insight.txt: $(cat "$w/insight.txt")"
[[ "$text" == "api: 40 CPU-min today, ↑200% on yesterday by this hour (build +27 CPU-min) — see what changed: agents report --view trends" ]] \
    || fail "insight.txt text: $text"
[[ "$(AGENTS_DATA_DIR="$w" _agents_insight_line)" == "insight"$'\t'"trends"$'\t'"$text" ]] || fail "insight row"
rm "$w/runs.tsv"
( FAKE_NOW=$((FAKE_NOW + 299)); AGENTS_DATA_DIR="$w" agents_insight_write )
[[ "$(cut -f1 "$w/insight.txt")" == "$FAKE_NOW" ]] || fail "insight.txt rewritten within 5 minutes"
( FAKE_NOW=$((FAKE_NOW + 300)); AGENTS_DATA_DIR="$w" agents_insight_write )
[[ "$(cat "$w/insight.txt")" == "$((FAKE_NOW + 300))"$'\t'"$((FAKE_NOW + 3900))" ]] || fail "insight.txt with nothing to say: $(cat "$w/insight.txt")"
[[ -z "$(AGENTS_DATA_DIR="$w" _agents_insight_line)" ]] || fail "an insight row with nothing to say"
printf '%s\t%s\twaste\tx\n' "$FAKE_NOW" "$FAKE_NOW" > "$w/insight.txt"
[[ -z "$(AGENTS_DATA_DIR="$w" _agents_insight_line)" ]] || fail "an expired insight is shown"
printf '%s\t%s\t--evil\tx\n' "$FAKE_NOW" "$((FAKE_NOW + 60))" > "$w/insight.txt"
[[ -z "$(AGENTS_DATA_DIR="$w" _agents_insight_line)" ]] || fail "an insight with a bad view is shown"
printf '%s\t%s\twaste\tx\n' "$FAKE_NOW" "$((FAKE_NOW + 60))" > "$w/insight.txt"
[[ -z "$(AGENTS_HISTORY=0 AGENTS_DATA_DIR="$w" _agents_insight_line)" ]] || fail "an insight row with history off"
( AGENTS_HISTORY=0; rm "$w/insight.txt"; AGENTS_DATA_DIR="$w" agents_insight_write; [[ ! -e "$w/insight.txt" ]] ) || fail "insight.txt written with history off"
# Midnight comes first: an insight written at 23:30 expires at 00:00.
( FAKE_NOW=$((1760400000 + 86400 - 1800)); ledger "$w"; AGENTS_DATA_DIR="$w" agents_insight_write
  [[ "$(cut -f2 "$w/insight.txt")" == $((1760400000 + 86400)) ]] ) || fail "insight.txt outlives the day: $(cat "$w/insight.txt")"
pass "insight.txt: today's top insight, at most every 5 minutes, until midnight or an hour; the tsv row only while current"

# 9. The menu: one line under Today, what was found as its label and the
# whole sentence as its tooltip, opening that view of the report.
printf 'hist\tok\t3600\ttest\t1800\ninsight\ttrends\t- a|b: `go` test ×3 — do "this"\n' > "$tmp/tsv"
printf '#!/bin/bash\ncase "$1" in tsv) cat "%s" ;; esac\n' "$tmp/tsv" > "$tmp/agents-stub"
chmod +x "$tmp/agents-stub"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
section="$(printf '%s\n' "$menu" | awk '/^Where the CPU goes/ { on = 1 } on && /^---$/ { exit } on')"
want="Today: 1.0 CPU-h · tests 50% | sfimage=chart.bar.xaxis refresh=true symbolize=false
a¦b: go test ×3 | bash=\"$tmp/agents-stub\" param1=open-term terminal=false param2=--hold param3=report param4=--view param5=trends tooltip=\"a¦b: go test ×3 — do 'this'\" sfimage=lightbulb symbolize=false
Open report | "
[[ "$section" == *"$want"* ]] || fail "menu insight line:"$'\n'"$section"
long="api: 40 CPU-min today, ↑200% on yesterday by this hour (build +27 CPU-min) — see what changed: agents report --view trends"
printf 'hist\tok\t3600\ttest\t1800\ninsight\ttrends\t%s\n' "$long" > "$tmp/tsv"
line="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh" | grep 'sfimage=lightbulb')"
# (67 characters or bytes, by the locale, then back to a word.)
[[ "$line" == "api: 40 CPU-min today, ↑200% on yesterday by this hour "*"... | "*" param5=trends tooltip=\"$long\" "* \
   && "${line%% | *}" != *" ..." && "${line%% | *}" != *"CPU-min)"* ]] \
    || fail "a long insight: label cut at a word, the sentence in the tooltip:"$'\n'"$line"
for bad in '--x' 'trends extra' ''; do
    printf 'hist\tok\t3600\ttest\t1800\ninsight\t%s\tsome text\n' "$bad" > "$tmp/tsv"
    menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
    [[ "$menu" != *"some text"* ]] || fail "menu shows an insight with the view '$bad'"
done
printf 'hist\toff\t0\t-\t0\ninsight\twaste\tsome text\n' > "$tmp/tsv"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
[[ "$menu" != *"some text"* ]] || fail "menu shows an insight with history off"
pass "menu: the top insight under Today (its finding as the label, cut at 70; the sentence as the tooltip; a fixed view as its only param), Open report after it"

# 10. A month of runs: thousands of commands, JSON far past mawk's 8 KiB
# sprintf limit, every number still in place.
big="$tmp/big"; mkdir -p "$big"
awk -v n="$FAKE_NOW" 'BEGIN {
    OFS = "\t"
    for (i = 0; i < 24000; i++) {
        e = n - (i * 107) % (28 * 86400); p = "project-" (i % 300); c = "cmd" (i % 7); j = (i % 3 ? "test" : "build")
        print e, e - 30 - i % 600, j, p, "claude:" (i % 40), (i % 5 ? "Explore" : "main"), c, 30 + i % 600, 10 + i % 90, 1000, i % 11 ? 0 : 1, i % 13 ? 0 : 1, i % 17 ? 0 : 1
    }
}' > "$big/runs.tsv"
for v in runs waste trends agents; do
    json="$(AGENTS_DATA_DIR="$big" agents_report --view "$v" --since 30d --json)"
    [[ ${#json} -gt 8192 || "$v" == agents ]] || fail "--view $v --json is small (${#json} bytes): the fixture is too"
    [[ "$json" == '{"schema_version":1,"view":"'"$v"'",'*'}' ]] || fail "--view $v --json on a month: ${json:0:200}"
    jqt "$json" '.schema_version == 1' "--view $v --json on a month"
done
json="$(AGENTS_DATA_DIR="$big" agents_report --view runs --since 30d --json)"
jqt "$json" '(.commands | length) == 2100 and .runs == 24000' "a month: every command" '{runs, n: (.commands | length)}'
out="$(AGENTS_DATA_DIR="$big" agents_report --view runs --since 30d)"
[[ "$out" == *"... 2090 more (agents report --view runs --json)"* ]] || fail "a month: the text is cut at 10:"$'\n'"$out"
jqt "$(AGENTS_DATA_DIR="$big" agents_report --since 30d --json)" '.insights[0].kind == "leak" and .insights[0].agent == "Explore"' "a month: insights" '.insights'
pass "a month of runs (24000, 2100 commands): JSON valid past 8 KiB, text cut at 10 rows"

echo "All agents report tests passed."
