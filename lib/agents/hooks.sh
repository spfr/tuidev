# shellcheck shell=bash
# lib/agents/hooks.sh — Claude Code's cleanup hooks (`agents hook`).
#
# `agents hook subagent-stop|session-end` runs from Claude Code's SubagentStop
# and SessionEnd hooks (configs/claude/settings.json) with the hook's JSON on
# stdin. It stops background commands (the Bash tool's run_in_background) that
# provably belong to the agent that ended and that nothing will read any more:
#   subagent-stop  every background command the subagent started that still
#                  runs, once it has delivered its final report (its last tool
#                  call is a SubagentHandback that went through). A subagent
#                  that ends a turn while its own commands run is waiting for
#                  them: Claude Code resumes it when they end, so they stay.
#   session-end    on /clear and /resume only (at exit Claude Code stops its
#                  background commands itself, and it keeps them across /clear
#                  and /resume on purpose): the session's own polling loops,
#                  which only the cleared conversation waited for, and what its
#                  finished subagents left.
# A task is matched to a live process only by the file its stdout goes to
# (Claude Code's tasks/<id>.output): one whose stdout can't be read is never
# matched (_agents_hook_match). Only direct children of the claude process
# that runs the hook are candidates, and every kill goes through
# agents_kill_tokens (start-time pinned, refusals, SIGTERM then SIGKILL).
# Always exits 0; prints nothing unless it is a dry run.
#
# Uses: config.sh (AGENTS_HOOK_REAP, AGENTS_HOOK_LOG, _AGENTS_HOOK_DRY),
#   util.sh, snapshot.sh, classify.sh (agents_project), kill.sh
#   (agents_kill_tokens), events.sh (agents_event, _agents_data_dir),
#   notify.sh, transcript.sh (the transcript reads);
#   awk/hook_claude.awk, awk/hook_children.awk, awk/hook_match.awk.
# Public: agents_hook.

# _agents_hook_input < HOOK_JSON — one tab-separated line: event session
# transcript agent_id agent_type agent_transcript cwd reason ("-" if absent).
_agents_hook_input() {
    jq -r '[.hook_event_name, .session_id, .transcript_path, .agent_id, .agent_type,
            .agent_transcript_path, .cwd, .reason]
        | map(if type == "string" and . != "" then gsub("[\t\n]"; " ") else "-" end) | join("\t")' 2>/dev/null
}

# Transcripts are read as transcript.sh says (a fixed-string grep first); jq
# runs only for tasks that may still be running.

# _agents_hook_tasks TRANSCRIPT [STARTED] — "id<TAB>path" for each
# background command the transcript's agent started (run_in_background, or
# moved to the background) that it does not show as ended (a task
# notification) or stopped (TaskStop). path: the output file its result
# names, or "-". STARTED: its _agents_tx_started lines, when the caller
# already has them.
_agents_hook_tasks() {
    local f="$1" started open gone
    [[ -f "$f" && -r "$f" ]] || return 0
    if [[ $# -ge 2 ]]; then started="$2"; else started="$(_agents_tx_started "$f")"; fi
    [[ -n "$started" ]] || return 0
    # Ids started and not ended: most tasks end, and then jq never runs.
    gone="$(LC_ALL=C grep -F '<task-id>' "$f" 2>/dev/null | LC_ALL=C grep -oE '<task-id>[A-Za-z0-9_-]+</task-id>' | LC_ALL=C sed -E 's:</?task-id>::g')"
    open="$(printf '%s\n' "$started" | _agents_tx_ids | H_GONE="$gone" LC_ALL=C awk '
        BEGIN { n = split(ENVIRON["H_GONE"], t, "\n"); for (i = 1; i <= n; i++) g[t[i]] = 1 }
        $0 != "" && !($0 in g) && !s[$0]++')"
    [[ -n "$open" ]] || return 0
    gone+=$'\n'"$(LC_ALL=C grep -F 'TaskStop' "$f" 2>/dev/null | LC_ALL=C grep -E '"name": ?"TaskStop"' | jq -r '.message.content[]?
        | select(.type == "tool_use" and .name == "TaskStop") | .input | (.task_id // .shell_id // empty)' 2>/dev/null)"
    printf '%s\n' "$started" | jq -rs --arg gone "$gone" '
        ($gone | split("\n")) as $gone
        | .[] | select(.type == "user" and (.toolUseResult | type) == "object"
                       and (.toolUseResult.backgroundTaskId | type) == "string")
        | .toolUseResult.backgroundTaskId as $id
        | select(($id | test("^[A-Za-z0-9_-]+$")) and ([$gone[] | select(. == $id)] | length) == 0)
        | (.message.content | arrays | .[] | select(.type == "tool_result")) as $r
        | (($r.content | if type == "array" then map(.text? // "") | join(" ") else tostring end)
           | (capture("Output is being written to: (?<p>/[^ ]+?\\.output)") | .p) // "-") as $path
        | [$id, $path] | join("\t")' 2>/dev/null
}

# _agents_hook_final TRANSCRIPT — true when the agent's last tool call is a
# SubagentHandback that went through (no result yet counts: the call ends the
# run); false for a subagent that only ended a turn. The end of the file is
# read first (the last call is there), the whole file only if that has none.
_agents_hook_final() {
    local f="$1" id res last n=1048576
    last="$(tail -c "$n" "$f" 2>/dev/null | LC_ALL=C grep -E '"type": ?"tool_use"' | tail -1)"
    if [[ -z "$last" ]]; then
        n=+1; last="$(LC_ALL=C grep -E '"type": ?"tool_use"' "$f" 2>/dev/null | tail -1)"
    fi
    id="$(printf '%s\n' "$last" | jq -r '[.message.content | arrays | .[] | select(.type == "tool_use")] | last
                 | select(.name == "SubagentHandback") | .id' 2>/dev/null)"
    [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    res="$(tail -c "$n" "$f" 2>/dev/null | LC_ALL=C grep -F "\"$id\"" | LC_ALL=C grep -E '"type": ?"tool_result"' | tail -1 \
        | jq -r 'if ((.toolUseResult | type) == "object" and .toolUseResult.success == false)
                    or ([.message.content | arrays | .[] | select(.type == "tool_result") | .is_error == true] | any)
                 then "no" else "yes" end' 2>/dev/null)"
    [[ "$res" != no ]]
}

# _agents_hook_inherited TRANSCRIPT MAIN [MAIN_IDS] — task ids the agent did
# not start itself: a fork begins with a copy of the conversation it was
# forked from (its parentAgentId's transcript, else MAIN), task results
# included. MAIN_IDS: MAIN's ids, when the caller already has them.
_agents_hook_inherited() {
    local id
    id="$(_agents_tx_meta "${1%.jsonl}.meta.json" parentAgentId)"
    if [[ "$id" =~ ^[A-Za-z0-9_-]+$ && "${1%/*}/agent-$id.jsonl" != "$1" ]]; then
        _agents_tx_started "${1%/*}/agent-$id.jsonl" | _agents_tx_ids
    elif [[ $# -ge 3 ]]; then
        printf '%s\n' "$3"
    elif [[ "$2" != "$1" ]]; then
        _agents_tx_started "$2" | _agents_tx_ids
    fi
}

# _agents_hook_own_tasks TRANSCRIPT MAIN SCOPE [STARTED [MAIN_IDS]] — the
# tasks of an agent that has handed back its final report
# (_agents_hook_final), without the ones it inherited, each line ending in
# SCOPE (all, or wait: polling loops only). Prints nothing, having said why,
# for an agent that has not handed back. STARTED and MAIN_IDS: what the
# caller already read (MAIN is read only when needed and not passed).
_agents_hook_own_tasks() {
    local tasks inh
    if [[ $# -ge 4 ]]; then tasks="$(_agents_hook_tasks "$1" "$4")"; else tasks="$(_agents_hook_tasks "$1")"; fi
    [[ -n "$tasks" ]] || return 0
    if ! _agents_hook_final "$1"; then
        _agents_hook_say "a subagent has not handed back a final report: Claude Code resumes it when its commands end, so they stay"
        return 0
    fi
    if [[ $# -ge 5 ]]; then inh="$(_agents_hook_inherited "$1" "$2" "$5")"; else inh="$(_agents_hook_inherited "$1" "$2")"; fi
    printf '%s\n' "$tasks" | H_INH="$inh" LC_ALL=C awk -F '\t' -v scope="$3" '
        BEGIN { n = split(ENVIRON["H_INH"], t, "\n"); for (i = 1; i <= n; i++) skip[t[i]] = 1 }
        NF >= 2 && !($1 in skip) { print $0 "\t" scope }'
}

# _agents_hook_claude SNAPSHOT — the claude process this hook runs under: the
# nearest ancestor of this process that is a claude agent.
_agents_hook_claude() {
    printf '%s\n' "$1" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc hook_claude" -v self="$AGENTS_SELF"
}

# _agents_hook_children SNAPSHOT CLAUDE — CLAUDE's direct children, without
# this process's own ancestors (the hook's shell).
_agents_hook_children() {
    printf '%s\n' "$1" | _agents_awk "lib_proc hook_children" -v self="$AGENTS_SELF" -v c="$2"
}

# _agents_hook_stdouts PID... — "pid<TAB>path" of each one's stdout (fd 1).
_agents_hook_stdouts() { _agents_proc_paths 1 "$@"; }

# _agents_hook_match SNAPSHOT CLAUDE TASKS STDOUTS — one line per task that
# runs as a direct child of CLAUDE:
#   pid@start <TAB> task id <TAB> output <TAB> name <TAB> wait(0|1)
# TASKS: "id<TAB>path<TAB>scope" lines (the first line for an id wins);
# STDOUTS: _agents_hook_stdouts. A process matches a task only when its
# stdout is the task's output file (the path the result named, else
# tasks/<id>.output). One whose stdout can't be read is never matched, even
# when it runs the task's command: another agent, or the main conversation,
# may run the same one. A scope of wait keeps polling loops only. name:
# "wait-loop", or the command's first word.
_agents_hook_match() {
    printf '%s\n' "$1" | H_TASKS="$3" H_OUTS="$4" AGENTS_NAMES="$AGENTS_NAMES" \
    _agents_awk "lib_proc lib_activity hook_match" -v self="$AGENTS_SELF" -v c="$2" -v me="$AGENTS_UID"
}

# _agents_hook_say TEXT — a line for dry runs only (on stderr, so it never
# mixes with data).
_agents_hook_say() { [[ "$_AGENTS_HOOK_DRY" != true ]] || printf 'agents hook: %s\n' "$1" >&2; }

# _agents_hook_collect EVENT TRANSCRIPT AGENT_TRANSCRIPT REASON — the tasks
# (_agents_hook_match's TASKS) this event may stop. Fails, having said why,
# when the event stops nothing by design.
_agents_hook_collect() {
    local event="$1" main="$2" agent="$3" reason="$4" f
    case "$event" in
        subagent-stop)
            if [[ ! -f "$agent" ]]; then _agents_hook_say "no subagent transcript ($agent): nothing to do"; return 1; fi
            if ! LC_ALL=C grep -qF "$_AGENTS_TX_TASK_KEY" "$agent" 2>/dev/null; then
                _agents_hook_say "the subagent started no background commands"; return 1
            fi
            _agents_hook_own_tasks "$agent" "$main" all ;;
        session-end)
            case "$reason" in
                clear|resume) ;;
                *) _agents_hook_say "session ended ($reason): Claude Code stops its own background commands at exit"; return 1 ;;
            esac
            # The main transcript is read once for its tasks and ids, and one
            # grep reads every subagent's task lines (prefixed with its file).
            local started ids subs=() all sf
            started="$(_agents_tx_started "$main")"
            ids="$(printf '%s\n' "$started" | _agents_tx_ids)"
            _agents_hook_tasks "$main" "$started" | awk '{ print $0 "\twait" }'
            _agents_tx_subagents "$main"
            [[ ${#_AGENTS_TX_SUBS[@]} -gt 0 ]] || return 0
            subs=("${_AGENTS_TX_SUBS[@]}")
            all="$(LC_ALL=C grep -HF "$_AGENTS_TX_TASK_KEY" "${subs[@]}" 2>/dev/null)"
            for f in "${subs[@]}"; do
                [[ "$all" == *"$f:"* ]] || continue
                sf="$(printf '%s\n' "$all" | H_F="$f:" LC_ALL=C awk '
                    BEGIN { p = ENVIRON["H_F"]; n = length(p) } substr($0, 1, n) == p { print substr($0, n + 1) }')"
                _agents_hook_own_tasks "$f" "$main" all "$sf" "$ids"
            done
            return 0 ;;
    esac
}

# _agents_hook_log EVENT — with AGENTS_HOOK_LOG=1, append one line per hook
# run to $AGENTS_DATA_DIR/hooks.log: epoch, event, agent id, whether the
# agent's transcript held a handback, background tasks it named, processes
# matched, dry run. No command lines. Pruned with the history.
_agents_hook_log() {
    [[ "$AGENTS_HOOK_LOG" == 1 ]] || return 0
    (
        umask 077
        _agents_data_dir || exit 0
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$1" "$_AGENTS_HL_AID" "$_AGENTS_HL_HB" \
            "$_AGENTS_HL_TASKS" "$_AGENTS_HL_MATCHED" "$_AGENTS_HOOK_DRY" >> "$AGENTS_DATA_DIR/hooks.log"
    ) 2>/dev/null
    return 0
}

# agents_hook subagent-stop|session-end [-n] < HOOK_JSON — the hook itself.
# Returns 0 whatever happens: a failing SubagentStop hook would keep the
# subagent running. Quiet unless -n (or AGENTS_DRY_RUN=true): then it prints
# what it would stop and signals nothing.
agents_hook() {
    local _AGENTS_HL_AID=- _AGENTS_HL_HB=- _AGENTS_HL_TASKS=0 _AGENTS_HL_MATCHED=0
    local _AGENTS_HOOK_DRY="$_AGENTS_HOOK_DRY"   # -n lasts for this call only
    _agents_hook_run "$@"
    _agents_hook_log "${1:-}"
    return 0
}

_agents_hook_run() {
    local event="${1:-}" a
    [[ $# -gt 0 ]] && shift
    for a in "$@"; do case "$a" in -n|--dry-run) _AGENTS_HOOK_DRY=true ;; esac; done
    case "$event" in
        subagent-stop|session-end) ;;
        *) echo "usage: agents hook subagent-stop|session-end [-n] < HOOK_JSON" >&2; return 0 ;;
    esac
    [[ "$AGENTS_HOOK_REAP" == 1 ]] || { _agents_hook_say "AGENTS_HOOK_REAP=$AGENTS_HOOK_REAP: off"; return 0; }
    command -v jq >/dev/null 2>&1 || return 0
    if _agents_is_root; then return 0; fi
    if [[ -t 0 ]]; then echo "agents hook: pipe the hook's JSON to stdin" >&2; return 0; fi
    local fields _ev _sid main _aid atype agent cwd reason
    fields="$(_agents_hook_input)"
    [[ -n "$fields" ]] || { _agents_hook_say "no hook JSON on stdin"; return 0; }
    IFS=$'\t' read -r _ev _sid main _aid atype agent cwd reason <<<"$fields"
    main="$(_agents_tx_path "$main")"; agent="$(_agents_tx_path "$agent")"
    _agents_tx_type_ok "$atype" || atype=-
    if [[ "$AGENTS_HOOK_LOG" == 1 ]]; then
        [[ "$_aid" =~ ^[A-Za-z0-9_-]+$ ]] && _AGENTS_HL_AID="$_aid"
        if [[ "$event" == subagent-stop ]]; then
            if [[ -f "$agent" ]] && _agents_hook_final "$agent"; then _AGENTS_HL_HB=yes; else _AGENTS_HL_HB=no; fi
        fi
    fi
    local tasks snap claude kids matches
    tasks="$(_agents_hook_collect "$event" "$main" "$agent" "$reason")" || return 0
    [[ -n "$tasks" ]] || { _agents_hook_say "no background commands left running"; return 0; }
    _AGENTS_HL_TASKS="$(printf '%s\n' "$tasks" | grep -c .)"
    snap="$(agents_snapshot)"
    [[ -n "$snap" ]] || { _agents_hook_say "cannot read the process table"; return 0; }
    claude="$(_agents_hook_claude "$snap")"
    [[ -n "$claude" ]] || { _agents_hook_say "not running under a claude process"; return 0; }
    # shellcheck disable=SC2046  # one pid per word
    kids="$(_agents_hook_stdouts $(_agents_hook_children "$snap" "$claude"))"
    matches="$(_agents_hook_match "$snap" "$claude" "$tasks" "$kids")"
    [[ -n "$matches" ]] || { _agents_hook_say "none of its background commands still runs"; return 0; }
    _AGENTS_HL_MATCHED="$(printf '%s\n' "$matches" | grep -c .)"
    # The session as every other event names it (kind:pid), so a report
    # groups hook cleanups with the rest.
    _agents_hook_reap "$event" "$matches" "claude:$claude" "$(agents_project "$cwd")" "$atype"
    return 0
}

# _agents_hook_reap EVENT MATCHES SESSION PROJECT AGENT_TYPE — stop the
# matched trees, log one event per stopped task, notify once.
_agents_hook_reap() {
    local event="$1" matches="$2" session="$3" proj="$4" atype="$5" tokens out planned token id how name _w n=0 who reason
    tokens="$(printf '%s\n' "$matches" | cut -f1)"
    if [[ "$event" == subagent-stop ]]; then
        reason=subagent-end; who="a subagent"
        [[ "$atype" == - || -z "$atype" ]] || who="a subagent ($atype)"
    else
        reason="session-end"; who="the ended session"
    fi
    if [[ "$_AGENTS_HOOK_DRY" == true ]]; then
        echo "agents hook: background commands $who left running:"
        while IFS=$'\t' read -r token id how name _w; do
            printf '  task %s: %s, pid %s (matched by %s)\n' "$id" "$name" "${token%@*}" "$how"
        done <<<"$matches"
        # shellcheck disable=SC2086  # one PID@START token per word
        AGENTS_DRY_RUN=true _agents_kill_unattended $tokens 2>&1
        return 0
    fi
    # shellcheck disable=SC2086
    out="$(AGENTS_DRY_RUN=false _agents_kill_unattended $tokens 2>&1)"
    planned="$(printf '%s\n' "$out" | awk '/^  [0-9]+ / { print $1 }')"
    while IFS=$'\t' read -r token id how name _w; do
        [[ $'\n'"$planned"$'\n' == *$'\n'"${token%@*}"$'\n'* ]] || continue
        n=$((n + 1))
        agents_event hook "$reason" "${token%@*}" "$name" "$proj" "$session"
    done <<<"$matches"
    [[ $n -gt 0 ]] || return 0
    AGENTS_NOTIFY=true _agents_notify "Stopped $n background command$([[ $n -gt 1 ]] && echo s) $who left running$([[ "$proj" != - ]] && echo " in $proj")"
}
