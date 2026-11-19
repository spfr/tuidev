# shellcheck shell=bash
# lib/agents/hc.sh — agents you can pick up from your phone: `agents hc run
# claude` starts the agent in herdr-core (`hc`, the runtime under Herdr's
# desktop and phone apps) instead of in the pane itself, and puts the pane on
# it. Herdr's phone app talks to herdr-core over SSH and lists what runs
# there: it never sees a program a Herdr TUI pane owns. Hosted this way the
# same agent is in the pane, in the phone's inbox, and still running when
# the pane is gone.
#
# Three things herdr-core leaves to its caller, which is all this adds:
#   - The Herdr TUI does not know the program in the pane is an agent (the
#     pane runs `herdr-core attach`). While the pane is on it, each status
#     the agent reports to herdr-core (OSC 7501) is reported to Herdr for
#     that pane, so the sidebar and tab names say working / blocked / done.
#   - On macOS a core started over SSH (the phone connecting first) runs
#     outside the desktop login: its programs cannot reach the Keychain, and
#     Claude Code comes up "Not logged in". `agents hc up` starts it in the
#     desktop session (the pack runs it at login and every 5 minutes, on
#     Linux too, so a core that stopped comes back), and says so when it is
#     not, restarting it only when told to (a restart ends its terminals).
#   - A detached agent is easy to forget: leaving the pane says it still
#     runs, and how to come back to it or end it.
#
# Nothing here parses a screen or keeps a daemon: one `herdr-core events`
# stream per attached pane, for as long as it is attached (opened again when
# the core restarts under it).
#
# With AGENTS_HC_AUTO=1, `agents hc auto` does the same for a `claude` or
# `codex` typed in a Herdr pane (the herdr-core pack's shell fragment calls
# it), and runs the command as typed whenever hosting cannot work.
#
# Owns: `agents hc` (status, up, run, auto, attach), the hc-pane.* marks,
#   hc-up.said.
# Uses: config.sh (AGENTS_RUN_DIR, AGENTS_NO_HERDR, AGENTS_HC_AUTO),
#   herdrlabel.sh (_agents_hl_herdr, _agents_hl_ready), util.sh
#   (_agents_timeout, _agents_replace), bin/agents (_AGENTS_ENV_IN);
#   hcmirror.sh and hcphone.sh for `mirror` and `ls`, and hcmirror.sh's
#   sync after `up`.
# Public: agents_hc, _agents_hc_marks (the hosted panes, from their marks).

_AGENTS_HC_SOURCE="tuidev-hc"    # our reports' source in Herdr: what leaving a pane releases
_AGENTS_HC_NAME_RE='^[a-z0-9_][a-z0-9_-]{0,31}$'
_AGENTS_HC_INSTALL="https://herdr.dev/core/"
_AGENTS_HC_HELLO='{"jsonrpc":"2.0","id":1,"method":"hello","params":{}}'
# Seconds a core gets to answer a question, and Herdr to take a report: one
# that hangs must not hold status, the login job or the pane. And how the
# bridge comes back after a core restart: a pause before each new try, and
# how many short-lived tries in a row it makes before it gives up.
_AGENTS_HC_WAIT=5
_AGENTS_HC_HERDR_WAIT=3
_AGENTS_HC_PAUSE=1
_AGENTS_HC_TRIES=30

# _agents_hc_bin — set _AGENTS_HC_BIN to herdr-core. By that name, never
# `hc`: another program may own the short one (herdr-core's installer leaves
# an existing `hc` alone). AGENTS_HC_BIN overrides (tests).
_agents_hc_bin() {
    _AGENTS_HC_BIN="${AGENTS_HC_BIN:-}"
    [[ -z "$_AGENTS_HC_BIN" ]] || { [[ -x "$_AGENTS_HC_BIN" ]]; return; }
    _AGENTS_HC_BIN="$(command -v herdr-core 2>/dev/null)" && return 0
    _AGENTS_HC_BIN="$HOME/.local/bin/herdr-core"
    [[ -x "$_AGENTS_HC_BIN" ]]
}

_agents_hc_need() {
    command -v jq >/dev/null 2>&1 || { echo "agents hc: needs jq" >&2; return 1; }
    _agents_hc_bin && return 0
    echo "agents hc: herdr-core is not installed. Its installer and what it does: $_AGENTS_HC_INSTALL" >&2
    return 1
}

# _agents_hc_socket — the socket herdr-core's default rules give this
# session (docs/security.md there): HC_SOCKET, else the runtime dir, else the
# state dir. A socket set in its config file is not looked for.
_agents_hc_socket() {
    local s="${HC_SESSION:-default}" d
    if [[ -n "${HC_SOCKET:-}" ]]; then printf '%s\n' "$HC_SOCKET"; return 0; fi
    for d in "${XDG_RUNTIME_DIR:-}" "/run/user/$(id -u)"; do
        [[ -n "$d" && -d "$d" ]] || continue
        printf '%s\n' "$d/herdr-core/$s.sock"
        return 0
    done
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/herdr-core/$s/$s.sock"
}

# _agents_hc_running — is a core up? Not asked of the core: a herdr-core
# client command starts one when none runs (and when one exits between this
# check and that call, so the check narrows the window, no more). The socket
# file alone is not the answer either, since a core that crashed leaves it
# behind; the kernel's table of unix sockets says whether a process still
# has it bound, without connecting to it. Where that table cannot be read
# (a sandbox denies it), the file is the answer, as it always was.
_agents_hc_running() {
    local sock
    sock="$(_agents_hc_socket)"
    [[ -S "$sock" ]] || return 1
    _agents_hc_listening "$sock"
    [[ $? -ne 1 ]]
}

# _agents_hc_listening SOCK — 0 when a process has SOCK bound, 1 when the
# table says none has, 2 when there is no table to ask. The path is matched
# as given and through its directory's real path (/tmp is /private/tmp).
_agents_hc_listening() {
    local sock="$1" dir
    dir="$(cd -P "${sock%/*}" 2>/dev/null && pwd -P)"
    _agents_hc_unix_table | LC_ALL=C awk -v a="$sock" -v b="${dir:+$dir/${sock##*/}}" '
        # Field N to the end of the line: a path may hold spaces.
        function from(n,   s, i) { s = $0; for (i = 1; i < n; i++) sub(/^[ \t]*[^ \t]+/, "", s); sub(/^[ \t]+/, "", s); return s }
        !fmt && $1 == "Num" && $NF == "Path" { fmt = "linux"; next }
        !fmt && $1 == "Address" && $NF == "Addr" { fmt = "bsd"; next }
        { p = "" }
        fmt == "linux" && $4 == "00010000" { p = from(8) }   # flags: accepting connections
        fmt == "bsd" && NF >= 9 && $5 != "0" { p = from(9) } # bound to a file (its vnode)
        p != "" && (p == a || p == b) { found = 1; exit }
        END { exit found ? 0 : (fmt ? 1 : 2) }'
}

# _agents_hc_unix_table — the unix sockets this machine has: /proc/net/unix
# on Linux, `netstat -f unix -n` on macOS (it says nothing in a sandbox).
_agents_hc_unix_table() {
    local ns
    if [[ -r /proc/net/unix ]]; then cat /proc/net/unix 2>/dev/null; return 0; fi
    ns="$(command -v netstat 2>/dev/null)" || ns=/usr/sbin/netstat
    [[ -x "$ns" ]] && "$ns" -f unix -n 2>/dev/null
}

# _agents_hc_hello — the running core's `hello` answer (its version, and
# login_session.gui: whether it runs in the desktop login); nothing when it
# has not answered in _AGENTS_HC_WAIT seconds. _agents_timeout gives what it
# runs no stdin, so the request is written from inside the timed function.
_agents_hc_hello() { _agents_timeout "$_AGENTS_HC_WAIT" _agents_hc_ask_hello; }
_agents_hc_ask_hello() {
    # Without the pane's identity: a client starts a core when the one that
    # ran is gone by now, and that core must not carry it (_agents_hc_start).
    printf '%s\n' "$_AGENTS_HC_HELLO" | env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID \
        -u HERDR_SOCKET_PATH -u HERDR_BIN_PATH "$_AGENTS_HC_BIN" connect 2>/dev/null | head -n 1
}

# _agents_hc_start — start a core. Without the Herdr pane's identity when we
# are in one: every terminal the core starts later gets the core's
# environment, and an agent there must not report into this pane. Without
# what loading agents exported either (config.sh's AGENTS_* patterns): an
# agent in the core that runs `agents` reads its own.
#
# Under the herdr-core pack's systemd unit nothing more is needed: on Linux
# herdr-core puts its server in a unit of its own (hc-serve-*.service), so
# it is no part of the job that started it (on macOS the LaunchAgent
# abandons its process group for the same reason).
_agents_hc_start() { _agents_hc_start_env "$_AGENTS_HC_BIN" server start; }
_agents_hc_start_env() {
    local n drop=()
    for n in $(compgen -e); do
        case "$n" in HERDR_*|AGENTS_*) drop+=(-u "$n") ;; esac
    done
    env ${drop[@]+"${drop[@]}"} "$@" >/dev/null 2>&1
}

# _agents_hc_gui HELLO — true, false, or nothing where the core does not say
# (Linux, older cores).
_agents_hc_gui() {
    printf '%s' "$1" | jq -r '.result.login_session.gui | if . == null then "" else tostring end' 2>/dev/null
}

# _agents_hc_live — how many live terminals the core has.
_agents_hc_live() {
    _agents_timeout "$_AGENTS_HC_WAIT" "$_AGENTS_HC_BIN" ls --json 2>/dev/null \
        | jq -r '[.terminals[]? | select(.state == "live")] | length' 2>/dev/null
}

# _agents_hc_over_ssh — are we in an SSH login, by the environment? Only a
# guess: a Herdr or tmux server started over SSH hands SSH_CONNECTION to every
# pane, at the Mac too. The core's own login_session.gui is the test; this
# only keeps `up --restart` from ending a core's terminals on that guess.
_agents_hc_over_ssh() { [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]]; }

_agents_hc_is_mac() { [[ "$(uname -s)" == Darwin ]]; }

_AGENTS_HC_HEADLESS="it was started over SSH, outside your desktop login: its programs cannot reach the Keychain (Claude Code says \"Not logged in\")"

# _agents_hc_start_here — start a core and, on macOS, check that it is in
# the desktop login. One that is not is left running and reported (non-zero):
# it is never stopped from here. The socket guess can miss a core that was
# already running, and a phone, a run or the mirror may have put a terminal
# in it since: only its owner, at the Mac, ends it (up --restart).
_agents_hc_start_here() {
    _agents_hc_start || { echo "agents hc: herdr-core did not start (herdr-core server status)" >&2; return 1; }
    _agents_hc_is_mac || return 0
    [[ "$(_agents_hc_gui "$(_agents_hc_hello)")" == false ]] || return 0
    echo "agents hc: the core is running, but $_AGENTS_HC_HEADLESS. It was left running. At the Mac's own terminal, not over SSH: agents hc up --restart (it ends the core's terminals)" >&2
    return 1
}

agents_hc_status() {
    local hello gui live v
    _agents_hc_need || return 1
    v="$("$_AGENTS_HC_BIN" --version 2>/dev/null)"
    if ! _agents_hc_running; then
        echo "herdr-core ${v#hc }: not running (agents hc up starts it)"
        _agents_hc_auto_status
        return 1
    fi
    hello="$(_agents_hc_hello)"
    if [[ -z "$hello" ]]; then
        echo "herdr-core ${v#hc }: running, but it did not answer within ${_AGENTS_HC_WAIT} s"
        _agents_hc_auto_status
        return 1
    fi
    gui="$(_agents_hc_gui "$hello")"
    live="$(_agents_hc_live)"
    echo "herdr-core ${v#hc }: running, ${live:-?} live terminal(s)"
    if [[ "$gui" == false ]] && _agents_hc_is_mac; then
        echo "  ! $_AGENTS_HC_HEADLESS."
        echo "    At this Mac, not over SSH: agents hc up --restart (it ends the core's terminals)."
        _agents_hc_auto_status
        return 1
    fi
    [[ "$gui" != true ]] || echo "  in your desktop login: agents started in it can use the Keychain"
    echo "  phone: Herdr's app reaches it over SSH (Tailscale SSH needs no key); agents hc run CMD puts an agent in its inbox"
    _agents_hc_phone_status
    _agents_hc_auto_status
}

# _agents_hc_remote_clients — how many clients reach this core from another
# device right now: `herdr-core connect` (or `hc connect`) processes with an
# sshd above them. Nothing printed, and failure, when the process table can't
# be read (a sandbox).
_agents_hc_remote_clients() {
    local ps
    ps="$(agents_snapshot)"
    [[ -n "$ps" ]] || return 1
    printf '%s\n' "$ps" | awk '
        { pp[$1] = $2; a = ""; for (i = 14; i <= NF; i++) a = a (i > 14 ? " " : "") $i; av[$1] = a }
        END {
            for (p in av) {
                if (av[p] !~ /(^|\/)(herdr-core|hc)( .*)? connect( |$)/) continue
                q = pp[p]; d = 0
                while (q > 1 && (q in av) && d++ < 16) {
                    if (av[q] ~ /^sshd|\/sshd|sshd-session|sshd:/) { n++; break }
                    q = pp[q]
                }
            }
            print n + 0
        }'
}

# _agents_hc_phone_status — one line: is a phone (or any other device)
# connected now. An empty inbox with no client is the network between the
# phone and this machine, not the core.
_agents_hc_phone_status() {
    local n
    n="$(_agents_hc_remote_clients)" || return 0
    if [[ "$n" -gt 0 ]]; then
        echo "  connected now: $n client$( [[ "$n" -eq 1 ]] || echo s ) over SSH"
    else
        echo "  connected now: no phone or other device. If the app says \"connecting\", look at the network between it and this machine (on the phone: Tailscale's own warnings, then off and on)"
    fi
}

# _agents_hc_auto_status — one line: is automatic hosting on, and can the
# shell reach it (the herdr-core pack's fragment defines claude and codex).
_agents_hc_auto_status() {
    local frag="${TUIDEV_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}/shell.d/hc-auto.zsh"
    if [[ "${AGENTS_HC_AUTO:-0}" != 1 ]]; then
        echo "  automatic hosting: off (AGENTS_HC_AUTO=1 in agents.conf hosts claude and codex typed in a Herdr pane)"
    elif [[ ! -f "$frag" ]]; then
        echo "  automatic hosting: on, but the shell fragment is missing (tuidev install --pack herdr-core)"
    else
        echo "  automatic hosting: on for claude and codex typed in a Herdr pane (a new shell picks up a change)"
    fi
}

# agents_hc_up [--restart] [-q] — a core in the desktop session: started when
# none runs, left alone when one does, and restarted (ending its terminals)
# only with --restart, when it is the headless kind.
#
# -q is the herdr-core pack's job, run at login and then every 5 minutes
# (AGENTS_HC_UP=0: it does nothing, and a core you stopped stays down): it
# prints nothing while all is well, and a problem once, not at every run
# that finds it again. What it said last is in AGENTS_RUN_DIR/hc-up.said
# (digits left out: a count of terminals is not a new problem), and is
# cleared once all is well, so the same problem is said again when it comes
# back. While all is well that is one subshell and one file test more.
#
# Once a core is found or started, the mirrors are synced (quietly, and
# never a failure of `up`): a core that was started again has none, and the
# Herdr events that would start them may be long past. Nothing, and no
# fork, while mirrors are off or there is no Herdr here.
agents_hc_up() {
    local restart=false quiet=false a err said="" rc=0 mark="$AGENTS_RUN_DIR/hc-up.said"
    for a in "$@"; do
        case "$a" in
            --restart)  restart=true ;;
            -q|--quiet) quiet=true ;;
            *)          echo "usage: agents hc up [--restart] [-q]" >&2; return 2 ;;
        esac
    done
    if [[ "$quiet" != true ]]; then
        _agents_hc_up "$restart" false || return
        _agents_hc_up_mirrors
        return 0
    fi
    # Off: nothing runs, and what was said before is forgotten, so a problem
    # still there when the job is turned on again is said then.
    if [[ "$AGENTS_HC_UP" == 0 ]]; then
        [[ ! -e "$mark" ]] || rm -f "$mark"
        return 0
    fi
    err="$(_agents_hc_up "$restart" true 2>&1 >/dev/null)" || rc=$?
    [[ $rc -ne 0 ]] || _agents_hc_up_mirrors
    if [[ -z "$err" ]]; then
        [[ ! -e "$mark" ]] || rm -f "$mark"
        return "$rc"
    fi
    [[ ! -r "$mark" ]] || said="$(cat "$mark" 2>/dev/null)"
    if [[ "${err//[0-9]/}" != "$said" ]]; then
        printf '%s\n' "$err" >&2
        { mkdir -p "$AGENTS_RUN_DIR" && _agents_replace "$mark" "${err//[0-9]/}"; } 2>/dev/null || true
    fi
    return "$rc"
}

# _agents_hc_up_mirrors — `agents hc mirror sync -q` after an `up` that
# found or started a core (hcmirror.sh, when loaded): what it says and its
# status go nowhere.
_agents_hc_up_mirrors() {
    declare -F agents_hc_mirror_sync >/dev/null || return 0
    agents_hc_mirror_sync -q </dev/null >/dev/null 2>&1 || true
}

# _agents_hc_up RESTART QUIET — agents_hc_up's work.
_agents_hc_up() {
    local restart="$1" quiet="$2" hello gui live
    _agents_hc_need || return 1
    if _agents_hc_running; then
        hello="$(_agents_hc_hello)"
        if [[ -z "$hello" ]]; then
            echo "agents hc: herdr-core is running, but it did not answer within ${_AGENTS_HC_WAIT} s; left alone" >&2
            return 1
        fi
        gui="$(_agents_hc_gui "$hello")"
        if [[ "$gui" != false ]] || ! _agents_hc_is_mac; then
            [[ "$quiet" == true ]] || echo "herdr-core is running"
            return 0
        fi
        live="$(_agents_hc_live)"
        if [[ "$restart" != true ]]; then
            echo "agents hc: herdr-core is running, but $_AGENTS_HC_HEADLESS." >&2
            echo "  agents hc up --restart starts it again here; that ends its ${live:-?} live terminal(s)." >&2
            return 1
        fi
        # The one decision left to the environment's guess: the stop cannot
        # be taken back, and a core started from an SSH login most likely
        # comes back outside the desktop login too.
        if _agents_hc_over_ssh; then
            echo "agents hc: run --restart at the Mac, not over SSH: a core started from here would most likely be outside the desktop login too, and its ${live:-?} live terminal(s) would end for nothing" >&2
            return 1
        fi
        "$_AGENTS_HC_BIN" server stop >/dev/null 2>&1 || { echo "agents hc: could not stop the core" >&2; return 1; }
    fi
    _agents_hc_start_here || return 1
    [[ "$quiet" == true ]] || echo "herdr-core started"
}

# _agents_hc_name DIR — a free terminal name for an agent in DIR: the
# directory's name in herdr-core's alphabet (a-z 0-9 - _, 32 at most), then
# NAME-2 … NAME-9. Nothing when none is free: herdr-core's own address
# (t7) is the name then.
_agents_hc_name() {
    local base taken n cand
    base="$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9_-' '-' | cut -c1-30)"
    while [[ "$base" == -* ]]; do base="${base#-}"; done
    [[ -n "$base" ]] || return 0
    # t7 is how herdr-core addresses a terminal: not a name.
    [[ ! "$base" =~ ^t[0-9]+[a-z]?$ ]] || base="dir-$base"
    taken="$(_agents_timeout "$_AGENTS_HC_WAIT" "$_AGENTS_HC_BIN" ls --json 2>/dev/null \
        | jq -r '.terminals[]? | select(.state == "live") | .name // empty' 2>/dev/null)"
    for n in "" 2 3 4 5 6 7 8 9; do
        cand="$base${n:+-$n}"
        printf '%s\n' "$taken" | grep -qxF -- "$cand" || { printf '%s\n' "$cand"; return 0; }
    done
}

# One line of `herdr-core events --json` -> what to tell Herdr: "end" when
# the terminal finished or was removed, else STATE, AGENT and MESSAGE (unit
# separators between them: an empty field must stay a field) for
# a status (the first line is a snapshot with the status as it is now), and
# nothing for every other event. herdr-core's done and idle are Herdr's idle
# (Herdr shows done by itself after working), error is blocked: it waits on
# you. No status (the agent went back to its shell) is unknown.
# shellcheck disable=SC2016  # jq's $names, not the shell's
_AGENTS_HC_EVENT_JQ='
def agent: if . == null then "" elif test("^claude") then "claude" elif test("^codex") then "codex" else . end;
def row(s): if s == null then "unknown\u001f\u001f"
    else ((s.state // "") as $st
        | (if $st == "working" then "working" elif $st == "blocked" or $st == "error" then "blocked"
           elif $st == "idle" or $st == "done" then "idle" else "unknown" end)
          + "\u001f" + ((s.app // null) | agent)
          + "\u001f" + ((s.msg // "") | tostring | gsub("[\u0000-\u001f\u007f]"; " ") | sub("^[- ]+"; "") | .[0:200]))
    end;
if has("terminals") then (.terminals[0] // empty | row(.status))
elif .method != "event" then empty
elif .params.type == "finished" or .params.type == "removed" then "end"
elif .params.type == "status" then row(.params.data.status)
else empty end'

# _agents_hc_bridge PANE — stdin: `herdr-core events --json` for one
# terminal; each status becomes a report to Herdr for PANE. The agent's name
# is the last one a status carried (Herdr wants one on every report). Herdr
# gets _AGENTS_HC_HERDR_WAIT seconds for each: a Herdr that hangs must not
# hold the pane.
_agents_hc_bridge() {
    local pane="$1" line row state agent msg last=agent
    while IFS= read -r line; do
        row="$(printf '%s' "$line" | jq -r "$_AGENTS_HC_EVENT_JQ" 2>/dev/null)" || continue
        [[ -n "$row" ]] || continue
        [[ "$row" != end ]] || break
        IFS=$'\x1f' read -r state agent msg <<<"$row"
        [[ "$agent" =~ $_AGENTS_HL_AGENT_RE ]] && last="$agent"
        _agents_timeout "$_AGENTS_HC_HERDR_WAIT" _agents_hl_herdr pane report-agent --source "$_AGENTS_HC_SOURCE" \
            --agent "$last" --state "$state" ${msg:+--message "$msg"} "$pane" >/dev/null 2>&1 || true
    done
    _agents_timeout "$_AGENTS_HC_HERDR_WAIT" _agents_hl_herdr pane release-agent "$pane" --source "$_AGENTS_HC_SOURCE" \
        --agent "$last" >/dev/null 2>&1 || true
}

# _agents_hc_events TERMINAL READER — `herdr-core events --json` for
# TERMINAL on stdout, and again after a stream ends while READER (the bridge)
# still reads: herdr-core ends every stream when the core restarts, and the
# attach goes on through that. Each try after the first waits a pause, and is
# skipped while no core runs (a client command starts a core that is gone). After _AGENTS_HC_TRIES
# tries in a row that each ended within 10 s it gives up, and the bridge
# releases the pane. A signal ends it, and the stream or pause it is in at
# once: both are background jobs it waits for, which a trap interrupts.
_agents_hc_events() {
    local t="$1" reader="$2" tries=0 since
    trap 'kill $(jobs -p) 2>/dev/null; exit 0' HUP INT TERM
    while kill -0 "$reader" 2>/dev/null; do
        if _agents_hc_running; then
            since=$SECONDS
            "$_AGENTS_HC_BIN" events --terminal "$t" --json 2>/dev/null &
            wait $!
            [[ $((SECONDS - since)) -lt 10 ]] || tries=0
        fi
        tries=$((tries + 1))
        [[ $tries -lt $_AGENTS_HC_TRIES ]] || break
        sleep "$_AGENTS_HC_PAUSE" &
        wait $!
    done
}

# A Herdr pane that is on a core-hosted agent is marked while it is, so a
# mirror sync (hcmirror.sh) does not mirror into herdr-core what already
# lives there, and the phone's view (hcphone.sh) knows which terminal the
# pane shows. The mark is a file in the run dir: the attaching shell's pid,
# then "PANE<TAB>ADDRESS<TAB>NAME" (an older agents wrote the pid only).
_agents_hc_pane_mark() { printf '%s\n' "$AGENTS_RUN_DIR/hc-pane.$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"; }
_agents_hc_pane_marked() {
    local f pid
    f="$(_agents_hc_pane_mark "$1")"
    [[ -f "$f" ]] || return 1
    read -r pid < "$f" 2>/dev/null || return 1
    _agents_hc_alive "$pid"
}
# _agents_hc_alive PID — a process that runs. A sandbox answers kill -0 for
# someone else's live process with EPERM: alive still, so ps has the last word.
_agents_hc_alive() {
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$1" 2>/dev/null || [[ -n "$(ps -o pid= -p "$1" 2>/dev/null)" ]]
}

# _agents_hc_marks — "PANE<US>ADDRESS<US>NAME" for each pane on a hosted agent
# now (its mark's attach still runs), from the marks alone: no core call, one
# read and one kill -0 a mark. A mark with no second line is left out.
_AGENTS_HC_ID_RE='^[A-Za-z0-9][A-Za-z0-9:/._-]{0,63}$'
_agents_hc_marks() {
    local f pid line pane addr name
    for f in "$AGENTS_RUN_DIR"/hc-pane.*; do
        [[ -f "$f" ]] || continue
        pid="" line=""
        { read -r pid; IFS= read -r line; } < "$f" 2>/dev/null || true
        if [[ -z "$line" ]] || ! _agents_hc_alive "$pid"; then continue; fi
        IFS=$'\t' read -r pane addr name <<<"$line"
        [[ "$pane" =~ $_AGENTS_HC_ID_RE && "$addr" =~ $_AGENTS_HC_ID_RE ]] || continue
        [[ "$name" =~ $_AGENTS_HC_ID_RE ]] || name="$addr"
        printf '%s\037%s\037%s\n' "$pane" "$addr" "$name"
    done
}

# _agents_hc_attach ADDRESS [NAME] — put this terminal on the core terminal at
# ADDRESS (a name can point at another terminal after a core restart; NAME is
# only what is shown) until you
# detach (ctrl+\) or its program ends. In a Herdr pane, the bridge runs
# beside it through a pipe: the events stream on one end is ours to end (its
# pid), and the reader on the other ends with it. A closed pane hangs up
# every process in it; the reader traps that instead of dying (a trap, not an
# ignored signal, so what it runs can still be timed out), and releases the
# pane once the stream is gone.
_agents_hc_attach() {
    local t="$1" shown="${2:-$1}" rc=0 state=""
    _AGENTS_HC_EV="" _AGENTS_HC_READER="" _AGENTS_HC_FIFO="" _AGENTS_HC_MARK=""
    if [[ -n "${HERDR_PANE_ID:-}" ]] && _agents_hl_ready; then
        mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null
        trap '_agents_hc_attach_end' EXIT
        trap '_agents_hc_attach_end; exit 129' HUP
        trap '_agents_hc_attach_end; exit 130' INT
        trap '_agents_hc_attach_end; exit 143' TERM
        _AGENTS_HC_MARK="$(_agents_hc_pane_mark "$HERDR_PANE_ID")"
        printf '%s\n%s\t%s\t%s\n' "$$" "$HERDR_PANE_ID" "$t" "$shown" > "$_AGENTS_HC_MARK" 2>/dev/null || _AGENTS_HC_MARK=""
        _AGENTS_HC_FIFO="$AGENTS_RUN_DIR/hc-bridge.$$"
        rm -f "$_AGENTS_HC_FIFO"
        if mkfifo -m 600 "$_AGENTS_HC_FIFO" 2>/dev/null; then
            # The trap before the pipe is opened: a signal while that waits
            # fails the open (bash 3.2), which is fine, nothing was reported.
            { trap : HUP INT TERM; _agents_hc_bridge "$HERDR_PANE_ID" < "$_AGENTS_HC_FIFO"; } >/dev/null 2>&1 &
            _AGENTS_HC_READER=$!
            _agents_hc_events "$t" "$_AGENTS_HC_READER" > "$_AGENTS_HC_FIFO" 2>/dev/null &
            _AGENTS_HC_EV=$!
        else
            _AGENTS_HC_FIFO=""
        fi
    fi
    "$_AGENTS_HC_BIN" attach "$t" || rc=$?
    _agents_hc_attach_end
    trap - EXIT HUP INT TERM
    # Asked only of a core that still runs: it would start one that is gone.
    ! _agents_hc_running || state="$(_agents_timeout "$_AGENTS_HC_WAIT" "$_AGENTS_HC_BIN" get "$t" --json 2>/dev/null \
        | jq -r '.state // empty' 2>/dev/null)"
    if [[ "$state" == live ]]; then
        echo "$shown still runs in herdr-core (your phone has it too): agents hc attach $t  ·  end it: herdr-core kill $t"
    fi
    return "$rc"
}

# _agents_hc_attach_end — the bridge's end, once, on every way out of an
# attach (detach, the program's end, a closed pane, ctrl-c): the events
# stream is ended, which ends the reader after its release of the pane (it
# has its own time limits), and the pipe and the pane's mark go. A reader
# still waiting for the pipe's other end (the stream was ended before it
# opened it) is let go by an opener that closes it at once; that opener is
# ended when the reader had the pipe already, or was gone.
_agents_hc_attach_end() {
    local ev="$_AGENTS_HC_EV" reader="$_AGENTS_HC_READER" opener
    _AGENTS_HC_EV="" _AGENTS_HC_READER=""
    if [[ -n "$ev" ]]; then
        kill "$ev" 2>/dev/null
        wait "$ev" 2>/dev/null
    fi
    if [[ -n "$reader" ]]; then
        ( : > "$_AGENTS_HC_FIFO" ) 2>/dev/null &
        opener=$!
        wait "$reader" 2>/dev/null
        kill "$opener" 2>/dev/null
        wait "$opener" 2>/dev/null
    fi
    [[ -z "$_AGENTS_HC_FIFO" ]] || rm -f "$_AGENTS_HC_FIFO"
    [[ -z "$_AGENTS_HC_MARK" ]] || rm -f "$_AGENTS_HC_MARK"
    _AGENTS_HC_FIFO="" _AGENTS_HC_MARK=""
}

# agents_hc_run [--name NAME] [--] CMD [ARG...] — start CMD in herdr-core,
# in this directory, and put this terminal on it. It gets the core's
# environment (herdr-core's rule) with this shell's PATH and the few
# variables of _AGENTS_HC_AUTO_ENV over it: a core started by the pack's job
# has launchd's or systemd's PATH, where node or the agent itself may not be.
agents_hc_run() {
    local name="" t out gui shown k envs=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)  name="${2:-}"; shift; [[ $# -gt 0 ]] && shift
                     [[ "$name" =~ $_AGENTS_HC_NAME_RE ]] || { echo "agents hc: a name is 1-32 of a-z 0-9 - _, not starting with -" >&2; return 2; } ;;
            --)      shift; break ;;
            -*)      echo "agents hc: unknown option $1" >&2; return 2 ;;
            *)       break ;;
        esac
    done
    [[ $# -gt 0 ]] || { echo "usage: agents hc run [--name NAME] [--] CMD [ARG...]" >&2; return 2; }
    _agents_hc_need || return 1
    if _agents_hc_running; then
        gui="$(_agents_hc_gui "$(_agents_hc_hello)")"
        if [[ "$gui" == false ]] && _agents_hc_is_mac; then
            echo "agents hc: warning: the core is running, but $_AGENTS_HC_HEADLESS (agents hc up --restart)." >&2
        fi
    else
        _agents_hc_start_here || return 1
    fi
    [[ -n "$name" ]] || name="$(_agents_hc_name "$PWD")"
    # No parent: started from inside a core terminal, it would end with that
    # terminal's program, and herdr-core would type notes about it there.
    for k in $_AGENTS_HC_AUTO_ENV; do
        [[ -z "${!k+set}" ]] || envs+=("$k=${!k}")
    done
    out="$("$_AGENTS_HC_BIN" run --bg --json --no-parent ${name:+--name "$name"} -- /usr/bin/env ${envs[@]+"${envs[@]}"} "$@")" || {
        [[ -z "$out" ]] || printf '%s\n' "$out" >&2
        return 1
    }
    t="$(printf '%s' "$out" | jq -r '.address // empty' 2>/dev/null)"
    [[ -n "$t" ]] || { echo "agents hc: herdr-core did not say what it started" >&2; return 1; }
    shown="$(printf '%s' "$out" | jq -r '.name // empty' 2>/dev/null)"
    _agents_hc_attach "$t" "${shown:-$t}"
}

# --- automatic hosting: agents hc auto CMD [ARG...] ---
#
# The herdr-core pack's shell fragment turns a `claude` or `codex` typed in
# a Herdr pane into `agents hc auto claude ...`. It hosts the agent in
# herdr-core only when everything for that holds, and otherwise runs the
# command as typed: its own environment, its exit status, nothing added.
# Every test before the core's is a variable or a file; the core is asked
# only once it is known to run, and never started from here.

# The options an interactive session takes, per agent: flags (F), options
# with one value (V: the next argument, or --opt=VALUE), and with an optional
# one (O). An option that takes several values is on V too: a second value
# then runs the command as typed, where taking every next word would host
# `codex --add-dir DIR exec ...`. Any other option, or
# an argument that is no option's value (a prompt, a subcommand such as
# `claude mcp` or `codex exec`), runs the command as typed: -p, --help and
# --version are not on these lists. A new option of the agent's is one more
# word here; until then the agent starts the plain way.
_AGENTS_HC_AUTO_CLAUDE_F=" -c --continue --fork-session --verbose --ide --chrome --no-chrome --strict-mcp-config --dangerously-skip-permissions --allow-dangerously-skip-permissions "
_AGENTS_HC_AUTO_CLAUDE_V=" --model --permission-mode --settings --setting-sources --append-system-prompt --system-prompt --agent --agents --session-id --add-dir --mcp-config --allowed-tools --allowedTools --disallowed-tools --disallowedTools --plugin-dir "
_AGENTS_HC_AUTO_CLAUDE_O=" -r --resume --debug "
_AGENTS_HC_AUTO_CODEX_F=" --search --full-auto --dangerously-bypass-approvals-and-sandbox --oss --no-alt-screen --no-daemon "
_AGENTS_HC_AUTO_CODEX_V=" -m --model -p --profile -s --sandbox -a --ask-for-approval -C --cd -c --config --local-provider --enable --disable -i --image --add-dir "
# Set in the pane, these choose the account, the provider or the network an
# agent uses, and a hosted one would not have them: such a start is not hosted.
_AGENTS_HC_AUTO_OWN="ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX OPENAI_API_KEY OPENAI_BASE_URL HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY NODE_EXTRA_CA_CERTS"
# What a hosted agent gets from the pane besides its directory, when set
# there: the PATH it was found on, the locale, the editor, and where the
# agents keep their settings. Never the rest of the shell's environment: a
# token exported there would live on in a terminal of a long-lived core.
_AGENTS_HC_AUTO_ENV="PATH LANG LC_ALL LC_CTYPE LC_MESSAGES TZ EDITOR VISUAL CLAUDE_CONFIG_DIR CODEX_HOME"

# _agents_hc_auto_interactive CMD [ARG...] — is this the start of an
# interactive session: claude or codex with only the options above (codex
# also as `codex resume [--last|--all] [SESSION]`)? Pure bash, no fork.
_agents_hc_auto_interactive() {
    local cmd="${1##*/}" f v o="" a want="" pos=0 maxpos=0
    shift
    case "$cmd" in
        claude) f="$_AGENTS_HC_AUTO_CLAUDE_F" v="$_AGENTS_HC_AUTO_CLAUDE_V" o="$_AGENTS_HC_AUTO_CLAUDE_O" ;;
        codex)  f="$_AGENTS_HC_AUTO_CODEX_F" v="$_AGENTS_HC_AUTO_CODEX_V"
                if [[ "${1:-}" == resume ]]; then shift; f+="--last --all "; maxpos=1; fi ;;
        *)      return 1 ;;
    esac
    for a in "$@"; do
        # The value of the option before it.
        if [[ -n "$want" && "$a" != -* ]]; then
            want=""
            continue
        fi
        [[ "$want" != v ]] || return 1
        want=""
        case "$a" in
            --*=*)  case "$v$o" in *" ${a%%=*} "*) continue ;; esac
                    return 1 ;;
            -*)     case "$f" in *" $a "*) continue ;; esac
                    case "$v" in *" $a "*) want=v; continue ;; esac
                    case "$o" in *" $a "*) want=o; continue ;; esac
                    return 1 ;;
            *)      pos=$((pos + 1))
                    [[ $pos -le $maxpos ]] || return 1 ;;
        esac
    done
    [[ "$want" != v ]]
}

# A person typed it: stdin and stdout are the terminal.
_agents_hc_auto_tty() { [[ -t 0 && -t 1 ]]; }

# _agents_hc_auto_wanted CMD [ARG...] — should this start be hosted? Silent
# when it should not; _AGENTS_HC_WHY says why only when the core was asked
# and did not answer (the start waited for it).
_agents_hc_auto_wanted() {
    local hello
    _AGENTS_HC_WHY=""
    [[ "${AGENTS_HC_AUTO:-0}" == 1 ]] || return 1
    # A Herdr pane, not a terminal of herdr-core's (where the agent would be
    # hosted already), with a person at it.
    [[ "${HERDR_ENV:-}" == 1 && -n "${HERDR_PANE_ID:-}" && -z "${HC_TERMINAL_ID:-}" ]] || return 1
    _agents_hc_auto_tty || return 1
    _agents_hc_auto_interactive "$@" || return 1
    for hello in $_AGENTS_HC_AUTO_OWN; do
        [[ -z "${!hello:-}" ]] || return 1
    done
    ! _agents_hc_pane_marked "$HERDR_PANE_ID" || return 1
    command -v jq >/dev/null 2>&1 && _agents_hc_bin || return 1
    _agents_hc_running || return 1
    _agents_hc_is_mac || return 0
    # A core outside the desktop login would give "Not logged in"; one that
    # does not say where it runs is not trusted with it either.
    hello="$(_agents_hc_hello)"
    if [[ -z "$hello" ]]; then
        _AGENTS_HC_WHY="herdr-core did not answer within ${_AGENTS_HC_WAIT} s"
        return 1
    fi
    [[ "$(_agents_hc_gui "$hello")" == true ]]
}

# _agents_hc_auto_undo NAME — the core may have started the terminal whose
# answer never came: end it, or the agent would run twice (the plain start
# follows), two processes on one session with --continue. NAME was free a
# moment ago (_agents_hc_name), so it is that terminal or none.
_agents_hc_auto_undo() {
    [[ -n "$1" ]] || return 0
    : "$(_agents_timeout "$_AGENTS_HC_WAIT" "$_AGENTS_HC_BIN" kill "$1" 2>/dev/null)"
}

# _agents_hc_auto_host REAL [ARG...] — start REAL in herdr-core, in this
# directory with _AGENTS_HC_AUTO_ENV from this shell, and attach to it.
# False, with _AGENTS_HC_WHY, when the core did not start it; else true,
# with the attach's status in _AGENTS_HC_RC.
_agents_hc_auto_host() {
    local real="$1" name out t shown rc=0 k envs=() pre=()
    shift
    # herdr-core's own rule: a codex without it runs its commands outside the core.
    [[ "${real##*/}" != codex || " $* " == *" --no-daemon "* ]] || pre=(--no-daemon)
    for k in $_AGENTS_HC_AUTO_ENV; do
        [[ -z "${!k+set}" ]] || envs+=("$k=${!k}")
    done
    name="$(_agents_hc_name "$PWD")"
    # env(1) sets them: herdr-core's CLI has no option for it. No parent, as
    # in agents_hc_run.
    out="$(_agents_timeout "$_AGENTS_HC_WAIT" "$_AGENTS_HC_BIN" run --bg --json --no-parent --cwd "$PWD" \
        ${name:+--name "$name"} -- /usr/bin/env ${envs[@]+"${envs[@]}"} "$real" ${pre[@]+"${pre[@]}"} "$@" 2>/dev/null)" || rc=$?
    if [[ $rc -eq 124 ]]; then
        _AGENTS_HC_WHY="herdr-core did not answer within ${_AGENTS_HC_WAIT} s"
        _agents_hc_auto_undo "$name"
        return 1
    elif [[ $rc -ne 0 ]]; then
        _AGENTS_HC_WHY="$(printf '%s' "$out" | jq -r '.error.message // empty' 2>/dev/null | head -n 1)"
        _AGENTS_HC_WHY="herdr-core did not start it${_AGENTS_HC_WHY:+ (${_AGENTS_HC_WHY})}"
        return 1
    fi
    t="$(printf '%s' "$out" | jq -r '.address // empty' 2>/dev/null)"
    if [[ -z "$t" ]]; then
        _AGENTS_HC_WHY="herdr-core did not say what it started"
        _agents_hc_auto_undo "$name"
        return 1
    fi
    shown="$(printf '%s' "$out" | jq -r '.name // empty' 2>/dev/null)"
    _AGENTS_HC_RC=0
    _agents_hc_attach "$t" "${shown:-$t}" || _AGENTS_HC_RC=$?
    return 0
}

# _agents_hc_auto_exec CMD REAL [ARG...] — run REAL as CMD with the
# environment this process was given: what loading agents exported itself
# (config.sh's patterns) is taken back out first (bin/agents kept the names
# it was started with in _AGENTS_ENV_IN).
_agents_hc_auto_exec() {
    local cmd="$1" real="$2" n
    shift 2
    if [[ -n "${_AGENTS_ENV_IN:-}" ]]; then
        for n in $(compgen -e); do
            # shellcheck disable=SC2163  # the variable named by $n
            [[ "$_AGENTS_ENV_IN" == *$'\n'"$n"$'\n'* ]] || export -n "$n"
        done
    fi
    exec -a "$cmd" "$real" "$@"
}

# agents_hc_auto CMD [ARG...] — CMD hosted in herdr-core when
# _agents_hc_auto_wanted says so, else CMD as typed. CMD is looked up on
# PATH (this is bash: the shell's claude function is not here).
agents_hc_auto() {
    local cmd="${1:-}" real
    [[ -n "$cmd" ]] || { echo "usage: agents hc auto CMD [ARG...]" >&2; return 2; }
    # What the shell fragment asks before it defines its functions.
    [[ "$cmd" != --supported ]] || return 0
    shift
    real="$(type -P "$cmd" 2>/dev/null)"
    [[ -n "$real" ]] || { echo "agents hc: $cmd: command not found" >&2; return 127; }
    # A path with = in it would be an assignment to env(1).
    if [[ "$real" != *=* ]] && _agents_hc_auto_wanted "$cmd" "$@"; then
        _agents_hc_auto_host "$real" "$@" && return "$_AGENTS_HC_RC"
    fi
    [[ -z "$_AGENTS_HC_WHY" ]] || echo "agents hc: $_AGENTS_HC_WHY; $cmd starts here, not in herdr-core" >&2
    _agents_hc_auto_exec "$cmd" "$real" "$@"
}

agents_hc() {
    local cmd="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$cmd" in
        status) agents_hc_status ;;
        up)     agents_hc_up "$@" ;;
        run)    agents_hc_run "$@" ;;
        auto)   agents_hc_auto "$@" ;;
        ls)     [[ $# -eq 0 ]] || { echo "usage: agents hc ls" >&2; return 2; }
                agents_hc_ls ;;
        mirror) agents_hc_mirror "$@" ;;
        _mirror) agents_hc_mirror_run "$@" ;;   # what a mirror's core terminal runs
        attach) [[ $# -eq 1 && "$1" != -* ]] || { echo "usage: agents hc attach TERMINAL" >&2; return 2; }
                _agents_hc_need || return 1
                _agents_hc_running || { echo "agents hc: no core runs (agents hc up)" >&2; return 1; }
                _agents_hc_attach "$1" ;;
        *)      echo "usage: agents hc [status] | up [--restart] [-q] | run [--name NAME] [--] CMD... | auto CMD... | attach TERMINAL | ls | mirror [status|sync|fit|end|off|on]" >&2; return 2 ;;
    esac
}
