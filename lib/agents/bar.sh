# shellcheck shell=bash
# lib/agents/bar.sh — the menu bar refreshes when something changed, not on a
# short timer (`agents bar poke`).
#
# The SwiftBar plugin (configs/swiftbar/agents.10s.sh) runs on a slow backstop
# timer (AGENTS_BAR_REFRESH, 1m) and when something asks: Claude Code's hooks
# (configs/claude/settings.json, and `agents hook` itself), Herdr's agent
# events (the tuidev.link plugin, through `agents herdr sync --poke`), Codex's
# notify, the menu opening, and the plugin's own early refresh while a command
# runs. Each asks through a poke, which opens swiftbar://refreshplugin. A poke:
#   - goes out only where SwiftBar runs the plugin now. On every run the plugin
#     writes bar.alive (EPOCH SWIFTBAR_PID NAME LAUNCH); a poke needs that pid
#     alive (kill -0, no fork) and the stamp younger than two backstops,
#     because `open` launches an app that is not running. Anywhere else (Linux,
#     the Pi, a Mac without SwiftBar or with the plugin turned off) it is a
#     silent no-op.
#   - is debounced: at most one every _AGENTS_BAR_GAP seconds. The poke that
#     goes out takes bar.busy and leaves a keeper behind for the window; a poke
#     that arrives inside it only marks bar.dirty, and the keeper sends exactly
#     one more at the window's end, so the last event is never lost and a storm
#     (an agent loop firing Stop after Stop) costs one refresh per window.
#     Every poke marks bar.dirty before it looks at bar.busy, and the keeper
#     looks at bar.dirty again after it lets go of bar.busy: one of them always
#     sees the other.
# The shipped hooks take the same path in sh before anything starts (a
# couple of [ -e ] tests): no bar.alive, no `agents`; bar.busy held, a mark
# and nothing else.
#
# Files, in $AGENTS_RUN_DIR:
#   bar.alive  EPOCH PID NAME LAUNCH  the plugin's last run under SwiftBar
#              (written by the plugin): SwiftBar's pid, the name SwiftBar
#              knows the plugin by, SwiftBar's launch time
#   bar.busy   EPOCH  a poke went out less than a window ago; its keeper holds it
#   bar.dirty  a poke arrived while busy (the plugin's idle fast path defers
#              to it too)
#   bar.poked  EPOCH of the last poke sent (the idle fast path compares its age)
#   bar.next   DUE TOKEN  the plugin's one pending early refresh (the plugin's)
#
# Uses: config.sh (AGENTS_RUN_DIR, AGENTS_BAR_REFRESH), util.sh (_agents_now,
#   _agents_detach).
# Public: agents_bar, agents_bar_poke, _agents_bar_secs.

_AGENTS_BAR_GAP=2      # seconds between two pokes, at least
_AGENTS_BAR_STALE=10   # a bar.busy this old lost its keeper: taken over

# _agents_bar_secs VAR INTERVAL — set VAR to AGENTS_BAR_REFRESH's shape (10s,
# 1m, 2h, 1d) in seconds; 60 for anything else.
_agents_bar_secs() {
    local v="${2:-}" n
    n="${v%[smhd]}"
    [[ "$v" =~ ^[1-9][0-9]{0,6}[smhd]$ ]] || { printf -v "$1" '%s' 60; return 0; }
    case "$v" in
        *s) printf -v "$1" '%s' "$n" ;;
        *m) printf -v "$1" '%s' "$((n * 60))" ;;
        *h) printf -v "$1" '%s' "$((n * 3600))" ;;
        *d) printf -v "$1" '%s' "$((n * 86400))" ;;
    esac
}

# _agents_bar_target NOW — true when a poke can go out: macOS, the plugin ran
# under SwiftBar lately and that SwiftBar still runs. Sets _AGENTS_BAR_NAME,
# the plugin's name for the URL. Reads bar.alive twice at most: the plugin
# rewrites it in place, and a read inside that write sees it empty.
_agents_bar_target() {
    local f="$AGENTS_RUN_DIR/bar.alive" t="" pid="" name="" back try
    _AGENTS_BAR_NAME=""
    [[ "${OSTYPE:-}" == darwin* && -f "$f" ]] || return 1
    for try in 1 2; do
        read -r t pid name _ < "$f" 2>/dev/null
        [[ -z "$t" && $try -eq 1 ]] || break
        sleep 0.05 2>/dev/null || true
    done
    [[ "$t" =~ ^[0-9]+$ && "$pid" =~ ^[0-9]+$ && "$name" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || return 1
    _agents_bar_secs back "$AGENTS_BAR_REFRESH"
    [[ $(( $1 - t )) -lt $(( 2 * back + 60 )) ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    _AGENTS_BAR_NAME="$name"
}

# _agents_bar_take NOW — take bar.busy (noclobber: O_EXCL, one winner). A
# bar.busy older than _AGENTS_BAR_STALE lost its keeper: taken over, once.
_agents_bar_take() {
    local f="$AGENTS_RUN_DIR/bar.busy" t="" rc
    set -C
    { printf '%s\n' "$1" > "$f"; } 2>/dev/null; rc=$?
    set +C
    [[ $rc -ne 0 ]] || return 0
    read -r t < "$f" 2>/dev/null
    [[ "$t" =~ ^[0-9]+$ && $(( $1 - t )) -lt $_AGENTS_BAR_STALE ]] && return 1
    rm -f "$f"
    set -C
    { printf '%s\n' "$1" > "$f"; } 2>/dev/null; rc=$?
    set +C
    return $rc
}

# _agents_bar_send NOW — the refresh itself, if SwiftBar is still there:
# `open -g` (in the background: a hook never waits on Launch Services), and
# bar.poked. False when it went nowhere.
_agents_bar_send() {
    _agents_bar_target "$1" || return 1
    printf '%s\n' "$1" > "$AGENTS_RUN_DIR/bar.poked" 2>/dev/null
    _agents_detach open -g "swiftbar://refreshplugin?name=$_AGENTS_BAR_NAME"
    return 0
}

# _agents_bar_keeper — hold bar.busy for the window after a poke: at its end,
# one more poke when any arrived meanwhile (and hold on for the next window),
# else let go. After letting go, a mark made just before is still honoured.
_agents_bar_keeper() {
    local r="$AGENTS_RUN_DIR" now
    while :; do
        sleep "$_AGENTS_BAR_GAP" 2>/dev/null || return 0
        _agents_now now
        if [[ -e "$r/bar.dirty" ]]; then
            rm -f "$r/bar.dirty"
            printf '%s\n' "$now" > "$r/bar.busy" 2>/dev/null
            _agents_bar_send "$now" && continue
            rm -f "$r/bar.busy"; return 0
        fi
        rm -f "$r/bar.busy"
        [[ -e "$r/bar.dirty" ]] || return 0
        _agents_bar_take "$now" || return 0     # another poke took it: its keeper sees the mark
        rm -f "$r/bar.dirty"
        _agents_bar_send "$now" || { rm -f "$r/bar.busy"; return 0; }
    done
}

# agents_bar_poke [--settle] — ask the menu bar to refresh now (see the top
# of this file). --settle: once more at the window's end, for an event whose
# effect lands a moment later (a session ending: its process exits after
# the hook). Silent, and always 0.
agents_bar_poke() {
    local settle=false a now r="$AGENTS_RUN_DIR"
    for a in "$@"; do
        case "$a" in
            --settle) settle=true ;;
            *) echo "usage: agents bar poke [--settle]" >&2; return 2 ;;
        esac
    done
    _agents_now now
    _agents_bar_target "$now" || return 0
    : > "$r/bar.dirty" 2>/dev/null || return 0
    _agents_bar_take "$now" || return 0         # inside a window: its keeper sends the mark
    rm -f "$r/bar.dirty"
    _agents_bar_send "$now" || { rm -f "$r/bar.busy"; return 0; }
    [[ "$settle" == false ]] || : > "$r/bar.dirty"
    _agents_detach _agents_bar_keeper
    return 0
}

# agents_bar_status — what a poke would do now, for people: the plugin's last
# run, SwiftBar's pid, the last poke, a window or an early refresh pending.
agents_bar_status() {
    local r="$AGENTS_RUN_DIR" now t="" pid="" name="" due=""
    _agents_now now
    if [[ -r "$r/bar.alive" ]]; then
        read -r t pid name _ < "$r/bar.alive"
        printf 'plugin: %s, last run %ss ago under SwiftBar pid %s\n' "${name:--}" "$(( now - ${t:-0} ))" "${pid:--}"
    else
        echo "plugin: has not run under SwiftBar here (no $r/bar.alive)"
    fi
    if _agents_bar_target "$now"; then echo "poke: goes out (open -g swiftbar://refreshplugin?name=$_AGENTS_BAR_NAME)"
    else echo "poke: a no-op here (not macOS, no SwiftBar running the plugin, or its last run is too old)"; fi
    t=""; [[ -r "$r/bar.poked" ]] && read -r t < "$r/bar.poked"
    [[ -z "$t" ]] || printf 'last poke: %ss ago\n' "$(( now - t ))"
    [[ ! -e "$r/bar.busy" ]] || echo "window: open (another poke now waits for its end)"
    [[ ! -r "$r/bar.next" ]] || { read -r due _ < "$r/bar.next"; printf 'early refresh: in %ss\n' "$(( ${due:-$now} - now ))"; }
    printf 'backstop: %s (AGENTS_BAR_REFRESH)\n' "$AGENTS_BAR_REFRESH"
}

# agents bar poke [--settle] | status
agents_bar() {
    local sub="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        poke)   agents_bar_poke "$@" ;;
        status) agents_bar_status ;;
        *)      echo "usage: agents bar [status | poke [--settle]]" >&2; return 2 ;;
    esac
}
