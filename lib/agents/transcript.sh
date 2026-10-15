# shellcheck shell=bash
# lib/agents/transcript.sh — reading Claude Code's session transcripts.
#
# Claude Code's layout: a session's transcript is
#   $CLAUDE_CONFIG_DIR/projects/<slug>/<session>.jsonl   (~/.claude by default)
# its subagents' are <slug>/<session>/subagents/agent-<id>.jsonl, each with an
# agent-<id>.meta.json (its agentType, or customAgentType for a named one;
# parentAgentId for one a subagent spawned, which, as a fork, starts with a
# copy of that subagent's history), and a tool command's output goes to <tmp>/claude-<uid>/<slug>/<session>/
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
#   which agent started a task (searched for, or resolved from the token
#   scan's index: runs.sh), and which transcripts changed lately and whose
#   session each is (tokens.sh).
# Uses: watched.sh (_agents_mtimes, for a bounded search).
# Public: _AGENTS_TX_TASK_KEY, _agents_tx_path, _agents_tx_started,
#   _agents_tx_ids, _agents_tx_meta, _agents_tx_type_ok, _agents_tx_agent_type,
#   _agents_tx_agent_types, _agents_tx_fork_parents, _agents_tx_main_of,
#   _agents_tx_task_owners, _agents_tx_task_sources, _agents_tx_task_resolve,
#   _agents_tx_find, _agents_tx_session_of.

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

# _agents_tx_type_ok TYPE — true when an agent type is a plain name: 1 to 64
# of A-Z a-z 0-9 . _ : - (spelled out: a range can take in other letters in
# some locales). Only such a name reaches runs.tsv, the report, the menu or a
# notification; a type comes from files and hook input agents does not own.
_AGENTS_TX_TYPE_CHARS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-'
_agents_tx_type_ok() {
    [[ -n "$1" && ${#1} -le 64 && -z "${1//[$_AGENTS_TX_TYPE_CHARS]/}" ]]
}

# _agents_tx_agent_type TRANSCRIPT — the type of the subagent whose
# transcript it is (customAgentType for a named one, else agentType: Explore,
# implementor-complex, fork…), "-" when unknown or not a plain name.
_agents_tx_agent_type() {
    local meta="${1%.jsonl}.meta.json" t
    t="$(_agents_tx_meta "$meta" customAgentType)"
    [[ -n "$t" ]] || t="$(_agents_tx_meta "$meta" agentType)"
    _agents_tx_type_ok "$t" || t=-
    printf '%s\n' "$t"
}

# _agents_tx_agent_types TRANSCRIPT... — "transcript<TAB>type" for each
# subagent transcript whose meta.json names a plain type, as
# _agents_tx_agent_type would (customAgentType first): one grep for all of
# them, however many. A transcript without one gets no line.
_agents_tx_agent_types() {
    local f metas=()
    [[ $# -gt 0 ]] || return 0
    for f in "$@"; do metas+=("${f%.jsonl}.meta.json"); done
    # grep -H: "META:MATCH"; the match is the line's last :"key": "value".
    LC_ALL=C grep -HoE '"(customAgentType|agentType)": ?"[^"\\]*"' "${metas[@]}" 2>/dev/null | LC_ALL=C awk -v ok="$_AGENTS_TX_TYPE_CHARS" '
        match($0, /:"(customAgentType|agentType)": ?"[^"\\]*"$/) {
            m = substr($0, 1, RSTART - 1); v = substr($0, RSTART + 1)
            c = (v ~ /^"customAgentType"/); sub(/^"[A-Za-z]+": ?"/, "", v); sub(/"$/, "", v)
            if (!(m in seen)) { seen[m] = 1; o[++n] = m }
            if (c) { if (!(m in cu)) cu[m] = v } else if (!(m in ag)) ag[m] = v
        }
        END {
            for (i = 1; i <= n; i++) {
                m = o[i]; v = (cu[m] != "") ? cu[m] : ag[m]
                bad = (v == "" || length(v) > 64)
                for (j = 1; !bad && j <= length(v); j++) if (index(ok, substr(v, j, 1)) == 0) bad = 1
                if (bad) continue
                f = m; sub(/\.meta\.json$/, ".jsonl", f); print f "\t" v
            }
        }'
}

# _agents_tx_fork_parents TRANSCRIPT... — "transcript<TAB>parent id" for each
# subagent transcript whose meta.json names the subagent that spawned it
# (parentAgentId, whose transcript is agent-<parent id>.jsonl beside it): one
# grep for all of them. A transcript without one gets no line.
_agents_tx_fork_parents() {
    local f metas=()
    [[ $# -gt 0 ]] || return 0
    for f in "$@"; do metas+=("${f%.jsonl}.meta.json"); done
    LC_ALL=C grep -HoE '"parentAgentId": ?"[A-Za-z0-9_-]{1,64}"' "${metas[@]}" 2>/dev/null | LC_ALL=C awk '
        match($0, /:"parentAgentId": ?"[A-Za-z0-9_-]+"$/) {
            m = substr($0, 1, RSTART - 1); v = substr($0, RSTART + 1)
            sub(/^"parentAgentId": ?"/, "", v); sub(/"$/, "", v)
            if (m in seen) next
            seen[m] = 1; sub(/\.meta\.json$/, ".jsonl", m); print m "\t" v
        }'
}

# _agents_tx_find DAYS FIND_ACTION... — every transcript, main and subagent,
# changed within the last DAYS days, with find's FIND_ACTION (-print, or
# -exec CMD {} +). Nothing when there is no projects directory.
_agents_tx_find() {
    local days="$1" p="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    shift
    [[ -d "$p" ]] || return 0
    find "$p" -mindepth 2 -maxdepth 4 -type f -name '*.jsonl' -mtime "-$days" \
        \( -path "$p/*/*/subagents/agent-*.jsonl" -o ! -path "$p/*/*/*" \) "$@" 2>/dev/null
    return 0
}

# _agents_tx_session_of VAR TRANSCRIPT — set VAR to the id of the session a
# transcript belongs to: its own name, or for a subagent's (…/<session>/
# subagents/agent-<id>.jsonl) its main session's.
_agents_tx_session_of() {
    local s="$2"
    case "$s" in
        */subagents/agent-*.jsonl) s="${s%/subagents/*}" ;;
        *) s="${s%.jsonl}" ;;
    esac
    printf -v "$1" '%s' "${s##*/}"
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
# One fixed-string grep over the main transcript and all its subagents'
# (_agents_tx_task_sources), resolved by _agents_tx_task_resolve.
_agents_tx_task_owners() {
    local main="$1"
    shift
    _agents_tx_task_sources "$main" 0 "$@" | _agents_tx_task_resolve
}

# The most of a transcript a bounded search reads, from its end.
_AGENTS_TX_TAIL=$((8 * 1048576))

# _agents_tx_task_sources MAIN SINCE ID... — "id<TAB>transcript" for each ID
# a transcript of MAIN's session names as a background task, one fixed-string
# grep over the main transcript and all its subagents'. With SINCE (an epoch;
# 0: none) the search is bounded: only the transcripts changed since then,
# each in its last _AGENTS_TX_TAIL bytes (a task started since then is named
# near the end of the transcript that started it).
_agents_tx_task_sources() {
    local main="$1" since="$2" id m p files=() pats=()
    shift 2
    [[ -f "$main" ]] && files+=("$main")
    _agents_tx_subagents "$main"
    files+=(${_AGENTS_TX_SUBS[@]+"${_AGENTS_TX_SUBS[@]}"})
    [[ ${#files[@]} -gt 0 && $# -gt 0 ]] || return 0
    for id in "$@"; do
        [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] && pats+=(-e "$_AGENTS_TX_TASK_KEY:\"$id\"" -e "$_AGENTS_TX_TASK_KEY: \"$id\"")
    done
    [[ ${#pats[@]} -gt 0 ]] || return 0
    # grep -Ho: "FILE:MATCH" lines; awk turns each into "id<TAB>file".
    if [[ "$since" -gt 0 ]]; then
        while IFS=$'\t' read -r m p; do
            [[ "$m" =~ ^[0-9]+$ && $m -ge $since ]] || continue
            tail -c "$_AGENTS_TX_TAIL" -- "$p" 2>/dev/null | LC_ALL=C grep -aoF "${pats[@]}" | LC_ALL=C awk -v f="$p" '{ print f ":" $0 }'
        done < <(_agents_mtimes "${files[@]}")
    else
        LC_ALL=C grep -HoF "${pats[@]}" "${files[@]}" 2>/dev/null
    fi | LC_ALL=C awk -v k="$_AGENTS_TX_TASK_KEY" '
        { i = index($0, ":" k); if (i == 0) next
          id = substr($0, i + 1 + length(k)); sub(/^: ?"/, "", id); sub(/"$/, "", id)
          print id "\t" substr($0, 1, i - 1) }' | LC_ALL=C sort -u
}

# _agents_tx_task_resolve < "id<TAB>transcript[<TAB>type]" — "id<TAB>agent"
# for each id: "main" when a main transcript (one not under subagents/)
# names it, else the type of the subagents that do (the line's type, or
# _agents_tx_agent_type when it has none or "-"). A fork inherits its
# parent's task lines, so an id a fork shares with another transcript is
# the other's; one only forks name is "fork"; one subagents of several
# types name is "-".
_agents_tx_task_resolve() {
    local id f t
    while IFS=$'\t' read -r id f t; do
        [[ -n "$id" ]] || continue
        if [[ "$f" != */subagents/agent-*.jsonl ]]; then t=main
        elif ! _agents_tx_type_ok "$t" || [[ "$t" == main ]]; then t="$(_agents_tx_agent_type "$f")"
        fi
        printf '%s\t%s\n' "$id" "$t"
    done | LC_ALL=C awk -F '\t' '
        !($1 in seen) { seen[$1] = 1; ids[++n] = $1 }
        $2 == "main" { m[$1] = 1 }
        $2 != "main" && $2 != "fork" { if (!(($1, $2) in got)) { got[$1, $2] = 1; c[$1]++; t[$1] = $2 } }
        END { for (i = 1; i <= n; i++) { id = ids[i]; print id "\t" ((id in m) ? "main" : (c[id] == 1) ? t[id] : (c[id] > 1) ? "-" : "fork") } }'
}
