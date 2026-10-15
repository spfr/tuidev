# shellcheck shell=bash
# lib/agents/where.sh — where a process lives, and going there.
#
# A session runs in a tmux pane, in a Herdr pane, over ssh or in a terminal
# app's window: the first of these up its ancestry (awk/lib_where.awk). tmux
# is asked once per run, with one list-panes, and only when its server's
# socket exists; everything else comes from the ps snapshot. agents_collect
# hands the pane map to agents_classify, which adds a "where" record per
# session (the menu's summaries show it).
#
# `agents jump` resolves the rest when you click, never on a refresh: which
# Herdr pane (by the Claude Code session id Herdr reports, else the pane
# whose processes include it, else, for a jump to a session whose id is
# known, the only agent of its kind in its directory), which tmux client,
# and which window or tab of the terminal app shows
# it (by tty, through the app's AppleScript: Ghostty 1.3 and later, iTerm2,
# Terminal; any other app is only brought forward).
#
# Owns: the tmux pane map, a process's place, the session a notification
#   jumps to (`agents root-of`), `agents jump` and `agents peek`.
# Uses: config.sh, util.sh (_agents_awk, _agents_timeout), snapshot.sh
#   (agents_snapshot, _agents_start, agents_secs), activity.sh
#   (_agents_session_of), terminal.sh (agents_terminal: the app to bring
#   forward when none is found), notify.sh (_agents_notify);
#   awk/lib_where.awk, awk/where.awk, awk/root.awk.
# Public: _agents_tmux_up, _agents_panes, agents_where, agents_root_of,
#   _agents_app_bundle, _agents_pid_token, agents_jump, agents_peek.

# _agents_tmux_up — true when a tmux server runs: the socket of the one this
# shell is in ($TMUX), or the default one, exists (no fork), and tmux is here.
# Never under the test harness (AGENTS_TESTING), whose fixture pids would
# meet this machine's panes: a test redefines it.
_agents_tmux_up() {
    [[ -z "${AGENTS_TESTING:-}" ]] || return 1
    local s="${TMUX:-}"
    s="${s%%,*}"
    [[ -n "$s" && -S "$s" ]] || s="${TMUX_TMPDIR:-/tmp}/tmux-$UID/default"
    [[ -S "$s" ]] && command -v tmux >/dev/null 2>&1
}

# _agents_panes — "pane_pid<TAB>session:window.pane<TAB>pane_id" for every
# tmux pane: the place people read, and the id (%N) tmux commands target (a
# place names another pane once windows are renumbered or a name repeats);
# nothing when no server runs (or it does not answer within a second).
_agents_panes() {
    _agents_tmux_up || return 0
    _agents_timeout 1 tmux list-panes -a -F '#{pane_pid}	#{session_name}:#{window_index}.#{pane_index}	#{pane_id}' 2>/dev/null
    return 0
}

# agents_where PID [SNAPSHOT [PANES]] — awk/where.awk's answer: first
# "HOW<TAB>PLACE<TAB>ROOT<TAB>KIND<TAB>TARGET" (HOW: tmux, herdr, ssh, app or
# -; ROOT the agent session PID is or runs under; TARGET the tmux pane's id),
# then the Herdr clients' "client
# PID APP" lines; nothing when PID is not running. The snapshot and the pane
# map are read when not given.
agents_where() {
    local snap="${2-}" panes="${3-}"
    [[ -n "$snap" ]] || snap="$(agents_snapshot)"
    [[ $# -ge 3 ]] || panes="$(_agents_panes)"
    printf '%s\n' "$snap" | AGENTS_PANES="$panes" AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc lib_where where" -v t="$1"
}

# _agents_pid_token VAR TOKEN USAGE — set VAR to the pid TOKEN names: PID, or
# PID@START refused when the pid now names another process. Prints USAGE (or
# the refusal) and fails otherwise.
_agents_pid_token() {
    local _now
    if [[ ! "${2:-}" =~ ^([0-9]+)(@([A-Za-z0-9_:]+))?$ ]]; then echo "usage: $3" >&2; return 2; fi
    printf -v "$1" '%s' "${BASH_REMATCH[1]}"
    [[ -n "${BASH_REMATCH[3]}" ]] || return 0
    _now="$(_agents_start "${BASH_REMATCH[1]}")"
    [[ "$_now" == "${BASH_REMATCH[3]}" ]] && return 0
    echo "agents: pid ${BASH_REMATCH[1]} is gone or now names another process" >&2
    return 1
}

# _agents_app_name TERMINAL — the app agents_terminal's TERMINAL is.
_agents_app_name() {
    case "$1" in
        ghostty) echo Ghostty ;; iterm) echo iTerm ;; wezterm) echo WezTerm ;;
        kitty) echo kitty ;; *) echo Terminal ;;
    esac
}

# _agents_app_bundle APP — the bundle id of a terminal app agents jump can
# focus by tty (what a notification activates on a click); "-" for any other.
_agents_app_bundle() {
    case "$1" in
        Ghostty) echo com.mitchellh.ghostty ;; iTerm|iTerm2) echo com.googlecode.iterm2 ;;
        Terminal) echo com.apple.Terminal ;; *) echo - ;;
    esac
}

# agents_root_of PID [SNAPSHOT] — the agent session PID runs under, for a
# notification to jump to when clicked: "PID@START<TAB>APP<TAB>BUNDLE" (the
# outermost claude or codex process from PID up, the terminal app that shows
# it, and that app's bundle id; "-" for either when unknown: awk/root.awk).
# One ps, no tmux or Herdr call: a hook runs it every time it notifies.
# Nothing, and false, when PID runs under no agent.
agents_root_of() {
    local snap="${2-}" tok app
    [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "usage: agents root-of PID" >&2; return 2; }
    [[ -n "$snap" ]] || snap="$(agents_snapshot)"
    IFS=$'\t' read -r tok app <<<"$(printf '%s\n' "$snap" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc lib_where root" -v t="$1")"
    [[ "$tok" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]] || return 1
    printf '%s\t%s\t%s\n' "$tok" "${app:--}" "$(_agents_app_bundle "${app:--}")"
}

# _agents_tty PID — the terminal PID runs on (/dev/ttys004), nothing when none.
_agents_tty() {
    local t
    t="$(LC_ALL=C ps -o tty= -p "$1" 2>/dev/null)"; t="${t//[[:space:]]/}"
    [[ -n "$t" && "$t" != \?* && "$t" != - ]] && printf '/dev/%s\n' "${t#/dev/}"
    return 0
}

# _agents_app_front APP — bring APP forward (macOS: open -a, which only
# activates a running app). False where that can't be done.
_agents_app_front() {
    [[ -n "$1" && "$1" != - ]] || return 1
    [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1 || return 1
    open -a "$1" >/dev/null 2>&1
}

# _agents_term_focus APP [TTY] — bring forward the window and tab of APP that
# shows TTY (Ghostty 1.3+, iTerm2 and Terminal say which terminal has which
# tty), else just APP. False when not even that worked.
_agents_term_focus() {
    local app="$1" tty="${2:-}" script=""
    if [[ "$tty" == /dev/* ]] && command -v osascript >/dev/null 2>&1; then
        case "$app" in
            Ghostty) script='tell application "Ghostty"
                set ts to (every terminal whose tty is (item 1 of argv))
                if ts is {} then return "none"
                focus (item 1 of ts)
                activate
            end tell' ;;
            iTerm|iTerm2) script='tell application "iTerm"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is (item 1 of argv) then
                                select w
                                tell t to select
                                tell s to select
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "none"
            end tell' ;;
            Terminal) script='tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is (item 1 of argv) then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
                return "none"
            end tell' ;;
        esac
        if [[ -n "$script" ]]; then
            [[ "$(_agents_timeout 3 osascript -e "on run argv
                $script
                return \"ok\"
            end run" "$tty" 2>/dev/null)" == ok ]] && return 0
        fi
    fi
    _agents_app_front "$app"
}

# _agents_tmux_client — "PID<TAB>TTY" of the tmux client used last.
_agents_tmux_client() {
    _agents_timeout 1 tmux list-clients -F '#{client_activity} #{client_pid} #{client_tty}' 2>/dev/null \
        | sort -rn | awk 'NR == 1 && $2 ~ /^[0-9]+$/ { print $2 "\t" $3 }'
}

# _agents_herdr_pane ROOT KIND CWD SESSION [guess] — the id of the Herdr
# pane the agent ROOT runs in: the agent Herdr reports with session id
# SESSION, else the pane whose processes include ROOT (herdr pane
# process-info, pane by pane); else, with guess and a SESSION (a jump: a
# wrong pane only costs a look), the only agent of KIND in CWD. Nothing when
# Herdr can't tell.
_agents_herdr_pane() {
    local root="$1" kind="$2" cwd="$3" sid="$4" guess="${5:-}" list pane="" p
    command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    list="$(_agents_timeout 2 herdr agent list 2>/dev/null | jq -r '.result.agents[]? |
        [(.pane_id // "-"), (.agent // "-"), (.cwd // "-"), (.agent_session.value // "-")] | map(tostring) | @tsv' 2>/dev/null)"
    [[ -n "$list" ]] || return 0
    [[ -z "$sid" || "$sid" == - ]] || pane="$(printf '%s\n' "$list" | awk -F '\t' -v s="$sid" '$4 == s { print $1; exit }')"
    if [[ -z "$pane" ]]; then
        while IFS=$'\t' read -r p _; do
            [[ "$p" =~ ^[A-Za-z0-9:_-]+$ ]] || continue
            if _agents_timeout 2 herdr pane process-info --pane "$p" 2>/dev/null \
                | jq -e --argjson r "$root" '.result.process_info | ([.shell_pid] + [.foreground_processes[]?.pid]) | index($r) != null' >/dev/null 2>&1; then
                pane="$p"; break
            fi
        done <<<"$list"
    fi
    if [[ -z "$pane" && "$guess" == guess && -n "$sid" && "$sid" != - ]]; then
        pane="$(printf '%s\n' "$list" | awk -F '\t' -v k="$kind" -v c="$cwd" '$2 == k && $3 == c { n++; m = $1 } END { if (n == 1) print m }')"
    fi
    [[ "$pane" =~ ^[A-Za-z0-9:_-]+$ ]] && printf '%s\n' "$pane"
    return 0
}

# _agents_herdr_target VAR PID ROOT KIND [guess] — set VAR to the Herdr pane
# of PID, whose agent session is ROOT (KIND): _agents_herdr_pane with its
# directory and, for Claude Code, the session id it recorded for ROOT.
_agents_herdr_target() {
    local _root="$3" _cwd _sid="" _age
    [[ "$_root" =~ ^[0-9]+$ ]] || _root="$2"
    _cwd="$(_agents_cwds "$_root" | cut -f2)"
    if [[ "$4" == claude ]]; then
        _age="$(agents_secs "$(LC_ALL=C ps -o etime= -p "$_root" 2>/dev/null | tr -d ' ')")"
        _sid="$(_agents_session_of "$_root" claude "$_age" | awk -F '\t' '$1 == "session" { print $2 }')"
    fi
    printf -v "$1" '%s' "$(_agents_herdr_pane "$_root" "$4" "${_cwd:--}" "$_sid" "${5:-}")"
}

# _agents_jump_to PID SNAPSHOT — go to PID's place (agents_jump); its outcome
# on stdout, false when there is nowhere to go.
_agents_jump_to() {
    local pid="$1" snap="$2" where how place root kind target client app="" tty="" pane
    where="$(agents_where "$pid" "$snap" "$(_agents_panes)")"
    IFS=$'\t' read -r how place root kind target <<<"${where%%$'\n'*}"
    case "$how" in
        tmux)
            [[ -n "$target" && "$target" != - ]] || target="$place"
            tmux select-window -t "$target" 2>/dev/null; tmux select-pane -t "$target" 2>/dev/null
            tmux switch-client -t "$target" 2>/dev/null
            IFS=$'\t' read -r client tty <<<"$(_agents_tmux_client)"
            [[ -z "$client" ]] || app="$(agents_where "$client" "$snap" "" | awk -F '\t' 'NR == 1 && $1 == "app" { print $2 }')"
            echo "tmux pane $place" ;;
        herdr)
            # The pane: by the session Herdr reports (the agent's), else its
            # processes, else (a guess) its directory.
            _agents_herdr_target pane "$pid" "$root" "$kind" guess
            [[ -z "$pane" ]] || _agents_timeout 2 herdr agent focus "$pane" >/dev/null 2>&1 || pane=""
            # The terminal a Herdr client runs in.
            IFS=$'\t' read -r _ client app <<<"$(printf '%s\n' "$where" | awk -F '\t' '$1 == "client" { print; exit }')"
            [[ -z "$client" ]] || tty="$(_agents_tty "$client")"
            if [[ -n "$pane" ]]; then echo "Herdr pane $pane"; else echo "Herdr (its pane not found)"; fi ;;
        app)
            app="$place"; tty="$(_agents_tty "$pid")"
            [[ -n "$tty" || ! "$root" =~ ^[0-9]+$ ]] || tty="$(_agents_tty "$root")"
            echo "$place" ;;
        ssh) echo "pid $pid runs in an ssh session: nothing to bring forward here"; return 1 ;;
        "")  echo "pid $pid is not running"; return 1 ;;
        *)   echo "pid $pid runs in no terminal agents can find"; return 1 ;;
    esac
    [[ -n "$app" && "$app" != - ]] || app="$(_agents_app_name "$(agents_terminal)")"
    _agents_term_focus "$app" "$tty" || true
}

# agents_jump [--notify] PID[@START] — go to where PID runs, so you can
# answer it: its Herdr pane or tmux pane (focused), then the window or tab of
# the terminal app that shows it; else that app. With --notify (the menu,
# which has no terminal) a failure is a notification.
agents_jump() {
    local notify="" a token="" pid snap msg rc=0
    for a in "$@"; do
        case "$a" in --notify) notify=1 ;; -*) echo "agents: unknown option $a" >&2; return 2 ;; *) token="$a" ;; esac
    done
    _agents_pid_token pid "$token" "agents jump [--notify] PID[@START]" || return
    snap="$(agents_snapshot)"
    msg="$(_agents_jump_to "$pid" "$snap")" || rc=1
    if [[ $rc -eq 0 ]]; then echo "pid $pid: $msg"; else echo "agents: $msg" >&2; fi
    [[ -z "$notify" || $rc -eq 0 ]] || AGENTS_NOTIFY=true _agents_notify "$msg"
    return "$rc"
}

# agents_peek PID[@START] [LINES] — the last LINES (default 40, at most 2000)
# lines of the tmux pane PID runs in, or of its Herdr pane (herdr pane read),
# as plain text.
agents_peek() {
    local pid lines="${2:-40}" how place root kind target pane
    _agents_pid_token pid "${1:-}" "agents peek PID[@START] [LINES]" || return
    [[ "$lines" =~ ^[1-9][0-9]{0,3}$ && $lines -le 2000 ]] || { echo "usage: agents peek PID[@START] [LINES] (1 to 2000)" >&2; return 2; }
    IFS=$'\t' read -r how place root kind target <<<"$(agents_where "$pid" | head -1)"
    case "$how" in
        tmux)  [[ -n "$target" && "$target" != - ]] || target="$place"
               printf '%s── tmux %s · pid %s ──%s\n' "$C_DIM" "$place" "$pid" "$C_0"
               tmux capture-pane -p -J -S "-$lines" -t "$target" ;;
        herdr) _agents_herdr_target pane "$pid" "$root" "$kind"   # never a guess: it prints what it reads
               [[ -n "$pane" ]] || { echo "agents: pid $pid runs in Herdr, but its pane was not found" >&2; return 1; }
               printf '%s── Herdr %s · pid %s ──%s\n' "$C_DIM" "$pane" "$pid" "$C_0"
               _agents_timeout 3 herdr pane read "$pane" --lines "$lines" --format text 2>/dev/null ;;
        "")    echo "agents: pid $pid is not running" >&2; return 1 ;;
        *)     echo "agents: pid $pid is not in a tmux or Herdr pane${place:+ (it runs in ${place/#-/a terminal})}: nothing to peek at" >&2; return 1 ;;
    esac
}
