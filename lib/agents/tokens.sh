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
# message of its own (_agents_tokens_forks; then tokens.state remembers it is
# past it); and a rewound or resumed session writes earlier messages again,
# with their old times: a message a minute older than the newest line read
# from its transcript is one of those. Model "<synthetic>" made no API call.
# Codex logs a token_count event per turn, sometimes twice: a turn counts
# once, by its running total.
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
# values never hold a tab or a newline; the .tsv files are pruned with
# history.tsv:
#   tokens.tsv    one row per API message (Claude Code) or turn (Codex):
#                   epoch cli project session agent model in cache_write cache_read out poll
#                 project: as runs.tsv names it (agents_project of the line's
#                 cwd); session: the session id (a subagent's main session);
#                 agent: main, the subagent type, or "-"; in excludes cached
#                 input (Codex's input_tokens counts it: it becomes
#                 cache_read); poll: 1 when every tool call in the message
#                 only waits (sleep, a sleep loop, reading a task's output
#                 file, BashOutput, TaskOutput, Monitor).
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
#   limits.tsv    epoch cli used_percent window_minutes resets_at: Codex's
#                 latest primary rate limit (one line, replaced).
#   tokens.today  day total in cache_write cache_read out: today's sums (local
#                 day), rewritten after each scan, for the menu.
#   tokens.state  one line per transcript read, kept while its last_epoch is
#                 within the window (listed or not: a sample that does not
#                 see a transcript must not make the next count it again):
#                   path cli inode offset last_epoch last_id session project agent model pending fork
#                 offset: the bytes read (whole lines; the last message of an
#                 active file is read again next time, until it is complete);
#                 a new inode or a shorter file is read again from 0, and only
#                 rows after last_epoch count (or at it, another message
#                 than last_id). last_id: the last message id (Codex: running
#                 total) counted; pending: the last message's tool calls,
#                 "id=tool=subject;…", for a denial that follows; fork: the
#                 id of the subagent a fork copied, while it is still in
#                 that copy, else "-".
#
# Uses: config.sh, util.sh (_agents_awk, _agents_window, _agents_replace),
#   transcript.sh (_agents_tx_find, _agents_tx_session_of,
#   _agents_tx_agent_types, _agents_tx_fork_parents); awk/tokens_plan.awk,
#   awk/tokens.awk.
# Public: _agents_tokens_scan.

# The most a sample reads (bytes, files), and how long a transcript must be
# quiet before its last message counts without the line that ends it.
_AGENTS_TOKENS_BUDGET=$((64 * 1048576))
_AGENTS_TOKENS_FILES=512
_AGENTS_TOKENS_QUIET=120
_AGENTS_TOKENS_CLAUDE_RE='"(type":"assistant"|subtype":"compact_boundary"|is_error":true)'
_AGENTS_TOKENS_CODEX_RE='"type":"(session_meta|turn_context|token_count)"'

# _agents_tokens_scan NOW DAY — scan the transcripts (a no-op with
# AGENTS_HISTORY=0). Runs inside agents_sample (sample.lock, umask 077); the
# state is replaced before the rows are appended, so a failure loses rows
# rather than counting them twice. False, with tokens.state as it was, when
# the scan could not be made. Today (DAY, and its midnight) is NOW's.
_agents_tokens_scan() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    # shellcheck disable=SC2034  # _agents_window sets off and period too
    local dir="$AGENTS_DATA_DIR" now="$1" day="$2" start off period plan types forks f o ag fk today subs=() kids=()
    _agents_window today "$1" || return 1
    plan="$(_agents_tokens_list | _agents_awk tokens_plan -F '\t' -v OFS='\t' -v sf="$dir/tokens.state" -v cut="$((now - AGENTS_HISTORY_DAYS * 86400))" \
        | LC_ALL=C sort -t "$(printf '\t')" -k6,6nr -k3,3)" || return 1
    # The subagents this scan may read: the types of those not known yet, in
    # one grep; and the forks among them that a subagent spawned, with the
    # ids of the messages they copied from it (_agents_tokens_forks).
    while IFS=$'\t' read -r _ _ f _ _ _ o _ _ _ _ ag _ _ fk; do
        [[ "$f" == */subagents/agent-*.jsonl ]] || continue
        [[ "$ag" != - ]] || subs+=("$f")
        [[ ( "$ag" != - || "$o" != 0 ) && "$fk" == - ]] || kids+=("$f")
    done < <(LC_ALL=C awk -F '\t' '$1 == 1' <<<"$plan" | head -n "$_AGENTS_TOKENS_FILES")
    types="$(_agents_tx_agent_types ${subs[@]+"${subs[@]}"})"
    forks="$(_agents_tokens_forks ${kids[@]+"${kids[@]}"})"
    rm -f "$dir"/tokens.add.* "$dir/tokens.state.new" 2>/dev/null
    _agents_tokens_probe
    if ! today="$(_agents_tokens_feed "$now" <<<"$plan" \
            | _agents_awk "lib_proc lib_activity tokens" -v now="$now" -v cut="$((now - AGENTS_HISTORY_DAYS * 86400))" \
                -v mid="$start" -v day="$day" -v quiet="$_AGENTS_TOKENS_QUIET" -v d="$dir" -v tyf=/dev/fd/3 -v frf=/dev/fd/4 \
                3<<<"$types" 4<<<"$forks")" \
        || [[ "$today" != "$day"$'\t'* ]] \
        || { [[ -f "$dir/tokens.state.new" ]] && ! mv -f "$dir/tokens.state.new" "$dir/tokens.state"; }; then
        rm -f "$dir"/tokens.add.* "$dir/tokens.state.new" 2>/dev/null
        return 1
    fi
    for f in tokens compacts denials; do
        [[ ! -s "$dir/tokens.add.$f" ]] || cat "$dir/tokens.add.$f" >> "$dir/$f.tsv"
    done
    [[ ! -f "$dir/tokens.add.limits" ]] || mv -f "$dir/tokens.add.limits" "$dir/limits.tsv"
    rm -f "$dir"/tokens.add.* 2>/dev/null
    _agents_replace "$dir/tokens.today" "$today"
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

# _agents_tokens_list — "@claude" then Claude Code's transcripts, "@codex"
# then Codex's, changed within AGENTS_HISTORY_DAYS: "inode<TAB>size<TAB>
# mtime<TAB>path", one stat per batch of files (no device: BSD stat's %d
# looks each one up by name, a thousand times slower).
_agents_tokens_list() {
    local c="${CODEX_HOME:-$HOME/.codex}/sessions" st
    if [[ "${OSTYPE:-}" == darwin* ]]; then st=(/usr/bin/stat -f '%i%t%z%t%m%t%N'); else st=(stat -c $'%i\t%s\t%Y\t%n'); fi
    echo "@claude"
    _agents_tx_find "$AGENTS_HISTORY_DAYS" -exec "${st[@]}" {} +
    echo "@codex"
    [[ ! -d "$c" ]] || find "$c" -mindepth 4 -maxdepth 4 -type f -name 'rollout-*.jsonl' \
        -mtime "-$AGENTS_HISTORY_DAYS" -exec "${st[@]}" {} + 2>/dev/null
    return 0
}

# _agents_tokens_feed NOW < PLAN — awk/tokens.awk's input: for each planned
# transcript a header, "F<TAB>END<TAB>PLAN_LINE" followed by the lines it
# reads ("OFFSET:LINE", OFFSET from the old offset: _agents_tokens_grep), or
# "K<TAB>-<TAB>PLAN_LINE" for one it leaves as it was. PLAN_LINE:
#   work cli path inode size mtime offset last_epoch last_id session project agent model pending fork
_agents_tokens_feed() {
    local now="$1" budget="$_AGENTS_TOKENS_BUDGET" n=0 work cli path ino size mtime off le lid sess rest end
    while IFS=$'\t' read -r work cli path ino size mtime off le lid sess rest; do
        end=""
        if [[ "$work" == 1 && $budget -gt 0 && $n -lt $_AGENTS_TOKENS_FILES && -f "$path" && ! -L "$path" ]]; then
            end=$size
            [[ $((size - off)) -le $budget ]] || end=$((off + budget))
            end="$(_agents_tokens_end "$path" "$off" "$end" "$size" "$((now - mtime))")"
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
