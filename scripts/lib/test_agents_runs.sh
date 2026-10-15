#!/bin/bash
# Unit tests for the run ledger (lib/agents/runs.sh): runs followed from
# snapshot to snapshot, the menu's 10 s feed, exit codes, the agent that
# started a run, dup and cleaned, `agents runs`, pruning and privacy.
# Run: bash scripts/lib/test_agents_runs.sh  -> exit 0 on pass.
#
# Everything runs against fixture `ps` text, synthetic transcripts, a fixed
# clock and temp dirs: nothing real is read or signalled, except one live
# smoke test where `ps` works.

# Tests change variables inside ( … ) on purpose; the stubs (date,
# agents_snapshot, _agents_cwds…) are called by the sourced functions.
# shellcheck disable=SC2030,SC2031,SC2034,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1 CLAUDE_CONFIG_DIR="$tmp/claude"
unset AGENTS_HISTORY AGENTS_HISTORY_DAYS
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
AGENTS_UID=501 AGENTS_SELF=9999

# A fixed clock: T0 is 2025-10-14 00:00 UTC.
T0=1760400000 FAKE_NOW=1760400000 FAKE_DAY=2025-10-14
date() {
    case "$*" in
        '+%s %Y-%m-%d') echo "$FAKE_NOW $FAKE_DAY" ;;
        '+%s %z')       echo "$FAKE_NOW +0000" ;;
        +%s)            echo "$FAKE_NOW" ;;
        *)              command date "$@" ;;
    esac
}
at() { FAKE_NOW=$((T0 + $1)); }

# pl PID PPID CPU_S AGE_S RSS START ARGS — one `ps` line (uid 501) at the
# fake clock: cputime and etime from seconds; START is its HH:MM:SS, the
# pid@start token's time.
pl() {
    printf '%5s %5s   501 me      1.0 %7s %4d:%02d.00 %8d:%02d Wed Oct 14 %s 2026     %s\n' \
        "$1" "$2" "$5" $(($3 / 60)) $(($3 % 60)) $(($4 / 60)) $(($4 % 60)) "$6" "$7"
}
cc() { printf "/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval '%s' < /dev/null && pwd -P >| /tmp/cwd-1" "$1"; }

# --- Claude Code's files for session S of project -code-app --------------------
S=11111111-2222-3333-4444-555555555555
proj="$CLAUDE_CONFIG_DIR/projects/-code-app"; main="$proj/$S.jsonl"; subs="$proj/$S/subagents"
tasks="$tmp/tmp/claude-501/-code-app/$S/tasks"
mkdir -p "$subs" "$tasks"
tl() { printf '{"type":"user","toolUseResult":{"stdout":"","stderr":"","interrupted":false,"backgroundTaskId":"%s"}}\n' "$1"; }
# main started bdev1 (npm run dev); a fork of main inherited that line and
# started bfk1; subagent aaa (implementor-complex) started bgo1; two
# subagents name btwo.
{ printf '{"type":"user","message":{"content":"hi"}}\n'; tl bdev1; } > "$main"
{ tl bdev1; tl bfk1; } > "$subs/agent-fff.jsonl"
printf '{"agentType":"fork","isFork":true}' > "$subs/agent-fff.meta.json"
{ tl bgo1; tl btwo; } > "$subs/agent-aaa.jsonl"
printf '{"agentType":"implementor-complex","spawnDepth":1}' > "$subs/agent-aaa.meta.json"
tl btwo > "$subs/agent-bbb.jsonl"
printf '{"agentType":"wt-name","customAgentType":"executor","name":"wt-name"}' > "$subs/agent-bbb.meta.json"
# Explore subagent abc works in its own worktree and starts no background task.
printf '{"type":"user"}\n' > "$subs/agent-abc.jsonl"
printf '{"agentType":"Explore"}' > "$subs/agent-abc.meta.json"

# 1. Whose task: main, a subagent (customAgentType wins), fork, ambiguous.
owners="$(_agents_tx_task_owners "$main" bdev1 bgo1 bfk1 btwo bnone 'bad;id' | sort)"
want="$(printf '%s\n' $'bdev1\tmain' $'bfk1\tfork' $'bgo1\timplementor-complex' $'btwo\t-' | sort)"
[[ "$owners" == "$want" ]] || fail "task owners:"$'\n'"$owners"$'\n'"want:"$'\n'"$want"
[[ "$(_agents_tx_agent_type "$subs/agent-bbb.jsonl")" == executor ]] || fail "customAgentType does not win"
[[ "$(_agents_tx_agent_type "$subs/agent-zzz.jsonl")" == - ]] || fail "a subagent without meta has a type"
printf '{"agentType":"bad name\\"x"}' > "$subs/agent-odd.meta.json"
[[ "$(_agents_tx_agent_type "$subs/agent-odd.jsonl")" == - ]] || fail "an odd agentType is kept"
# Hostile names are "-", and so is the task they would own: a tab, a raw
# newline, JSON escapes, a command substitution, a pipe, a space, backquotes,
# a non-ASCII letter (the check is locale-proof). agentType is no plain name
# either, so nothing falls back to a type.
# shellcheck disable=SC2016  # literal $( ) and backquotes, never run
for bad in $'a\tb' $'a\nb' 'a\tb' '$(touch pwned)' 'a|b' 'a b' '`id`' $'caf\xc3\xa9'; do
    printf '{"agentType":"x y","customAgentType":"%s"}' "$bad" > "$subs/agent-evl.meta.json"
    t="$(_agents_tx_agent_type "$subs/agent-evl.jsonl")"
    [[ "$t" == - ]] || fail "hostile customAgentType $bad: $t"
done
# shellcheck disable=SC2016
printf '{"agentType":"$(id)|x"}' > "$subs/agent-evl.meta.json"; tl bevl > "$subs/agent-evl.jsonl"
[[ "$(_agents_tx_task_owners "$main" bevl)" == $'bevl\t-' ]] || fail "a hostile type names a task's owner: $(_agents_tx_task_owners "$main" bevl)"
rm -f "$subs/agent-evl.jsonl" "$subs/agent-evl.meta.json"
[[ ! -e pwned ]] || fail "a type was run"
[[ "$(_agents_tx_main_of "$tasks/bgo1.output")" == "$main" ]] || fail "main transcript of a task output: $(_agents_tx_main_of "$tasks/bgo1.output")"
! _agents_tx_main_of /tmp/x.log >/dev/null || fail "a non-task path has a transcript"
pass "transcripts: a task's owner is main, a subagent's type (customAgentType first), fork, or - when ambiguous or not a plain name"

# --- The process table ----------------------------------------------------------
# claude 300 in ~/code/app runs: go test (301, a background task of subagent
# aaa, with a test binary), two identical pnpm test (310, 311: dup), npm run dev
# (330, main's background task), and, briefly, make build (320, in subagent
# abc's worktree). codex 400 runs cargo build (401). 500 is a stale MCP helper.
agents_snapshot() { cat "$tmp/snap"; }
_agents_keep_pids() { :; }
_agents_listeners() { :; }
_agents_cwds() {   # [--stdout] PID...: from FIX_CWD / FIX_OUT ("pid path" lines)
    local s="" p c o
    [[ "${1:-}" == --stdout ]] && { s=1; shift; }
    for p in "$@"; do
        c="$(printf '%s\n' "$FIX_CWD" | awk -v p="$p" '$1 == p { print $2 }')"
        o="$(printf '%s\n' "$FIX_OUT" | awk -v p="$p" '$1 == p { print $2 }')"
        if [[ -n "$s" ]]; then
            [[ -z "$c" ]] || printf '%s\t%s\tcwd\n' "$p" "$c"
            [[ -z "$o" ]] || printf '%s\t%s\t1\n' "$p" "$o"
        else
            [[ -z "$c" ]] || printf '%s\t%s\n' "$p" "$c"
        fi
    done
}
APP=/Users/NAME/code/app
FIX_CWD="$(printf '%s\n' "300 $APP" "301 $APP" "310 $APP" "311 $APP" "330 $APP" "320 $APP/.claude/worktrees/agent-abc" \
    "400 /Users/NAME/code/svc" "401 /Users/NAME/code/svc" "500 $APP")"
FIX_OUT="$(printf '%s\n' "301 $tasks/bgo1.output" "330 $tasks/bdev1.output" "320 $tasks/bfg1.output" \
    "310 $tasks/bt1.output" "311 $tasks/bt2.output" "300 /dev/ttys001" "401 pipe:[77]")"
base() {   # the processes every snapshot has, at age offset $1
    pl 1 0 0 999999 20000 08:00:00 /sbin/launchd
    pl 290 1 0 99999 3000 04:00:00 -zsh
    pl 300 290 $((60 + $1 / 10)) $((3600 + $1)) 600000 08:00:00 claude
    pl 400 290 30 $((1800 + $1)) 300000 08:30:00 codex
}
# feed: what a menu refresh does (agents tsv runs agents_collect with _AGENTS_FEED=1).
feed() { _AGENTS_FEED=1 agents_collect >/dev/null; }
row() { awk -F '\t' -v c="$1" '$7 == c' "$AGENTS_DATA_DIR/runs.tsv"; }
col() { printf '%s\n' "$1" | cut -f"$2"; }

# S0 at T0: the baseline sample. go test is 300 s old.
at 0
{
    base 0
    pl 301 300 1 300 3000 08:55:00 "$(cc 'go test ./...')"
    pl 302 301 20 290 180000 08:55:10 "/tmp/go-build1/b001/app.test -test.v"
    pl 310 300 1 100 3000 08:58:20 "$(cc 'pnpm test')"
    pl 311 300 1 100 3000 08:58:20 "$(cc 'pnpm test')"
    pl 330 300 2 200 9000 08:56:40 "$(cc 'npm run dev')"
    pl 401 400 2 60 3000 08:59:00 "bash -lc 'cargo build'"
    pl 500 1 1 3000 50000 08:10:00 "npx -y some-mcp"
} > "$tmp/snap"
agents_sample || fail "S0 failed"
[[ ! -s "$AGENTS_DATA_DIR/runs.tsv" ]] || fail "S0 finished runs: $(cat "$AGENTS_DATA_DIR/runs.tsv")"
st="$AGENTS_DATA_DIR/runs.state"
[[ "$(grep -c $'^run\t' "$st")" == 6 ]] || fail "S0 ledger runs:"$'\n'"$(cat "$st")"
grep -q $'^run\t301@Wed_Oct_14_08:55:00_2026\t'$((T0 - 300))$'\ttest\tapp\tclaude:300\tgo\t183000\t0\t'"$T0"$'\t-\t'"$tasks/bgo1.output"'$' "$st" \
    || fail "go test's ledger line:"$'\n'"$(grep 301@ "$st")"
grep -q $'^run\t310@Wed_Oct_14_08:58:20_2026\t.*\tpnpm\t3000\t1\t' "$st" || fail "two identical pnpm test are not dup"
grep -q $'^run\t401@Wed_Oct_14_08:59:00_2026\t.*\tbuild\tsvc\tcodex:400\tcargo\t3000\t0\t'"$T0"$'\t-\t-$' "$st" || fail "codex run: $(grep 401@ "$st")"
grep -q $'^run\t500@Wed_Oct_14_08:10:00_2026\t.*\tmcp\tapp\t-\tnpx\t50000\t0\t' "$st" || fail "stale run: $(grep 500@ "$st")"
grep -q $'^proc\t301@Wed_Oct_14_08:55:00_2026\t302@Wed_Oct_14_08:55:10_2026\t20$' "$st" || fail "per-process CPU of a run"
pass "ledger: tool commands and stale trees by pid@start, with job, project, session, name, tree RSS, dup and output file"

# F1 at T0+10: go test compiles (303); make build (320, 321) has started.
at 10
{
    base 10
    pl 301 300 1 310 3000 08:55:00 "$(cc 'go test ./...')"
    pl 302 301 40 300 190000 08:55:10 "/tmp/go-build1/b001/app.test -test.v"
    pl 303 301 5 4 80000 08:59:56 "/usr/local/go/pkg/tool/compile -o /tmp/x.a"
    pl 310 300 1 110 3000 08:58:20 "$(cc 'pnpm test')"
    pl 311 300 1 110 3000 08:58:20 "$(cc 'pnpm test')"
    pl 320 300 3 5 4000 09:00:05 "$(cc 'make build')"
    pl 321 320 6 5 70000 09:00:05 "cc -c x.c"
    pl 330 300 2 210 9000 08:56:40 "$(cc 'npm run dev')"
    pl 401 400 4 70 3000 08:59:00 "bash -lc 'cargo build'"
    pl 500 1 1 3010 50000 08:10:00 "npx -y some-mcp"
} > "$tmp/snap"
feed
[[ -n "$(ls "$AGENTS_RUN_DIR/runs.feed")" ]] || fail "a menu refresh fed nothing"
# F2 at T0+20: make build and the compile step are gone; go test's binary at 60 s.
at 20
{
    base 20
    pl 301 300 1 320 3000 08:55:00 "$(cc 'go test ./...')"
    pl 302 301 60 310 200000 08:55:10 "/tmp/go-build1/b001/app.test -test.v"
    pl 310 300 1 120 3000 08:58:20 "$(cc 'pnpm test')"
    pl 311 300 1 120 3000 08:58:20 "$(cc 'pnpm test')"
    pl 330 300 2 220 9000 08:56:40 "$(cc 'npm run dev')"
    pl 401 400 5 80 3000 08:59:00 "bash -lc 'cargo build'"
    pl 500 1 1 3020 50000 08:10:00 "npx -y some-mcp"
} > "$tmp/snap"
feed
# Then: go test ends at T0+30 with exit 1; agents stops 311 at T0+25 and reaps
# 500 at T0+33; npm run dev exits 0 at T0+40; cargo build ends on its own.
printf 'ok\nFAIL\n[exited with code 1]\n' > "$tasks/bgo1.output"
printf 'ready\n[exited with code 0]\n' > "$tasks/bdev1.output"
printf 'ok\n' > "$tasks/bt1.output"
touch -t "$(TZ=UTC command date -r $((T0 + 30)) +%Y%m%d%H%M.%S 2>/dev/null || TZ=UTC command date -d "@$((T0 + 30))" +%Y%m%d%H%M.%S)" "$tasks/bgo1.output"
touch -t "$(TZ=UTC command date -r $((T0 + 40)) +%Y%m%d%H%M.%S 2>/dev/null || TZ=UTC command date -d "@$((T0 + 40))" +%Y%m%d%H%M.%S)" "$tasks/bdev1.output"
printf '%s\tkill\tmanual\t311\tpnpm\tapp\tclaude:300\n%s\treap\tstale\t500\tnpx\tapp\t-\n%s\tkill\tmanual\t401\tbash\tsvc\tcodex:400\n' \
    $((T0 + 25)) $((T0 + 33)) $((T0 - 600)) > "$AGENTS_DATA_DIR/events.tsv"
# S1 at T0+60: pid 301 now names another process (git status); 310 runs on.
at 60
{
    base 60
    pl 301 300 0 3 3000 09:00:57 "$(cc 'git status')"
    pl 310 300 2 160 3000 08:58:20 "$(cc 'pnpm test')"
} > "$tmp/snap"
agents_sample || fail "S1 failed"
[[ -z "$(ls "$AGENTS_RUN_DIR/runs.feed")" ]] || fail "the sample left the feed it read"
[[ "$(wc -l < "$AGENTS_DATA_DIR/runs.tsv" | tr -d ' ')" == 6 ]] || fail "S1 rows:"$'\n'"$(cat "$AGENTS_DATA_DIR/runs.tsv")"
# end start job project session agent cmd duration cpu peak exit dup cleaned
r="$(row go)"
[[ "$r" == "$((T0 + 30))"$'\t'"$((T0 - 300))"$'\ttest\tapp\tclaude:300\timplementor-complex\tgo\t330\t66\t273000\t1\t0\t0' ]] \
    || fail "go test row: $r"
pass "a run's end: its task output's mtime; exit code from [exited with code N]; agent from the transcript that started the task"
pass "a run's CPU: every process ever seen in it at its largest (a compile step seen once by the menu counts)"
r="$(row make)"
[[ "$r" == "$((T0 + 10))"$'\t'"$((T0 + 5))"$'\tbuild\tapp\tclaude:300\tExplore\tmake\t5\t9\t74000\t-\t0\t0' ]] || fail "make build row: $r"
pass "sub-minute run: seen only by a menu refresh, recorded with its CPU; agent from its worktree (agent-ID) without an output file"
r="$(row npm)"
[[ "$(col "$r" 1)/$(col "$r" 6)/$(col "$r" 11)" == "$((T0 + 40))/main/0" ]] || fail "npm run dev row: $r"
pass "a main-conversation background task is main's (a fork's copy of the line does not count)"
r="$(row pnpm)"
[[ "$(col "$r" 1)/$(col "$r" 6)/$(col "$r" 11)/$(col "$r" 12)/$(col "$r" 13)" == "$((T0 + 25))/-/-/1/1" ]] || fail "stopped pnpm test row: $r"
r="$(row npx)"
[[ "$(col "$r" 1)/$(col "$r" 5)/$(col "$r" 13)/$(col "$r" 3)" == "$((T0 + 33))/-/1/mcp" ]] || fail "reaped stale row: $r"
r="$(row cargo)"
[[ "$(col "$r" 1)/$(col "$r" 5)/$(col "$r" 6)/$(col "$r" 11)/$(col "$r" 13)" == "$((T0 + 20))/codex:400/-/-/0" ]] || fail "codex row (an old kill of its pid is not its end): $r"
pass "cleaned: a kill or reap logged for its pid within seconds of its end; an old event is not; dup kept from any snapshot"
grep -q $'^run\t301@Wed_Oct_14_09:00:57_2026\t.*\tgit\t' "$st" || fail "a reused pid is not a new run: $(grep 301@ "$st")"
grep -q $'^run\t310@' "$st" || fail "a live run left the ledger"
[[ "$(grep -c $'^done\t' "$st")" == 6 ]] || fail "finished runs not remembered: $(grep '^done' "$st")"
pass "pid reuse: a new start time is a new run; the finished one keeps its row"
# History: the processes that ended between samples count up to the last refresh.
hist="$(awk -F '\t' -v t=$((T0 + 60)) '$1 == t { print $2 "/" $3 "/" $4 "/" $5 }' "$AGENTS_DATA_DIR/history.tsv" | sort | tr '\n' ' ')"
[[ "$hist" == *"build/app/claude/9 "* && "$hist" == *"test/app/claude/46 "* ]] || fail "history with the menu's feed: $hist"
pass "history: a command's process that ended between samples counts up to the last menu refresh (make build 9 s; go test 45 s more)"

# S2 at T0+120: a late feed file still names make build: never a second row.
at 120
mkdir -p "$AGENTS_RUN_DIR/runs.feed"
printf 'run\t%s\t320@Wed_Oct_14_09:00:05_2026\t%s\tbuild\tapp\tclaude:300\tmake\t4000\t0\t-\t-\n' $((T0 + 12)) $((T0 + 5)) > "$AGENTS_RUN_DIR/runs.feed/$((T0 + 12)).1"
printf 'run\t%s\t999@Wed_Oct_14_09:01:00_2026\t%s\tother\tapp\tclaude:300\tls\t1000\t0\t-\t-\n' $((T0 + 200)) $((T0 + 199)) > "$AGENTS_RUN_DIR/runs.feed/$((T0 + 200)).1"
agents_sample || fail "S2 failed"
[[ "$(row make | wc -l | tr -d ' ')" == 1 ]] || fail "a late feed reopened a finished run"
[[ -e "$AGENTS_RUN_DIR/runs.feed/$((T0 + 200)).1" ]] || fail "a feed newer than the sample was read"
grep -q $'^run\t999@' "$st" && fail "a feed newer than the sample was folded in"
pass "a finished run is never reopened by a late feed; a feed newer than the sample waits for the next one"

# 2. agents runs: a table, newest first, and JSON.
out="$(agents_runs --since 1h)"
want="$(printf '%s\n' \
    'Runs ended in the last 1h: 6 · 1m24s CPU · 2 stopped by agents · newest first' '' \
    'ENDED           TOOK    CPU  PEAK  EXIT  PROJECT  SESSION     AGENT                CMD    JOB     FLAGS' \
    'Oct 14 00:00   4m00s     2s    8M     0  app      claude:300  main                 npm    server  -' \
    'Oct 14 00:00  50m33s     1s   48M     -  app      -           -                    npx    mcp     cleaned' \
    'Oct 14 00:00   5m30s  1m06s  266M     1  app      claude:300  implementor-complex  go     test    -' \
    'Oct 14 00:00   2m05s     1s    2M     -  app      claude:300  -                    pnpm   test    dup,cleaned' \
    'Oct 14 00:00   1m20s     5s    2M     -  svc      codex:400   -                    cargo  build   -' \
    'Oct 14 00:00      5s     9s   72M     -  app      claude:300  Explore              make   build   -')"
[[ "$out" == "$want" ]] || fail "agents runs:"$'\n'"$out"$'\n'"want:"$'\n'"$want"
json="$(agents_runs --since 1h --json)"
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -e '.schema_version == 1 and .window == "1h" and .until == 1760400120 and (.runs | length) == 6' >/dev/null || fail "runs json: $json"
    printf '%s' "$json" | jq -e '[.runs[] | select(.cmd == "go")][0] == {"end":1760400030,"start":1760399700,"job":"test","project":"app","session":"claude:300","agent":"implementor-complex","cmd":"go","duration_s":330,"cpu_s":66,"peak_rss_kib":273000,"exit":1,"dup":false,"cleaned":false}' >/dev/null \
        || fail "runs json go: $(printf '%s' "$json" | jq -c '.runs[] | select(.cmd == "go")')"
    printf '%s' "$json" | jq -e '[.runs[] | select(.cmd == "npx")][0] | .session == null and .agent == null and .exit == null and .cleaned' >/dev/null || fail "runs json nulls"
    pass "agents runs --json: one object, - as null, booleans for dup and cleaned (checked with jq)"
else
    [[ "$json" == '{"schema_version":1,"since":'*'"window":"1h"'* ]] || fail "runs json: $json"
    pass "agents runs --json (jq not installed: shape only)"
fi
[[ "$(agents_runs --since today)" == "Runs ended today: 6 "* ]] || fail "--since today"
rc=0; agents_runs --since 3x 2>/dev/null || rc=$?; [[ $rc == 2 ]] || fail "bad --since accepted"
rc=0; agents_runs --bogus 2>/dev/null || rc=$?; [[ $rc == 2 ]] || fail "unknown option accepted"
[[ "$(AGENTS_DATA_DIR="$tmp/none" agents_runs)" == "no runs recorded yet:"* ]] || fail "runs without a ledger"
[[ "$(at 99999; agents_runs --since 1h)" == "no runs ended in the last 1h" ]] || fail "runs in an empty window"
[[ "$(agents_main runs --since 1h | head -1)" == "Runs ended in the last 1h: 6"* ]] || fail "agents runs is not a command"
pass "agents runs: newest first, aligned columns, --since today, bad options refused, friendly lines without data"

# 3. Privacy: the data dir 700, its files 600; the feed's directory 700 (no
# one else can reach the files in it, so they are not chmodded each time).
perm() { if [[ "$(uname)" == Darwin ]]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }
for f in runs.tsv runs.state; do [[ "$(perm "$AGENTS_DATA_DIR/$f")" == 600 ]] || fail "$f mode $(perm "$AGENTS_DATA_DIR/$f")"; done
fd="$AGENTS_RUN_DIR/runs.feed"
rm -rf "$fd"; at 130; feed
[[ "$(perm "$fd")" == 700 ]] || fail "feed dir mode $(perm "$fd")"
[[ "$(ls "$fd")" == "$((T0 + 130)).$$" ]] || fail "feed file name: $(ls "$fd")"
! grep -qE 'pnpm test|git status' "$fd"/* || fail "the feed holds a command line"
# The menu's own call: agents tsv feeds the spool (the system probes stubbed).
(
    agents_system() { printf '1.00\t8\t50\tnormal\t-\t-\n'; }
    agents_thermal_level() { :; }; agents_powermode() { echo normal; }
    _agents_awake_prime() { :; }; _agents_awake_now() { return 1; }
    agents_lid_state() { return 1; }; agents_lid_stale() { return 1; }
    rm -rf "$fd"; at 135
    agents_tsv > "$tmp/tsv.out" || fail "agents tsv failed"
    grep -q $'^hist\t' "$tmp/tsv.out" || fail "agents tsv output: $(cat "$tmp/tsv.out")"
    grep -q $'^run\t'$((T0 + 135))$'\t310@' "$fd/$((T0 + 135)).$$" || fail "agents tsv fed nothing"
)
! grep -qE 'pnpm test|go test|/Users/NAME' "$AGENTS_DATA_DIR/runs.tsv" || fail "runs.tsv holds a command line or a path"
pass "private: runs.tsv and runs.state 600, the feed agents tsv writes in a 700 directory; names only, never arguments or paths"

# 4. The feed stops at 64 waiting refreshes; nothing is fed or sampled with history off.
rm -rf "$fd"; mkdir -p "$fd"
for i in $(seq 1 64); do : > "$fd/$((T0 + i)).$i"; done
at 140; feed
n=0; for f in "$fd"/*; do n=$((n + 1)); done; [[ $n == 64 ]] || fail "the feed grew past 64 files: $n"
rm -rf "$fd"
(
    AGENTS_HISTORY=0 AGENTS_DATA_DIR="$tmp/off"
    feed; agents_sample
    [[ ! -e "$fd" && ! -e "$tmp/off" ]] || fail "AGENTS_HISTORY=0 fed or sampled"
    [[ "$(agents_runs)" == "history is off (AGENTS_HISTORY=0): no runs are recorded" ]] || fail "runs with history off: $(agents_runs)"
)
# With no tool command or stale tree, a refresh has nothing to feed: no awk, no file.
( _agents_runs_observe() { echo "observe called" >&2; }
  { base 150; } > "$tmp/snap"; at 150
  [[ -z "$(feed 2>&1)" && ! -e "$fd" ]] ) || fail "an idle refresh fed the spool"
# A sample with no run alive still writes its (empty) state, quietly.
( AGENTS_DATA_DIR="$tmp/idle"; { base 150; } > "$tmp/snap"; at 150
  err="$(agents_sample 2>&1)" && [[ -z "$err" && -f "$AGENTS_DATA_DIR/runs.state" && ! -s "$AGENTS_DATA_DIR/runs.state" ]] ) \
    || fail "a sample with no run alive: no runs.state, or it complained"
pass "the feed is bounded (64 refreshes); an idle refresh feeds nothing; AGENTS_HISTORY=0 feeds, samples and records nothing"

# 4b. A ledger that fails (runs.state.new can't be written) never makes the
# history count an interval twice: sample.state and today.tsv move on, the feed
# the history read is gone, runs.state stays as it was.
(
    AGENTS_DATA_DIR="$tmp/lfail" AGENTS_RUN_DIR="$tmp/lfailrun"
    snap() { { base "$1"; pl 301 300 1 "$((300 + $1))" 3000 08:55:00 "$(cc 'go test ./...')"
               pl 302 301 "$2" "$((290 + $1))" 180000 08:55:10 "/tmp/go-build1/b001/app.test -test.v"; } > "$tmp/snap"; }
    t302() { awk -F '\t' '$2 == "test" { s += $5 } END { print s + 0 }' "$AGENTS_DATA_DIR/history.tsv"; }
    at 0; snap 0 10; agents_sample || fail "ledger failure: S0"
    cp "$AGENTS_DATA_DIR/runs.state" "$tmp/runs.state.s0"
    mkdir "$AGENTS_DATA_DIR/runs.state.new"   # the ledger's awk can't write it
    at 10; snap 10 20; feed
    at 60; snap 60 30
    err="$(agents_sample 2>&1)" || fail "ledger failure: S1 failed: $err"
    [[ "$err" == *"run ledger was not updated"* ]] || fail "ledger failure: S1 said nothing: $err"
    cmp -s "$AGENTS_DATA_DIR/runs.state" "$tmp/runs.state.s0" || fail "ledger failure: runs.state changed"
    [[ "$(sed -n 1p "$AGENTS_DATA_DIR/sample.state")" == $((T0 + 60)) ]] || fail "ledger failure: sample.state left stale"
    [[ -z "$(ls "$AGENTS_RUN_DIR/runs.feed")" ]] || fail "ledger failure: the feed the history read is still there"
    [[ "$(t302)" == 20 ]] || fail "ledger failure: S1 test CPU $(t302), want 20"
    at 120; snap 120 40; agents_sample 2>/dev/null || fail "ledger failure: S2 failed"
    [[ "$(t302)" == 30 ]] || fail "ledger failure: two samples counted test CPU $(t302), want 30 (no interval twice)"
)
pass "a failing run ledger leaves the history committed: two samples never count an interval twice"

# 4c. A project directory named with ESC and BEL: no control character reaches
# history, the ledger, agents runs, agents report or the menu's insight.
(
    AGENTS_DATA_DIR="$tmp/ctl" AGENTS_RUN_DIR="$tmp/ctlrun"
    evil=$'/Users/NAME/code/ev\033[2J\033]0;x\007il'
    FIX_CWD="$(printf '%s\n' "300 $evil" "301 $evil")"
    at 0
    { base 0; pl 301 300 1 300 3000 08:55:00 "$(cc 'go test ./...')"
      pl 302 301 20 290 180000 08:55:10 "/tmp/go-build1/b001/app.test -test.v"; } > "$tmp/snap"
    agents_sample || fail "control characters: S0"
    at 60; { base 60; } > "$tmp/snap"
    agents_sample || fail "control characters: S1"
    [[ "$(cut -f4 "$AGENTS_DATA_DIR/runs.tsv")" == "ev[2J]0;xil" ]] || fail "control characters: runs.tsv project $(cut -f4 "$AGENTS_DATA_DIR/runs.tsv" | od -c | head -2)"
    {
        cat "$AGENTS_DATA_DIR/history.tsv" "$AGENTS_DATA_DIR/runs.tsv" "$AGENTS_DATA_DIR/insight.txt"
        agents_runs --since 1h; agents_runs --since 1h --json
        for v in summary runs waste trends agents; do agents_report --view "$v" --since 24h; agents_report --view "$v" --since 24h --json; done
    } > "$tmp/ctl.out" 2>&1
    grep -q 'ev\[2J\]0;xil' "$tmp/ctl.out" || fail "control characters: the project is missing from the output"
    ! LC_ALL=C tr -d '\t\n' < "$tmp/ctl.out" | LC_ALL=C grep -q '[[:cntrl:]]' \
        || fail "control characters reached the output: $(LC_ALL=C grep -n '[[:cntrl:]]' "$tmp/ctl.out" | head -3 | od -c | head -4)"
)
pass "a project named with ESC and BEL: history, runs.tsv, agents runs, agents report and insight.txt hold no control character"

# 5. Prune: runs.tsv with history, by end_epoch.
pd="$tmp/prune"; mkdir -p "$pd"
old=$((T0 - 31 * 86400)) new=$((T0 - 86400))
printf '%s\t1\ttest\tapp\t-\t-\tgo\t1\t1\t1\t-\t0\t0\n%s\t1\ttest\tapp\t-\t-\tgo\t1\t1\t1\t-\t0\t0\n' "$old" "$new" > "$pd/runs.tsv"
( AGENTS_DATA_DIR="$pd"; at 0; _agents_history_prune "$FAKE_NOW" 2025-10-14 )
[[ "$(cut -f1 "$pd/runs.tsv")" == "$new" ]] || fail "runs prune: $(cat "$pd/runs.tsv")"
pass "prune: runs.tsv older than AGENTS_HISTORY_DAYS goes with history"

# 6. Live smoke test: a real sample and a real feed into temp dirs, where ps works.
unset -f agents_snapshot _agents_keep_pids _agents_cwds _agents_listeners date
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    AGENTS_DATA_DIR="$tmp/live" AGENTS_RUN_DIR="$tmp/liverun" bash "$REPO_DIR/bin/agents" tsv >/dev/null || fail "live tsv failed"
    AGENTS_DATA_DIR="$tmp/live" AGENTS_RUN_DIR="$tmp/liverun" bash "$REPO_DIR/bin/agents" sample || fail "live sample failed"
    [[ -f "$tmp/live/runs.state" ]] || fail "live sample wrote no ledger"
    AGENTS_DATA_DIR="$tmp/live" bash "$REPO_DIR/bin/agents" runs >/dev/null || fail "live runs failed"
    pass "live: agents tsv feeds, agents sample keeps the ledger, agents runs reads it"
else
    echo "SKIP: ps unavailable here (sandbox?): live run ledger not run"
fi

echo "All agents runs tests passed."
