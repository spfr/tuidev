# shellcheck shell=bash
# lib/agents/activity.sh — which session a process is, and what it is doing
# now, from the end of its transcript.
#
# Claude Code records each running session in
# $CLAUDE_CONFIG_DIR/sessions/PID.json (default ~/.claude): its id, name,
# status, version and the process's start time, which must match (a reused
# pid names another process). The session's transcript is then
# projects/*/ID.jsonl. A Codex session keeps its rollout file
# ($CODEX_HOME/sessions/…/rollout-*-ID.jsonl) open, so the process's open
# files name it. Only the last 256 KiB of a transcript are read (tail -c),
# whatever its size, and jq reads those lines, the first, partial one
# dropped. Without jq there is no activity to show.
#
# Owns: a session's identity (id, name, status, version, transcript) and its
#   activity: the last tool call and what it was aimed at, the last line it
#   wrote, the model, and when.
# Uses: config.sh; jq.
# Public: _agents_session_of, _agents_activity.

_AGENTS_TX_TAIL=262144   # bytes of a transcript read for its activity

# _agents_session_of PID KIND AGE [FILES] — "key<TAB>value" lines: session,
# name, status, version, transcript; nothing that is unknown. KIND: claude or
# codex. AGE: how long the process has run (seconds), checked against the
# start Claude Code recorded (procStart, in UTC), so a record a crash left
# behind never names a new process with the same pid. FILES: the paths the
# process has open (lsof), where Codex's rollout file is found.
_agents_session_of() {
    local pid="$1" kind="$2" age="$3" files="${4:-}" cdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local rec sid name status ver pstart now f
    case "$kind" in
        claude)
            [[ -f "$cdir/sessions/$pid.json" ]] && command -v jq >/dev/null 2>&1 || return 0
            rec="$(jq -r '[.sessionId, .name, .status, .version,
                    (.procStart | strings | gsub("  +"; " ") | try (strptime("%a %b %d %H:%M:%S %Y") | mktime) catch null)]
                | map(if . == null then "-" else tostring | gsub("[[:cntrl:]]"; " ") end) | join("\t")' \
                "$cdir/sessions/$pid.json" 2>/dev/null)" || return 0
            IFS=$'\t' read -r sid name status ver pstart <<<"$rec"
            if [[ "$pstart" =~ ^[0-9]+$ && "$age" =~ ^[0-9]+$ ]]; then
                _agents_now now
                (( (now - age - pstart) * (now - age - pstart) <= 25 )) || return 0
            fi
            [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
            printf 'session\t%s\n' "$sid"
            [[ "$name" == - ]] || printf 'name\t%s\n' "$name"
            [[ "$status" == - ]] || printf 'status\t%s\n' "$status"
            [[ "$ver" == - ]] || printf 'version\t%s\n' "$ver"
            for f in "$cdir/projects/"*/"$sid.jsonl"; do
                [[ -f "$f" ]] && { printf 'transcript\t%s\n' "$f"; break; }
            done ;;
        codex)
            while IFS= read -r f; do
                [[ "$f" == */sessions/*/rollout-*.jsonl && -f "$f" ]] || continue
                sid="${f##*/}"; sid="${sid%.jsonl}"
                [[ "$sid" =~ ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$ ]] && printf 'session\t%s\n' "${BASH_REMATCH[1]}"
                printf 'transcript\t%s\n' "$f"
                break
            done <<<"$files" ;;
    esac
    return 0
}

# The jq that reads a transcript's last lines (Claude Code's and Codex's) for
# _agents_activity: the last tool call (name, and the file, command, pattern
# or URL it was given), the last text the assistant wrote, the model, and the
# time of the last of these.
# shellcheck disable=SC2016  # jq source
_AGENTS_ACTIVITY_JQ='
def one: tostring | gsub("[[:cntrl:]]"; " ") | gsub("  +"; " ") | sub("^ "; "") | .[0:160];
def lastline: tostring | split("\n") | map(select(test("\\S"))) | (last // "");
def aim: if type == "object" then (.file_path // .notebook_path // .path // .command // .pattern // .url // .query // .description // .prompt // "")
         elif type == "array" then (map(tostring) | join(" ")) else . end | lastline;
def when: (. // "") | tostring | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null);
reduce (inputs | fromjson? // empty | objects) as $l ({};
    if $l.type == "assistant" and ($l.message | type) == "object" then
        .model = ($l.message.model // .model)
        | reduce ($l.message.content | if type == "array" then .[] else empty end | objects) as $c (.;
            if $c.type == "tool_use" then .tool = $c.name | .aim = ($c.input | aim) | .at = ($l.timestamp | when)
            elif $c.type == "text" and ($c.text | test("\\S")) then .said = ($c.text | lastline) | .at = ($l.timestamp | when)
            else . end)
    elif $l.type == "turn_context" then .model = ($l.payload.model // .model)
    elif $l.type == "response_item" and ($l.payload | type) == "object" then
        ($l.payload) as $p
        | if ($p.type | tostring | test("call$")) then
              .tool = ($p.name // "shell")
              | .aim = (($p.arguments // $p.input // $p.action // "") | if type == "string" then (fromjson? // .) else . end
                        | if type == "object" then (.command // .cmd // .path // .) else . end
                        | if type == "array" then (map(tostring) | (if length > 2 and (.[1] == "-lc" or .[1] == "-c") then .[2:] else . end) | join(" ")) else . end
                        | aim)
              | .at = ($l.timestamp | when)
          elif $p.type == "message" and $p.role == "assistant" then
              ([$p.content[]? | objects | .text? // empty] | join("\n")) as $t
              | if ($t | test("\\S")) then .said = ($t | lastline) | .at = ($l.timestamp | when) else . end
          else . end
    else . end)
| (if .tool then "tool\t" + (.tool | one) else empty end),
  (if (.aim // "") != "" then "aim\t" + (.aim | one) else empty end),
  (if .said then "said\t" + (.said | one) else empty end),
  (if .model then "model\t" + (.model | one) else empty end),
  (if .at then "at\t" + (.at | floor | tostring) else empty end)'

# _agents_activity TRANSCRIPT — "key<TAB>value" lines: tool, aim, said,
# model, at (epoch), from the transcript's last _AGENTS_TX_TAIL bytes.
_agents_activity() {
    [[ -f "$1" && -r "$1" ]] && command -v jq >/dev/null 2>&1 || return 0
    tail -c "$_AGENTS_TX_TAIL" "$1" 2>/dev/null | jq -Rnr "$_AGENTS_ACTIVITY_JQ" 2>/dev/null
    return 0
}
