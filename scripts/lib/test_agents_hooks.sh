#!/bin/bash
# Unit tests for `agents hook subagent-stop|session-end` (bin/agents), the
# Claude Code cleanup hooks shipped in configs/claude/settings.json.
# Run: bash scripts/lib/test_agents_hooks.sh  -> exit 0 on pass.
#
# Synthetic transcripts and a fixture process table: nothing is signalled
# (the signal step is stubbed) until the last test, which starts its own
# throwaway processes and stops only those. It is skipped where ps can't
# report start times (a sandbox, BusyBox).

# Tests change PATH and settings inside ( … ) on purpose.
# shellcheck disable=SC2030,SC2031,SC2016,SC2329  # literal commands; stubs called indirectly
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
live_pids=""
cleanup() {
    local p
    for p in $live_pids; do kill "$p" 2>/dev/null || true; done
    rm -rf "$tmp"
}
trap cleanup EXIT
export HOME="$tmp/home" NO_COLOR=1
export TUIDEV_TERMINAL_NOTIFIER=""   # never this machine's: a notification is osascript's (a stub)
mkdir -p "$HOME"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed: the hooks need it (and do nothing without it)"
    echo "All agents hook tests passed."
    exit 0
fi

export AGENTS_TESTING=1 AGENTS_SELF=5101 AGENTS_UID=501 AGENTS_CONF="$tmp/none.conf"
export AGENTS_DATA_DIR="$tmp/data" AGENTS_HISTORY=1
# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

# --- Fixtures -----------------------------------------------------------------
# Claude Code's layout: <project>/<session>.jsonl, its subagents in
# <project>/<session>/subagents/agent-<id>.jsonl, task output files in
# <tmp>/<project>/<session>/tasks/<id>.output.
proj="$tmp/projects/-work-myapp"
sess=11111111-2222-3333-4444-555555555555
main="$proj/$sess.jsonl"
subs="$proj/$sess/subagents"
tasks_dir="/private/tmp/claude-501/-work-myapp/$sess/tasks"
mkdir -p "$subs"

# bg TOOL_USE_ID TASK_ID COMMAND — a Bash call started in the background: the
# assistant's tool_use and the tool_result that names the task and its file.
bg() {
    jq -nc --arg id "$1" --arg cmd "$3" \
        '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Bash",
          input: {command: $cmd, description: "x", run_in_background: true}}]}}'
    jq -nc --arg id "$1" --arg t "$2" --arg dir "$tasks_dir" \
        '{type: "user", toolUseResult: {stdout: "", stderr: "", interrupted: false, backgroundTaskId: $t},
          message: {content: [{type: "tool_result", tool_use_id: $id,
            content: ("Command running in background with ID: " + $t + ". Output is being written to: " + $dir + "/" + $t + ".output. You will be notified when it completes.")}]}}'
}
# ended TASK_ID — the notification Claude Code sends when a task ends.
ended() {
    jq -nc --arg t "$1" '{type: "user", message: {content: ("<task-notification>\n<task-id>" + $t + "</task-id>\n<status>completed</status>\n</task-notification>")}}'
}
# handback [true|false] — the subagent's last tool call: SubagentHandback.
handback() {
    jq -nc '{type: "assistant", message: {content: [{type: "text", text: "done"},
        {type: "tool_use", id: "toolu_hb", name: "SubagentHandback", input: {message: "report"}}]}}'
    jq -nc --argjson ok "${1:-true}" '{type: "user", toolUseResult: {success: $ok, message: "Report delivered to your caller."},
        message: {content: [{type: "tool_result", tool_use_id: "toolu_hb", content: "{\"success\":true}"}]}}'
}
turn_end() { jq -nc '{type: "assistant", message: {content: [{type: "text", text: "waiting for the tests"}]}}'; }

# Subagent A: seven background commands; a5 has ended; then its report.
{
    bg tu1 a1task001 'F=/tmp/x.log; until grep -q ok $F; do sleep 5; done'
    bg tu2 a2task002 'npm run dev'
    bg tu3 a3task003 'go test ./...'
    bg tu4 a4task004 'pytest -q'
    bg tu5 a5task005 'sleep 999'
    ended a5task005
    bg tu6 a6task006 'cargo build'
    bg tu7 a7task007 'claude -p hi'
    handback true
} > "$subs/agent-aaa.jsonl"
printf '{"agentType":"general-purpose","spawnDepth":1}\n' > "$subs/agent-aaa.meta.json"
# Subagent B: one command, report delivered.
{ bg tu8 b1task001 'make test'; handback true; } > "$subs/agent-bbb.jsonl"
# Subagent C: started a test run and only ended its turn (it waits for it).
{ bg tu9 c1task001 'make test-c'; turn_end; } > "$subs/agent-ccc.jsonl"
# Subagent D: its handback was refused.
{ bg tu10 d1task001 'make test-d'; handback false; } > "$subs/agent-ddd.jsonl"
# Subagent E: a lint run whose process already ended (no notification yet);
# the main conversation runs the same command, with a stdout that can't be read.
{ bg tu13 e1task001 'make lint'; handback true; } > "$subs/agent-eee.jsonl"
# Subagent G: no background commands at all.
{ handback true; } > "$subs/agent-ggg.jsonl"
# Fork F of the main conversation: begins with a copy of it (m1's result).
{ bg tu11 m1task001 'tail -f /tmp/app.log'; handback true; } > "$subs/agent-fff.jsonl"
printf '{"agentType":"fork","isFork":true}\n' > "$subs/agent-fff.meta.json"
# The main conversation: a log tail and a polling loop.
{ bg tu11 m1task001 'tail -f /tmp/app.log'; bg tu12 m2task002 'until [ -s /tmp/done ]; do sleep 2; done'; } > "$main"

# The process table: claude 5000 runs the hook (sh 5100, agents 5101) and
# one tool shell per task; claude 6000 is another session.
shell() {   # PID PPID COMMAND: a Claude Code tool shell
    printf '%s %s   501 me  0.0 1000 0:00.00 10:00 Wed Oct 14 09:00:00 2026     /bin/zsh -c source /h/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval %s < /dev/null && pwd -P >| /tmp/claude-501/cwd-x\n' \
        "$1" "$2" "'$3'"
}
proc() {    # PID PPID ARGS
    printf '%s %s   501 me  0.0 1000 0:00.00 10:00 Wed Oct 14 09:00:00 2026     %s\n' "$1" "$2" "$3"
}
SNAP="$(
    proc 4000 1 "-zsh"
    proc 5000 4000 "claude --continue"
    proc 5100 5000 "/bin/sh -c [ -x \"\$HOME/.local/bin/agents\" ] && \"\$HOME/.local/bin/agents\" hook subagent-stop; exit 0"
    proc 5101 5100 "bash /h/.local/bin/agents hook subagent-stop"
    shell 5200 5000 'F=/tmp/x.log; until grep -q ok $F; do sleep 5; done'
    proc 5201 5200 "sleep 5"
    shell 5300 5000 'npm run dev'
    proc 5301 5300 "node /w/node_modules/.bin/vite"
    shell 5400 5000 'make test'
    shell 5500 5000 'tail -f /tmp/app.log'
    shell 5550 5000 'until [ -s /tmp/done ]; do sleep 2; done'
    shell 5600 5000 'go test ./...'
    shell 5700 5000 'pytest -q'
    shell 5701 5000 'pytest -q'
    shell 5800 5000 'sleep 999'
    shell 5900 5000 'make test-c'
    shell 5910 5000 'make test-d'
    shell 5950 5000 'claude -p hi'
    shell 5960 5000 'make lint'
    proc 5951 5950 "claude -p hi"
    proc 6000 4000 "claude"
    shell 6100 6000 'cargo build'
)"
# Each tool shell's stdout. 5600, 5700/5701 and 5960 can't be read; 6100
# belongs to claude 6000 (outside this hook's tree) whatever file it writes.
OUTS="$(
    for t in 5200:a1task001 5300:a2task002 5400:b1task001 5500:m1task001 5550:m2task002 \
             5800:a5task005 5900:c1task001 5910:d1task001 5950:a7task007 6100:a6task006; do
        printf '%s\t%s/%s.output\n' "${t%%:*}" "$tasks_dir" "${t#*:}"
    done
    printf '5100\t/dev/null\n'
)"
agents_snapshot() { printf '%s\n' "$SNAP"; }
_agents_hook_stdouts() {
    local p
    for p in "$@"; do printf '%s\n' "$OUTS" | awk -F '\t' -v p="$p" '$1 == p'; done
}
# Signals are recorded, never sent; everything exits on SIGTERM.
_agents_signal() { echo "$1 $2" >> "$tmp/signals"; }
_agents_alive() { :; }
_agents_cwds() { :; }
_agents_notify() { [[ "${AGENTS_NOTIFY:-false}" != true ]] || { echo "$1" >> "$tmp/notified"; echo "${2:-} ${3:-}" >> "$tmp/notified.target"; }; }

hook_json() {   # EVENT AGENT_ID [REASON]
    jq -nc --arg ev "$1" --arg a "$2" --arg main "$main" --arg sub "$subs/agent-$2.jsonl" --arg r "${3:-}" \
        '{session_id: "'"$sess"'", transcript_path: $main, cwd: "/work/myapp", hook_event_name: $ev,
          permission_mode: "auto", stop_hook_active: false}
         + (if $ev == "SubagentStop" then {agent_id: $a, agent_type: "general-purpose", agent_transcript_path: $sub,
             last_assistant_message: "", background_tasks: [], session_crons: []} else {reason: $r} end)'
}
run_hook() {    # EVENT_ARG HOOK_JSON [ARGS...]: rc in $tmp/rc, stdout in $tmp/out
    local ev="$1" json="$2"; shift 2
    rm -f "$tmp/signals" "$tmp/notified" "$tmp/notified.target"
    set +e
    printf '%s\n' "$json" | agents_main hook "$ev" "$@" > "$tmp/out" 2> "$tmp/err"
    echo $? > "$tmp/rc"
    set -e
}
signalled() { [[ -f "$tmp/signals" ]] && sort -n -k2 "$tmp/signals" | awk '{ print $2 }' | tr '\n' ' '; }

# --- Parsing ------------------------------------------------------------------
t="$(_agents_hook_tasks "$subs/agent-aaa.jsonl" | cut -f1 | tr '\n' ' ')"
[[ "$t" == "a1task001 a2task002 a3task003 a4task004 a6task006 a7task007 " ]] || fail "tasks: $t"
[[ "$(_agents_hook_tasks "$subs/agent-aaa.jsonl" | awk -F '\t' '$1 == "a2task002" { print $2 }')" == "$tasks_dir/a2task002.output" ]] \
    || fail "output path not read from the tool result"
_agents_hook_final "$subs/agent-aaa.jsonl" || fail "a delivered report not final"
! _agents_hook_final "$subs/agent-ccc.jsonl" || fail "a turn end counted as final"
! _agents_hook_final "$subs/agent-ddd.jsonl" || fail "a refused handback counted as final"
mids="$(_agents_tx_started "$main" | _agents_tx_ids)"
[[ "$(printf '%s\n' "$mids" | tr '\n' ' ')" == "m1task001 m2task002 " ]] || fail "main task ids: $mids"
[[ -z "$(_agents_hook_own_tasks "$subs/agent-fff.jsonl" "$main" all)" ]] || fail "a fork owns the task it inherited"
[[ -z "$(_agents_hook_own_tasks "$subs/agent-fff.jsonl" /nonexistent all "$(_agents_tx_started "$subs/agent-fff.jsonl")" "$mids")" ]] || fail "a fork owns the task it inherited (ids passed in)"
[[ "$(_agents_hook_own_tasks "$subs/agent-bbb.jsonl" "$main" all "$(_agents_tx_started "$subs/agent-bbb.jsonl")" "$mids")" == "b1task001"$'\t'"$tasks_dir/b1task001.output"$'\t'"all" ]] \
    || fail "own tasks: $(_agents_hook_own_tasks "$subs/agent-bbb.jsonl" "$main" all "$(_agents_tx_started "$subs/agent-bbb.jsonl")" "$mids")"
pass "transcripts: background tasks with their files, ended ones left out, final reports, fork inheritance"

# --- subagent-stop ------------------------------------------------------------
run_hook subagent-stop "$(hook_json SubagentStop aaa)" -n
[[ "$(cat "$tmp/rc")" == 0 ]] || fail "dry run rc"
[[ ! -f "$tmp/signals" ]] || fail "a dry run signalled: $(cat "$tmp/signals")"
for p in 5200 5201 5300 5301; do grep -qE "^  $p " "$tmp/out" || fail "dry run misses $p: $(cat "$tmp/out")"; done
for p in 5400 5500 5550 5600 5700 5701 5800 5900 5910 5950 5951 5960 6000 6100 5000 5100 5101; do
    ! grep -qE "^  $p " "$tmp/out" || fail "dry run would stop $p: $(cat "$tmp/out")"
done
grep -q "task a1task001: wait-loop, pid 5200 (matched by output)" "$tmp/out" || fail "wait loop not matched by its file: $(cat "$tmp/out")"
! grep -q "a3task003" "$tmp/out" || fail "a task whose stdout can't be read was matched (by its command?): $(cat "$tmp/out")"
grep -q "refuse 5950: it hosts a session" "$tmp/out" || fail "a tool shell running a nested claude not refused: $(cat "$tmp/out")"
grep -q "dry run: would send SIGTERM" "$tmp/out" || fail "no dry-run summary"
[[ ! -e "$AGENTS_DATA_DIR/events.tsv" ]] || fail "a dry run logged events"
pass "subagent-stop -n: only that subagent's live tasks, by their output file; not one whose stdout can't be read, another subagent's, the main session's, ended tasks, nested sessions or another claude's"

( _AGENTS_HOOK_DRY=true run_hook subagent-stop "$(hook_json SubagentStop aaa)"
  { grep -q "dry run: would send SIGTERM" "$tmp/out" && [[ ! -f "$tmp/signals" ]]; } || fail "AGENTS_DRY_RUN=true is not a dry run" )
# The variable is read when agents starts (agents_main resets AGENTS_DRY_RUN):
# a separate process, whose explanation goes to stderr; nothing it reads is real.
err="$(hook_json SubagentStop aaa | AGENTS_DRY_RUN=true bash "$REPO_DIR/bin/agents" hook subagent-stop 2>&1 >/dev/null)" \
    || fail "AGENTS_DRY_RUN=true: non-zero exit"
[[ "$err" == *"agents hook:"* ]] || fail "AGENTS_DRY_RUN=true from the environment is not a dry run: $err"
pass "AGENTS_DRY_RUN=true is a dry run too"

# An agent type that is not a plain name never reaches the output.
run_hook subagent-stop "$(hook_json SubagentStop aaa | jq -c '.agent_type = "x|$(touch y)\tz\nw"')" -n
{ grep -q "^agents hook: background commands a subagent left running:" "$tmp/out" && ! grep -q 'touch' "$tmp/out"; } \
    || fail "a hostile agent_type reached the output: $(cat "$tmp/out")"
pass "a hook's agent_type is shown only when it is a plain name"

run_hook subagent-stop "$(hook_json SubagentStop aaa)"
[[ "$(cat "$tmp/rc")" == 0 && ! -s "$tmp/out" ]] || fail "a real run is not quiet: rc $(cat "$tmp/rc"), $(cat "$tmp/out")"
[[ "$(signalled)" == "5200 5201 5300 5301 " ]] || fail "signalled: $(signalled)"
[[ "$(awk '{ print $1 }' "$tmp/signals" | sort -u)" == TERM ]] || fail "not SIGTERM: $(cat "$tmp/signals")"
ev="$(cut -f2- "$AGENTS_DATA_DIR/events.tsv" | sort)"
[[ "$ev" == "$(printf 'hook\tsubagent-end\t5200\twait-loop\tmyapp\tclaude:5000\nhook\tsubagent-end\t5300\tnpm\tmyapp\tclaude:5000')" ]] \
    || fail "events: $ev"
[[ "$(cat "$tmp/notified")" == "Stopped 2 background commands a subagent (general-purpose) left running in myapp" ]] \
    || fail "notification: $(cat "$tmp/notified" 2>/dev/null)"
[[ "$(cat "$tmp/notified.target")" =~ ^5000@[A-Za-z]{3}_[A-Za-z]{3}_[0-9]+_[0-9:]{8}_[0-9]{4}\ -$ ]] \
    || fail "the notification does not jump to the session: $(cat "$tmp/notified.target" 2>/dev/null)"
pass "subagent-stop: SIGTERMs those trees, quietly; one event per task (hook subagent-end, session claude:PID), one notification that jumps to the session"

rm -rf "$AGENTS_DATA_DIR"
AGENTS_HISTORY=0 run_hook subagent-stop "$(hook_json SubagentStop aaa)"
[[ -n "$(signalled)" && ! -e "$AGENTS_DATA_DIR" ]] || fail "AGENTS_HISTORY=0 still logged"
pass "AGENTS_HISTORY=0: stops them, logs nothing"

run_hook subagent-stop "$(hook_json SubagentStop bbb)"
[[ "$(signalled)" == "5400 " ]] || fail "subagent B: $(signalled)"
run_hook subagent-stop "$(hook_json SubagentStop ccc)" -n
[[ -z "$(signalled)" && "$(cat "$tmp/err")" == *"has not handed back a final report"* ]] || fail "a waiting subagent: $(cat "$tmp/err")"
run_hook subagent-stop "$(hook_json SubagentStop ddd)"
[[ -z "$(signalled)" && ! -s "$tmp/out" ]] || fail "a refused handback: $(signalled)"
run_hook subagent-stop "$(hook_json SubagentStop fff)"
[[ -z "$(signalled)" ]] || fail "a fork stopped the main session's task: $(signalled)"
run_hook subagent-stop "$(hook_json SubagentStop eee)" -n
[[ -z "$(signalled)" && "$(cat "$tmp/err")" == *"none of its background commands still runs"* && "$(cat "$tmp/out")" != *5960* ]] \
    || fail "an ended task matched a sibling running the same command: $(cat "$tmp/out" "$tmp/err")"
run_hook subagent-stop "$(hook_json SubagentStop eee)"
[[ -z "$(signalled)" ]] || fail "an ended task stopped the main conversation's same command: $(signalled)"
run_hook subagent-stop "$(hook_json SubagentStop ggg)" -n
[[ -z "$(signalled)" && "$(cat "$tmp/err")" == *"started no background commands"* ]] || fail "no background commands: $(cat "$tmp/err")"
pass "each subagent stops only its own; none while it waits for its commands, after a refused handback, for what a fork inherited, or for an ended task whose command a sibling runs"

# --- session-end --------------------------------------------------------------
run_hook session-end "$(hook_json SessionEnd - clear)"
[[ "$(signalled)" == "5200 5201 5300 5301 5400 5550 " ]] || fail "session-end clear: $(signalled)"
for r in other prompt_input_exit logout; do
    run_hook session-end "$(hook_json SessionEnd - "$r")"
    [[ -z "$(signalled)" && ! -s "$tmp/out" ]] || fail "session-end $r: $(signalled)"
done
pass "session-end on /clear: the session's polling loops (not its log tail) and its finished subagents' leftovers; nothing at exit"

# --- Budget: a large session ends well inside the hook timeout ------------------------
# A 20 MB main transcript and 30 subagents of 1 MB, each with a live task: the
# main file is read once, the subagents in one pass (not once per subagent).
big="$tmp/big"; mkdir -p "$big/s/subagents"
filler() { awk -v n="$1" 'BEGIN { s = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\""; for (i = 0; i < 40; i++) s = s "lorem ipsum dolor sit amet "; s = s "\"}]}}"; for (i = 0; i < n; i++) print s }'; }
{ filler 18000; bg tuM1 bigmain01 'until [ -s /tmp/x ]; do sleep 2; done'; filler 1000; } > "$big/s.jsonl"
for i in $(seq 1 30); do
    { filler 900; bg "tuS$i" "bigsub$i" 'make test'; handback true; } > "$big/s/subagents/agent-b$i.jsonl"
done
t0="$(date +%s)"
jq -nc --arg m "$big/s.jsonl" '{session_id: "s", transcript_path: $m, cwd: "/work/big", hook_event_name: "SessionEnd", reason: "clear"}' \
    | agents_main hook session-end -n > "$tmp/out" 2> "$tmp/err" || true
[[ $(( $(date +%s) - t0 )) -le 8 ]] || fail "session-end on a 20 MB session with 30 subagents took $(( $(date +%s) - t0 )) s"
[[ "$(cat "$tmp/err")" == *"none of its background commands still runs"* ]] || fail "big session-end: $(cat "$tmp/out" "$tmp/err")"
rm -rf "$big"
pass "budget: session-end on a 20 MB session with 30 subagents stays well inside the hook timeout"

# --- Off switches and bad input: always exit 0, never signal ----------------------
quiet_ok() {    # LABEL
    [[ "$(cat "$tmp/rc")" == 0 ]] || fail "$1: rc $(cat "$tmp/rc")"
    [[ -z "$(signalled)" ]] || fail "$1: signalled $(signalled)"
    [[ ! -s "$tmp/out" ]] || fail "$1: printed $(cat "$tmp/out")"
}
AGENTS_HOOK_REAP=0 run_hook subagent-stop "$(hook_json SubagentStop aaa)"; quiet_ok "AGENTS_HOOK_REAP=0"
run_hook subagent-stop '{"session_id": "x", "agent_transcript_path": '; quiet_ok "malformed JSON"
run_hook subagent-stop 'not json at all'; quiet_ok "not JSON"
run_hook subagent-stop ''; quiet_ok "empty stdin"
run_hook bogus-event "$(hook_json SubagentStop aaa)"; quiet_ok "unknown event"
# shellcheck disable=SC2317,SC2329  # called by the hook under test
( agents_snapshot() { :; }; run_hook subagent-stop "$(hook_json SubagentStop aaa)"; quiet_ok "no process table" )
( SNAP="$(printf '%s\n' "$SNAP" | sed 's/claude --continue/node server.js/')"
  run_hook subagent-stop "$(hook_json SubagentStop aaa)"; quiet_ok "no claude above the hook" )
( AGENTS_EUID=0 run_hook subagent-stop "$(hook_json SubagentStop aaa)"; quiet_ok "as root" )
[[ "$(AGENTS_HOOK_REAP=0 bash "$REPO_DIR/bin/agents" config | grep '^AGENTS_HOOK_REAP=')" == AGENTS_HOOK_REAP=0 ]] || fail "config key"
[[ "$(AGENTS_HOOK_REAP=yes bash "$REPO_DIR/bin/agents" config 2>/dev/null | grep '^AGENTS_HOOK_REAP=')" == AGENTS_HOOK_REAP=1 ]] \
    || fail "a bad AGENTS_HOOK_REAP is not reset to 1"
mkdir -p "$tmp/nojq"
for b in dirname basename cat; do ln -s "$(command -v "$b")" "$tmp/nojq/$b"; done
out="$(printf '%s\n' "$(hook_json SubagentStop aaa)" | PATH="$tmp/nojq" "$BASH" "$REPO_DIR/bin/agents" hook subagent-stop -n 2>"$tmp/nojq.err")" \
    || fail "missing jq: non-zero exit"
[[ -z "$out" && "$(cat "$tmp/nojq.err")" != *"agents hook"* ]] || fail "missing jq: printed $out $(cat "$tmp/nojq.err")"
pass "always exit 0 and silent: AGENTS_HOOK_REAP=0, malformed or empty JSON, unknown event, no ps, no claude, root, no jq"

# --- AGENTS_HOOK_LOG: one line per run, off by default, private, no commands ------
[[ ! -e "$AGENTS_DATA_DIR/hooks.log" ]] || fail "hooks.log written with AGENTS_HOOK_LOG unset"
export AGENTS_HOOK_LOG=1
run_hook subagent-stop "$(hook_json SubagentStop aaa)"
run_hook subagent-stop "$(hook_json SubagentStop ddd)" -n
run_hook subagent-stop '{"hook_event_name": "SubagentStop", "agent_id": "zzz"}'
run_hook session-end "$(hook_json SessionEnd x other)"
unset AGENTS_HOOK_LOG
hl="$(cut -f2- "$AGENTS_DATA_DIR/hooks.log")"
[[ "$(printf '%s\n' "$hl" | sed -n 1p)" == $'subagent-stop\taaa\tyes\t6\t3\tfalse' ]] || fail "hooks.log, handback run: $hl"
[[ "$(printf '%s\n' "$hl" | sed -n 2p)" == $'subagent-stop\tddd\tno\t0\t0\ttrue' ]] || fail "hooks.log, refused handback, dry: $hl"
[[ "$(printf '%s\n' "$hl" | sed -n 3p)" == $'subagent-stop\tzzz\tno\t0\t0\tfalse' ]] || fail "hooks.log, no transcript: $hl"
[[ "$(printf '%s\n' "$hl" | sed -n 4p)" == $'session-end\t-\t-\t0\t0\tfalse' ]] || fail "hooks.log, session end: $hl"
! grep -qE 'sleep|npm|pytest|make' "$AGENTS_DATA_DIR/hooks.log" || fail "hooks.log holds a command line"
case "$(uname)" in Darwin) mode="$(stat -f %Lp "$AGENTS_DATA_DIR/hooks.log")" ;; *) mode="$(stat -c %a "$AGENTS_DATA_DIR/hooks.log")" ;; esac
[[ "$mode" == 600 ]] || fail "hooks.log mode $mode"
[[ "$(AGENTS_HOOK_LOG=yes bash "$REPO_DIR/bin/agents" config 2>/dev/null | grep '^AGENTS_HOOK_LOG=')" == AGENTS_HOOK_LOG=0 ]] || fail "a bad AGENTS_HOOK_LOG is not reset to 0"
pass "AGENTS_HOOK_LOG: off by default; one private line per run with handback, tasks, matches, dry"

# --- Live: a real throwaway task under a fake claude --------------------------------
# A process named claude starts two tool shells (sh -c 'until …'), one writing
# to a task file the transcript names, one a decoy; then runs the hook as its
# child, like Claude Code does. Only the named task's tree may be stopped.
live_ok=false
if ps -o lstart= -p $$ >/dev/null 2>&1 &&{ [[ -d /proc/self/fd ]] || command -v lsof >/dev/null 2>&1; }; then
    live_ok=true
fi
if [[ "$live_ok" == true ]]; then
    L="$tmp/live"; mkdir -p "$L/tasks" "$L/proj/s/subagents" "$L/bin"
    printf '#!/bin/sh\necho "$@" >> "%s/notified"\n' "$L" > "$L/bin/osascript"; chmod +x "$L/bin/osascript"
    tasks_dir="$L/tasks"
    { bg tuL1 livetask01 'until false; do sleep 1; done'; handback true; } > "$L/proj/s/subagents/agent-live.jsonl"
    jq -nc --arg m "$L/proj/s.jsonl" --arg a "$L/proj/s/subagents/agent-live.jsonl" \
        '{session_id: "s", transcript_path: $m, cwd: "/work/live", hook_event_name: "SubagentStop",
          agent_id: "live", agent_type: "Explore", agent_transcript_path: $a}' > "$L/hook.json"
    : > "$L/proj/s.jsonl"
    # shellcheck disable=SC2016  # expanded by the fake claude
    ( cd "$L" && exec -a claude bash -c '
        sh -c "until false; do sleep 1; done" > tasks/livetask01.output 2>&1 &
        echo $! > task.pid
        sh -c "until false; do sleep 1; done" > tasks/decoy0001.output 2>&1 &
        echo $! > decoy.pid
        sleep 0.5
        env -u AGENTS_TESTING -u AGENTS_SELF -u AGENTS_UID PATH="$0/bin:$PATH" AGENTS_GRACE=2 \
            bash "$1" hook subagent-stop < hook.json > hook.out 2>&1
        echo $? > hook.rc
        sleep 60 & echo $! > sleep.pid; wait $!' "$L" "$REPO_DIR/bin/agents" ) </dev/null >/dev/null 2>&1 &
    fake=$!; live_pids="$fake"
    disown "$fake" 2>/dev/null || true
    for _ in $(seq 100); do [[ -s "$L/hook.rc" ]] && break; sleep 0.1; done
    [[ -s "$L/hook.rc" ]] || fail "live: the hook did not finish: $(cat "$L/hook.out" 2>/dev/null)"
    task="$(cat "$L/task.pid")"; decoy="$(cat "$L/decoy.pid")"
    live_pids="$fake $decoy $task $(cat "$L/sleep.pid" 2>/dev/null)"
    [[ "$(cat "$L/hook.rc")" == 0 && ! -s "$L/hook.out" ]] || fail "live: rc $(cat "$L/hook.rc"), output $(cat "$L/hook.out")"
    alive() { kill -0 "$1" 2>/dev/null && [[ "$(ps -o stat= -p "$1" 2>/dev/null)" != Z* ]]; }   # a zombie is gone
    for _ in 1 2 3 4 5 6 7 8 9 10; do alive "$task" || break; sleep 0.1; done
    ! alive "$task" || fail "live: the subagent's loop still runs ($(ps -o pid=,stat=,args= -p "$task"))"
    alive "$decoy" || fail "live: the decoy was stopped"
    alive "$fake" || fail "live: the fake claude was stopped"
    grep -q "Stopped 1 background command a subagent (Explore) left running in live" "$L/notified" \
        || fail "live: notification $(cat "$L/notified" 2>/dev/null)"
    [[ "$(cut -f2-5 "$AGENTS_DATA_DIR/events.tsv" | tail -1)" == "$(printf 'hook\tsubagent-end\t%s\twait-loop' "$task")" ]] \
        || fail "live: event $(tail -1 "$AGENTS_DATA_DIR/events.tsv")"
    for p in $live_pids; do kill "$p" 2>/dev/null || true; done
    pass "live: a real background loop under a fake claude is stopped; its sibling and the claude are not"
else
    echo "SKIP: ps can't report start times here (sandbox? BusyBox?): live hook test not run"
fi

echo "All agents hook tests passed."
