# shellcheck shell=bash
# lib/agents/transcript.sh — reading Claude Code's session transcripts.
#
# Claude Code's layout: a session's transcript is
#   $CLAUDE_CONFIG_DIR/projects/<slug>/<session>.jsonl   (~/.claude by default)
# its subagents' are <slug>/<session>/subagents/agent-<id>.jsonl, each with an
# agent-<id>.meta.json (its agentType, or customAgentType for a named one),
# and a tool command's output goes to <tmp>/claude-<uid>/<slug>/<session>/
# tasks/<task id>.output. A background command's task id is named, under the
# key "backgroundTaskId", in the transcript of the agent that started it (and
# in the copy a fork inherits).
#
# Transcripts run to tens of megabytes (85 MB has been seen), and a session
# can have dozens of subagents, so each file is read as few times as
# possible, by grep under LC_ALL=C with fixed strings; jq and awk see only the
# lines it finds.
#
# Owns: those paths, the task-id lines, a subagent's meta fields and type,
#   and which agent started a task.
# Uses: nothing.
# Public: _AGENTS_TX_TASK_KEY, _agents_tx_path, _agents_tx_started,
#   _agents_tx_ids, _agents_tx_meta, _agents_tx_agent_type,
#   _agents_tx_main_of, _agents_tx_task_owners.

# The key on every transcript line that names a background task.
_AGENTS_TX_TASK_KEY='"backgroundTaskId"'

# _agents_tx_path PATH — PATH with a leading ~/ expanded; "-" stays "-".
_agents_tx_path() {
    case "$1" in \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;; *) printf '%s\n' "$1" ;; esac
}

# _agents_tx_started TRANSCRIPT — the lines that name a background task.
_agents_tx_started() {
    [[ -f "$1" && -r "$1" ]] || return 0
    LC_ALL=C grep -F "$_AGENTS_TX_TASK_KEY" "$1" 2>/dev/null
}

# _agents_tx_ids < LINES — every background task id they name.
_agents_tx_ids() {
    LC_ALL=C grep -oE '"backgroundTaskId": ?"[A-Za-z0-9_-]+"' | LC_ALL=C sed -E 's/.*"([A-Za-z0-9_-]+)"$/\1/'
}

# _agents_tx_subagents MAIN — set _AGENTS_TX_SUBS to the transcripts of
# MAIN's subagents (an array; empty when there are none).
_agents_tx_subagents() {
    local f
    _AGENTS_TX_SUBS=()
    for f in "${1%.jsonl}"/subagents/agent-*.jsonl; do [[ -f "$f" ]] && _AGENTS_TX_SUBS+=("$f"); done
    return 0
}

# _agents_tx_meta META KEY — the string value of KEY in a subagent's
# meta.json (one flat object), empty when it has none.
_agents_tx_meta() {
    [[ -f "$1" && -r "$1" ]] || return 0
    LC_ALL=C grep -oE "\"$2\": ?\"[^\"\\\\]*\"" "$1" 2>/dev/null | head -1 | LC_ALL=C sed -E 's/^[^:]*: ?"(.*)"$/\1/'
}

# _agents_tx_agent_type TRANSCRIPT — the type of the subagent whose
# transcript it is (customAgentType for a named one, else agentType: Explore,
# implementor-complex, fork…), "-" when unknown or not a plain name.
_agents_tx_agent_type() {
    local meta="${1%.jsonl}.meta.json" t
    t="$(_agents_tx_meta "$meta" customAgentType)"
    [[ -n "$t" ]] || t="$(_agents_tx_meta "$meta" agentType)"
    [[ "$t" =~ ^[A-Za-z0-9._:-]{1,64}$ ]] || t=-
    printf '%s\n' "$t"
}

# _agents_tx_main_of OUTPUT — the main transcript of the session a task
# output file (…/<slug>/<session>/tasks/<id>.output) belongs to; false when
# OUTPUT is not one.
_agents_tx_main_of() {
    local d="${1%/tasks/*}" sid slug
    [[ "$1" =~ /tasks/[A-Za-z0-9_-]+\.output$ && "$d" != "$1" ]] || return 1
    sid="${d##*/}"; d="${d%/*}"; slug="${d##*/}"
    [[ "$sid" =~ ^[A-Za-z0-9_-]+$ && -n "$slug" && "$slug" != . && "$slug" != .. ]] || return 1
    printf '%s/projects/%s/%s.jsonl\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$slug" "$sid"
}

# _agents_tx_task_owners MAIN ID... — "id<TAB>agent" for each ID a transcript
# of MAIN's session names as a background task: "main" when the main
# conversation started it, else the subagent's type (_agents_tx_agent_type).
# One fixed-string grep over the main transcript and all its subagents'. A
# fork inherits its parent's task lines, so an id a fork shares with another
# transcript is the other's; one only forks name is "fork"; one several
# other subagents name is "-".
_agents_tx_task_owners() {
    local main="$1" f id files=() pats=() pairs
    shift
    [[ -f "$main" ]] && files+=("$main")
    _agents_tx_subagents "$main"
    files+=(${_AGENTS_TX_SUBS[@]+"${_AGENTS_TX_SUBS[@]}"})
    [[ ${#files[@]} -gt 0 && $# -gt 0 ]] || return 0
    for id in "$@"; do
        [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] && pats+=(-e "$_AGENTS_TX_TASK_KEY:\"$id\"" -e "$_AGENTS_TX_TASK_KEY: \"$id\"")
    done
    [[ ${#pats[@]} -gt 0 ]] || return 0
    # grep -Ho: "FILE:MATCH" lines; awk turns each into "id<TAB>file".
    pairs="$(LC_ALL=C grep -HoF "${pats[@]}" "${files[@]}" 2>/dev/null | LC_ALL=C awk -v k="$_AGENTS_TX_TASK_KEY" '
        { i = index($0, ":" k); if (i == 0) next
          id = substr($0, i + 1 + length(k)); sub(/^: ?"/, "", id); sub(/"$/, "", id)
          print id "\t" substr($0, 1, i - 1) }' | LC_ALL=C sort -u)"
    [[ -n "$pairs" ]] || return 0
    while IFS=$'\t' read -r id f; do
        if [[ "$f" == "$main" ]]; then printf '%s\tmain\n' "$id"; else printf '%s\t%s\n' "$id" "$(_agents_tx_agent_type "$f")"; fi
    done <<<"$pairs" | LC_ALL=C awk -F '\t' '
        !($1 in seen) { seen[$1] = 1; ids[++n] = $1 }
        $2 == "main" { m[$1] = 1 }
        $2 != "main" && $2 != "fork" { if (!(($1, $2) in got)) { got[$1, $2] = 1; c[$1]++; t[$1] = $2 } }
        END { for (i = 1; i <= n; i++) { id = ids[i]; print id "\t" ((id in m) ? "main" : (c[id] == 1) ? t[id] : (c[id] > 1) ? "-" : "fork") } }'
}
