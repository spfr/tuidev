# shellcheck shell=bash
# lib/agents/show.sh — `agents show PID`: one process in detail, like Activity
# Monitor's inspector.
#
# What it is (an agent session, an MCP server, a command a session runs, a
# stale helper, a hog, any process) and whose; its verdict and evidence (the
# rows agents why reads, from agents_assess); how long it has run, its CPU,
# CPU time, memory and threads; its children; the ports its tree listens on
# and the files it has open; which session it is and what that session is
# doing (activity.sh: the end of its transcript); and where it lives (its
# tmux pane, Herdr, ssh or terminal app; where.sh). One ps snapshot, one
# collect over it, one lsof of the process (with a timeout) and a bounded read
# of one transcript: a fraction of a second, so --watch redraws it every 2 s.
#
# With _agents_session_info defined (the token scanner's session lookup), its
# "key<TAB>value" lines about the session (model, origin, tokens, cost…) are
# shown as well; without it, show stands on its own.
#
# Owns: `agents show` and its JSON (schema_version 1: add fields freely,
#   bump it for anything that removes or changes one).
# Uses: config.sh, util.sh (_agents_awk, _agents_timeout, _agents_now),
#   snapshot.sh (agents_snapshot, agents_collect), assess.sh (agents_assess),
#   where.sh (agents_where, _agents_panes, _agents_pid_token), activity.sh,
#   mcp.sh (_agents_mcp_lookup), render.sh (colors); awk/show_tree.awk,
#   awk/show.awk.
# Public: agents_show.

# agents_show [--json] [--watch] PID[@START]
agents_show() {
    local json="" watch="" a token="" pid
    for a in "$@"; do
        case "$a" in
            --json)  json=1 ;;
            --watch) watch=1 ;;
            -*)      echo "agents: unknown option $a" >&2; return 2 ;;
            *)       token="$a" ;;
        esac
    done
    _agents_pid_token pid "$token" "agents show [--json] [--watch] PID[@START]" || return
    if [[ -n "$watch" && -n "$json" ]]; then echo "agents: --watch shows text, not JSON" >&2; return 2; fi
    if [[ -n "$watch" ]]; then _agents_show_watch "$pid"; return; fi
    _agents_show_once "$pid" "$json"
}

# _agents_show_watch PID — redraw every 2 s until q (or the process ends).
_agents_show_watch() {
    local out key rc
    trap 'tput cnorm 2>/dev/null; echo; exit 0' INT TERM
    tput civis 2>/dev/null
    while :; do
        out="$(_agents_show_once "$1" "")"; rc=$?
        printf '\033[H\033[2J%sagents show · %s · every 2s · q quit%s\n\n%s\n' "$C_DIM" "$(date +%H:%M:%S)" "$C_0" "$out"
        [[ $rc -eq 0 ]] || break
        if [[ -t 0 ]]; then
            read -r -s -n 1 -t 2 key && [[ "$key" == q ]] && break
        else
            sleep 2
        fi
    done
    tput cnorm 2>/dev/null
}

# _agents_show_once PID JSON — gather, then render (awk/show.awk). The
# process's own part of the snapshot (its tree, its ancestors, tmux's panes)
# and its open files are read while agents_collect runs.
_agents_show_once() {
    local pid="$1" json="$2" tree proc recs needs cls label root rkind rage cwd
    local extra="" info="" open now t
    _agents_bg 6 _agents_show_tree "$pid"
    _agents_bg 9 _agents_show_proc "$pid"
    recs="$(AGENTS_HERDR_MODE=async agents_collect)"
    _agents_bg_wait tree 6 || true
    _agents_bg_wait proc 9 || true
    [[ -n "$recs" ]] || return 1
    [[ "$tree" == *proc$'\t'* ]] || { echo "agents: pid $pid is not running" >&2; return 1; }
    needs="$(printf '%s\n' "$recs" | agents_assess "$pid")"
    IFS=$'\t' read -r _ cls _ label root rkind rage cwd _ _ <<<"$(
        { printf '%s\n' "$recs"; printf '%s\n' "$tree"; } | _agents_awk "lib_fmt lib_json lib_proc lib_where show" -v t="$pid" -v phase=who)"
    [[ "$cwd" == - ]] && cwd=""
    # Its session: who it is, and what it is doing.
    if [[ "$rkind" == claude || "$rkind" == codex ]] && [[ "$root" =~ ^[0-9]+$ ]]; then
        open="$(_agents_show_open "$proc")"   # where Codex's rollout file is
        [[ "$root" == "$pid" || "$rkind" != codex ]] || open="$(_agents_show_files "$root")"
        extra+="$(_agents_session_of "$root" "$rkind" "$rage" "$open" | _agents_show_f)"$'\n'
        t="$(printf '%s' "$extra" | awk -F '\t' '$2 == "transcript" { print $3; exit }')"
        [[ -z "$t" ]] || extra+="$(_agents_activity "$t" | _agents_show_f)"$'\n'
        if declare -F _agents_session_info >/dev/null; then
            info="$(_agents_session_info "$root" 2>/dev/null | awk -F '\t' 'NF >= 2 && $1 ~ /^[a-z_]+$/ { gsub(/[[:cntrl:]]/, " ", $2); print "info\t" $1 "\t" $2 }')"
        fi
    fi
    [[ -z "$cwd" ]] || extra+="f"$'\t'"branch"$'\t'"$(_agents_git_branch "$cwd")"$'\n'
    if [[ "$cls" == mcp && "$label" != - ]]; then
        extra+="$(_agents_mcp_lookup "$label" "$rkind" | awk -F '\t' 'NR == 1 { print "f\tmcp_cli\t" $1; print "f\tmcp_scope\t" $2; print "f\tmcp_source\t" $3; print "f\tmcp_type\t" $4; print "f\tmcp_needle\t" $5 }')"$'\n'
    fi
    _agents_now now
    { printf '%s\n' "$recs"; printf '%s\n' "$needs"; printf '%s\n' "$tree"; printf '%s\n' "$proc"; printf '%s' "$extra"
      [[ -z "$info" ]] || printf '%s\n' "$info"; } \
        | W="${AGENTS_WIDTH:-120}" HOME="$HOME" B="$C_B" DIM="$C_DIM" Y="$C_Y" R="$C_R" G="$C_G" N="$C_0" \
          _agents_awk "lib_fmt lib_json lib_proc lib_where show" -v t="$pid" -v phase="${json:+json}" -v now="$now"
}

# _agents_show_tree PID — awk/show_tree.awk's rows for PID, from a snapshot
# of its own, then tmux's "pane PANE_PID PLACE" rows (show.awk finds where it
# lives from its ancestors).
_agents_show_tree() {
    agents_snapshot | _agents_awk "lib_proc show_tree" -v t="$1"
    _agents_panes | awk -F '\t' 'NF >= 2 { print "pane\t" $1 "\t" $2 }'
}

# _agents_show_proc PID — show.awk's rows about the process itself: "f files
# N", "f threads N", and "open PATH" for each file it has open.
_agents_show_proc() {
    local files
    files="$(_agents_show_files "$1")"
    printf 'f\tfiles\t%s\n' "$(printf '%s\n' "$files" | grep -c .)"
    printf 'f\tthreads\t%s\n' "$(_agents_show_threads "$1")"
    [[ -z "$files" ]] || printf '%s\n' "$files" | awk '{ print "open\t" $0 }'
}

# _agents_show_open ROWS — the paths of _agents_show_proc's "open" rows.
_agents_show_open() { printf '%s\n' "$1" | awk -F '\t' '$1 == "open" { print $2 }'; }

# _agents_show_f — "key<TAB>value" lines as show.awk's "f" rows.
_agents_show_f() { awk -F '\t' 'NF >= 2 { print "f\t" $1 "\t" $2 }'; }

# _agents_show_files PID — the paths PID has open, one per line: /proc on
# Linux, else one lsof (within 2 s); nothing when neither can tell.
_agents_show_files() {
    local f
    if [[ -d "/proc/$1/fd" ]]; then
        for f in "/proc/$1/fd/"*; do readlink "$f" 2>/dev/null || echo "?"; done
    elif command -v lsof >/dev/null 2>&1; then
        _agents_timeout 2 lsof -b -w -nP -p "$1" -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2) }'
    fi
    return 0
}

# _agents_show_threads PID — how many threads PID runs ("-" when unknown).
_agents_show_threads() {
    local n=""
    if [[ -r "/proc/$1/status" ]]; then
        n="$(awk '/^Threads:/ { print $2 }' "/proc/$1/status" 2>/dev/null)"
    else
        n="$(LC_ALL=C ps -M -p "$1" 2>/dev/null | awk 'NR > 1 { n++ } END { print n + 0 }')"
        [[ "$n" != 0 ]] || n=""
    fi
    echo "${n:--}"
}

# _agents_git_branch DIR — the branch DIR's git checkout is on, read from
# .git/HEAD (a worktree's .git file leads to its own HEAD); nothing when DIR
# is in none, "detached at SHA" off a branch. No git command runs.
_agents_git_branch() {
    local d="$1" g head n=0
    while [[ -n "$d" && $n -lt 32 ]]; do
        n=$((n + 1))
        if [[ -d "$d/.git" ]]; then g="$d/.git"; break; fi
        if [[ -f "$d/.git" ]]; then
            { read -r g < "$d/.git"; } 2>/dev/null || return 0
            g="${g#gitdir: }"; [[ "$g" == /* ]] || g="$d/$g"
            break
        fi
        [[ "$d" == / ]] && return 0
        d="${d%/*}"; [[ -n "$d" ]] || d=/
    done
    [[ -n "${g:-}" && -r "$g/HEAD" ]] || return 0
    { read -r head < "$g/HEAD"; } 2>/dev/null || return 0
    case "$head" in
        "ref: refs/heads/"*) printf '%s\n' "${head#ref: refs/heads/}" ;;
        [0-9a-f]*) printf 'detached at %s\n' "${head:0:8}" ;;
    esac
}
