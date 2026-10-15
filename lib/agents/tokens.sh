# shellcheck shell=bash
# lib/agents/tokens.sh — where agent tokens go: the token scanner.
#
# Each `agents sample` reads what Claude Code and Codex appended to their
# transcripts since the last one (transcript.sh has Claude Code's layout;
# Codex writes ${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-*.jsonl)
# and appends what they say about tokens to files `agents report` reads.
# Claude Code writes one API message as several lines, one per content
# block, each repeating its usage: a message counts once, by its id. Copies
# count not at all: a fork's copy of the main session's last message (its
# first line); a fork a subagent spawned starts with a copy of that
# subagent's whole history (same ids and times), passed over until its first
# message of its own (_agents_tokens_forks; then the state remembers it is
# past it); and a rewound or resumed session writes earlier messages again,
# with their old times: a message a minute older than the newest line read
# from its transcript is one of those. Model "<synthetic>" made no API call.
# Codex logs a token_count event per turn, sometimes twice: a turn counts
# once, by its running total. The same pass notes the background tasks a
# transcript names (the run ledger's tasks.idx, so a finished command's
# agent needs no search of the transcripts), what the tool calls of each
# counted message use (MCP servers, skills, subagent types) and the MCP
# tools each session's deferred tool list names (uses.tsv).
#
# Transcripts run to tens of megabytes and gigabytes in all, so a scan reads
# only new bytes (tail -c), whole lines only, at most _AGENTS_TOKENS_BUDGET
# bytes and _AGENTS_TOKENS_FILES files per sample, newest files first; the
# rest waits for the next sample. One grep under LC_ALL=C picks the lines
# that matter (an ERE whose branches share their first byte: BSD grep makes
# one pass per -F pattern), and only those reach awk/tokens.awk; where grep
# gives no line offsets (BusyBox), awk does (_agents_tokens_grep). The first
# scan reads the files changed within AGENTS_HISTORY_DAYS, a row older than
# that never written: on a heavy machine the budget makes that a catch-up
# over many samples (64 MiB each: some 16 a GiB), the newest files first.
#
# Files, private like the rest of $AGENTS_DATA_DIR, none with AGENTS_HISTORY=0;
# one writer (agents sample, under sample.lock); tab-separated, no header,
# values never hold a tab or a newline; pruned with history.tsv, once a day
# (_agents_tokens_prune):
#   tokens.tsv    one row per API message (Claude Code) or turn (Codex):
#                   epoch cli project session agent model in cache_write cache_read out poll cache_write_1h origin
#                 project: as runs.tsv names it (agents_project of the line's
#                 cwd); session: the session id (a subagent's main session);
#                 agent: main, the subagent type, or "-"; in excludes cached
#                 input (Codex's input_tokens counts it: it becomes
#                 cache_read); cache_write counts every cache write,
#                 cache_write_1h those of them cached for an hour (the rest
#                 for 5 minutes); poll: 1 when every tool call in the message
#                 only waits (sleep, a sleep loop, reading a task's output
#                 file, BashOutput, TaskOutput, Monitor); origin: who drove
#                 the session: you (Claude Code's CLI, desktop app or IDE;
#                 Codex's TUI or IDE), headless (the Agent SDK, claude -p,
#                 codex exec), subagent or fork (a subagent's transcript; a
#                 Codex subagent), "-" when unknown. A row an older agents
#                 wrote has 11 columns: its cache writes all 5-minute ones,
#                 its origin unknown.
#                 Rows older than local midnight yesterday are rolled up, at
#                 the daily prune, into one row per local day and cli project
#                 session agent model poll origin, at the top of the file:
#                   day_epoch ... origin calls
#                 (14 columns: the day's local midnight, the sums, and how
#                 many rows they sum). One file, so the rollup replaces it in
#                 one rename: no row ever counts twice or not at all.
#   compacts.tsv  epoch cli project session agent trigger pre_tokens post_tokens
#   denials.tsv   epoch cli project session agent tool by reason subject
#                 by: classifier, safety or user; reason: the classifier's
#                 [tag], else "-"; subject: never arguments: for Bash the
#                 program that acts (the last, past cd, echo and filters such
#                 as cat, grep or sed, which count only when nothing else
#                 runs; quoted text and heredocs are not commands) and, for
#                 a multi-command tool, its subcommand when it comes first
#                 and is a known one (git push, gh pr, kubectl delete;
#                 kubectl -n X delete is kubectl); WebFetch's host; else the
#                 tool name.
#   uses.tsv      epoch cli project session agent kind name count
#                 per transcript, hour and name: kind mcp (calls to an MCP
#                 server: name as the tool names it, mcp__NAME__TOOL; Codex's
#                 MCP calls too), skill (Skill calls, by skill), agent
#                 (subagents started, by type), each only from messages
#                 that count; listed (the most tools of server NAME a deferred
#                 tool list of the session named). Names only, never inputs.
#   tasks.idx     epoch session task_id source type: a background task a
#                 transcript of the session names ("backgroundTaskId"):
#                 source main, or the subagent's agent id; type: its agent
#                 type when the scan knew it, else "-" (runs.sh reads it).
#   limits.tsv    epoch cli used_percent window_minutes resets_at: Codex's
#                 latest primary rate limit (one line, replaced).
#   tokens.today  day total in cache_write cache_read out: today's sums (local
#                 day), rewritten after each scan, for the menu.
#   tokens.stamp, tokens.full
#                 when the last scan began (the stamp's mtime, 2 s early)
#                 and the epoch of the last full listing: a scan lists only
#                 the transcripts changed since the stamp, and the hot ones,
#                 unless the full listing is _AGENTS_TOKENS_FULL old, or the
#                 last scan's budget left work (tokens.full is then 0: a
#                 catch-up lists them all every sample until it is done).
#   tokens.state, tokens.hot
#                 one line per transcript read, kept while its last_epoch is
#                 within the window (listed or not: a sample that does not
#                 see a transcript must not make the next count it again):
#                   path cli inode offset last_epoch last_id session project agent model pending fork origin
#                 offset: the bytes read (whole lines; the last message of an
#                 active file is read again next time, until it is complete);
#                 a new inode or a shorter file is read again from 0, and only
#                 rows after last_epoch count (or at it, another message
#                 than last_id). last_id: the last message id (Codex: running
#                 total) counted; pending: the last message's tool calls,
#                 "id=tool=subject;…", for a denial that follows; fork: the
#                 id of the subagent a fork copied, while it is still in
#                 that copy, else "-"; origin as in tokens.tsv. A line in
#                 tokens.hot wins over one in tokens.state: each scan
#                 rewrites only tokens.hot (the transcripts it read, and the
#                 ones read within the hour), and only when it changed; the
#                 cold majority stays in tokens.state, which a compaction
#                 (_agents_tokens_compact) rewrites when 64 hot lines have
#                 gone cold, and once a day. An older agents' tokens.state,
#                 alone, is all cold.
#
# Uses: config.sh, util.sh (_agents_awk, _agents_window, _agents_replace),
#   history.sh (_agents_prune_file), transcript.sh (_agents_tx_find,
#   _agents_tx_session_of, _agents_tx_agent_types, _agents_tx_fork_parents);
#   awk/tokens_plan.awk, awk/tokens.awk, awk/tokens_state.awk,
#   awk/tokens_rollup.awk.
# Public: _agents_tokens_scan, _agents_tokens_prune, _agents_tokens_raw_since,
#   _agents_tokens_task_sources.

# The most a sample reads (bytes, files), and how long a transcript must be
# quiet before its last message counts without the line that ends it.
_AGENTS_TOKENS_BUDGET=$((64 * 1048576))
_AGENTS_TOKENS_FILES=512
_AGENTS_TOKENS_QUIET=120
# A state line is hot while its transcript had a row within this many
# seconds; this many cold lines in tokens.hot make a compaction. A scan
# lists only the transcripts changed since the last one (and the hot ones),
# and all of them when the last full listing is this many seconds old: a
# file whose mtime went back (a copy that kept its own) is found then.
_AGENTS_TOKENS_HOT=3600
_AGENTS_TOKENS_COLD_BATCH=64
_AGENTS_TOKENS_FULL=3600
_AGENTS_TOKENS_CLAUDE_RE='"(type":"assistant"|subtype":"compact_boundary"|is_error":true|backgroundTaskId": ?"|type":"deferred_tools_delta")'
_AGENTS_TOKENS_CODEX_RE='"type":"(session_meta|turn_context|token_count|function_call)"'

# _agents_tokens_scan NOW DAY — scan the transcripts (a no-op with
# AGENTS_HISTORY=0). Runs inside agents_sample (sample.lock, umask 077); the
# hot state is replaced before the rows are appended, so a failure loses
# rows rather than counting them twice. False, with the state as it was,
# when the scan could not be made. Today (DAY, and its midnight) is NOW's.
_agents_tokens_scan() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    # shellcheck disable=SC2034  # _agents_window sets off and period too
    local dir="$AGENTS_DATA_DIR" now="$1" day="$2" start off period plan types forks f o ag fk out today hot cold left since="" age subs=() kids=()
    _agents_window today "$1" || return 1
    # The transcripts changed since the last scan's listing (tokens.stamp,
    # whose mtime is just before it), unless a full listing is due.
    _agents_stamp_age age "$dir/tokens.full" "$now"
    [[ $age -ge $_AGENTS_TOKENS_FULL || ! -f "$dir/tokens.stamp" ]] || since="$dir/tokens.stamp"
    _agents_tokens_stamp "$dir/tokens.stamp.new" "$((now - 2))"
    plan="$(_agents_tokens_list "$since" | _agents_awk tokens_plan -F '\t' -v OFS='\t' -v sf="$dir/tokens.state" -v hf="$dir/tokens.hot" \
        -v cut="$((now - AGENTS_HISTORY_DAYS * 86400))" | LC_ALL=C sort -t "$(printf '\t')" -k6,6nr -k3,3)" || return 1
    # The subagents this scan may read: the types of those not known yet, in
    # one grep; and the forks among them that a subagent spawned, with the
    # ids of the messages they copied from it (_agents_tokens_forks).
    while IFS=$'\t' read -r _ _ f _ _ _ o _ _ _ _ ag _ _ fk _; do
        [[ "$f" == */subagents/agent-*.jsonl ]] || continue
        [[ "$ag" != - ]] || subs+=("$f")
        [[ ( "$ag" != - || "$o" != 0 ) && "$fk" == - ]] || kids+=("$f")
    done < <(LC_ALL=C awk -F '\t' '$1 == 1' <<<"$plan" | head -n "$_AGENTS_TOKENS_FILES")
    types="$(_agents_tx_agent_types ${subs[@]+"${subs[@]}"})"
    forks="$(_agents_tokens_forks ${kids[@]+"${kids[@]}"})"
    rm -f "$dir"/tokens.add.* "$dir/tokens.hot.new" 2>/dev/null
    _agents_tokens_probe
    out="$(_agents_tokens_feed "$now" <<<"$plan" \
        | _agents_awk "lib_proc lib_activity tokens" -v now="$now" -v cut="$((now - AGENTS_HISTORY_DAYS * 86400))" \
            -v mid="$start" -v day="$day" -v quiet="$_AGENTS_TOKENS_QUIET" -v hotsecs="$_AGENTS_TOKENS_HOT" \
            -v d="$dir" -v tyf=/dev/fd/3 -v frf=/dev/fd/4 3<<<"$types" 4<<<"$forks")" || out=""
    { IFS= read -r today; IFS=$'\t' read -r hot _ cold left; } <<<"$out" || true
    if [[ "$today" != "$day"$'\t'* || "$hot" != hot ]] \
        || { [[ -f "$dir/tokens.hot.new" ]] && ! mv -f "$dir/tokens.hot.new" "$dir/tokens.hot"; }; then
        rm -f "$dir"/tokens.add.* "$dir/tokens.hot.new" "$dir/tokens.stamp.new" 2>/dev/null
        return 1
    fi
    [[ ! -f "$dir/tokens.stamp.new" ]] || mv -f "$dir/tokens.stamp.new" "$dir/tokens.stamp"
    # Work the budget left (a catch-up) is listed again by the next scan,
    # whether its transcripts changed or not: the full listing stays due.
    if [[ "$left" =~ ^[0-9]+$ && $left -gt 0 ]]; then
        _agents_replace "$dir/tokens.full" 0
    elif [[ -z "$since" ]]; then
        _agents_replace "$dir/tokens.full" "$now"
    fi
    for f in tokens compacts denials uses; do
        [[ ! -s "$dir/tokens.add.$f" ]] || cat "$dir/tokens.add.$f" >> "$dir/$f.tsv"
    done
    [[ ! -s "$dir/tokens.add.tasks" ]] || cat "$dir/tokens.add.tasks" >> "$dir/tasks.idx"
    [[ ! -f "$dir/tokens.add.limits" ]] || mv -f "$dir/tokens.add.limits" "$dir/limits.tsv"
    rm -f "$dir"/tokens.add.* 2>/dev/null
    _agents_replace "$dir/tokens.today" "$today"
    [[ ! "$cold" =~ ^[0-9]+$ || $cold -lt $_AGENTS_TOKENS_COLD_BATCH ]] || _agents_tokens_compact "$now" 0
    return 0
}

# _agents_tokens_stamp FILE EPOCH — FILE, empty, with EPOCH as its mtime
# (touch -t: BSD date -r, GNU and BusyBox date -d @); nothing when it
# cannot be made, and the next scan then lists every transcript.
_agents_tokens_stamp() {
    local t
    if t="$(date -r "$2" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$2" +%Y%m%d%H%M.%S 2>/dev/null)" \
        && : > "$1" && touch -t "$t" "$1" 2>/dev/null; then
        return 0
    fi
    rm -f "$1"
}

# _agents_tokens_compact NOW CUT — move the hot state's lines that went cold
# (no row within _AGENTS_TOKENS_HOT) into tokens.state, and drop every line
# whose last_epoch is before CUT (0: none). tokens.state is replaced first,
# holding the hot lines' current values too, so a failure between the two
# renames leaves tokens.hot saying the same thing over it. False, with both
# as they were, when it could not be made.
_agents_tokens_compact() {
    local dir="$AGENTS_DATA_DIR"
    [[ -f "$dir/tokens.hot" || $2 -gt 0 ]] || return 0
    rm -f "$dir/tokens.state.new" "$dir/tokens.hot.new" 2>/dev/null
    if ! _agents_awk tokens_state -F '\t' -v sf="$dir/tokens.state" -v hf="$dir/tokens.hot" \
            -v hot="$(($1 - _AGENTS_TOKENS_HOT))" -v cut="$2" -v so="$dir/tokens.state.new" -v ho="$dir/tokens.hot.new" </dev/null \
        || ! mv -f "$dir/tokens.state.new" "$dir/tokens.state" || ! mv -f "$dir/tokens.hot.new" "$dir/tokens.hot"; then
        rm -f "$dir/tokens.state.new" "$dir/tokens.hot.new" 2>/dev/null
        return 1
    fi
}

# _agents_tokens_raw_since NOW OFF — the epoch from which tokens.tsv holds
# every row as written: local midnight yesterday (OFF: the UTC offset). A
# report window that starts before it counts whole local days there.
_agents_tokens_raw_since() {
    printf '%s\n' "$(( $1 - ($1 + $2) % 86400 - 86400 ))"
}

# _agents_tokens_prune NOW CUT — the token files' daily prune (history.sh,
# under sample.lock): tokens.tsv rolled up (awk/tokens_rollup.awk: the rows
# before _agents_tokens_raw_since become day rows; a day that ended before
# CUT goes), the other files' rows before CUT dropped, the state compacted.
_agents_tokens_prune() {
    # shellcheck disable=SC2034  # _agents_window sets start and period too
    local dir="$AGENTS_DATA_DIR" f start now off period tmp seen
    _agents_window today "$1" || return 1
    for f in compacts.tsv denials.tsv limits.tsv uses.tsv tasks.idx; do _agents_prune_file "$dir/$f" "$2"; done
    if [[ -f "$dir/tokens.tsv" ]]; then
        tmp="$dir/tokens.tsv.prune.$$"
        seen="$(_agents_awk "lib_sort tokens_rollup" -F '\t' -v OFS='\t' -v raw="$(_agents_tokens_raw_since "$1" "$off")" -v cut="$2" \
            -v off="$off" -v out="$tmp" < "$dir/tokens.tsv")"
        if [[ "$seen" =~ ^[0-9]+$ && -f "$tmp" ]]; then
            # Rows appended meanwhile (none: the scan runs under the same lock).
            tail -n "+$((seen + 1))" "$dir/tokens.tsv" >> "$tmp" 2>/dev/null
            mv -f "$tmp" "$dir/tokens.tsv"
        else
            rm -f "$tmp"
        fi
    fi
    _agents_tokens_compact "$1" "$2"
}

# _agents_tokens_task_sources MAIN ID... — from tasks.idx, for the IDs a
# transcript of MAIN's session named: "id<TAB>transcript<TAB>type" (type "-"
# when the scan did not know it); an ID not indexed yet gets no line.
_agents_tokens_task_sources() {
    local main="$1" sid
    shift
    [[ $# -gt 0 && -r "$AGENTS_DATA_DIR/tasks.idx" ]] || return 0
    sid="${main##*/}"; sid="${sid%.jsonl}"
    LC_ALL=C awk -F '\t' -v sid="$sid" -v main="$main" -v ids="$*" '
        BEGIN { n = split(ids, w, " "); for (i = 1; i <= n; i++) want[w[i]] = 1 }
        NF >= 5 && $2 == sid && ($3 in want) && !(($3, $4) in seen) {
            seen[$3, $4] = 1
            f = $4 == "main" ? main : substr(main, 1, length(main) - 6) "/subagents/agent-" $4 ".jsonl"
            print $3 "\t" f "\t" ($5 == "" ? "-" : $5)
        }' "$AGENTS_DATA_DIR/tasks.idx"
}

# _agents_tokens_forks TRANSCRIPT... — of these subagent transcripts, those
# whose meta.json names the subagent that spawned them (a fork of a
# subagent, which starts with a copy of that one's history: the same
# messages, ids and times): "F<TAB>transcript<TAB>parent id"; then, for each
# such parent, "I<TAB>parent transcript<TAB>message id" for every message it
# logged so far. One grep for the metas, one for the parents.
_agents_tokens_forks() {
    local t p fp seen=$'\n' pars=()
    [[ $# -gt 0 ]] || return 0
    fp="$(_agents_tx_fork_parents "$@")"
    [[ -n "$fp" ]] || return 0
    while IFS=$'\t' read -r t p; do
        printf 'F\t%s\t%s\n' "$t" "$p"
        p="${t%/*}/agent-$p.jsonl"
        [[ "$seen" == *$'\n'"$p"$'\n'* || ! -f "$p" ]] || { pars+=("$p"); seen+="$p"$'\n'; }
    done <<<"$fp"
    [[ ${#pars[@]} -gt 0 ]] || return 0
    # grep -H: "PATH:MATCH"; the match starts at :"model":".
    LC_ALL=C grep -aHoE '"model":"[^"]*","id":"[^"]*"' "${pars[@]}" 2>/dev/null | LC_ALL=C awk '
        (i = index($0, ":\"model\":\"")) > 0 {
            id = substr($0, i + 1); sub(/^.*","id":"/, "", id); sub(/"$/, "", id); gsub(/[^A-Za-z0-9_-]/, "", id)
            if (id != "") print "I\t" substr($0, 1, i - 1) "\t" substr(id, 1, 128)
        }'
    return 0
}

# _agents_tokens_list [STAMP] — "@claude" then Claude Code's transcripts,
# "@codex" then Codex's, changed within AGENTS_HISTORY_DAYS: "inode<TAB>size
# <TAB>mtime<TAB>path", one stat per batch of files (no device: BSD stat's %d
# looks each one up by name, a thousand times slower). With STAMP, only
# those changed since it, and those tokens.hot holds (a transcript a budget
# cut is still being read): every other one is as the state left it.
_agents_tokens_list() {
    local c="${CODEX_HOME:-$HOME/.codex}/sessions" p="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" st new=()
    if [[ "${OSTYPE:-}" == darwin* ]]; then st=(/usr/bin/stat -f '%i%t%z%t%m%t%N'); else st=(stat -c $'%i\t%s\t%Y\t%n'); fi
    [[ -z "${1:-}" || ! -f "$1" ]] || new=(-newer "$1")
    echo "@claude"
    _agents_tx_find "$AGENTS_HISTORY_DAYS" ${new[@]+"${new[@]}"} -exec "${st[@]}" {} +
    [[ ${#new[@]} -eq 0 ]] || _agents_tokens_hot claude "$p/" "${st[@]}"
    echo "@codex"
    [[ ! -d "$c" ]] || find "$c" -mindepth 4 -maxdepth 4 -type f -name 'rollout-*.jsonl' \
        -mtime "-$AGENTS_HISTORY_DAYS" ${new[@]+"${new[@]}"} -exec "${st[@]}" {} + 2>/dev/null
    [[ ${#new[@]} -eq 0 ]] || _agents_tokens_hot codex "$c/" "${st[@]}"
    return 0
}

# _agents_tokens_hot CLI PREFIX STAT... — the stat lines of the transcripts
# of CLI under PREFIX that tokens.hot holds.
_agents_tokens_hot() {
    local cli="$1" pre="$2" f files=()
    shift 2
    [[ -r "$AGENTS_DATA_DIR/tokens.hot" ]] || return 0
    while IFS= read -r f; do [[ -f "$f" ]] && files+=("$f"); done < <(LC_ALL=C awk -F '\t' -v c="$cli" -v p="$pre" \
        '$2 == c && substr($1, 1, length(p)) == p { print $1 }' "$AGENTS_DATA_DIR/tokens.hot")
    [[ ${#files[@]} -eq 0 ]] || "$@" "${files[@]}" 2>/dev/null
    return 0
}

# _agents_tokens_feed NOW < PLAN — awk/tokens.awk's input: for each planned
# transcript a header, "F<TAB>END<TAB>PLAN_LINE" followed by the lines it
# reads ("OFFSET:LINE", OFFSET from the old offset: _agents_tokens_grep), or
# "K<TAB>-<TAB>PLAN_LINE" for one it leaves as it was. PLAN_LINE:
#   work cli path inode size mtime offset last_epoch last_id session project agent model pending fork origin
# work, in a header, is 2 for a transcript the budget (bytes or files) left
# unread, or read only in part: work a later scan must come back to.
_agents_tokens_feed() {
    local now="$1" budget="$_AGENTS_TOKENS_BUDGET" n=0 work cli path ino size mtime off le lid sess rest end
    while IFS=$'\t' read -r work cli path ino size mtime off le lid sess rest; do
        [[ "$path" == /* ]] || continue   # an empty plan is one empty line
        end=""
        if [[ "$work" == 1 && ( $budget -le 0 || $n -ge $_AGENTS_TOKENS_FILES ) ]]; then
            work=2
        elif [[ "$work" == 1 && -f "$path" && ! -L "$path" ]]; then
            end=$size
            [[ $((size - off)) -le $budget ]] || { end=$((off + budget)); work=2; }
            end="$(_agents_tokens_end "$path" "$off" "$end" "$size" "$((now - mtime))")"
            [[ "$work" != 2 || -z "$end" || $end -lt $size ]] || work=1
        fi
        [[ "$cli" != claude || "$sess" != - ]] || _agents_tx_session_of sess "$path"
        if [[ -n "$end" && $end -gt $off ]]; then
            printf 'F\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$end" "$work" "$cli" "$path" "$ino" "$size" "$mtime" "$off" "$le" "$lid" "$sess" "$rest"
            _agents_tokens_read "$cli" "$path" "$off" "$end" "$size"
            budget=$((budget - (end - off))); n=$((n + 1))
        else
            printf 'K\t-\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$work" "$cli" "$path" "$ino" "$size" "$mtime" "$off" "$le" "$lid" "$sess" "$rest"
        fi
    done
}

# _agents_tokens_end FILE OFFSET END SIZE AGE — where a read from OFFSET up to
# END stops: END when the byte before it ends a line (or END is the end of a
# file quiet for AGE seconds, whose writer is done), else just after the last
# newline before END; nothing when there is none (a line still being written,
# or one longer than the budget: a budget-cut read then takes the rest of
# the file).
_agents_tokens_end() {
    local f="$1" off="$2" end="$3" size="$4" age="$5" w=1048576 c r nr l
    if [[ $end -eq $size && $age -ge $_AGENTS_TOKENS_QUIET ]]; then echo "$end"; return 0; fi
    c="$(dd if="$f" bs=1 skip=$((end - 1)) count=1 2>/dev/null; echo x)"
    if [[ "$c" == $'\nx' ]]; then echo "$end"; return 0; fi
    while :; do
        [[ $w -lt $((end - off)) ]] || w=$((end - off))
        r="$(tail -c "+$((end - w + 1))" -- "$f" 2>/dev/null | head -c "$w" | LC_ALL=C awk '{ l = length($0) } END { print NR + 0, l + 0 }')"
        read -r nr l <<<"$r"
        if [[ "$nr" =~ ^[0-9]+$ && $nr -ge 2 ]]; then echo "$((end - l))"; return 0; fi
        if [[ $w -ge $((end - off)) ]]; then
            [[ $end -lt $size ]] && _agents_tokens_end "$f" "$off" "$size" "$size" "$age"
            return 0
        fi
        w=$((w * 4))
    done
}

# _agents_tokens_read CLI FILE OFFSET END SIZE — the lines between OFFSET and
# END that matter to tokens.awk, with their offsets from OFFSET. Lines past
# END (the file grew) are dropped by tokens.awk.
_agents_tokens_read() {
    local re="$_AGENTS_TOKENS_CLAUDE_RE"
    [[ "$1" != codex ]] || re="$_AGENTS_TOKENS_CODEX_RE"
    if [[ $3 -eq 0 && $4 -eq $5 ]]; then
        _agents_tokens_grep "$re" "$2" 2>/dev/null
    elif [[ $4 -eq $5 ]]; then
        tail -c "+$(($3 + 1))" -- "$2" 2>/dev/null | _agents_tokens_grep "$re"
    else
        tail -c "+$(($3 + 1))" -- "$2" 2>/dev/null | head -c "$(($4 - $3))" | _agents_tokens_grep "$re"
    fi
    return 0
}

# _agents_tokens_probe — once per process: whether grep -ab prints each
# matching line's own byte offset (GNU and BSD grep do; BusyBox grep has no
# -b, and ugrep's is the match's offset): _AGENTS_TOKENS_GREPB 1 or 0.
_agents_tokens_probe() {
    [[ -z "${_AGENTS_TOKENS_GREPB:-}" ]] || return 0
    _AGENTS_TOKENS_GREPB=0
    [[ "$(printf 'ab\nxyz\n' | LC_ALL=C grep -abE 'y' 2>/dev/null)" != 3:xyz ]] || _AGENTS_TOKENS_GREPB=1
}

# _agents_tokens_grep ERE [FILE] — FILE's (or stdin's) lines that match ERE,
# as "OFFSET:LINE", OFFSET the line's first byte: grep -ab (-a: a stray NUL
# byte must not turn the rest into "Binary file matches"), or, where that
# gives no line offsets (_agents_tokens_probe), awk counting bytes under
# LC_ALL=C (slower; a NUL byte, which JSON lines never hold raw, would put
# BusyBox awk's count off).
_agents_tokens_grep() {
    if [[ "${_AGENTS_TOKENS_GREPB:-1}" == 1 ]]; then
        if [[ $# -gt 1 ]]; then LC_ALL=C grep -abE "$1" -- "$2"; else LC_ALL=C grep -abE "$1"; fi
    elif [[ $# -gt 1 ]]; then
        _agents_tokens_grep "$1" < "$2"
    else
        LC_ALL=C awk -v re="$1" '$0 ~ re { print o ":" $0 } { o += length($0) + 1 }'
    fi
}
