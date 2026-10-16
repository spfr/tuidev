# shellcheck shell=bash
# lib/agents/limits.sh — the usage limits of every AI CLI: limits.tsv, the
# probes that ask a CLI for its own, `agents limits`, and the menu's Usage
# records.
#
# limits.tsv, private like the rest of $AGENTS_DATA_DIR (nothing with
# AGENTS_HISTORY=0), one line per CLI and window, tab-separated, no header:
#   epoch cli used_percent window_minutes resets_at [label]
# epoch: when the CLI reported it; cli: its family (claude, codex, agy...),
# then ":KEY" for a CLI with several quotas per window (agy:gemini);
# used_percent: 0-100, may have decimals; resets_at: epoch, 0 when the CLI
# gives none (nothing used yet); label: the quota's name for people ("-" or
# absent: none). Each source replaces only its own lines
# (_agents_limits_put), under limits.lock, in one rename:
#   claude  `agents statusline` (statusline.sh), from Claude Code's status
#           line JSON (Pro and Max plans), when a reading changed or is
#           5 minutes old;
#   codex   the token scan (tokens.sh, awk/tokens.awk), from the
#           rate_limits of Codex's latest token_count event (primary and
#           secondary windows);
#   agy     a probe (_agents_limits_probe_agy): `agy -p /quota`, which
#           costs no tokens, every _AGENTS_LIMITS_EVERY seconds, from
#           `agents sample` (the token scan runs the probes).
# A CLI is added with a probe function here (_agents_limits_probe_NAME,
# named in _AGENTS_LIMITS_PROBES) and its name in awk/limits.awk (cliname).
# Grok and Cursor expose no limits locally (Grok's tokens come from its
# session files: grok.sh). Never a credential, a keychain or a vendor API:
# only what the CLIs print or write themselves.
#
# Uses: config.sh, util.sh (_agents_awk, _agents_lock, _agents_replace,
#   _agents_timeout, _agents_window, _agents_now), events.sh
#   (_agents_data_dir); awk/limits.awk.
# Public: agents_limits, _agents_limits_put, _agents_limits_prune,
#   _agents_limits_probe, _agents_limits_lines.

_AGENTS_LIMITS_PROBES="agy"
_AGENTS_LIMITS_EVERY=600
_AGENTS_LIMITS_TIMEOUT=6

# agents_limits [--json] — the latest reading of every CLI's limit windows,
# with when each was read; a window that has reset since is dimmed.
agents_limits() {
    # shellcheck disable=SC2034  # _agents_window sets start and period too
    local mode=view start now off period
    case "${1:-}" in
        "")     ;;
        --json) mode=json ;;
        *)      echo "usage: agents limits [--json]" >&2; return 2 ;;
    esac
    _agents_now now
    _agents_window today "$now" || return 1
    B="${C_B:-}" DIM="${C_DIM:-}" N="${C_0:-}" \
    _agents_awk "lib_fmt lib_json limits" -v mode="$mode" -v lf="$AGENTS_DATA_DIR/limits.tsv" -v now="$now" -v off="$off" \
        -v hist="$AGENTS_HISTORY" -v b="${C_B:-}" -v dim="${C_DIM:-}" -v e="${C_0:-}" </dev/null
}

# _agents_limits_lines — agents tsv's usage records, from the state files
# alone (never a CLI): one per limit window not reset yet, then today's
# denials and compactions when there are any:
#   limit NAME WINDOW PCT RESETS CLI AGE   (RESETS: 14:05, Mon 09:00, Oct 19, "-")
#   denials COUNT TOP_REASON               (TOP_REASON "-" when none was tagged)
#   compacts COUNT
_agents_limits_lines() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    # shellcheck disable=SC2034  # _agents_window sets period too
    local d="$AGENTS_DATA_DIR" start now off period
    [[ -r "$d/limits.tsv" || -r "$d/denials.tsv" || -r "$d/compacts.tsv" ]] || return 0
    _agents_now now
    _agents_window today "$now" || return 0
    _agents_awk "lib_fmt lib_json limits" -v mode=tsv -v lf="$d/limits.tsv" -v df="$d/denials.tsv" -v cf="$d/compacts.tsv" \
        -v now="$now" -v off="$off" -v mid="$start" </dev/null
}

# _agents_limits_put FAMILY ROWS — write ROWS (limits.tsv lines: epoch cli
# used window resets label) into limits.tsv: each replaces the line of its
# cli and window; FAMILY, when not empty, also drops every other line of
# that family (a source that reports all its windows at once, so one that
# went away goes too). Malformed rows are left out. Under limits.lock
# (a second at most), one rename; a no-op with AGENTS_HISTORY=0. False when
# it could not be written.
_agents_limits_put() {
    [[ "$AGENTS_HISTORY" == 1 && -n "$2" ]] || return 0
    local fam="$1" rows="$2"
    (
        umask 077
        _agents_data_dir || exit 1
        f="$AGENTS_DATA_DIR/limits.tsv" lock="$AGENTS_DATA_DIR/limits.lock"
        _agents_lock "$lock" 20 0.05 || exit 1
        # The rows on stdin (an awk -v value can't hold a newline everywhere).
        out="$(printf '%s\n' "$rows" | LC_ALL=C awk -F '\t' -v fam="$fam" -v f="$f" '
            function ok(n, a) {
                return n >= 5 && a[1] ~ /^[0-9]+$/ && a[2] ~ /^[a-z0-9][a-z0-9:._-]*$/ && a[3] ~ /^[0-9]+([.][0-9]+)?$/ \
                    && a[4] ~ /^[1-9][0-9]*$/ && a[5] ~ /^[0-9]+$/
            }
            {
                m = split($0, a, "\t")
                if (!ok(m, a)) next
                l = (m >= 6 && a[6] != "") ? a[6] : "-"
                gsub(/[[:cntrl:]]/, "", l)
                k = a[2] SUBSEP a[4]
                if (!(k in nw)) o[++no] = k
                nw[k] = a[1] "\t" a[2] "\t" a[3] "\t" a[4] "\t" a[5] "\t" substr(l, 1, 64)
            }
            END {
                if (!no) exit 3
                while ((getline ln < f) > 0) {
                    m = split(ln, a, "\t")
                    if (!ok(m, a) || ((a[2] SUBSEP a[4]) in nw)) continue
                    c = a[2]; sub(/:.*/, "", c)
                    if (fam != "" && c == fam) continue
                    print ln
                }
                for (i = 1; i <= no; i++) print nw[o[i]]
            }')" || { _agents_unlock "$lock"; exit 1; }
        _agents_replace "$f" "$out"; rc=$?
        _agents_unlock "$lock"
        exit "$rc"
    )
}

# _agents_limits_prune CUT — drop the readings older than CUT (the daily
# prune, tokens.sh), under limits.lock.
_agents_limits_prune() {
    local f="$AGENTS_DATA_DIR/limits.tsv"
    [[ -f "$f" ]] || return 0
    (
        umask 077
        lock="$AGENTS_DATA_DIR/limits.lock"
        _agents_lock "$lock" 20 0.05 || exit 1
        out="$(LC_ALL=C awk -F '\t' -v cut="$1" '$1 ~ /^[0-9]+$/ && $1 + 0 >= cut' "$f")" || { _agents_unlock "$lock"; exit 1; }
        _agents_replace "$f" "$out"; rc=$?
        _agents_unlock "$lock"
        exit "$rc"
    )
}

# _agents_limits_probe NOW — run each probe in _AGENTS_LIMITS_PROBES whose
# CLI is installed and whose last run is _AGENTS_LIMITS_EVERY seconds old
# (a stamp per probe in the run dir, written first: a failing probe waits
# its turn too), each bounded by _AGENTS_LIMITS_TIMEOUT seconds, and write
# what it reports. Never fails the caller.
_agents_limits_probe() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    # The test harness (AGENTS_TESTING) runs one only when it asks to.
    [[ -z "${AGENTS_TESTING:-}" || "${AGENTS_TEST_PROBES:-}" == 1 ]] || return 0
    local now="$1" p age rows
    for p in $_AGENTS_LIMITS_PROBES; do
        command -v "$p" >/dev/null 2>&1 || continue
        _agents_stamp_age age "$AGENTS_RUN_DIR/limits.$p.stamp" "$now"
        [[ $age -ge $_AGENTS_LIMITS_EVERY ]] || continue
        # Only when the CLI was used since its last reading (else the quota
        # can't have moved): a probe has a cost of its own.
        if [[ -f "$AGENTS_RUN_DIR/limits.$p.stamp" ]] && declare -F "_agents_limits_used_$p" >/dev/null; then
            "_agents_limits_used_$p" "$AGENTS_RUN_DIR/limits.$p.stamp" || continue
        fi
        { mkdir -p "$AGENTS_RUN_DIR" && _agents_replace "$AGENTS_RUN_DIR/limits.$p.stamp" "$now"; } 2>/dev/null || continue
        rows="$("_agents_limits_probe_$p" "$now" 2>/dev/null)" || continue
        [[ -z "$rows" ]] || _agents_limits_put "$p" "$rows" || true
    done
    return 0
}

# _agents_limits_probe_agy NOW — Antigravity's quota: `agy -p /quota
# --output-format json` (no model call: num_turns 0, about a second),
# .command.data.groups[].buckets[] → one row per bucket: cli agy:GROUP (the
# bucket id without its -5h/-weekly), used = 100 × (1 − remaining_fraction),
# window 300 (5h) or 10080 (weekly), resets_at from reset_time (none while
# nothing is used: it is then just now + the window), label: the group's
# name ("Gemini Models" → Gemini). It runs as "agents-probe-agy" (exec -a),
# so a refresh that catches it never lists it as a session. Needs jq.
# _agents_limits_used_agy STAMP — Antigravity was used since STAMP: a
# conversation of it changed. (Its quota probe writes a log, no conversation.)
_AGENTS_AGY_CONVERSATIONS="${_AGENTS_AGY_CONVERSATIONS:-$HOME/.gemini/antigravity-cli/conversations}"
_agents_limits_used_agy() {
    [[ -d "$_AGENTS_AGY_CONVERSATIONS" ]] || return 1
    [[ -n "$(find "$_AGENTS_AGY_CONVERSATIONS" -type f -newer "$1" 2>/dev/null | head -1)" ]]
}

_agents_limits_probe_agy() {
    local bin out
    bin="$(command -v agy)" && command -v jq >/dev/null 2>&1 || return 1
    out="$(_agents_timeout "$_AGENTS_LIMITS_TIMEOUT" _agents_exec_as agents-probe-agy "$bin" -p /quota --output-format json 2>/dev/null)" || return 1
    printf '%s' "$out" | jq -r --argjson now "$1" "$_AGENTS_JQ_EPOCH$_AGENTS_LIMITS_AGY_JQ" 2>/dev/null
}
# jq's epoch: an ISO 8601 time as epoch seconds (Z, or an offset such as
# +02:00 or -0500; a fraction dropped), nothing for anything else: date's
# parsing differs between BSD, GNU and BusyBox, jq's does not.
# shellcheck disable=SC2016  # jq's own variables
_AGENTS_JQ_EPOCH='
def epoch: (sub("\\.[0-9]+"; "")) as $t
  | if ($t | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) then ($t | fromdateiso8601)
    elif ($t | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:?[0-9]{2}$")) then
      (($t[0:19] + "Z") | fromdateiso8601) as $b | ($t[19:] | gsub(":"; "")) as $z
      | $b - (if $z[0:1] == "-" then -1 else 1 end) * (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60)
    else empty end;'
# shellcheck disable=SC2016  # jq's own variables
_AGENTS_LIMITS_AGY_JQ='
.command.data.groups[]? | (.name // "" | tostring | sub(" [Mm]odels$"; "")) as $g | .buckets[]?
| select((.remaining_fraction | type) == "number")
| (if .window == "5h" then 300 elif .window == "weekly" then 10080 elif .window == "daily" then 1440 else empty end) as $w
| ((.id // "" | tostring | sub("-(5h|weekly|daily)$"; "") | ascii_downcase | gsub("[^a-z0-9._-]"; "")) | if . == "" then "default" else . end) as $k
| ((1 - .remaining_fraction) * 100 | if . < 0 then 0 elif . > 100 then 100 else . end | . + 0.5 | floor) as $u
| (if .remaining_fraction >= 1 then 0 else ((.reset_time // "" | tostring | try epoch catch 0) // 0) end) as $r
| [$now, "agy:" + $k, $u, $w, $r, ($g | gsub("[\t\n]"; " ") | if . == "" then "-" else .[0:40] end)] | @tsv'

# _agents_exec_as NAME CMD [ARGS...] — run CMD with NAME as its argv[0],
# the name ps shows (a probe is then never taken for a session).
_agents_exec_as() {
    local name="$1"; shift
    exec -a "$name" "$@"
}
