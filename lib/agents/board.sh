# shellcheck shell=bash
# lib/agents/board.sh — `agents board`: one screen for every session on every
# machine, to glance at from the pane you work in or to leave open.
#
# The list is one line a session, grouped by what you would do about it:
# Needs you (the longest wait first), To review, Working, and the parked ones
# folded into a line. A line is a name that stays (the session's own task
# title, else its project), a word or two for what it does, since when, its
# machine when there is more than one, and a count of what runs under it. The
# right-hand side follows the cursor: why it waits, what runs under it, the end
# of its pane, its model, tokens and cost. Nothing else is on screen until a key
# asks for it:
#   enter   go to that session's pane (here: agents jump; elsewhere: a look at
#           its pane), or open what runs under one
#   tab     the lens: Attention, Tree (each session with its sub-agents and
#           commands), Machines; shift-tab goes back, 1 2 3 pick one
#   ← →     the right-hand side: Card, Trace (what the session did, in
#           order), Pane (more of it), Details (agents show)
#   space   hide or show the right-hand side · . the parked · / find
#   ctrl-p  everything you can do with the row, and everywhere else
#   ctrl-k  stop it (agents kill: its refusals and its y/N question)
#   -       back to the pane you came from · ? the keys · q quit
# The mouse does the same: a click selects, a double click goes, the wheel
# scrolls, and each word of the footer is a button.
#
# This machine answers on every reload. A board reloads when Herdr says
# something changed: the tuidev.link plugin's event hooks run `agents board
# --poke`, which posts fzf's ctrl-r to each board's --listen socket (a Unix
# socket beside its state; never a port). The timer stays as the fallback:
# every AGENTS_BOARD_EVERY seconds, 15 while a board listens and 5 where it
# can't (where fzf has no every(): ctrl-r). The others answer `agents board --rows` over ssh and are
# asked again once their answer is AGENTS_BOARD_REMOTE seconds old (20), in
# the background: the list never waits for a machine twice. What they send
# is text, checked in one place (awk/board_view.awk).
#
# Owns: `agents board`, its rows, list, card, trace, keys, palette and
#   actions, and the run dir's board/ (each machine's last answer, the pane
#   to go back to, and per board ui.PID.*: its lens, view and switches, the
#   rows and header of its last list, its listen record and socket).
# Uses: config.sh (AGENTS_RUN_DIR, AGENTS_MEM_WARN), util.sh, palette.sh (the
#   colors), glyph.sh (_agents_glyph_map), snapshot.sh (agents_collect),
#   assess.sh (_agents_with_needs), activity.sh (_agents_session_of),
#   transcript.sh (_agents_tx_agent_type), watched.sh (_agents_mtimes),
#   system.sh, limits.sh (_agents_limits_lines), remote.sh (machines, ssh),
#   map.sh (_agents_map_act, _agents_map_remote, _agents_map_plain,
#   _AGENTS_MAP_ID_RE), pick.sh (_agents_fzf), where.sh and kill.sh through
#   agents_main; awk/board_rows.awk, awk/board_view.awk, awk/board_trace.awk;
#   curl (a poke), nc (back to a pane no agent holds).
# Public: agents_board.

# What another machine runs over ssh: its rows. When they don't come, why:
# no agents there, an agents too old to have a board (its help names none),
# or one that has a board and did not answer.
# shellcheck disable=SC2016  # the remote shell expands $HOME
_AGENTS_BOARD_REMOTE_CMD='a="$HOME/.local/bin/agents"; if [ ! -x "$a" ]; then printf "sys\tno agents there (tuidev install --pack monitoring)\n"; elif ! "$a" board --rows 2>/dev/null; then if "$a" help 2>/dev/null | grep -q "agents board"; then printf "sys\tno answer from agents there\n"; else printf "sys\tneeds a newer tuidev there (tuidev update)\n"; fi; fi'
_AGENTS_BOARD_SUB_RUN=90      # a sub-agent's transcript written this lately: it runs
_AGENTS_BOARD_SUB_MIN=30      # minutes a finished sub-agent stays listed
_AGENTS_BOARD_SUB_MAX=12      # sub-agents listed for one session, newest first
_AGENTS_BOARD_TRACE_TAIL=4194304   # bytes of a transcript the trace reads, from its end
_AGENTS_BOARD_TRACE_MAX=40    # events the trace shows at most

_agents_board_dir() { REPLY="$AGENTS_RUN_DIR/board"; [[ -d "$REPLY" ]] || mkdir -p "$REPLY" 2>/dev/null; }

# This board's lens, view and switches: a file each beside AGENTS_BOARD_UI,
# which fzf's commands inherit.
_agents_board_get() { local v=""; [[ -z "${AGENTS_BOARD_UI:-}" ]] || { IFS= read -r v < "$AGENTS_BOARD_UI.$1"; } 2>/dev/null; printf '%s' "${v:-$2}"; }
_agents_board_put() { [[ -z "${AGENTS_BOARD_UI:-}" ]] || printf '%s\n' "$2" > "$AGENTS_BOARD_UI.$1"; }

# _agents_board_subs RECORDS — "sub<TAB>PID<TAB>ID<TAB>TYPE<TAB>AGE<TAB>run|done"
# for the sub-agents of each Claude Code session here: those whose transcript
# changed in the last _AGENTS_BOARD_SUB_MIN minutes, newest first. One runs
# while its transcript is being written.
_agents_board_subs() {
    local pid kind age key val tx d now m f id type a n files st
    _agents_now now
    while IFS=$'\t' read -r pid kind age; do
        [[ "$kind" == claude && "$pid" =~ ^[0-9]+$ ]] || continue
        tx=""
        while IFS=$'\t' read -r key val; do [[ "$key" != transcript ]] || tx="$val"; done < <(_agents_session_of "$pid" "$kind" "$age")
        d="${tx%.jsonl}/subagents"
        [[ -n "$tx" && -d "$d" ]] || continue
        files=()
        while IFS= read -r f; do files+=("$f"); done < <(find "$d" -maxdepth 1 -type f -name 'agent-*.jsonl' -mmin "-$_AGENTS_BOARD_SUB_MIN" 2>/dev/null)
        [[ ${#files[@]} -gt 0 ]] || continue
        n=0
        while IFS=$'\t' read -r m f; do
            [[ "$m" =~ ^[0-9]+$ ]] || continue
            id="${f##*/agent-}"; id="${id%.jsonl}"
            # A letter in it: never an id that reads as a process id.
            [[ "$id" =~ ^[A-Za-z0-9_-]{1,64}$ && "$id" == *[A-Za-z]* ]] || continue
            type="$(_agents_tx_agent_type "$f")"
            a=$((now - m)); [[ $a -ge 0 ]] || a=0
            st=run; [[ $a -lt $_AGENTS_BOARD_SUB_RUN ]] || st="done"
            printf 'sub\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$id" "${type:--}" "$a" "$st"
            n=$((n + 1)); [[ $n -lt $_AGENTS_BOARD_SUB_MAX ]] || break
        done < <(_agents_mtimes "${files[@]}" | LC_ALL=C sort -rn)
    done < <(awk -F '\t' '$1 == "agent" { print $2 "\t" $3 "\t" $4 }' <<<"$1")
}

# _agents_board_rows — this machine's rows (awk/board_rows.awk has the format).
_agents_board_rows() {
    local r _load cores memfree _rest cpu warn=0
    r="$(agents_collect)" || return 1
    IFS=$'\t' read -r _load cores memfree _rest <<<"$(agents_system)"
    cpu="$(_agents_cpu_pct "$cores" "$r" 2>/dev/null)"
    [[ ! "${AGENTS_MEM_WARN:-}" =~ ^[0-9]+$ ]] || warn=$((AGENTS_MEM_WARN * 1048576))
    { _agents_board_subs "$r"; _agents_with_needs "$r"; } \
        | _agents_awk "lib_fmt board_rows" -F '\t' -v warn_kib="$warn" \
            -v sys="cpu ${cpu:--}% · memory ${memfree:--}% free"
}

# _agents_board_fetch TARGET FILE — ask one machine, and keep its answer under
# an "at<TAB>EPOCH" line (at most 1 MiB of rows; none: it did not answer).
_agents_board_fetch() {
    local now tmp="$2.$$"
    _agents_now now
    { printf 'at\t%s\n' "$now"
      _agents_timeout 12 _agents_ssh_mux "$1" "$_AGENTS_BOARD_REMOTE_CMD" 2>/dev/null | head -c 1048576
    } > "$tmp" 2>/dev/null
    [[ "$(wc -l < "$tmp" 2>/dev/null)" -gt 1 ]] || printf 'sys\tno answer (ssh %s)\n' "$1" >> "$tmp"
    mv -f "$tmp" "$2" 2>/dev/null || rm -f "$tmp"
}

# _agents_board_all [MACHINE|local] — every machine's rows, each prefixed
# with its label: this one now, the others from their last answer. A machine
# never asked is asked and waited for (all of them at once); one whose answer
# is old is asked again in the background, for the next reload.
_agents_board_all() {
    local only="${1:-}" dir now label target key f at pids=() max="${AGENTS_BOARD_REMOTE:-20}"
    _agents_board_dir; dir="$REPLY"
    [[ "$max" =~ ^[0-9]+$ ]] || max=20
    _agents_now now
    if [[ -z "$only" || "$only" == local ]]; then
        _agents_board_rows 2>/dev/null | awk '{ print "local\t" $0 }'
    fi
    [[ "$only" != local ]] || return 0
    while IFS=$'\t' read -r label target _; do
        [[ -n "$label" && -n "$target" ]] || continue
        [[ -z "$only" || "$only" == "$label" ]] || continue
        key="$(printf '%s' "$label" | cksum)"; f="$dir/m.${key%% *}"
        printf '%s\t%s\n' "$label" "$f"
        at=""
        [[ ! -r "$f" ]] || { IFS=$'\t' read -r _ at _ < "$f"; } 2>/dev/null
        if [[ ! "$at" =~ ^[0-9]+$ ]]; then
            _agents_board_fetch "$target" "$f" </dev/null >/dev/null 2>&1 &
            pids+=("$!")
        elif [[ $((now - at)) -ge $max ]]; then
            # The fetcher holds the lock, not this run: a list that ends
            # before the answer comes leaves it held, so the next reload does
            # not ask again.
            ( _agents_lock "$f.lock" 2>/dev/null || exit 0
              _agents_board_fetch "$target" "$f"; _agents_unlock "$f.lock" ) </dev/null >/dev/null 2>&1 &
        fi
    done < <(_agents_machines 2>/dev/null) > "$dir/machines.$$"
    [[ ${#pids[@]} -eq 0 ]] || wait "${pids[@]}" 2>/dev/null
    while IFS=$'\t' read -r label f; do
        [[ -r "$f" ]] || continue
        awk -v l="$label" 'NR > 1 { print l "\t" $0 }' "$f"
    done < "$dir/machines.$$"
    rm -f "$dir/machines.$$"
}

# _agents_board_limits — every CLI's fullest limit window on one line:
# "Claude 62% of 5h · Codex 18% of week". Nothing where none is known.
_agents_board_limits() {
    _agents_limits_lines 2>/dev/null | awk -F '\t' '
        $1 == "limit" && $4 ~ /^[0-9.]+$/ { if (!($2 in p)) o[++n] = $2; if (!($2 in p) || $4 + 0 > p[$2] + 0) { p[$2] = $4; w[$2] = $3 } }
        END { for (i = 1; i <= n; i++) printf "%s%s %d%% of %s", (i > 1 ? " \302\267 " : ""), o[i], p[o[i]], w[o[i]] }'
}

# _agents_board_view MODE [AWK_OPTION...] < ROWS — awk/board_view.awk, with the
# colors and the kinds' marks.
_agents_board_view() {
    local mode="$1"; shift
    _agents_awk_colored "lib_fmt lib_maprows board_view" -F '\t' -v mode="$mode" -v home="$HOME" -v glyphs="$(_agents_glyph_map)" "$@"
}

# _agents_board_list [MACHINE] — the list, as fzf gets it; MACHINE defaults
# to the board's own (AGENTS_BOARD_ONLY), so every reload keeps it. A board
# keeps the rows it was made from (ui.PID.rows, for the card) and the header
# (ui.PID.header) beside its other state: two boards never share them.
# Without a board (the plain list) nothing is kept.
_agents_board_list() {
    local dir cols="${FZF_COLUMNS:-${COLUMNS:-}}" w rows hf=""
    _agents_board_dir; dir="$REPLY"
    _agents_colors
    [[ "$cols" =~ ^[0-9]+$ ]] || cols="${AGENTS_WIDTH:-120}"
    # The list's share of the window: all of it with the right-hand side
    # hidden or under it (or no right-hand side), a little over half beside it.
    w="$cols"
    [[ -z "${AGENTS_BOARD_UI:-}" || "$(_agents_board_get side 1)" != 1 || $cols -lt 100 ]] || w=$((cols * 54 / 100))
    if [[ -n "${AGENTS_BOARD_UI:-}" ]]; then rows="$AGENTS_BOARD_UI.rows" hf="$AGENTS_BOARD_UI.header.$$"
    else rows="$dir/rows.$$"; fi
    _agents_board_all "${1:-${AGENTS_BOARD_ONLY:-}}" > "$rows.$$" 2>/dev/null
    mv -f "$rows.$$" "$rows"
    LIMITS="$(_agents_board_limits)" _agents_board_view list -v lens="$(_agents_board_get lens attention)" \
        -v all="$(_agents_board_get all 0)" -v W="$w" -v hf="$hf" < "$rows"
    if [[ -z "${AGENTS_BOARD_UI:-}" ]]; then rm -f "$rows"
    elif [[ -f "$hf" ]]; then mv -f "$hf" "$AGENTS_BOARD_UI.header"; fi
}

_agents_board_header() { [[ -z "${AGENTS_BOARD_UI:-}" ]] || cat "$AGENTS_BOARD_UI.header" 2>/dev/null; }

# _agents_board_rowsf — REPLY: the rows this board's list was made from.
_agents_board_rowsf() { REPLY="${AGENTS_BOARD_UI:-$AGENTS_RUN_DIR/board/none}.rows"; }

# _agents_board_idok KIND ID — an id of the shape its kind has.
_agents_board_idok() {
    case "$1" in
        ses|cmd|proc) [[ "$2" =~ $_AGENTS_MAP_ID_RE ]] ;;
        sub)          [[ "$2" =~ ^[A-Za-z0-9_-]{1,64}$ && "$2" == *[A-Za-z]* ]] ;;
        *)            return 1 ;;
    esac
}

# _agents_board_tabs CURRENT NAME... — " Card  Pane  Details ", CURRENT lit.
_agents_board_tabs() {
    local cur="$1" t out=""; shift
    for t in "$@"; do
        if [[ "$t" == "$cur" ]]; then out+=" $C_ACC$C_B$t$C_0 "; else out+=" $C_DIM$t$C_0 "; fi
    done
    printf '%s' "$out"
}

# _agents_board_pane MACHINE ID LINES — the end of a session's pane, as plain
# text with its empty lines squeezed; a line saying so when it can't be read.
_agents_board_pane() {
    local out
    if [[ "$1" == local ]]; then out="$(agents_main peek "$2" "$3" 2>/dev/null | _agents_map_plain)"
    else out="$(_agents_map_remote "$1" peek "$2" "$3" 2>/dev/null | _agents_map_plain)"; fi
    out="$(printf '%s\n' "$out" | awk -v n="$3" '
        { sub(/[ \t]+$/, "") }
        $0 == "" { blank++; next }
        { if (m && blank) l[++m] = ""; blank = 0; l[++m] = $0 }
        END { for (i = (m > n ? m - n + 1 : 1); i <= m; i++) print "  " l[i] }')"
    if [[ -n "$out" ]]; then printf '%s\n' "$out"
    else printf '  %s(its pane is not one that can be read from here)%s\n' "$C_DIM" "$C_0"; fi
}

# _agents_board_facts MACHINE ID — "branch · model · tokens · cost", from
# `agents show --json` on its machine; nothing without jq or an answer.
_agents_board_facts() {
    local j
    command -v jq >/dev/null 2>&1 || return 0
    if [[ "$1" == local ]]; then j="$(agents_main show --json "$2" 2>/dev/null)"
    else j="$(_agents_map_remote "$1" show --json "$2" 2>/dev/null | head -c 262144)"; fi
    printf '%s' "$j" | jq -r '[.branch, .session.model, .info.tokens, .info.cost] | map(select(type == "string" and . != "")) | map(.[0:60]) | join(" · ")' 2>/dev/null \
        | _agents_map_plain | head -n 1
}

# _agents_board_transcript PID@START — the transcript of the Claude Code
# session that process is, when it still runs (its start time the same) and
# its record is its own (activity.sh checks that against how long it has run).
_agents_board_transcript() {
    local pid want st a b c d e etime age key val
    _agents_token "$1" || return 0
    pid="${BASH_REMATCH[1]}" want="${BASH_REMATCH[3]}"
    read -r etime st a b c d e _ <<<"$(LC_ALL=C ps -o etime=,stat=,lstart= -p "$pid" 2>/dev/null)"
    [[ -n "$e" && "$st" != Z* && "${a}_${b}_${c}_${d}_${e}" == "$want" ]] || return 0
    age="$(agents_secs "$etime")"
    while IFS=$'\t' read -r key val; do
        [[ "$key" != transcript ]] || { printf '%s\n' "$val"; return 0; }
    done < <(_agents_session_of "$pid" claude "$age")
}

# _agents_board_sub_said OWNER SUBID — the last lines a sub-agent of a session
# here wrote, from the end of its transcript: model text, so with no control
# character (C0 or C1) and no bidi or line-separator character (lib_maprows'
# clean), as the trace.
_agents_board_sub_said() {
    local tx f
    command -v jq >/dev/null 2>&1 || return 0
    tx="$(_agents_board_transcript "$1")"
    f="${tx%.jsonl}/subagents/agent-$2.jsonl"
    [[ -n "$tx" && -f "$f" && ! -L "$f" && -r "$f" ]] || return 0
    tail -c 131072 "$f" 2>/dev/null | sed 1d \
        | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null \
        | _agents_map_plain \
        | _agents_awk_eval "lib_fmt lib_maprows" 'NF { l[++m] = dcut(clean($0), 400) } END { for (i = (m > 12 ? m - 11 : 1); i <= m; i++) print "  " l[i] }'
}

# The jq that turns a Claude Code transcript's last lines into the trace:
# "HH:MM<TAB>KIND<TAB>TEXT<TAB>NOTE<TAB>COUNT" a line, the oldest first, the
# last $n. KIND: you (a prompt: its first line; a slash command: its name),
# stop (you interrupted it), edit (the files' names, a run of edits in one
# line), run (a command's first words, after a leading cd and VAR=value;
# NOTE "exit N" when it failed), agent
# (a sub-agent: its type and description), ask (a question for you, a plan to
# approve), denied (a tool call you or a rule turned down; NOTE "denied" on
# an event of its own). The same event twice in a row is one line, COUNT
# saying how many. Every text is one line with no control character.
# shellcheck disable=SC2016  # jq source
_AGENTS_BOARD_TRACE_JQ='
def one: tostring | gsub("[[:cntrl:]]"; " ") | gsub("  +"; " ") | sub("^ +"; "") | sub(" +$"; "");
def line1: tostring | split("\n") | map(select(test("\\S"))) | (.[0] // "") | one | .[0:200];
def hm: (. // "") | tostring | sub("\\.[0-9]+"; "") | (try (fromdateiso8601 | strflocaltime("%H:%M")) catch "--:--");
def base: tostring | sub("/+$"; "") | split("/") | (last // "") | one;
def words($n): line1 | split(" ") | .[0:$n] | join(" ");
def cmd: line1 | sub("^cd [^;&|]+(&&|;) *"; "") | sub("^([A-Za-z_][A-Za-z0-9_]*=[^ $`(\"'"'"']* +)+"; "") | words(6);
def said: if type == "string" then . elif type == "array" then [.[] | objects | select(.type == "text") | .text | strings] | join("\n") else "" end;
def add($e): .ev += [$e];
def mark($id; $e): .ix[$id] = (.ev | length) | add($e);
reduce (inputs | fromjson? // empty | objects | select((.type == "user" or .type == "assistant") and (.message | type) == "object")) as $l ({ev: [], ix: {}, nm: {}};
    ($l.timestamp | hm) as $t
    | if $l.type == "assistant" then
        reduce ($l.message.content | if type == "array" then .[] else empty end | objects | select(.type == "tool_use")) as $c (.;
            ($c.input | if type == "object" then . else {} end) as $in
            | ($c.id // "" | tostring) as $id
            | ($c.name | tostring) as $name
            | .nm[$id] = $name
            | if ($name | IN("Edit", "Write", "MultiEdit", "NotebookEdit")) then mark($id; {t: $t, k: "edit", x: ($in.file_path // $in.notebook_path // "" | base)})
              elif $name == "Bash" then mark($id; {t: $t, k: "run", x: ($in.command // "" | cmd)})
              elif ($name | IN("Agent", "Task")) then
                  mark($id; {t: $t, k: "agent", x: (($in.subagent_type // "general-purpose" | line1)
                      + (if ($in.description | type) == "string" then ": " + ($in.description | line1) else "" end))})
              elif $name == "AskUserQuestion" then
                  mark($id; {t: $t, k: "ask", x: (($in.questions | if type == "array" then (.[0] | objects | .question) else null end) // "a question" | line1)})
              elif $name == "ExitPlanMode" then mark($id; {t: $t, k: "ask", x: "approve the plan"})
              else . end)
      elif ($l.message.content | type) == "array" and any($l.message.content[]; type == "object" and .type == "tool_result") then
        reduce ($l.message.content[] | objects | select(.type == "tool_result" and .is_error == true)) as $r (.;
            ($r.tool_use_id // "" | tostring) as $id
            | ($r.content | said) as $out
            | if ($out | test("^Exit code [0-9]+")) then
                  (if .ix[$id] then .ev[.ix[$id]].n = ("exit " + ($out | capture("^Exit code (?<c>[0-9]+)").c)) else . end)
              elif ($out | test("denied|doesn.t want to proceed|rejected"; "i")) then
                  (if .ix[$id] then .ev[.ix[$id]].n = "denied" else add({t: $t, k: "denied", x: (.nm[$id] // "a tool")}) end)
              else . end)
      elif $l.isMeta == true or $l.isCompactSummary == true then .
      else
        ($l.message.content | said) as $p
        | if ($p | test("^\\s*<command-name>")) then add({t: $t, k: "you", x: ($p | capture("<command-name>(?<c>[^<]*)</command-name>").c // "" | line1)})
          elif ($p | test("^\\s*<")) then .
          elif ($p | test("^\\[Request interrupted")) then add({t: $t, k: "stop", x: "you interrupted it"})
          elif ($p | test("\\S")) then add({t: $t, k: "you", x: ($p | line1)})
          else . end
      end)
| reduce .ev[] as $e ([];
    if length > 0 and $e.k == "edit" and .[-1].k == "edit" and (.[-1].n // "") == "" and ($e.n // "") == "" then
        (if (.[-1].f | index([$e.x])) then . else .[-1].f += [$e.x] end)
    elif length > 0 and .[-1].k == $e.k and .[-1].x == $e.x and (.[-1].n // "") == ($e.n // "") then .[-1].c += 1
    else . + [$e + {c: 1, f: [$e.x]}] end)
| .[-$n:][]
| [.t, .k, (if .k == "edit" then (.f | join(", ")) else .x end), (.n // ""), (.c | tostring)]
| map(one | if . == "" then "-" else . end) | join("\t")'

# _agents_board_trace MACHINE ID ROWS — what a session did, in order, the
# newest at the bottom: as many events as fit in ROWS under the tabs (so the
# newest is in view), _AGENTS_BOARD_TRACE_MAX at most. A Claude Code session's
# here, from the last _AGENTS_BOARD_TRACE_TAIL bytes of its transcript.
_agents_board_trace() {
    local m="$1" id="$2" n="$3" kind tx rows w="${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}" out
    _agents_board_rowsf; rows="$REPLY"
    if [[ "$m" != local ]]; then
        printf '  %sIts trace is read on %s, beside its transcript: enter looks at its pane there.%s\n' "$C_DIM" "$m" "$C_0"
        return 0
    fi
    kind="$(awk -F '\t' -v id="$id" '$1 == "local" && $2 == "ses" && $3 == id { print $7; exit }' "$rows" 2>/dev/null)"
    if [[ "$kind" != claude ]]; then
        printf '  %sThe trace is for Claude Code sessions (this one is %s): Pane shows its screen.%s\n' "$C_DIM" "${kind:-gone}" "$C_0"
        return 0
    fi
    command -v jq >/dev/null 2>&1 || { printf '  %sThe trace needs jq.%s\n' "$C_DIM" "$C_0"; return 0; }
    tx="$(_agents_board_transcript "$id")"
    [[ -n "$tx" && -f "$tx" && -r "$tx" ]] || { printf '  %sIts transcript is not one that can be found from here.%s\n' "$C_DIM" "$C_0"; return 0; }
    if [[ "$n" =~ ^[0-9]{1,4}$ && $n -gt 3 ]]; then n=$((n - 2)); else n=$_AGENTS_BOARD_TRACE_MAX; fi
    [[ $n -le $_AGENTS_BOARD_TRACE_MAX ]] || n=$_AGENTS_BOARD_TRACE_MAX
    [[ "$w" =~ ^[0-9]+$ ]] || w=80
    out="$(tail -c "$_AGENTS_BOARD_TRACE_TAIL" "$tx" 2>/dev/null | sed 1d \
        | LC_ALL=C grep -aF -e '"type":"user"' -e '"type":"assistant"' \
        | jq -Rnr --argjson n "$n" "$_AGENTS_BOARD_TRACE_JQ" 2>/dev/null | _agents_map_plain)"
    if [[ -z "$out" ]]; then printf '  %sNothing yet: no prompt, edit or command near the end of its transcript.%s\n' "$C_DIM" "$C_0"; return 0; fi
    printf '%s\n' "$out" | _agents_awk_colored "lib_fmt lib_maprows board_trace" -F '\t' -v W="$w"
}

_agents_board_section() { printf '\n %s%s%s\n' "$C_DIM" "$1" "$C_0"; }

# _agents_board_peek MACHINE KIND ID OWNER — the right-hand side for one row.
_agents_board_peek() {
    local m="$1" kind="$2" id="$3" owner="$4" rows view facts said
    _agents_board_rowsf; rows="$REPLY"
    _agents_colors
    if [[ "$(_agents_board_get help 0)" == 1 ]]; then _agents_board_help; return; fi
    [[ -r "$rows" ]] || return 0
    case "$kind" in
        head) _agents_board_view group -v cid="$id" < "$rows"; return ;;
        mach) _agents_board_view mach -v cm="$m" < "$rows"; return ;;
        kid)
            _agents_board_view kid -v cm="$m" -v cid="$id" -v cowner="$owner" < "$rows"
            if _agents_board_idok sub "$id" && ! _agents_board_idok cmd "$id"; then
                [[ "$m" == local ]] || { printf '\n %sIts own lines are on %s: enter looks at that session.%s\n' "$C_DIM" "$m" "$C_0"; return; }
                _agents_board_idok ses "$owner" || return 0
                said="$(_agents_board_sub_said "$owner" "$id")"
                [[ -z "$said" ]] || { _agents_board_section 'ITS LAST LINES'; printf '%s\n' "$said"; }
            elif _agents_board_idok cmd "$id"; then
                _agents_board_section 'DETAILS'
                if [[ "$m" == local ]]; then agents_main show "$id" 2>/dev/null | sed 's/^/  /'
                else _agents_map_remote "$m" show "$id" 2>/dev/null | _agents_map_plain | sed 's/^/  /'; fi
            fi
            return ;;
        ses) _agents_board_idok ses "$id" || return 0 ;;
        *)   return 0 ;;
    esac
    view="$(_agents_board_get view card)"
    case "$view" in
        trace)   _agents_board_tabs Trace Card Trace Pane Details; printf '\n\n'
                 _agents_board_trace "$m" "$id" "${FZF_PREVIEW_LINES:-}" ;;
        pane)    _agents_board_tabs Pane Card Trace Pane Details; printf '\n\n'
                 _agents_board_pane "$m" "$id" 120 ;;
        details) _agents_board_tabs Details Card Trace Pane Details; printf '\n\n'
                 if [[ "$m" == local ]]; then agents_main show "$id" 2>/dev/null | sed 's/^/ /'
                 else _agents_map_remote "$m" show "$id" 2>/dev/null | _agents_map_plain | sed 's/^/ /'; fi ;;
        *)       _agents_board_tabs Card Card Trace Pane Details; printf '\n'
                 _agents_board_view card -v cm="$m" -v cid="$id" < "$rows"
                 _agents_board_section 'ITS PANE, LAST LINES'
                 _agents_board_pane "$m" "$id" 14
                 facts="$(_agents_board_facts "$m" "$id")"
                 [[ -z "$facts" ]] || printf '\n %s%s%s\n' "$C_DIM" "$facts" "$C_0" ;;
    esac
}

# _agents_board_help — the keys, the few you need first.
_agents_board_help() {
    k() { printf '   %s%-13s%s %s\n' "$C_ACC" "$1" "$C_0" "$2"; }
    printf '\n %sKeys%s  %s? or esc closes this%s\n' "$C_B" "$C_0" "$C_DIM" "$C_0"
    _agents_board_section 'START HERE'
    k 'up down  j k' 'move; the right side follows'
    k 'enter'        'go to that session, on its machine'
    k 'ctrl-p'       'everything you can do, searchable'
    k 'q'            'leave the board (esc, when it is a popup)'
    _agents_board_section 'WHEN YOU WANT MORE'
    k 'tab'          'lens: Attention, Tree, Machines (1 2 3)'
    k 'left right'   'the right side: Card, Trace, Pane, Details'
    k 'space'        'hide or show the right side'
    k '.'            'show the parked sessions'
    k '/'            'find by typing; esc ends it'
    k '-'            'back to the pane you came from'
    k 'ctrl-k'       'stop what is under the cursor; asks first'
    k 'ctrl-r'       'reload now'
    k 'ctrl-d ctrl-u' 'scroll the right side'
    _agents_board_section 'MOUSE'
    k 'click'        'select a row'
    k 'double click' 'go to it, as enter does'
    k 'wheel'        'scroll the list, or the right side'
    k 'footer'       'each word down there is a button'
    unset -f k
}

# _agents_board_focus PANE — bring Herdr's pane PANE forward, whatever runs in
# it. An agent's pane through `herdr agent focus` (which also marks it seen);
# Herdr's CLI focuses no other pane by its id, so then the socket API's
# pane.focus, over nc; without nc, its tab (`herdr tab focus`), which comes
# back on the pane last focused there.
_agents_board_focus() {
    local pane="$1" sock="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" out
    [[ "$pane" =~ ^[A-Za-z0-9:_-]{1,64}$ ]] || return 2
    _agents_timeout 2 herdr agent focus "$pane" >/dev/null 2>&1 && return 0
    if [[ -S "$sock" || -n "${AGENTS_TESTING:-}" ]] && command -v nc >/dev/null 2>&1; then
        out="$(printf '{"id":"agents:board","method":"pane.focus","params":{"pane_id":"%s"}}\n' "$pane" \
            | nc -U -w 2 "$sock" 2>/dev/null | head -c 4096)"
        [[ "$out" != *'"result":'* ]] || return 0
    fi
    out="$(_agents_timeout 2 herdr pane get "$pane" 2>/dev/null | head -c 65536)"
    [[ "$out" =~ \"tab_id\":\"([A-Za-z0-9:_-]{1,64})\" ]] || return 1
    _agents_timeout 2 herdr tab focus "${BASH_REMATCH[1]}" >/dev/null 2>&1
}

# _agents_board_pager — a full-screen look at what a command prints.
# shellcheck disable=SC2086  # $PAGER is a command line
_agents_board_pager() { ${PAGER:-less -R}; }

# _agents_board_act ACTION MACHINE KIND ID OWNER — one key's action on one row.
#   go       a session: its pane (here), a look at it (elsewhere); what runs
#            under one: its details or its last lines, full screen (a
#            sub-agent elsewhere: a look at its session's pane)
#   pane     the end of a session's pane, full screen
#   details  agents show, full screen
#   stop     agents kill on its machine (its refusals and its question)
#   back     the Herdr pane a board was opened over before the last go (none
#            yet: the one this board was opened over), whatever runs in it
_agents_board_act() {
    local act="$1" m="$2" kind="$3" id="$4" owner="${5:--}" dir pane type=ses
    _agents_board_dir; dir="$REPLY"
    _agents_colors
    if [[ "$act" == back ]]; then
        { IFS= read -r pane < "$dir/back"; } 2>/dev/null || pane=""
        [[ -n "$pane" ]] || pane="${AGENTS_BOARD_FROM:-}"
        [[ "$pane" =~ ^[A-Za-z0-9:_-]{1,64}$ ]] || { echo "agents: no pane to go back to yet" >&2; return 1; }
        _agents_board_focus "$pane"
        return
    fi
    case "$kind" in
        ses) ;;
        kid) type=cmd; _agents_board_idok cmd "$id" || type=sub ;;
        *)   return 0 ;;
    esac
    _agents_board_idok "$type" "$id" || { echo "agents: not an id: $id" >&2; return 2; }
    case "$act:$type" in
        go:ses)
            # Where to come back to: the pane the board was opened over.
            [[ ! "${AGENTS_BOARD_FROM:-}" =~ ^[A-Za-z0-9:_-]{1,64}$ ]] || printf '%s\n' "$AGENTS_BOARD_FROM" > "$dir/back"
            _agents_map_act go "$m" proc "$id" ;;
        pane:ses)      _agents_board_pane "$m" "$id" 400 | _agents_board_pager ;;
        go:cmd|details:ses|details:cmd)
            if [[ "$m" == local ]]; then agents_main show "$id" 2>&1 | _agents_board_pager
            else _agents_map_remote "$m" show "$id" 2>&1 | _agents_map_plain | _agents_board_pager; fi ;;
        go:sub)
            _agents_board_idok ses "$owner" || return 0
            # Elsewhere its lines stay there: a look at its session's pane.
            if [[ "$m" == local ]]; then _agents_board_sub_said "$owner" "$id" | _agents_board_pager
            else _agents_map_act go "$m" proc "$owner"; fi ;;
        stop:ses|stop:cmd) _agents_map_act stop "$m" proc "$id" ;;
        *) return 0 ;;
    esac
}

# _agents_board_key KEY MACHINE KIND ID OWNER — what a key does, as fzf
# actions on stdout (a transform). The row's fields reach the commands as
# fzf's own {1} {2} {3} {4}, quoted by fzf: nothing a row says is pasted in.
_agents_board_key() {
    local key="$1" m="${2:-}" kind="${3:-}" a act
    a="$(printf '%q' "$AGENTS_PATH")"
    act="$a board --act"
    case "$key" in
        lens-next|lens-prev|lens-1|lens-2|lens-3)
            local cur; cur="$(_agents_board_get lens attention)"
            case "$key:$cur" in
                lens-1:*|lens-next:machines|lens-prev:tree)      cur=attention ;;
                lens-2:*|lens-next:attention|lens-prev:machines) cur=tree ;;
                *)                                               cur=machines ;;
            esac
            _agents_board_put lens "$cur"
            _agents_colors
            printf 'change-list-label(%s)+reload-sync(%s board --list)' "$(_agents_board_lens_label)" "$a" ;;
        view-next|view-prev)
            local v; v="$(_agents_board_get view card)"
            case "$key:$v" in
                view-next:card|view-prev:pane)     v=trace ;;
                view-next:trace|view-prev:details) v=pane ;;
                view-next:pane|view-prev:card)     v=details ;;
                *)                                v=card ;;
            esac
            _agents_board_put view "$v"; _agents_board_put help 0; _agents_board_put side 1
            printf 'show-preview+refresh-preview' ;;
        parked)
            if [[ "$(_agents_board_get all 0)" == 1 ]]; then _agents_board_put all 0; else _agents_board_put all 1; fi
            printf 'reload-sync(%s board --list)' "$a" ;;
        side)
            if [[ "$(_agents_board_get side 1)" == 1 ]]; then _agents_board_put side 0; else _agents_board_put side 1; fi
            printf 'toggle-preview+reload-sync(%s board --list)' "$a" ;;
        help)
            if [[ "$(_agents_board_get help 0)" == 1 ]]; then _agents_board_put help 0; else _agents_board_put help 1; fi
            _agents_board_put side 1
            printf 'show-preview+refresh-preview' ;;
        esc)
            # Out of the keys, then out of find, then (a popup only) out.
            if [[ "$(_agents_board_get help 0)" == 1 ]]; then _agents_board_put help 0; printf 'refresh-preview'
            elif [[ "${FZF_INPUT_STATE:-hidden}" != hidden ]]; then
                printf 'hide-input+disable-search+clear-query+reload-sync(%s board --list)+rebind(%s)' "$a" "$_AGENTS_BOARD_NAV"
            elif [[ -n "${AGENTS_BOARD_POPUP:-}" ]]; then printf 'abort'; fi ;;
        go)
            case "$kind" in
                ses) if [[ "$m" != local ]]; then printf 'execute(%s go {1} {2} {3} {4})' "$act"
                     elif [[ -n "${AGENTS_BOARD_POPUP:-}" ]]; then printf 'execute-silent(%s go {1} {2} {3} {4})+abort' "$act"
                     else printf 'execute-silent(%s go {1} {2} {3} {4})' "$act"; fi ;;
                kid) printf 'execute(%s go {1} {2} {3} {4})' "$act" ;;
            esac ;;
        back)
            if [[ -n "${AGENTS_BOARD_POPUP:-}" ]]; then printf 'execute-silent(%s back - - - -)+abort' "$act"
            else printf 'execute-silent(%s back - - - -)' "$act"; fi ;;
        stop)
            # A sub-agent is no process of its own: nothing to stop.
            [[ "$kind" != kid ]] || _agents_board_idok cmd "${4:-}" || return 0
            case "$kind" in ses|kid)
                printf 'execute(%s stop {1} {2} {3} {4}; printf "\\n[press any key] "; read -r -s -n 1)+reload-sync(%s board --list)' "$act" "$a" ;;
            esac ;;
        palette)
            printf 'execute(%s board --palette {1} {2} {3} {4})+reload-sync(%s board --list)+refresh-preview' "$a" "$a" ;;
        footer)
            case "${FZF_CLICK_FOOTER_WORD:-}" in
                enter|go)        _agents_board_key go "${@:2}" ;;
                tab|lens)        _agents_board_key lens-next ;;
                '?'|keys)        _agents_board_key help ;;
                ctrl-p|anything) _agents_board_key palette ;;
                esc|close)       [[ -z "${AGENTS_BOARD_POPUP:-}" ]] || printf 'abort' ;;
            esac ;;
    esac
}

# The keys that are letters: off while you type into find, back on after.
_AGENTS_BOARD_NAV='j,k,g,G,q,space,.,?,1,2,3,-,/,left,right'

_agents_board_lens_label() {
    case "$(_agents_board_get lens attention)" in
        tree)     _agents_board_tabs Tree Attention Tree Machines ;;
        machines) _agents_board_tabs Machines Attention Tree Machines ;;
        *)        _agents_board_tabs Attention Attention Tree Machines ;;
    esac
}

# _agents_board_palette MACHINE KIND ID OWNER — ctrl-p: the row's own actions
# first, then what else there is; the one you pick runs.
_agents_board_palette() {
    local m="$1" kind="$2" id="$3" owner="${4:--}" t=$'\t' pick what
    _agents_colors
    pick="$({
        case "$kind" in
            ses) printf '%s\n' "go${t}Go to this session${t}enter" "pane${t}Read its pane, full screen${t}" \
                     "details${t}Its details: memory, ports, files, children${t}" "stop${t}Stop it${t}ctrl-k, asks first" ;;
            kid) printf '%s\n' "go${t}Open it, full screen${t}enter"
                 ! _agents_board_idok cmd "$id" || printf '%s\n' "stop${t}Stop it${t}ctrl-k, asks first" ;;
        esac
        printf '%s\n' "back${t}Back to the pane you came from${t}-" \
            "map${t}Map: servers, files and what was left behind${t}agents map" \
            "ports${t}Ports: what listens where${t}agents ports" \
            "mem${t}Memory: who holds it${t}agents mem" \
            "limits${t}Usage limits${t}agents limits" \
            "runs${t}Runs: the commands that finished${t}agents runs" \
            "report${t}Report: where the day went${t}agents report" \
            "tokens${t}Report: tokens and cost${t}agents report --view tokens" \
            "reap${t}Sweep what sessions left behind here${t}agents reap, asks first"
        ! command -v tuidev >/dev/null 2>&1 || printf '%s\n' "tuidev${t}More: everything tuidev can do${t}tuidev palette"
    } | awk -F '\t' -v d="$C_DIM" -v z="$C_0" '{ printf "%s\t%-46s %s%s%s\n", $1, $2, d, $3, z }' \
      | SHELL="${BASH:-/bin/bash}" "$(_agents_fzf)" --ansi --delimiter "$t" --with-nth '2..' --layout reverse --height 100% \
            --margin '12%,18%' --border rounded --border-label ' anything ' --prompt '> ' --info hidden --no-sort --gutter ' ')" || return 0
    what="${pick%%"$t"*}"
    case "$what" in
        go|pane|details|stop|back) _agents_board_act "$what" "$m" "$kind" "$id" "$owner" ;;
        map)    agents_main map ;;
        ports)  agents_main ports --pick ;;
        mem)    agents_main mem 2>&1 | _agents_board_pager ;;
        limits) agents_main limits 2>&1 | _agents_board_pager ;;
        runs)   agents_main runs 2>&1 | _agents_board_pager ;;
        report) agents_main report 2>&1 | _agents_board_pager ;;
        tokens) agents_main report --view tokens 2>&1 | _agents_board_pager ;;
        reap)   agents_main reap; printf '\n[press any key] '; read -r -s -n 1 ;;
        tuidev) tuidev palette ;;
    esac
    return 0
}

# _agents_board_fzf_ok — true when this fzf has what the board is made of:
# a hidden input, a footer, clicks on it, transform and a header that reloads
# (0.63 and later). An unknown option or action is fzf's exit status 2.
_agents_board_fzf_ok() {
    "$(_agents_fzf)" --no-input --footer x --footer-border top --list-border top --list-label x --gutter ' ' \
        --bind 'click-footer:transform(true),load:transform-header(true),esc:hide-input+disable-search' --filter x </dev/null >/dev/null 2>&1
    [[ $? -ne 2 ]]
}

# _agents_board_listens SOCK — true when this fzf listens on a Unix socket
# (--listen=PATH.sock, fzf 0.66 and later) and has the trigger action a poke
# posts. With --filter nothing listens.
_agents_board_listens() {
    "$(_agents_fzf)" --listen="$1" --bind 'ctrl-r:trigger(ctrl-a)' --filter x </dev/null >/dev/null 2>&1
    [[ $? -ne 2 ]]
}

# _agents_board_listen VAR — VAR set to fzf's --listen option for this board,
# and its record written (ui.PID.listen: "START<TAB>sock", START the board's
# own start time, so a record a dead board left is told from a live one);
# false, and no record, where a poke can't work: no curl, an fzf with no
# socket, or a path longer than a socket's (about 100 bytes). The board then
# reloads on its timer alone.
# Only a Unix socket, never fzf's loopback port: what reaches fzf's listener
# runs commands outside any sandbox (execute, reload), a sandboxed agent may
# connect to localhost, and the port's key would sit in a file it can read.
# The socket is mode 600 in the run dir, where no sandbox profile lets an
# agent connect.
_agents_board_listen() {
    local start
    command -v curl >/dev/null 2>&1 || return 1
    [[ ${#AGENTS_BOARD_UI} -le 90 ]] || return 1
    start="$(_agents_start "$$")"
    [[ -n "$start" ]] && _agents_board_listens "$AGENTS_BOARD_UI.sock" || return 1
    (umask 077; printf '%s\tsock\n' "$start" > "$AGENTS_BOARD_UI.listen") || return 1
    # A key of your own (FZF_API_KEY) would lock the poke out.
    unset FZF_API_KEY
    printf -v "$1" '%s' "--listen=$AGENTS_BOARD_UI.sock"
}

# _agents_board_every LISTENING — the timer's seconds: AGENTS_BOARD_EVERY when
# set, else 15 for a board Herdr's events reload (LISTENING 1), 5 otherwise.
_agents_board_every() {
    local e="${AGENTS_BOARD_EVERY:-}"
    [[ -n "$e" ]] || { if [[ "$1" == 1 ]]; then e=15; else e=5; fi; }
    printf '%s\n' "$e"
}

# _agents_board_poke — every board open here reloads now (fzf's ctrl-r, posted
# to its socket): what the tuidev.link plugin's event hooks run when Herdr
# says something changed. Nothing when no board listens. A burst of pokes is
# one: one poke at a time, and one that finds another running leaves a mark
# (poke.dirty) for it to post once more, a moment later. A board that is gone
# has its record and what it left removed; a record whose pid now names
# another process loses only the record (the files may be a new board's).
_agents_board_poke() {
    local dir f b pid start how st round=0 any=""
    _agents_board_dir; dir="$REPLY"
    for f in "$dir"/ui.*.listen; do [[ ! -f "$f" ]] || { any=1; break; }; done
    [[ -n "$any" ]] || return 0
    if ! _agents_lock "$dir/poke.lock" 2>/dev/null; then : > "$dir/poke.dirty"; return 0; fi
    while [[ $round -lt 3 ]]; do
        round=$((round + 1))
        rm -f "$dir/poke.dirty"
        sleep 0.2 2>/dev/null || true
        for f in "$dir"/ui.*.listen; do
            [[ -f "$f" ]] || continue
            b="${f%.listen}"; pid="${b##*/ui.}"
            [[ "$pid" =~ ^[0-9]{1,10}$ ]] || continue
            start="" how=""
            { IFS=$'\t' read -r start how _ < "$f"; } 2>/dev/null
            st="$(_agents_start "$pid")"
            if [[ -z "$st" ]]; then
                kill -0 "$pid" 2>/dev/null || rm -f "$b".*
                continue
            fi
            [[ "$st" == "$start" ]] || { rm -f "$f"; continue; }
            [[ "$how" == sock ]] && [[ -S "$b.sock" || -n "${AGENTS_TESTING:-}" ]] || continue
            curl -s -m 1 -o /dev/null --unix-socket "$b.sock" --data-raw 'trigger(ctrl-r)' http://localhost 2>/dev/null
        done
        [[ -e "$dir/poke.dirty" ]] || break
    done
    _agents_unlock "$dir/poke.lock"
    # A poke that found the lock held just as this one finished left its mark
    # unread: once more for it.
    if [[ -e "$dir/poke.dirty" && "${1:-}" != again ]]; then _agents_board_poke again; fi
    return 0
}

# _agents_board_sweep — what boards and lists that are gone left in the run
# dir's board/: their state (ui.PID.*) and half-written files (rows.PID,
# machines.PID, list.PID, m.KEY.PID). One ps for the pids that run; nothing
# when ps can't list them (a sandbox), so a live board's files are never taken.
_agents_board_sweep() {
    local dir f n pid live
    _agents_board_dir; dir="$REPLY"
    live=" $(LC_ALL=C ps -A -o pid= 2>/dev/null | tr -s ' \n' '  ') "
    [[ "$live" == *" $$ "* ]] || return 0
    for f in "$dir"/ui.* "$dir"/rows.* "$dir"/machines.* "$dir"/list.* "$dir"/m.*.*; do
        [[ -e "$f" ]] || continue
        n="${f##*/}"
        case "$n" in
            ui.*) pid="${n#ui.}"; pid="${pid%%.*}" ;;
            m.*.lock) continue ;;
            *)    pid="${n##*.}" ;;
        esac
        [[ "$pid" =~ ^[0-9]{1,10}$ && "$live" != *" $pid "* ]] || continue
        rm -f "$f"
    done
}

# agents_board [--popup] [MACHINE|local] — the board. Also:
#   --rows                      this machine's rows (what the others ask for)
#   --list [MACHINE]            the list, as fzf gets it
#   --peek MACHINE KIND ID OWNER, --key KEY [MACHINE KIND ID OWNER],
#   --act ACTION MACHINE KIND ID OWNER, --palette MACHINE KIND ID OWNER,
#   --header                    the header of this board's last list
#   --poke                      every board open here reloads now
agents_board() {
    local a list name="" popup="" dir every keys args=() go listen=""
    case "${1:-}" in
        --rows)    _agents_board_rows; return ;;
        --poke)    _agents_board_poke; return ;;
        --list)    shift; _agents_board_list "$@"; return ;;
        --header)  _agents_board_header; return ;;
        --peek)    [[ $# -eq 5 ]] || return 2
                   _agents_board_peek "$2" "$3" "$4" "$5"; return ;;
        --key)     [[ $# -ge 2 ]] || return 2
                   shift; _agents_board_key "$@"; return ;;
        --act)     [[ $# -eq 6 ]] || { echo "usage: agents board --act go|pane|details|stop|back MACHINE KIND ID OWNER" >&2; return 2; }
                   _agents_board_act "$2" "$3" "$4" "$5" "$6"; return ;;
        --palette) [[ $# -eq 5 ]] || return 2
                   _agents_board_palette "$2" "$3" "$4" "$5"; return ;;
        --popup)   popup=1; shift ;;
    esac
    case "${1:-}" in
        -*) echo "usage: agents board [--popup] [MACHINE|local]" >&2; return 2 ;;
        *)  name="${1:-}" ;;
    esac
    if [[ ! -t 1 ]] || ! command -v "$(_agents_fzf)" >/dev/null 2>&1 || ! _agents_board_fzf_ok; then
        [[ ! -t 1 ]] || echo "agents: the board needs fzf 0.63 or later (brew install fzf); here is its list" >&2
        NO_COLOR=1 AGENTS_BOARD_UI="" _agents_board_list "$name" | cut -f5-
        return
    fi
    _agents_board_dir; dir="$REPLY"
    _agents_board_sweep
    # Every list this board makes is of the machine it was opened for.
    AGENTS_BOARD_UI="$dir/ui.$$" AGENTS_BOARD_POPUP="$popup" AGENTS_BOARD_ONLY="$name"
    export AGENTS_BOARD_UI AGENTS_BOARD_POPUP AGENTS_BOARD_ONLY
    [[ -z "${AGENTS_BOARD_FROM:-}" ]] || export AGENTS_BOARD_FROM
    _agents_board_put lens attention; _agents_board_put view card; _agents_board_put all 0; _agents_board_put help 0; _agents_board_put side 1
    # shellcheck disable=SC2064  # the path is this run's
    trap "rm -f '$AGENTS_BOARD_UI'.*" EXIT
    _agents_colors
    a="$(printf '%q' "$AGENTS_PATH")"
    list="$a board --list"
    go="$a board --key"
    keys=" ${C_0}enter${C_DIM} go    ${C_0}tab${C_DIM} lens    ${C_0}?${C_DIM} keys    ${C_0}ctrl-p${C_DIM} anything"
    [[ -z "$popup" ]] || keys+="    ${C_0}esc${C_DIM} close"
    keys+="$C_0"
    _agents_board_list "$name" > "$dir/list.$$"
    # Herdr's events reload a board that listens (the plugin's hooks: --poke);
    # its timer is then only the fallback.
    if _agents_board_listen listen; then args+=("$listen"); every="$(_agents_board_every 1)"
    else every="$(_agents_board_every 0)"; fi
    args+=(--ansi --delimiter "$(printf '\t')" --with-nth '5..' --no-sort --disabled --no-input
        --layout reverse --height 100% --border none --margin 0 --padding 0 --info hidden --no-scrollbar
        --gutter ' ' --highlight-line --cycle
        --header "$(_agents_board_header)" --header-border none
        --footer "$keys" --footer-border top
        --list-label "$(_agents_board_lens_label)" --list-border top
        --preview "$a board --peek {1} {2} {3} {4}" --preview-window 'right,46%,border-left,wrap,<50(down,50%,border-top,wrap)'
        --bind "j:down,k:up,g:first,G:last,q:abort,ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up"
        --bind "tab:transform($go lens-next),btab:transform($go lens-prev)"
        --bind "1:transform($go lens-1),2:transform($go lens-2),3:transform($go lens-3)"
        --bind "right:transform($go view-next),left:transform($go view-prev)"
        --bind "space:transform($go side),.:transform($go parked),?:transform($go help)"
        --bind "enter:transform($go go {1} {2} {3} {4}),double-click:transform($go go {1} {2} {3} {4})"
        --bind "-:transform($go back),ctrl-k:transform($go stop {1} {2} {3} {4})"
        --bind "ctrl-p:transform($go palette),esc:transform($go esc)"
        --bind "click-footer:transform($go footer {1} {2} {3} {4})"
        --bind "ctrl-r:reload-sync($list)+refresh-preview"
        --sync --bind "start:pos(2)"
        --bind "load:transform-header($a board --header)"
        --bind "/:show-input+enable-search+clear-query+unbind($_AGENTS_BOARD_NAV)")
    if _agents_pick_live && [[ "$every" =~ ^[1-9][0-9]*$ ]]; then
        args+=(--track --id-nth '1..3' --bind "every($every):reload-sync($list)")
    fi
    SHELL="${BASH:-/bin/bash}" "$(_agents_fzf)" "${args[@]}" < "$dir/list.$$" >/dev/null
    rm -f "$dir/list.$$" "$AGENTS_BOARD_UI".*
    return 0
}
