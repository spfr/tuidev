# shellcheck shell=bash
# lib/agents/grok.sh — Grok CLI's tokens, into the token files.
#
# Grok (`grok`) keeps no transcript of token counts to tail: each session
# rewrites ${GROK_HOME:-~/.grok}/sessions/<url-encoded cwd>/<session id>/
# usage.json, whose .turns[] hold each turn's tokens by model (modelUsage:
# inputTokens, which include the cached reads; cachedReadTokens;
# cacheCreationTokens; outputTokens, reasoning included), its turnNumber and
# endedAt. Each token scan (tokens.sh, under sample.lock) reads the
# usage.json files changed since the last one (grok.stamp), with one jq,
# and appends the turns it has not counted (grok.state: "path<TAB>last
# turnNumber counted") to tokens.tsv as cli grok, agent main, origin "-",
# one row per turn and model:
#   epoch grok project session main model in cache_write cache_read out 0 0 -
# (in: inputTokens less cachedReadTokens). tokens.today gets today's share.
# Grok's models have no list price in prices.tsv: the report counts them
# unpriced. Never ~/.grok/auth.json or any other file: usage.json only.
# Needs jq; without it Grok's tokens are not counted.
#
# Uses: config.sh, util.sh (_agents_awk_eval, _agents_replace), tokens.sh
#   (_agents_tokens_stamp), limits.sh (_AGENTS_JQ_EPOCH); awk/lib_proc.awk
#   (projname).
# Public: _agents_grok_scan, _agents_grok_prune.

# _agents_grok_scan NOW DAY MID — count the Grok turns not counted yet
# (MID: local midnight of DAY, for tokens.today). A no-op without Grok's
# sessions or jq. False, with the state as it was, when it could not be made.
_agents_grok_scan() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    local dir="${GROK_HOME:-$HOME/.grok}/sessions" d="$AGENTS_DATA_DIR" now="$1" day="$2" mid="$3" f turns sums new=() files=()
    [[ -d "$dir" ]] && command -v jq >/dev/null 2>&1 || return 0
    [[ ! -f "$d/grok.stamp" ]] || new=(-newer "$d/grok.stamp")
    _agents_tokens_stamp "$d/grok.stamp.new" "$((now - 2))"
    while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done < <(find "$dir" -mindepth 3 -maxdepth 3 -type f -name usage.json \
        -mtime "-$AGENTS_HISTORY_DAYS" ${new[@]+"${new[@]}"} 2>/dev/null)
    if [[ ${#files[@]} -gt 0 ]]; then
        turns="$(_agents_grok_turns "$now" "${files[@]}")"
        rm -f "$d/grok.add" "$d/grok.state.new"
        sums="$(printf '%s\n' "$turns" | _agents_awk_eval lib_proc "$_AGENTS_GROK_AWK" -F '\t' -v OFS='\t' -v sf="$d/grok.state" \
            -v so="$d/grok.state.new" -v out="$d/grok.add" -v cut="$((now - AGENTS_HISTORY_DAYS * 86400))" -v mid="$mid")" || sums=""
        if [[ "$sums" != sums$'\t'* || ! -f "$d/grok.state.new" ]] || ! mv -f "$d/grok.state.new" "$d/grok.state"; then
            rm -f "$d/grok.add" "$d/grok.state.new" "$d/grok.stamp.new"
            return 1
        fi
        [[ ! -s "$d/grok.add" ]] || cat "$d/grok.add" >> "$d/tokens.tsv"
        rm -f "$d/grok.add"
        _agents_grok_today "$day" "${sums#sums$'\t'}"
    fi
    [[ ! -f "$d/grok.stamp.new" ]] || mv -f "$d/grok.stamp.new" "$d/grok.stamp"
    return 0
}

# _agents_grok_turns NOW FILE... — "path session turn epoch model in
# cache_write cache_read out" for every turn and model of the usage.json
# FILEs: one jq for all, and one per file only when one of them could not
# be read (a file mid-write stops jq's batch). A turn with no endedAt is NOW's.
_agents_grok_turns() {
    local now="$1" f
    shift
    jq -r --argjson now "$now" "$_AGENTS_JQ_EPOCH$_AGENTS_GROK_JQ" "$@" 2>/dev/null && return 0
    for f in "$@"; do jq -r --argjson now "$now" "$_AGENTS_JQ_EPOCH$_AGENTS_GROK_JQ" "$f" 2>/dev/null; done
    return 0
}
# shellcheck disable=SC2016  # jq's own variables
_AGENTS_GROK_JQ='
def n: if type == "number" and . >= 0 then floor else 0 end;
input_filename as $f | (.sessionId // "-" | tostring) as $sid | .turns[]? | select(type == "object")
| ((.endedAt // "" | tostring | try epoch catch 0) // 0 | if . > 0 then . else $now end) as $t
| (.turnNumber | n) as $k
| if (.modelUsage | type) == "object" and (.modelUsage | length) > 0
  then .modelUsage | to_entries[] | [$f, $sid, $k, $t, .key, (.value.inputTokens | n), (.value.cacheCreationTokens | n), (.value.cachedReadTokens | n), (.value.outputTokens | n)]
  else [$f, $sid, $k, $t, (.primaryModelId // "-" | tostring), (.inputTokens | n), (.cacheCreationTokens | n), (.cachedReadTokens | n), (.outputTokens | n)]
  end | @tsv'

# The join with grok.state: the rows of turns past each file's last one
# counted (and within the window, cut) to out, the new state to so, and
# "sums<TAB>in<TAB>cache_write<TAB>cache_read<TAB>out" of the rows from mid on.
# shellcheck disable=SC2016  # awk's own fields
_AGENTS_GROK_AWK='
function dec(s,   o, i, c, h) {
    o = ""
    while ((i = index(s, "%")) > 0) {
        h = toupper(substr(s, i + 1, 2))
        if (h ~ /^[0-9A-F][0-9A-F]$/) c = sprintf("%c", (index("0123456789ABCDEF", substr(h, 1, 1)) - 1) * 16 + index("0123456789ABCDEF", substr(h, 2, 1)) - 1)
        else { c = "%"; h = "" }
        o = o substr(s, 1, i - 1) c; s = substr(s, i + 1 + length(h))
    }
    return o s
}
BEGIN { while ((getline l < sf) > 0) if (split(l, a, "\t") >= 2 && a[2] ~ /^[0-9]+$/) st[a[1]] = a[2] + 0; close(sf) }
NF >= 9 && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ {
    f = $1
    if (!(f in was)) { was[f] = (f in st) ? st[f] : 0; if (!(f in st)) st[f] = 0 }
    if ($3 + 0 > st[f]) st[f] = $3 + 0
    if ($3 + 0 <= was[f] || $4 + 0 < cut) next
    n = split(f, p, "/"); cwd = n >= 3 ? dec(p[n - 2]) : ""
    sid = $2; gsub(/[^A-Za-z0-9_-]/, "", sid); if (sid == "") sid = "-"
    m = $5; gsub(/[^A-Za-z0-9._:\/@+-]/, "", m); if (m == "") m = "-"
    i = $6 - $8; if (i < 0) i = 0
    print $4, "grok", projname(cwd), substr(sid, 1, 64), "main", substr(m, 1, 64), i, $7 + 0, $8 + 0, $9 + 0, 0, 0, "-" > out
    if ($4 + 0 >= mid) { ai += i; aw += $7; ar += $8; ao += $9 }
}
END {
    printf "" > so
    for (f in st) print f, st[f] > so
    printf "sums\t%.0f\t%.0f\t%.0f\t%.0f\n", ai, aw, ar, ao
}'

# _agents_grok_today DAY "IN CW CR OUT" — add Grok's share to tokens.today
# (DAY TOTAL IN CACHE_WRITE CACHE_READ OUT), when it is DAY's.
_agents_grok_today() {
    local f="$AGENTS_DATA_DIR/tokens.today" d="" tot ti tw tr to i w r o
    IFS=$'\t' read -r i w r o <<<"$2"
    [[ "$i$w$r$o" =~ ^[0-9]+$ && $((i + w + r + o)) -gt 0 && -r "$f" ]] || return 0
    IFS=$'\t' read -r d tot ti tw tr to < "$f"
    [[ "$d" == "$1" && "$tot$ti$tw$tr$to" =~ ^[0-9]+$ ]] || return 0
    _agents_replace "$f" "$d"$'\t'"$((tot + i + w + r + o))"$'\t'"$((ti + i))"$'\t'"$((tw + w))"$'\t'"$((tr + r))"$'\t'"$((to + o))"
}

# _agents_grok_prune — the daily prune: grok.state keeps only the files
# still there.
_agents_grok_prune() {
    local f="$AGENTS_DATA_DIR/grok.state" p n keep=""
    [[ -f "$f" ]] || return 0
    while IFS=$'\t' read -r p n; do [[ -f "$p" ]] && keep+="$p"$'\t'"$n"$'\n'; done < "$f"
    _agents_replace "$f" "${keep%$'\n'}"
}
