# shellcheck shell=bash
# lib/agents/hcmirror.sh — every agent in this machine's Herdr, on your phone
# too. An agent that a Herdr TUI pane owns cannot be moved into herdr-core,
# but it can be mirrored there: a core terminal that runs `herdr agent attach
# PANE`. Herdr's phone app lists it like any other, typing in it reaches the
# agent in the pane, and its state is in the inbox.
#
# One mirror per agent pane, kept in step by `agents hc mirror sync`, which
# `agents herdr sync` runs after its own (the tuidev.link plugin's event
# hooks: an agent detected, changed, gone): a mirror is started for an agent
# pane that has none, and ended when its pane has no agent any more. A mirror
# is a core terminal labelled tuidev_mirror=PANE_ID, and only those are ever
# ended here. One that ends goes from the core with it (--rm), and a pane's
# mirror is started again only a minute after the last start: one that ends
# at once (its attach failed) is not started on every event.
#
# Inside a mirror (`agents hc _mirror`, the program the core terminal runs):
#   - the terminal is first sized to the pane, because the attach gives the
#     pane the mirror's size, and a core terminal nobody looks at is 200x120;
#   - herdr-core stores only the status a program reports (OSC 7501), and an
#     attach reports none, so Herdr's state for the pane is printed as one:
#     `herdr agent wait` blocks until it changes, no polling.
# While the phone shows a mirror the pane has the phone's size, and it gets
# its own back when the phone stops showing that session (typing at the desk
# does not give it back). Herdr's phone app keeps the last session it opened
# attached while it shows its Inbox, so focusing the pane at the desk gives it
# its own size back too (`agents hc mirror fit`, the tuidev.link plugin's
# pane.focused hook): the desk wins while you are at it, and the phone's
# view of that session is a corner of the pane until the phone sets a size
# again (it opens the session again, or turns).
#
# Not mirrored: a pane that is itself on a core-hosted agent (`agents hc run`:
# hc.sh marks it), a pane you opted out (`agents hc mirror off [PANE]`, until
# `on` or until the pane is gone), and anything while no core runs. A sync
# asks a core only after it found one running, but a core that stops between
# that look and the question is started again by it (every herdr-core client
# command starts one). Every call to the core or to Herdr has a time limit:
# the sync holds a lock, and one that hangs must not hold every later one. An
# answer that is not one (a list or a snapshot that did not come, or does
# not parse) changes nothing: read as "no mirrors" it would start them all
# again.
#
# Owns: `agents hc mirror` (status, sync, fit, end, off, on), `agents hc _mirror`,
#   hc-mirror.lock, hc-mirror.dirty (a sync that came in while one ran),
#   hc-mirror-fit.lock, hc-mirror-fit.dirty (the same for fits),
#   hc-mirror.started/ (when each pane's mirror last started),
#   hc-mirror.wait/ (each pane's follower's last answer from Herdr),
#   hc-mirror.off (the opted-out panes).
# Uses: config.sh (AGENTS_HC_MIRROR, AGENTS_HC_MIRROR_FIT, AGENTS_RUN_DIR), hc.sh (_agents_hc_bin,
#   _agents_hc_running, _agents_hc_name, _agents_hc_pane_marked,
#   _AGENTS_HC_WAIT, _AGENTS_HC_HERDR_WAIT), herdrlabel.sh (_agents_hl_herdr,
#   _agents_hl_ready), util.sh (_agents_lock, _agents_unlock, _agents_timeout,
#   _agents_now, _agents_stamp_age, _agents_replace).
# Public: agents_hc_mirror, agents_hc_mirror_sync, agents_hc_mirror_fit,
#   agents_hc_mirror_end, agents_hc_mirror_off, agents_hc_mirror_on, _agents_hm_sync for
#   herdrlabel.sh (a sync from the snapshot it has), and for hcphone.sh
#   _agents_hm_on, _agents_hm_list, _agents_hm_have_of, _agents_hm_want,
#   _agents_hm_off_read, _agents_hm_is_off.

_AGENTS_HM_LABEL="tuidev_mirror"
_AGENTS_HM_PANE_RE='^[A-Za-z0-9][A-Za-z0-9:._-]{0,63}$'
_AGENTS_HM_AGAIN=60              # seconds before a pane's mirror is started again
_AGENTS_HM_PAUSE=1               # seconds a sync waits before going again for syncs that came in
_AGENTS_HM_RETRY=2               # a follower Herdr did not answer asks again after this, doubled each time
_AGENTS_HM_RETRY_MAX=60          # … up to this

# The agent panes of one `herdr api snapshot`, a line each:
# PANE, COLS, ROWS, AGENT, STATE, CWD and TITLE (the session's task title,
# "" for none), unit separators between them. The size is the pane's
# in its tab's layout (160x50 for one the snapshot has no layout for). An
# error (jq exits 5) when the answer has no list of panes.
# shellcheck disable=SC2016  # jq's $names, not the shell's
_AGENTS_HM_PANES_JQ='
.result.snapshot as $s
| if ($s.panes | type) != "array" then error("no panes") else . end
| ([$s.layouts[]? | .panes[]? | {key: .pane_id, value: .rect}] | from_entries) as $rect
| $s.panes[] | select((.agent // "") != "")
| [.pane_id, ($rect[.pane_id].width // 160), ($rect[.pane_id].height // 50), .agent, (.agent_status // ""),
   (.foreground_cwd // .cwd // ""), (.terminal_title_stripped // "" | tostring | .[0:120])]
| map(tostring | gsub("[\u0000-\u001f\u007f]"; " ")) | join("\u001f")'

# _agents_hm_want — the agent panes, as above; false when Herdr did not
# answer in time or the answer has no panes. _agents_hm_snap is Herdr's
# answer itself, and _agents_hm_want_of SNAP the panes in it.
_agents_hm_want() {
    local snap
    snap="$(_agents_hm_snap)" || return 1
    _agents_hm_want_of "$snap"
}
_agents_hm_snap() {
    local snap
    snap="$(_agents_timeout "$_AGENTS_HC_HERDR_WAIT" _agents_hl_herdr api snapshot 2>/dev/null)" && [[ -n "$snap" ]] || return 1
    printf '%s\n' "$snap"
}
_agents_hm_want_of() { printf '%s' "$1" | jq -r "$_AGENTS_HM_PANES_JQ" 2>/dev/null; }
# _agents_hm_ids_of SNAP — every pane of the snapshot, an agent in it or not.
_agents_hm_ids_of() {
    printf '%s' "$1" | jq -r '.result.snapshot.panes | if type == "array" then .[] | objects | .pane_id // empty | tostring else error("no panes") end' 2>/dev/null
}

# _agents_hm_have — the live mirrors among the core's terminals: ADDRESS,
# PANE and NAME. From the API's terminal.list: `herdr-core ls` leaves the
# labels out. False unless the core gave the answer in time: the response
# to our id (a notification may come first), with a list of terminals.
# _agents_hm_list is that answer, one line of JSON (hcphone.sh reads it
# too), and _agents_hm_have_of LIST the mirrors in it.
_AGENTS_HM_LIST='{"jsonrpc":"2.0","id":1,"method":"terminal.list","params":{}}'
_agents_hm_have() {
    local out
    out="$(_agents_hm_list)" || return 1
    _agents_hm_have_of "$out"
}
_agents_hm_list() {
    local out
    out="$(_agents_timeout "$_AGENTS_HC_WAIT" _agents_hm_ask_list)" && [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
}
_agents_hm_have_of() { printf '%s\n' "$1" | jq -r --arg l "$_AGENTS_HM_LABEL" "$_AGENTS_HM_HAVE_JQ" 2>/dev/null; }
# _agents_hm_core ARGS — a herdr-core client call without the Herdr identity of
# whoever runs the sync (a Herdr hook, a pane): a client call starts a core
# when none runs, and that core must not hand a pane's identity to the
# terminals it starts later (_agents_hc_start does the same).
_agents_hm_core() {
    env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_SOCKET_PATH -u HERDR_BIN_PATH \
        "$_AGENTS_HC_BIN" "$@"
}
# The request is written from inside the timed function: _agents_timeout
# gives what it runs no stdin. This relies on `connect` exiting when its
# stdin ends (herdr-core 0.1.x does): one that stayed open would run into the
# time limit, and the sync would change nothing.
_agents_hm_ask_list() {
    printf '%s\n' "$_AGENTS_HM_LIST" | _agents_hm_core connect 2>/dev/null \
        | jq --unbuffered -Rc 'fromjson? | select(type == "object" and .id == 1)' 2>/dev/null | head -n 1
}
# shellcheck disable=SC2016
_AGENTS_HM_HAVE_JQ='
if (.result.terminals | type) != "array" then error("no list") else . end
| .result.terminals[] | select(.state == "live") | select((.labels // {})[$l] != null)
| [.address, .labels[$l], (.name // "")] | map(tostring | gsub("[\u0000-\u001f\u007f]"; " ")) | join("\u001f")'

_agents_hm_on() { [[ "${AGENTS_HC_MIRROR:-0}" == 1 ]]; }
_agents_hm_ready() {
    _agents_hm_on || return 1
    _agents_hl_ready || return 1
    _agents_hc_bin || return 1
    _agents_hc_running
}

_agents_hm_why_not() {
    if ! _agents_hm_on; then echo "off (AGENTS_HC_MIRROR=1 in agents.conf turns it on; experimental)"
    elif ! _agents_hl_ready; then echo "this machine's Herdr is not reachable"
    elif ! _agents_hc_bin; then echo "herdr-core is not installed"
    else echo "herdr-core is not running (agents hc up)"; fi
}

# The panes opted out of mirrors (`agents hc mirror off`): hc-mirror.off in
# the run dir, a pane id a line. Not with the settings: a pane id names a
# pane of the Herdr server that runs now, and the panes of a restarted Herdr
# are new ones, so a sync drops the id of a pane its snapshot no longer has
# (_agents_hm_off_prune). Changed only under the sync's lock.

# _agents_hm_off_read — REPLY: the opted-out panes, each between newlines
# ("\np1\np2\n", "\n" for none). Read by bash: no fork.
_agents_hm_off_read() {
    local f line out=$'\n'
    f="$AGENTS_RUN_DIR/hc-mirror.off"
    if [[ -r "$f" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ ! "$line" =~ $_AGENTS_HM_PANE_RE || "$out" == *$'\n'"$line"$'\n'* ]] || out+="$line"$'\n'
        done < "$f"
    fi
    REPLY="$out"
}

# _agents_hm_is_off PANE LIST — PANE is in LIST (_agents_hm_off_read's).
_agents_hm_is_off() { [[ "$2" == *$'\n'"$1"$'\n'* ]]; }

# _agents_hm_off_write LIST — hc-mirror.off holds LIST; gone when it is empty.
_agents_hm_off_write() {
    local f l="${1#$'\n'}"
    f="$AGENTS_RUN_DIR/hc-mirror.off"
    if [[ -z "${l//$'\n'/}" ]]; then rm -f "$f"; return 0; fi
    _agents_replace "$f" "${l%$'\n'}"
}

# _agents_hm_off_prune SNAP — drop each opted-out pane that SNAP (Herdr's
# answer, one that parsed) has no more. Nothing without the file, or when
# the snapshot has no list of panes or an empty one.
_agents_hm_off_prune() {
    local ids keep=$'\n' p
    [[ -f "$AGENTS_RUN_DIR/hc-mirror.off" ]] || return 0
    ids="$(_agents_hm_ids_of "$1")" || return 0
    # A Herdr that names no pane at all (starting, restoring) proves nothing.
    [[ -n "$ids" ]] || return 0
    ids=$'\n'"$ids"$'\n'
    _agents_hm_off_read
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        [[ "$ids" != *$'\n'"$p"$'\n'* ]] || keep+="$p"$'\n'
    done <<<"$REPLY"
    [[ "$keep" == "$REPLY" ]] || _agents_hm_off_write "$keep"
}

# When each pane's mirror last started: a file per pane, its name the pane
# id in file-name letters.
_agents_hm_started_dir() { printf '%s\n' "$AGENTS_RUN_DIR/hc-mirror.started"; }
_agents_hm_file_name() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_'; }

# _agents_hm_pane_size PANE W H — "COLS ROWS", the size PANE's own terminal
# has now: its layout place is W by H, and the terminal inside can be a
# column or a row less (a border). Read from the tty of the pane's shell;
# the place itself when that cannot be read or is not near it (a pane an
# earlier attach left at another size).
_agents_hm_pane_size() {
    local pane="$1" w="$2" h="$3" c r
    if _agents_hm_pane_tty_size "$pane"; then
        read -r c r <<<"$REPLY"
        if [[ $c -le $w && $c -ge $((w - 2)) && $r -le $h && $r -ge $((h - 2)) ]]; then
            printf '%s %s\n' "$c" "$r"; return 0
        fi
    fi
    printf '%s %s\n' "$w" "$h"
}

# _agents_hm_pane_tty_size PANE — REPLY "COLS ROWS": the size PANE's own
# terminal has now, read from its shell's tty; false when Herdr does not say
# the shell, or its tty cannot be read.
_agents_hm_pane_tty_size() {
    local pid
    pid="$(_agents_timeout "$_AGENTS_HC_HERDR_WAIT" _agents_hl_herdr pane process-info --pane "$1" 2>/dev/null \
        | jq -r '.result.process_info.shell_pid // empty' 2>/dev/null)"
    _agents_hm_pid_tty_size "$pid"
}

# _agents_hm_pid_tty_size PID — REPLY "COLS ROWS" of PID's terminal, and
# _AGENTS_HM_PTTY that terminal (/dev/…); false when PID has none, or its
# size cannot be read.
_agents_hm_pid_tty_size() {
    local tty r c
    REPLY="" _AGENTS_HM_PTTY=""
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    tty="$(ps -o tty= -p "$1" 2>/dev/null | tr -d ' ')"
    [[ "$tty" =~ ^[A-Za-z0-9/]+$ && -c "/dev/$tty" ]] || return 1
    read -r r c <<<"$(stty size < "/dev/$tty" 2>/dev/null)"
    [[ "$r" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]] || return 1
    REPLY="$c $r" _AGENTS_HM_PTTY="/dev/$tty"
}

# _agents_hm_name TITLE CWD — a mirror's name in herdr-core: the session's
# task title when it has one ("Fix login redirect" is fix-login-redirect),
# so the phone tells two sessions of one project apart; else its directory's
# name. hc.sh's _agents_hc_name makes either free (NAME-2 …) and legal. The
# name is given once, when the mirror starts: herdr-core renames nothing. A
# title that comes or changes later is the terminal's own (_agents_hm_title).
_agents_hm_name() {
    local slug
    slug="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' '-' | tr -s '-' | cut -c1-30)"
    slug="${slug#-}"; slug="${slug%-}"
    if [[ -n "$slug" ]]; then _agents_hc_name "/$slug"; else _agents_hc_name "$2"; fi
}

# _agents_hm_title TITLE — the mirror's terminal takes the session's task
# title (OSC 2, which herdr-core keeps as the terminal's title), in one
# write. Nothing for none: the last one stands. No control character goes out.
_agents_hm_title() {
    local t
    t="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | cut -c1-80)"
    [[ -n "$t" ]] || return 0
    # shellcheck disable=SC1003  # ESC \ ends the sequence
    printf '\033]2;%s\033\\' "$t"
}

# _agents_hm_start PANE W H CWD [TITLE] — a mirror of PANE in herdr-core, named
# after TITLE or its directory, at the size the pane's terminal has (W by H
# is its place in the layout). It runs this same agents, by its path, with
# the Herdr it was asked from: the core's own environment may know neither.
# 124 when the core did not answer.
_agents_hm_start() {
    local pane="$1" w="$2" h="$3" cwd="$4" title="${5:-}" name herdr cols rows
    read -r cols rows <<<"$(_agents_hm_pane_size "$pane" "$w" "$h")"
    name="$(_agents_hm_name "$title" "$cwd")"
    herdr="${HERDR_BIN_PATH:-}"
    [[ -n "$herdr" && -x "$herdr" ]] || herdr="$(command -v herdr 2>/dev/null)" || return 1
    # Absolute, so it cannot read as an option either.
    [[ "$cwd" == /* && -d "$cwd" ]] || cwd="$HOME"
    _agents_timeout "$_AGENTS_HC_WAIT" _agents_hm_core run --bg --json --no-parent --no-notify --rm ${name:+--name "$name"} \
        --label "$_AGENTS_HM_LABEL=$pane" --cwd "$cwd" -- \
        /usr/bin/env HERDR_BIN_PATH="$herdr" \
        HERDR_SOCKET_PATH="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" \
        bash "$AGENTS_PATH" hc _mirror "$pane" "$cols" "$rows" "$w" "$h" >/dev/null 2>&1
}

# agents_hc_mirror_sync [-q] [-n] — one mirror for each agent pane, none for
# anything else. Quietly nothing when it is off or no core runs, or when
# Herdr or the core did not answer. Once the core has not answered one call,
# it is not asked again this time.
#
# One sync at a time, the label sync's way (herdrlabel.sh): a sync that
# finds another running leaves a mark (hc-mirror.dirty) and returns, and the
# running one goes again a second later, so a burst of Herdr events costs one
# more pass, not one each. -q (the event hooks, `agents hc up -q`) tries the
# lock once; a sync run by hand waits up to 2 s for it. `off` and `end` hold
# the lock too: a mark left while they did is taken up when they let go.
agents_hc_mirror_sync() { _agents_hm_sync "" "$@"; }

# _agents_hm_sync SNAP [-q] [-n] — agents_hc_mirror_sync, where SNAP is a
# `herdr api snapshot` answer the caller already has (`agents herdr sync`'s,
# taken a moment ago): the first pass reads it instead of asking Herdr
# again; "" asks. A pass after a mark asks again.
_agents_hm_sync() {
    local snap="$1" quiet=false dry=false a lock="$AGENTS_RUN_DIR/hc-mirror.lock" dirty="$AGENTS_RUN_DIR/hc-mirror.dirty"
    local tries=10 round=0 pass
    shift
    for a in "$@"; do
        case "$a" in
            -q|--quiet)   quiet=true tries=1 ;;
            -n|--dry-run) dry=true ;;
            *)            echo "usage: agents hc mirror sync [-n] [-q]" >&2; return 2 ;;
        esac
    done
    if ! _agents_hm_ready; then
        # Off, with mirrors an earlier sync started: they go, once.
        if [[ "$dry" == false && -d "$AGENTS_RUN_DIR/hc-mirror.started" ]] && ! _agents_hm_on; then
            agents_hc_mirror_end -q || true
        fi
        [[ "$quiet" == true ]] || echo "agents hc mirror: $(_agents_hm_why_not)"
        return 0
    fi
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null
    while [[ $round -lt 2 ]]; do
        round=$((round + 1)) pass=0
        if ! _agents_lock "$lock" "$tries" 0.2; then
            : > "$dirty" 2>/dev/null
            # The running sync may have let go between that try and the mark,
            # which nobody would read then: with the mark down, look once more.
            if ! _agents_lock "$lock"; then
                [[ "$quiet" == true ]] || echo "agents hc mirror: another sync is running; it goes again for this one"
                return 0
            fi
        fi
        while [[ $pass -lt 5 ]]; do
            pass=$((pass + 1))
            rm -f "$dirty"
            _agents_hm_pass "$quiet" "$dry" "$snap"
            snap=""
            [[ -e "$dirty" && "$dry" == false ]] || break
            sleep "$_AGENTS_HM_PAUSE" 2>/dev/null || true
        done
        _agents_unlock "$lock"
        # A sync that came in between the last look and the unlock.
        [[ -e "$dirty" ]] || break
    done
    return 0
}

# _agents_hm_let_go — let go of the sync's lock (`off`, `end`), then take up
# a sync that came in meanwhile and found it held.
_agents_hm_let_go() {
    _agents_unlock "$AGENTS_RUN_DIR/hc-mirror.lock"
    [[ ! -e "$AGENTS_RUN_DIR/hc-mirror.dirty" ]] || _agents_hm_sync "" -q
}

# _agents_hm_pass QUIET DRY SNAP — one pass of the sync, under its lock.
_agents_hm_pass() {
    local quiet="$1" dry="$2" snap="$3" want have started=0 ended=0 waiting=0
    local pane cols rows agent state cwd title addr name seen="" panes dir wdir names f now age rc hung=false off nooff=0
    if { [[ -z "$snap" ]] && ! snap="$(_agents_hm_snap)"; } || ! want="$(_agents_hm_want_of "$snap")"; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: Herdr did not answer; nothing changed" >&2
        return 0
    fi
    [[ "$dry" == true ]] || _agents_hm_off_prune "$snap"
    _agents_hm_off_read; off="$REPLY"
    if ! have="$(_agents_hm_have)"; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: herdr-core did not answer; nothing changed" >&2
        return 0
    fi
    # Up to 3.25.0 a follower's file had a random name (hc-mirror-wait.XXXXXX),
    # and one killed outright left it behind: those go once, when the folder
    # for the new ones is made, before this pass starts a mirror whose
    # follower would make it.
    wdir="$(_agents_hm_wait_dir)"
    if [[ "$dry" == false && ! -d "$wdir" ]]; then
        rm -f "$AGENTS_RUN_DIR"/hc-mirror-wait.* 2>/dev/null
        mkdir -p "$wdir" 2>/dev/null
    fi
    panes="$(printf '%s\n' "$want" | cut -d$'\x1f' -f1)"
    while IFS=$'\x1f' read -r addr pane name; do
        [[ -n "$addr" && "$hung" == false ]] || continue
        # Still an agent pane, not one that went on to a core-hosted agent or
        # was opted out, and its first mirror: a second one (a sync that
        # raced) goes.
        if printf '%s\n' "$panes" | grep -qxF -- "$pane" && ! _agents_hc_pane_marked "$pane" \
            && ! _agents_hm_is_off "$pane" "$off" && ! printf '%s\n' "$seen" | grep -qxF -- "$pane"; then
            seen="$seen$pane"$'\n'
            continue
        fi
        ended=$((ended + 1))
        [[ "$quiet" == true ]] || echo "end the mirror of $pane (${name:-$addr})"
        [[ "$dry" == false && "$addr" != -* ]] || continue
        rc=0; _agents_timeout "$_AGENTS_HC_WAIT" _agents_hm_core kill "$addr" >/dev/null 2>&1 || rc=$?
        [[ $rc -ne 124 ]] || hung=true
    done <<<"$have"
    dir="$(_agents_hm_started_dir)"
    _agents_now now
    while IFS=$'\x1f' read -r pane cols rows agent state cwd title; do
        [[ "$hung" == false ]] || break
        [[ "$pane" =~ $_AGENTS_HM_PANE_RE && "$cols" =~ ^[0-9]+$ && "$rows" =~ ^[0-9]+$ ]] || continue
        ! printf '%s\n' "$have" | cut -d$'\x1f' -f2 | grep -qxF -- "$pane" || continue
        ! _agents_hc_pane_marked "$pane" || continue
        if _agents_hm_is_off "$pane" "$off"; then nooff=$((nooff + 1)); continue; fi
        f="$dir/$(_agents_hm_file_name "$pane")"
        _agents_stamp_age age "$f" "$now"
        if [[ $age -ge 0 && $age -lt $_AGENTS_HM_AGAIN ]]; then
            waiting=$((waiting + 1))
            [[ "$quiet" == true ]] || echo "mirror $pane again in $((_AGENTS_HM_AGAIN - age)) s (its last mirror started ${age} s ago)"
            continue
        fi
        started=$((started + 1))
        [[ "$quiet" == true ]] || echo "mirror $pane ($agent, ${cwd##*/})"
        [[ "$dry" == false ]] || continue
        mkdir -p "$dir" 2>/dev/null && _agents_replace "$f" "$now" || true
        rc=0; _agents_hm_start "$pane" "$cols" "$rows" "$cwd" "$title" || rc=$?
        [[ $rc -eq 0 ]] || { [[ "$quiet" == true ]] || echo "  could not start it" >&2; }
        [[ $rc -ne 124 ]] || hung=true
    done <<<"$want"
    # The start times and the followers' files of panes that have no agent
    # any more.
    if [[ "$dry" == false ]]; then
        names=$'\n'"$(printf '%s\n' "$panes" | LC_ALL=C tr -c 'A-Za-z0-9._\n-' '_')"$'\n'
        for f in "$dir"/* "$wdir"/*; do
            [[ -e "$f" && "$names" != *$'\n'"${f##*/}"$'\n'* ]] || continue
            rm -f "$f"
        done
    fi
    if [[ "$quiet" == false && $((started + ended + waiting)) -eq 0 ]]; then
        if [[ $nooff -eq 0 ]]; then echo "agents hc mirror: every agent pane has its mirror"
        else echo "agents hc mirror: every agent pane has its mirror, but the $nooff opted out (agents hc mirror status)"; fi
    fi
    return 0
}

agents_hc_mirror_status() {
    local want have pane cols rows agent state cwd title m off
    _agents_hm_off_read; off="$REPLY"
    if ! _agents_hm_ready; then
        echo "agents hc mirror: $(_agents_hm_why_not)"
        _agents_hm_off_say "$off"
        return 0
    fi
    want="$(_agents_hm_want)" || { echo "agents hc mirror: Herdr did not answer" >&2; return 1; }
    have="$(_agents_hm_have)" || { echo "agents hc mirror: herdr-core did not answer" >&2; return 1; }
    if [[ -z "$want" ]]; then
        echo "no agent panes in this machine's Herdr"
    fi
    while IFS=$'\x1f' read -r pane cols rows agent state cwd title; do
        [[ -n "$pane" ]] || continue
        m="$(printf '%s\n' "$have" | awk -F$'\x1f' -v p="$pane" '$2 == p { print ($3 != "" ? $3 : $1); exit }')"
        if _agents_hc_pane_marked "$pane"; then m="in herdr-core itself (agents hc run)"
        elif _agents_hm_is_off "$pane" "$off"; then
            if [[ -n "$m" ]]; then m="opted out; its mirror $m ends at the next sync"
            else m="opted out (agents hc mirror on $pane)"; fi
        elif [[ -n "$m" ]]; then m="mirrored as $m$(_agents_hm_size_note "$pane" "$cols" "$rows")"
        else m="not mirrored yet (agents hc mirror sync)"; fi
        printf '%-10s %-8s %-8s %-24s %s\n' "$pane" "$agent" "$state" "${cwd##*/}" "$m"
    done <<<"$want"
    _agents_hm_off_say "$off"
}

# _agents_hm_size_note PANE W H — "; phone-sized: 43x31 of 139x48 (agents hc
# mirror fit PANE)" when PANE's own terminal is not the size of its place W
# by H (a border of up to 2 aside); nothing when it is, or cannot be read.
_agents_hm_size_note() {
    local c r
    _agents_hm_pane_tty_size "$1" || return 0
    read -r c r <<<"$REPLY"
    [[ $c -gt $2 || $c -lt $(($2 - 2)) || $r -gt $3 || $r -lt $(($3 - 2)) ]] || return 0
    if [[ $c -lt $2 || $r -lt $3 ]]; then printf '; phone-sized: %sx%s of %sx%s' "$c" "$r" "$2" "$3"
    else printf '; at %sx%s, not %sx%s' "$c" "$r" "$2" "$3"; fi
    printf ' (agents hc mirror fit %s)' "$1"
}

# _agents_hm_off_say LIST — one line naming the opted-out panes; nothing for none.
_agents_hm_off_say() {
    local l="${1#$'\n'}"
    l="${l%$'\n'}"
    [[ -n "$l" ]] || return 0
    echo "opted out of mirrors: ${l//$'\n'/, } (agents hc mirror on PANE mirrors one again)"
}

# _agents_hm_pane_arg PANE WORD — REPLY: PANE, else this pane (HERDR_PANE_ID);
# 2 with a line when there is none, or it is no pane id.
_agents_hm_pane_arg() {
    REPLY="${1:-${HERDR_PANE_ID:-}}"
    if [[ -z "$REPLY" ]]; then
        echo "usage: agents hc mirror $2 [PANE] (in a Herdr pane: that pane; else an id agents hc mirror lists)" >&2
        return 2
    fi
    [[ "$REPLY" =~ $_AGENTS_HM_PANE_RE ]] || { echo "agents hc mirror: not a pane id: $REPLY" >&2; return 2; }
}

# agents_hc_mirror_off [PANE] — no mirror for PANE (default: this pane) from
# now on: it is recorded (whether mirrors are on or not), and its mirror is
# ended when one runs. The core is asked only when it runs; when it does not
# answer, the next sync ends the mirror. The agent stays in its pane.
agents_hc_mirror_off() {
    local pane lock="$AGENTS_RUN_DIR/hc-mirror.lock" have addr p name rc said=""
    [[ $# -le 1 ]] || { echo "usage: agents hc mirror off [PANE]" >&2; return 2; }
    _agents_hm_pane_arg "${1:-}" off || return
    pane="$REPLY"
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null
    _agents_lock "$lock" 10 0.2 || { echo "agents hc mirror: a sync holds the lock; nothing changed, try again" >&2; return 1; }
    _agents_hm_off_read
    if ! _agents_hm_is_off "$pane" "$REPLY" && ! _agents_hm_off_write "$REPLY$pane"$'\n'; then
        _agents_unlock "$lock"
        echo "agents hc mirror: could not write $AGENTS_RUN_DIR/hc-mirror.off; nothing changed" >&2
        return 1
    fi
    if command -v jq >/dev/null 2>&1 && _agents_hc_bin && _agents_hc_running; then
        if have="$(_agents_hm_have)"; then
            while IFS=$'\x1f' read -r addr p name; do
                [[ "$p" == "$pane" && -n "$addr" && "$addr" != -* ]] || continue
                rc=0; _agents_timeout "$_AGENTS_HC_WAIT" _agents_hm_core kill "$addr" >/dev/null 2>&1 || rc=$?
                if [[ $rc -eq 124 ]]; then said="herdr-core did not answer; the next sync ends its mirror"; break; fi
                [[ $rc -ne 0 ]] || echo "ended the mirror of $pane (${name:-$addr})"
            done <<<"$have"
        else
            said="herdr-core did not answer; the next sync ends its mirror"
        fi
    fi
    _agents_hm_let_go
    echo "$pane: no mirror from now on (agents hc mirror on $pane undoes it)${said:+; $said}"
}

# agents_hc_mirror_on [PANE] — PANE (default: this pane) is mirrored again:
# taken off the list, then a sync when mirrors are on and a core runs.
agents_hc_mirror_on() {
    local pane lock="$AGENTS_RUN_DIR/hc-mirror.lock"
    [[ $# -le 1 ]] || { echo "usage: agents hc mirror on [PANE]" >&2; return 2; }
    _agents_hm_pane_arg "${1:-}" on || return
    pane="$REPLY"
    _agents_hm_off_read
    if ! _agents_hm_is_off "$pane" "$REPLY"; then echo "$pane: not opted out; nothing changed"; return 0; fi
    _agents_lock "$lock" 10 0.2 || { echo "agents hc mirror: a sync holds the lock; nothing changed, try again" >&2; return 1; }
    _agents_hm_off_read
    if ! _agents_hm_off_write "${REPLY//$'\n'"$pane"$'\n'/$'\n'}"; then
        _agents_unlock "$lock"
        echo "agents hc mirror: could not write $AGENTS_RUN_DIR/hc-mirror.off; nothing changed" >&2
        return 1
    fi
    _agents_unlock "$lock"
    if _agents_hm_ready; then
        echo "$pane: mirrored again"
        agents_hc_mirror_sync
    else
        echo "$pane: mirrored again once mirrors run (agents hc mirror: $(_agents_hm_why_not))"
    fi
}

# agents_hc_mirror_fit [-q] [PANE] — a mirrored pane takes its own size back
# from a phone that still shows it: the mirror's terminal is set to the pane's
# place in the layout less its border (_agents_hm_set_size, as the follower
# does), and the attach passes that on to the pane. PANE defaults to the pane
# Herdr has focused. A pane with no mirror, or at its size already, is left
# alone. The phone keeps its own size: it sees the top left of the pane until
# it sets a size again (it opens the session again, or turns), and the pane
# then has the phone's size again until the next focus here.
#
# -q is the tuidev.link plugin's pane.focused hook: nothing unless
# AGENTS_HC_MIRROR_FIT is 1 (the default) and a sync started the focused
# pane's mirror (its start time), and nothing said. Fits coalesce as syncs do
# (hc-mirror-fit.lock and .dirty): one that finds another running leaves a
# mark and returns, and the running one goes again for the pane focused by
# then, so a burst of focus events is one fit more, not one each. Never a
# loop with the follower: what a fit sets is not the core's own size, which
# is the only size the follower acts on, and a size a terminal has already is
# never set again.
agents_hc_mirror_fit() {
    local quiet=false pane="" a tries=10 round=0 pass lock="$AGENTS_RUN_DIR/hc-mirror-fit.lock" dirty="$AGENTS_RUN_DIR/hc-mirror-fit.dirty"
    for a in "$@"; do
        case "$a" in
            -q|--quiet) quiet=true tries=1 ;;
            -*)         echo "usage: agents hc mirror fit [-q] [PANE]" >&2; return 2 ;;
            *)          [[ -z "$pane" ]] || { echo "usage: agents hc mirror fit [-q] [PANE]" >&2; return 2; }
                        pane="$a" ;;
        esac
    done
    [[ -z "$pane" || "$pane" =~ $_AGENTS_HM_PANE_RE ]] || { echo "agents hc mirror: not a pane id: $pane" >&2; return 2; }
    [[ "$quiet" == false || "${AGENTS_HC_MIRROR_FIT:-1}" == 1 ]] || return 0
    if ! _agents_hm_ready; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: $(_agents_hm_why_not)"
        return 0
    fi
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null
    while [[ $round -lt 2 ]]; do
        round=$((round + 1)) pass=0
        if ! _agents_lock "$lock" "$tries" 0.2; then
            : > "$dirty" 2>/dev/null
            # The running fit may have let go between that try and the mark.
            if ! _agents_lock "$lock"; then
                [[ "$quiet" == true ]] || echo "agents hc mirror: another fit is running; it goes again for this one"
                return 0
            fi
        fi
        while [[ $pass -lt 5 ]]; do
            pass=$((pass + 1))
            rm -f "$dirty"
            _agents_hm_fit_pass "$quiet" "$pane" || true
            [[ -e "$dirty" ]] || break
        done
        _agents_unlock "$lock"
        # A fit that came in between the last look and the unlock.
        [[ -e "$dirty" ]] || break
    done
    return 0
}

# _agents_hm_fit_pass QUIET PANE — one fit, under its lock: PANE, else the
# pane Herdr has focused now.
_agents_hm_fit_pass() {
    local quiet="$1" pane="$2" snap rect list row pid w h c r dc dr rc=0
    if ! snap="$(_agents_hm_snap)"; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: Herdr did not answer; nothing changed" >&2
        return 1
    fi
    if [[ -z "$pane" ]]; then
        pane="$(printf '%s' "$snap" | jq -r '.result.snapshot.focused_pane_id // empty | tostring' 2>/dev/null)"
        if [[ ! "$pane" =~ $_AGENTS_HM_PANE_RE ]]; then
            [[ "$quiet" == true ]] || echo "agents hc mirror: Herdr has no pane focused; name one (agents hc mirror fit PANE)" >&2
            return 1
        fi
    fi
    # The hook's way: only a pane a sync gave a mirror is worth asking the core about.
    [[ "$quiet" == false || -e "$(_agents_hm_started_dir)/$(_agents_hm_file_name "$pane")" ]] || return 0
    if ! _agents_hm_rect "$pane" "$snap"; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: $pane is in no layout Herdr has; nothing changed" >&2
        return 1
    fi
    rect="$REPLY"
    if ! list="$(_agents_hm_list)"; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: herdr-core did not answer; nothing changed" >&2
        return 1
    fi
    row="$(printf '%s\n' "$list" | jq -r --arg l "$_AGENTS_HM_LABEL" --arg p "$pane" "$_AGENTS_HM_FIT_JQ" 2>/dev/null | head -n 1)"
    read -r pid c r w h <<<"$row"
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: $pane has no mirror; nothing to fit"
        return 0
    fi
    if ! _agents_hm_pid_tty_size "$pid"; then
        [[ "$quiet" == true ]] || echo "agents hc mirror: the terminal of $pane's mirror cannot be read; nothing changed" >&2
        return 1
    fi
    _agents_hm_border "$c" "$r" "$w" "$h"
    read -r dc dr <<<"$REPLY"
    _agents_hm_set_size "$_AGENTS_HM_PTTY" "$rect" "$dc" "$dr" || rc=$?
    [[ "$quiet" == false ]] || return 0
    read -r w h <<<"$rect"
    case $rc in
        0) echo "$pane: $((w - dc))x$((h - dr)), its place in the layout" ;;
        1) echo "$pane: at its place's size already ($((w - dc))x$((h - dr)))" ;;
        *) echo "agents hc mirror: $pane's place is ${w}x${h}: too small to set, or its mirror's terminal did not take it" >&2; return 1 ;;
    esac
}

# A pane's live mirror in terminal.list -> "PID COLS ROWS W H": the attach's
# pid (the mirror's terminal is its tty), and the sizes `_mirror` was started
# with (its argv: _mirror PANE COLS ROWS [W H]), for the pane's border.
# shellcheck disable=SC2016  # jq's $names
_AGENTS_HM_FIT_JQ='
.result.terminals[]? | select(.state == "live") | select((.labels // {})[$l] == $p) | select(.pid | type == "number")
| (.argv // []) as $a | ([range(0; $a | length) | select($a[.] == "_mirror")][0]) as $i
| [(.pid // ""), (if $i == null then [] else $a[$i + 2:$i + 6] end | .[])] | map(tostring | gsub("[^0-9]"; "")) | join(" ")'

# Herdr's word for a state -> the OSC 7501 report herdr-core stores (printed
# in one write, so it cannot land inside one of the attach's own sequences
# more than a byte-level race allows). unknown reports nothing: the last
# state stands. The agent's name in the spec's alphabet for app, else agent.
_agents_hm_report() {
    local state="$1" agent="$2"
    case "$state" in idle|working|blocked|done) ;; *) return 0 ;; esac
    [[ "$agent" =~ ^[A-Za-z0-9_.+-]{1,32}$ ]] || agent=agent
    # shellcheck disable=SC1003  # ESC \ ends the sequence
    printf '\033]7501;state=%s:app=%s\033\\' "$state" "$agent"
}

# _agents_hm_follow PANE [OWNER] — report PANE's state now, then each time it
# changes, for as long as the process OWNER (the mirror's attach) runs: until
# OWNER is gone, the terminal takes no more reports, or a TERM or HUP (the
# terminal's hangup). When Herdr does not answer (the pane's state not given
# in time, no agent in the pane for now, a `herdr agent wait` that failed:
# Herdr restarting, its socket gone, the run dir removed), it asks again
# after a pause, 2 s doubling to 60 s, from the pane's state: the phone's
# status and the size kept for the pane (_agents_hm_resized) last as long as
# the attach. Without OWNER (tests) the first of these ends it.
# The wait, and each pause, is a background job the trap ends with it (a
# signal is taken only between commands, never inside a $( ) the shell waits
# for): herdr itself, not a function around it, so its pid is the one to
# end. Its answer goes through the pane's file in hc-mirror.wait/, one name a
# pane, so a follower killed outright (SIGKILL, a reboot) leaves no more than
# that one, which the pane's next follower reuses and the sync removes with
# the pane's start time. Run only as its own process (`&`, a pipeline): the
# trap is that process's, and a ( ) body would put it in a child the
# caller's kill never reaches.
_agents_hm_follow() {
    local pane="$1" owner="${2:-}" out cur="" agent="" s args wp back=0 again=false h="${HERDR_BIN_PATH:-}"
    [[ -n "$h" && -x "$h" ]] || h="$(command -v herdr 2>/dev/null)" || return 0
    _AGENTS_HM_OUT="$(_agents_hm_wait_dir)/$(_agents_hm_file_name "$pane")"
    trap 'kill $(jobs -p) 2>/dev/null; wait; rm -f "$_AGENTS_HM_OUT"; exit 0' HUP TERM
    [[ -z "$_AGENTS_HM_BASE" ]] || trap '_agents_hm_resized "$pane"' WINCH
    while :; do
        if [[ "$again" == true ]]; then
            again=false
            if [[ -z "$owner" ]] || ! kill -0 "$owner" 2>/dev/null; then break; fi
            _agents_hm_pause "$back"
            kill -0 "$owner" 2>/dev/null || break
        fi
        if [[ -z "$agent" ]]; then
            if ! out="$(_agents_timeout "$_AGENTS_HC_HERDR_WAIT" _agents_hl_herdr pane get "$pane" 2>/dev/null)"; then
                _agents_hm_later; continue
            fi
            cur="$(printf '%s' "$out" | jq -r '.result.pane.agent_status // empty' 2>/dev/null)"
            agent="$(printf '%s' "$out" | jq -r '.result.pane.agent // empty' 2>/dev/null)"
            [[ -n "$agent" ]] || { _agents_hm_later; continue; }
            _agents_hm_tell "$cur" "$agent" "$(printf '%s' "$out" | jq -r '.result.pane.terminal_title_stripped // empty' 2>/dev/null)" || break
            mkdir -p "${_AGENTS_HM_OUT%/*}" 2>/dev/null
        fi
        [[ -z "$owner" ]] || kill -0 "$owner" 2>/dev/null || break
        args=()
        for s in idle working blocked "done" unknown; do [[ "$s" == "$cur" ]] || args+=(--until "$s"); done
        "$h" agent wait "$pane" "${args[@]}" > "$_AGENTS_HM_OUT" 2>/dev/null &
        wp=$!
        # A resize (WINCH) ends a wait early; the job is waited for again.
        while kill -0 "$wp" 2>/dev/null; do wait "$wp" 2>/dev/null; done
        # Asked again from the pane's state: what changed meanwhile is reported.
        wait "$wp" 2>/dev/null || { agent=""; _agents_hm_later; continue; }
        back=0
        s="$(jq -r '.result.agent.agent_status // empty' "$_AGENTS_HM_OUT" 2>/dev/null)"
        [[ -n "$s" && "$s" != "$cur" ]] || { sleep 1; continue; }
        cur="$s"
        _agents_hm_tell "$cur" "$agent" "$(jq -r '.result.agent.terminal_title_stripped // empty' "$_AGENTS_HM_OUT" 2>/dev/null)" || break
    done
    rm -f "$_AGENTS_HM_OUT"
}

# _agents_hm_later — a pause before the follower's next try: _AGENTS_HM_RETRY
# seconds after a wait that worked, else twice the last, up to
# _AGENTS_HM_RETRY_MAX. Sets the caller's `back` and `again` (bash's dynamic
# scope; no fork).
_agents_hm_later() {
    again=true back=$((back * 2))
    [[ $back -ge $_AGENTS_HM_RETRY ]] || back=$_AGENTS_HM_RETRY
    [[ $back -le $_AGENTS_HM_RETRY_MAX ]] || back=$_AGENTS_HM_RETRY_MAX
}

# _agents_hm_pause SECONDS — the follower's pause: a job, like its wait, so
# the hangup's trap runs at once and ends it too (a sleep in the foreground
# would hold the trap until it ended); waited for again after a WINCH.
_agents_hm_pause() {
    local sp
    sleep "$1" &
    sp=$!
    while kill -0 "$sp" 2>/dev/null; do wait "$sp" 2>/dev/null; done
    return 0
}

# hc-mirror.wait/: each pane's follower's file, named as its start time is.
_agents_hm_wait_dir() { printf '%s\n' "$AGENTS_RUN_DIR/hc-mirror.wait"; }

# _agents_hm_tell STATE AGENT TITLE — the report and the title; false when
# the terminal did not take them (it is gone).
_agents_hm_tell() {
    _agents_hm_report "$1" "$2" 2>/dev/null && _agents_hm_title "$3" 2>/dev/null
}

# The size a pane gets back when the phone stops looking. A viewer of the
# mirror (the phone) sets the mirror terminal's size, the attach passes it on
# and the pane takes it. When the last viewer leaves, herdr-core gives the
# terminal its own size again (200x120 unless its config says otherwise), not
# the one the mirror set, and the pane would stay at that. The follower gets a
# WINCH for every change: a terminal back at the core's size (_AGENTS_HM_BASE,
# read before the mirror set its own) has no viewer, so it is set to the
# pane's size again. That is the pane's place in the layout as it is now,
# less what the pane's terminal was smaller by when the mirror started
# (_AGENTS_HM_DC, _AGENTS_HM_DR); the size at the start when Herdr does not
# answer. A size that is neither is a viewer's: left alone here (a focus at
# the desk takes it back: agents_hc_mirror_fit).
_AGENTS_HM_BASE="" _AGENTS_HM_COLS="" _AGENTS_HM_ROWS="" _AGENTS_HM_DC=0 _AGENTS_HM_DR=0
_AGENTS_HM_TTY=/dev/tty
_agents_hm_resized() {
    local pane="$1" now
    now="$(stty size < "$_AGENTS_HM_TTY" 2>/dev/null)" || return 0
    [[ -n "$_AGENTS_HM_BASE" && "$now" == "$_AGENTS_HM_BASE" && "$now" != "$_AGENTS_HM_ROWS $_AGENTS_HM_COLS" ]] || return 0
    _agents_hm_rect "$pane" || REPLY=""
    _agents_hm_set_size "$_AGENTS_HM_TTY" "$REPLY" "$_AGENTS_HM_DC" "$_AGENTS_HM_DR" "$_AGENTS_HM_COLS $_AGENTS_HM_ROWS" || true
    return 0
}

# The one sizing both the follower (above) and a fit (below) use.
#
# _agents_hm_rect PANE [SNAP] — REPLY "W H": PANE's place in its tab's
# layout, from SNAP (a `herdr api snapshot` answer) or a snapshot asked for
# now; false when Herdr did not answer or has no place for PANE.
_agents_hm_rect() {
    local snap="${2:-}" w h
    [[ -n "$snap" ]] || snap="$(_agents_hm_snap)" || { REPLY=""; return 1; }
    read -r w h <<<"$(printf '%s' "$snap" \
        | jq -r --arg p "$1" '[.result.snapshot.layouts[]?.panes[]? | select(.pane_id == $p) | .rect][0] | "\(.width) \(.height)"' 2>/dev/null)"
    REPLY=""
    [[ "$w" =~ ^[0-9]{1,4}$ && "$h" =~ ^[0-9]{1,4}$ ]] || return 1
    REPLY="$((10#$w)) $((10#$h))"
}

# _agents_hm_border COLS ROWS [W H] — REPLY "DC DR": how much a pane's own
# terminal (COLS by ROWS) is smaller than its place (W by H): 0, 1 or 2 each
# (a border); 0 for anything else, or with no place given.
_agents_hm_border() {
    local dc=0 dr=0
    if [[ "$1" =~ ^[0-9]{1,4}$ && "$2" =~ ^[0-9]{1,4}$ && "${3:-}" =~ ^[0-9]{1,4}$ && "${4:-}" =~ ^[0-9]{1,4}$ ]]; then
        dc=$((10#$3 - 10#$1)) dr=$((10#$4 - 10#$2))
        [[ $dc -ge 0 && $dc -le 2 ]] || dc=0
        [[ $dr -ge 0 && $dr -le 2 ]] || dr=0
    fi
    REPLY="$dc $dr"
}

# _agents_hm_set_size TTY "W H" DC DR ["COLS ROWS"] — TTY (a mirror's
# terminal) at the pane's place W by H less DC by DR; at COLS by ROWS when no
# place is given or what is left of it is less than 20x5, and nothing with
# neither. Nothing either when TTY has that size already: the follower gets a
# WINCH for every change, so a size set for nothing would wake it for nothing.
# 0 when it set the size, 1 when it had it, 2 when there was none to set or
# TTY did not take it.
_agents_hm_set_size() {
    local tty="$1" w h cols rows now
    read -r w h <<<"$2"
    read -r cols rows <<<"${5:-}"
    if [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && $((w - $3)) -ge 20 && $((h - $4)) -ge 5 ]]; then
        cols=$((w - $3)) rows=$((h - $4))
    fi
    [[ "$cols" =~ ^[0-9]+$ && "$rows" =~ ^[0-9]+$ ]] || return 2
    now="$(stty size < "$tty" 2>/dev/null)"
    [[ "$now" != "$rows $cols" ]] || return 1
    stty cols "$cols" rows "$rows" < "$tty" 2>/dev/null || return 2
}

# _agents_hm_size COLS ROWS — the terminal's size; a tty that cannot take it
# is not attached (the attach would give the pane the core's 200x120). With
# no tty there is nothing to size.
_agents_hm_tty() { [[ -t 0 ]]; }
_agents_hm_size() {
    _agents_hm_tty || return 0
    stty cols "$1" rows "$2" 2>/dev/null
}

# agents_hc_mirror_run PANE COLS ROWS [W H] — what a mirror's core terminal
# runs: COLS by ROWS is the pane's terminal, W by H its place in the layout
# (the same when not given). The size is kept to one a pane can have (a
# sliver of a pane would otherwise leave the core's default in place).
#
# The attach takes this process's place (exec), so a mirror is three
# processes, not four: the attach, the follower and the follower's wait.
# Nothing is left to end the follower by hand, so it ends by itself: the
# terminal's hangup reaches it (it stays in this process group, the
# terminal's foreground one, which is also how it gets each WINCH), it looks
# for the attach (this pid, which the exec keeps) before each wait and around
# each pause, and a report the terminal does not take ends it. Herdr not
# answering does not: it asks again while the attach runs. Does not return once it
# attaches; the attach's exit status is the mirror's.
agents_hc_mirror_run() {
    local pane="${1:-}" cols="${2:-}" rows="${3:-}" w="${4:-}" h="${5:-}" herdr="${HERDR_BIN_PATH:-}"
    [[ "$pane" =~ $_AGENTS_HM_PANE_RE && "$cols" =~ ^[0-9]+$ && "$rows" =~ ^[0-9]+$ ]] \
        || { echo "usage: agents hc _mirror PANE COLS ROWS [W H]" >&2; return 2; }
    [[ -z "$w$h" || ( "$w" =~ ^[0-9]{1,4}$ && "$h" =~ ^[0-9]{1,4}$ ) ]] \
        || { echo "usage: agents hc _mirror PANE COLS ROWS [W H]" >&2; return 2; }
    [[ -n "$herdr" && -x "$herdr" ]] || herdr="$(command -v herdr 2>/dev/null)" \
        || { echo "agents hc _mirror: herdr is not installed" >&2; return 127; }
    [[ ${#cols} -le 4 ]] || cols=9999
    [[ ${#rows} -le 4 ]] || rows=9999
    cols=$((10#$cols)) rows=$((10#$rows))
    [[ $cols -ge 20 ]] || cols=20
    [[ $cols -le 1000 ]] || cols=1000
    [[ $rows -ge 5 ]] || rows=5
    [[ $rows -le 500 ]] || rows=500
    # What the core gave this terminal, before it gets the pane's size.
    ! _agents_hm_tty || _AGENTS_HM_BASE="$(stty size 2>/dev/null)"
    _agents_hm_size "$cols" "$rows" || { echo "agents hc _mirror: could not size this terminal to ${cols}x${rows}; not attached" >&2; return 1; }
    _AGENTS_HM_COLS="$cols" _AGENTS_HM_ROWS="$rows"
    _agents_hm_border "$cols" "$rows" "$w" "$h"
    read -r _AGENTS_HM_DC _AGENTS_HM_DR <<<"$REPLY"
    _agents_hm_follow "$pane" "$$" &
    exec "$herdr" agent attach "$pane"
}

# agents_hc_mirror_end [-q] — end every mirror (the core terminals labelled
# as one; nothing else), and forget when each started. The agents stay in
# their panes. Asks only a core that runs; when it does not answer, nothing
# is forgotten, so the next sync that finds mirrors off tries again.
agents_hc_mirror_end() {
    local quiet=false lock="$AGENTS_RUN_DIR/hc-mirror.lock" have addr pane name n=0 rc
    [[ "${1:-}" != -q ]] || quiet=true
    _agents_hc_bin || { [[ "$quiet" == true ]] || echo "agents hc mirror: herdr-core is not installed"; return 0; }
    if ! _agents_hc_running; then
        rm -rf "$(_agents_hm_started_dir)" 2>/dev/null
        [[ "$quiet" == true ]] || echo "agents hc mirror: herdr-core is not running, so no mirror is"
        return 0
    fi
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null
    _agents_lock "$lock" 10 0.2 || return 0
    if ! have="$(_agents_hm_have)"; then
        _agents_unlock "$lock"
        [[ "$quiet" == true ]] || echo "agents hc mirror: herdr-core did not answer; nothing changed" >&2
        return 1
    fi
    while IFS=$'\x1f' read -r addr pane name; do
        [[ -n "$addr" && "$addr" != -* ]] || continue
        rc=0; _agents_timeout "$_AGENTS_HC_WAIT" _agents_hm_core kill "$addr" >/dev/null 2>&1 || rc=$?
        if [[ $rc -eq 124 ]]; then _agents_unlock "$lock"; return 1; fi
        n=$((n + 1))
        [[ "$quiet" == true ]] || echo "ended the mirror of $pane (${name:-$addr})"
    done <<<"$have"
    rm -rf "$(_agents_hm_started_dir)" 2>/dev/null
    _agents_hm_let_go
    [[ "$quiet" == true || $n -gt 0 ]] || echo "agents hc mirror: no mirror runs"
    return 0
}

agents_hc_mirror() {
    local sub="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        status) agents_hc_mirror_status ;;
        sync)   agents_hc_mirror_sync "$@" ;;
        fit)    agents_hc_mirror_fit "$@" ;;
        end)    agents_hc_mirror_end "$@" ;;
        off)    agents_hc_mirror_off "$@" ;;
        on)     agents_hc_mirror_on "$@" ;;
        *)      echo "usage: agents hc mirror [status | sync [-n] [-q] | fit [-q] [PANE] | end | off [PANE] | on [PANE]]" >&2; return 2 ;;
    esac
}
