# shellcheck shell=bash
# lib/agents/link.sh — `agents link`: a click on another machine opens here.
#
# A Herdr plugin runs on the machine that owns the pane, so a click on
# http://localhost:5173 in a pane of another machine is handled over there,
# where no browser is. This is the way back, over one ssh per machine that
# your own machine starts (nothing listens anywhere, and the other machine
# never connects to yours):
#
#   your machine                           the other machine
#   agents link watch                      agents link serve   (run by that ssh)
#     ssh TARGET agents link serve  <----    a fifo, $AGENTS_RUN_DIR/link/l.PID
#     reads a line, acts on it               agents link click URL  (the plugin)
#                                              writes one line to each fifo
#
# The lines are requests, not commands, and your machine decides what each
# may do: open-url takes only a loopback http(s) URL, which becomes a tunnel
# to that machine's localhost on a port this machine picks (47000 up, eight
# a machine) and a browser tab on 127.0.0.1; open-file takes only an absolute
# path with a viewer's extension, fetched under a size cap this machine
# applies. At most five a machine in ten seconds. With nobody attached, a click
# opens on the machine itself, as it would without any of this. The other
# direction, a file of yours dropped onto a session over there, is want-file
# (below): never sent without your yes.
#
# Owns: the fifos, the watcher's per-machine state, `agents link`.
# Uses: config.sh, util.sh, snapshot.sh (_agents_zombie), remote.sh, forward.sh,
#   notify.sh (_agents_notify).
# Public: agents_link, agents_link_click.

_AGENTS_LINK_PROTO="tuidev-link 1"
_AGENTS_LINK_LABEL="dev.tuidev.link"
# What the watcher's ssh runs over there: the installed agents, by its path
# (a non-interactive ssh has no ~/.local/bin on PATH). Where there is none,
# or one too old to know `link`, the machine says so itself: reachable, but
# not set up, is not the same as unreachable.
# shellcheck disable=SC2016  # the remote shell expands $HOME
_AGENTS_LINK_REMOTE='"$HOME/.local/bin/agents" link serve 2>/dev/null || echo "tuidev-link none"'

_agents_link_dir() { printf '%s\n' "$AGENTS_RUN_DIR/link"; }

# _agents_link_is_serve PID — is PID an `agents link serve`? (A fifo outlives
# a reboot, and its pid may name another process by then.) True too when ps
# can't say.
_agents_link_is_serve() {
    local args
    args="$(LC_ALL=C ps -o args= -p "$1" 2>/dev/null)" || return 0
    [[ -z "$args" || "$args" == *"link serve"* ]]
}

# _agents_link_listeners — the fifo of each watcher attached to this machine;
# one whose reader is gone is removed.
_agents_link_listeners() {
    local f pid dir
    dir="$(_agents_link_dir)"
    for f in "$dir"/l.*; do
        [[ -p "$f" ]] || continue
        pid="${f##*.}"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && ! _agents_zombie "$pid" && _agents_link_is_serve "$pid"; then
            printf '%s\n' "$f"
        else
            rm -f "$f"
        fi
    done
    return 0
}

# _agents_link_serve — the far end of a watcher's ssh: say the protocol, then
# pass on each request written to this process's fifo, and a ping every 20 s
# of silence so a watcher that went away is noticed (the write fails) and
# this ends. The fifo is opened read-write: no writer coming or going ends it.
_agents_link_serve() {
    local dir fifo me line
    dir="$(_agents_link_dir)"
    if ! { mkdir -p "$dir" && chmod 700 "$dir"; } 2>/dev/null; then
        echo "agents: can't write $dir" >&2; return 1
    fi
    _agents_link_listeners >/dev/null
    # What a hook that was cut off left behind (its wait is under a minute).
    find "$dir" -maxdepth 1 -type f \( -name 'w.*' -o -name 'r.*' \) -mmin +5 -exec rm -f {} + 2>/dev/null
    _agents_mypid me
    fifo="$dir/l.$me"
    rm -f "$fifo"
    mkfifo -m 600 "$fifo" || return 1
    # shellcheck disable=SC2064  # this fifo, now
    trap "rm -f '$fifo'" EXIT
    trap 'exit 0' PIPE HUP TERM INT
    exec 3<>"$fifo"
    printf '%s\n' "$_AGENTS_LINK_PROTO" || return 0
    while :; do
        if IFS= read -r -t 20 line <&3; then
            printf '%s\n' "$line" || break
        else
            printf 'ping\n' || break
        fi
    done 2>/dev/null
    return 0
}

# _agents_link_file_path URL — the path of a file:// URL (its host dropped,
# %XX decoded) or of a bare absolute path; nothing for anything else.
_agents_link_file_path() {
    local p="$1"
    case "$p" in
        file://*) p="${p#file://}"; p="/${p#*/}" ;;
        /*)       ;;
        *)        return 1 ;;
    esac
    [[ "$p" != *\\* ]] || return 1
    if [[ "$p" == *%* ]]; then
        [[ "$p" =~ ^([^%]|%[0-9A-Fa-f]{2})*$ ]] || return 1
        p="$(printf '%b' "${p//%/\\x}")"
    fi
    [[ "$p" != *[[:cntrl:]]* ]] || return 1
    printf '%s\n' "$p"
}

# agents_link_click URL — what the Herdr plugin runs for a clicked link (and
# `agents ports` for a local port). With a watcher attached, the request goes
# to it: the click opens on the machine you are sitting at. With none, it
# opens here.
# _agents_link_send LINE — write one request line to every attached watcher;
# true when at least one took it.
_agents_link_send() {
    local f n=0
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        ( exec 4<>"$f" && printf '%s\n' "$1" >&4 ) 2>/dev/null && n=$((n + 1))
    done < <(_agents_link_listeners)
    [[ $n -gt 0 ]]
}

agents_link_click() {
    local url="${1:-}" kind arg n=0
    [[ $# -eq 1 && -n "$url" && "$url" != *[[:cntrl:]]* ]] || { echo "usage: agents link click URL|/PATH" >&2; return 2; }
    case "$url" in
        http://*|https://*) kind=open-url arg="$url" ;;
        *) arg="$(_agents_link_file_path "$url")" || { echo "agents: not an http(s) URL or a file: $url" >&2; return 2; }
           kind=open-file ;;
    esac
    # Only what a watcher will act on is sent: a click that would be refused
    # over there must not look as if it went somewhere.
    if [[ "$kind" == open-file ]] || [[ "$arg" =~ $_AGENTS_FORWARD_URL_RE ]]; then
        ! _agents_link_send "$kind"$'\t'"$arg" || n=1
    fi
    if [[ $n -gt 0 ]]; then
        echo "sent to the machine you are attached from"
        return 0
    fi
    if [[ "$kind" == open-file ]]; then
        [[ -f "$arg" ]] || { _agents_link_click_fail "no such file: $arg" "that file is gone: ${arg##*/} (moved or deleted since the link was printed)"; return 1; }
        _agents_open_ext "$arg" || { _agents_link_click_fail "not opened (only: $_AGENTS_OPEN_EXTS): $arg" "not opened: ${arg##*/} is not a kind of file a click opens"; return 1; }
    fi
    _agents_open_local "$arg" || { _agents_link_click_fail "nothing here opens $arg, and no machine is attached (agents link status)" "nothing here opens ${arg##*/}"; return 1; }
}

# _agents_link_click_fail TEXT BANNER — a click that opened nothing says why:
# TEXT on stderr, and where nobody reads that (the Herdr plugin runs it with
# no terminal) BANNER as a notification, or the click does nothing you can see.
_agents_link_click_fail() {
    echo "agents: $1" >&2
    [[ -t 2 ]] || AGENTS_NOTIFY=true _agents_notify "$2" || true
}

# ---- a dropped file: from the machine you sit at, into a session elsewhere --
#
# Drag a file onto a pane of another machine and the terminal pastes its path,
# which exists only on your machine. The session's own prompt hook
# (`agents link drop`, Claude Code's UserPromptSubmit) sees a path that is not
# there and asks the attached watcher for it: "want-file ID PATH". The
# watcher asks YOU, in a dialog naming the machine and the file, and only on
# "Send" copies it into that machine's drop folder and answers; the hook then
# tells the session where the file is. Nothing is ever sent unasked: a
# request is another machine asking for one of your files.

_AGENTS_LINK_DROP_BUDGET=50   # seconds one prompt's hook may wait in all (its timeout is 60)
_AGENTS_LINK_DROP_NEED=35     # seconds a request needs to be worth asking: the dialog's 30, and the copy
_AGENTS_LINK_DROP_MAX=3       # paths asked for from one prompt
_AGENTS_LINK_ID_RE='^[a-z0-9]{6,20}$'
# Where a dragged file is pasted from: a home directory, a temp folder (a
# screenshot's thumbnail is dragged from one) or a mounted volume. What the
# hook asks about; whether a file may be sent is _agents_link_may_send's.
_AGENTS_LINK_DROP_FROM='^/(Users|home|Volumes|tmp|private/tmp|var/folders|private/var/folders)/'

# _agents_link_drop_paths TEXT — the file paths pasted into TEXT, one a line:
# 'single-quoted' or with \-escaped spaces, as a terminal pastes a dropped
# file. Only an absolute path that starts a word (src/tmp/x.json names no
# /tmp/x.json), has an extension, and is from where dragged files come.
_agents_link_drop_paths() {
    local rest=" $1" p q="'" re1 re2 n=0
    rest="${rest//$'\n'/ }"; rest="${rest//$'\t'/ }"
    re1="[[:space:]]$q(/[^$q]+)$q"
    # shellcheck disable=SC1003  # a backslash and a quote in a bracket expression
    re2='[[:space:]](/([^[:space:]\\'"$q"'"]|\\.)+)'
    # The quoted ones first, each taken out of the text, then what is left.
    while [[ $n -lt 20 && "$rest" =~ $re1 ]]; do
        n=$((n + 1)); p="${BASH_REMATCH[1]}"
        rest="${rest%%"${BASH_REMATCH[0]}"*} ${rest#*"${BASH_REMATCH[0]}"}"
        _agents_link_drop_path "$p"
    done
    while [[ $n -lt 40 && "$rest" =~ $re2 ]]; do
        n=$((n + 1)); p="${BASH_REMATCH[1]}"
        rest=" ${rest#*"$p"}"; p="${p//\\/}"
        while [[ "$p" == *[.,\;:\)] ]]; do p="${p%?}"; done   # the sentence's own punctuation
        _agents_link_drop_path "$p"
    done
}
# _agents_link_drop_path PATH — print PATH when it could be a dropped file.
_agents_link_drop_path() {
    [[ "$1" =~ $_AGENTS_LINK_DROP_FROM && "$1" =~ \.[A-Za-z0-9]{1,8}$ && "$1" != *[[:cntrl:]]* && ${#1} -le 1024 ]] || return 0
    printf '%s\n' "$1"
}

# _agents_link_drop — the prompt hook (the hook's JSON on stdin). For each
# pasted path that is not a file on this machine, ask the attached watcher
# and wait for its answer; what it prints is added to the session's context.
# Silent, and at once, with no watcher attached or nothing to ask for. It
# waits _AGENTS_LINK_DROP_BUDGET seconds in all, and asks about a further
# path only while enough of that is left for an answer. It says something
# only about a file that was sent, or that you were asked about and did not
# send: a path your machine has no such file for is not a dropped file, and
# the session hears nothing about it.
_agents_link_drop() {
    local prompt p id dir ans path n=0 t0 now left
    command -v jq >/dev/null 2>&1 || return 0
    [[ ! -t 0 ]] || return 0
    prompt="$(jq -r '.prompt // empty' 2>/dev/null)" || return 0
    [[ -n "$prompt" && -n "$(_agents_link_listeners)" ]] || return 0
    dir="$(_agents_link_dir)"
    t0="$(date +%s)"
    while IFS= read -r p; do
        [[ -n "$p" && ! -e "$p" ]] || continue
        n=$((n + 1)); [[ $n -le $_AGENTS_LINK_DROP_MAX ]] || break
        now="$(date +%s)"; left=$((_AGENTS_LINK_DROP_BUDGET - (now - t0)))
        [[ $n -eq 1 || $left -ge $_AGENTS_LINK_DROP_NEED ]] || break
        id="d$$x$RANDOM$RANDOM"; id="$(printf '%s' "$id" | cut -c1-20)"
        # w.ID says someone waits: an answer that comes after this gave up
        # is not written (_agents_link_reply).
        rm -f "$dir/r.$id"; : > "$dir/w.$id"
        _agents_link_send "want-file"$'\t'"$id"$'\t'"$p" || { rm -f "$dir/w.$id"; return 0; }
        ans=""
        while [[ $(( $(date +%s) - t0 )) -lt $_AGENTS_LINK_DROP_BUDGET ]]; do
            if [[ -f "$dir/r.$id" ]]; then IFS=$'\t' read -r ans path < "$dir/r.$id" || true; break; fi
            sleep 1
        done
        rm -f "$dir/w.$id" "$dir/r.$id"
        if [[ "$ans" == ok && "$path" =~ ^/[A-Za-z0-9._/-]+$ && -f "$path" ]]; then
            printf '[tuidev] The file %s is on the user'"'"'s own machine, not this one. It has been copied here: read it at %s\n' "$p" "$path"
        elif [[ "$ans" == no ]]; then
            printf '[tuidev] The file %s is on the user'"'"'s own machine, not this one, and the user did not send it. To get it, ask them to run: agents push FILE\n' "$p"
        fi
    done < <(_agents_link_drop_paths "$prompt")
    return 0
}

# _agents_link_reply ID ok PATH | ID no | ID skip — the watcher's answer,
# written where the waiting hook looks (run on this machine by the watcher's
# ssh): ok with where the file landed, no when you were asked and did not
# send it, skip when your machine has no such file to offer (the hook then
# says nothing). Nothing is written when no hook waits for ID any more.
_agents_link_reply() {
    local id="${1:-}" ans="${2:-}" path="${3:-}" dir
    [[ "$id" =~ $_AGENTS_LINK_ID_RE ]] || return 2
    case "$ans" in
        ok)      [[ "$path" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 2 ;;
        no|skip) path="" ;;
        *)       return 2 ;;
    esac
    dir="$(_agents_link_dir)"
    [[ -f "$dir/w.$id" ]] || return 1
    _agents_replace "$dir/r.$id" "$ans"$'\t'"$path"
}

# _agents_link_may_send PATH — may this file of yours be offered for sending
# at all (before you are asked)? A plain, readable file, at most 50 MB, by
# its real path (no link, no .. on the way), which must be under your own
# home directory, a temp folder or a mounted volume, with no hidden folder
# (~/.ssh, ~/.aws, ~/.config…) and no Library folder on the way, however
# either is spelled (the filesystem ignores case). Sets _AGENTS_LINK_REAL (the
# real path) and _AGENTS_LINK_INODE on success, _AGENTS_LINK_WHY otherwise.
_agents_link_may_send() {
    local p="$1" d real home lc size
    _AGENTS_LINK_REAL="" _AGENTS_LINK_INODE=""
    _AGENTS_LINK_WHY="not a path to a file"
    [[ "$p" == /* && "$p" != *[[:cntrl:]]* && ${#p} -le 1024 ]] || return 1
    case "$p/" in */../*|*/./*|*//*) return 1 ;; esac
    _AGENTS_LINK_WHY="no such file here"
    [[ -f "$p" && ! -L "$p" ]] || return 1
    d="$(cd -P "${p%/*}" 2>/dev/null && pwd)" || return 1
    real="$d/${p##*/}"
    home="$(cd -P "$HOME" 2>/dev/null && pwd)" || home="$HOME"
    lc="$(printf '%s' "$real" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    _AGENTS_LINK_WHY="outside your home directory, the temp folders and mounted volumes"
    case "$lc/" in
        "$(printf '%s' "$home" | LC_ALL=C tr '[:upper:]' '[:lower:]')"/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*|/volumes/*) ;;
        *) return 1 ;;
    esac
    _AGENTS_LINK_WHY="in a hidden folder or a Library"
    case "$lc" in */.*|*/library/*) return 1 ;; esac
    _AGENTS_LINK_WHY="it could not be read (macOS may ask to let agents read that folder)"
    size="$(wc -c < "$real" 2>/dev/null | tr -d ' ')"
    [[ "$size" =~ ^[0-9]+$ ]] || return 1
    _AGENTS_LINK_WHY="larger than $((_AGENTS_OPEN_MAX / 1048576)) MB"
    [[ "$size" -le "$_AGENTS_OPEN_MAX" ]] || return 1
    # shellcheck disable=SC2012  # one file's inode; stat's flags differ by system
    _AGENTS_LINK_INODE="$(ls -di "$real" 2>/dev/null | awk '{ print $1 }')"
    _AGENTS_LINK_REAL="$real" _AGENTS_LINK_WHY=""
}

# _agents_link_consent LABEL PATH — ask you, in a dialog, whether LABEL may
# have PATH; true only for "Send". Cancel is the default button, and no
# answer in 30 s is no. No dialog to ask with (not macOS, no osascript, no
# desktop session) is no; _AGENTS_LINK_WHY says which of these it was. A test
# answers with AGENTS_CONSENT=yes|no, or runs its own osascript (=osascript).
_agents_link_consent() {
    local out err kb
    _AGENTS_LINK_WHY="declined"
    if [[ -n "${AGENTS_TESTING:-}" && "${AGENTS_CONSENT:-no}" != osascript ]]; then
        [[ -z "${AGENTS_CONSENT_SLEEP:-}" ]] || _AGENTS_LINK_ASKED=$((${_AGENTS_LINK_ASKED:-0} + 1))
        [[ "${AGENTS_CONSENT:-no}" == yes ]]; return
    fi
    _AGENTS_LINK_WHY="no dialog to ask you with here (agents push FILE sends it by hand)"
    command -v osascript >/dev/null 2>&1 || return 1
    kb="$(( ($(wc -c < "$2" | tr -d ' ') + 1023) / 1024 ))"
    err="$(mktemp "${TMPDIR:-/tmp}/agents-consent.XXXXXX")" || return 1
    # "activate" first: a dialog from a background job otherwise opens
    # behind whatever you are working in. Names are cut to what a dialog shows.
    out="$(osascript -e 'on run argv' -e 'tell current application to activate' \
        -e 'display dialog ((item 1 of argv) & " asks for a file from this Mac:" & return & return & (item 2 of argv) & return & "in " & (item 3 of argv) & return & (item 4 of argv) & " KB" & return & return & "Send it only if you just dropped or pasted it into a session there.") with title "agents: send a file?" buttons {"Send", "Cancel"} default button "Cancel" cancel button "Cancel" with icon caution giving up after 30' \
        -e 'end run' "$1" "$(printf '%s' "${2##*/}" | cut -c1-120)" "$(printf '%s' "${2%/*}" | cut -c1-200)" "$kb" 2>"$err")"
    # Cancel is osascript's error -128; anything else it says is why no
    # dialog could be shown.
    if [[ "$out" == *"gave up:true"* ]]; then _AGENTS_LINK_WHY="no answer in 30 s"
    elif [[ "$out" == *"button returned:Send"* ]]; then rm -f "$err"; _AGENTS_LINK_WHY=""; return 0
    elif grep -q -- '-128' "$err" 2>/dev/null; then _AGENTS_LINK_WHY="declined"
    else _AGENTS_LINK_WHY="the dialog could not be shown: $(tr -d '\n' < "$err" | cut -c1-160)"
    fi
    rm -f "$err"
    return 1
}

# How often one machine may make you look at a dialog: after one you did not
# answer with Send, none from it for five minutes; three in five minutes at
# most. A machine that keeps asking is not asked about again and again until
# a tired click says yes.
_AGENTS_LINK_WANT_MUTE=300
_AGENTS_LINK_WANT_MAX=3

# _agents_link_want LABEL TARGET ID PATH — a machine asks for one of your
# files: check it, ask you, check it is still that file, send it, answer.
# _AGENTS_LINK_WMUTE, _WT and _WN (the session's) keep the dialogs' count.
_agents_link_want() {
    local label="$1" target="$2" id="$3" path="$4" out now real inode ans=no
    [[ "$id" =~ $_AGENTS_LINK_ID_RE ]] || return 0
    _AGENTS_M_LABEL="$label" _AGENTS_M_TARGET="$target"
    _agents_now now
    if ! _agents_link_may_send "$path"; then
        echo "agents link: $label asked for a file that is not offered ($_AGENTS_LINK_WHY)" >&2
        ans=skip
    elif [[ $now -lt ${_AGENTS_LINK_WMUTE:-0} ]]; then
        echo "agents link: $label: ${path##*/} not sent (it asked again within $((_AGENTS_LINK_WANT_MUTE / 60)) minutes of a request you did not approve)" >&2
    else
        if [[ $((now - ${_AGENTS_LINK_WT:-0})) -ge $_AGENTS_LINK_WANT_MUTE ]]; then _AGENTS_LINK_WT="$now" _AGENTS_LINK_WN=0; fi
        _AGENTS_LINK_WN=$((${_AGENTS_LINK_WN:-0} + 1))
        real="$_AGENTS_LINK_REAL" inode="$_AGENTS_LINK_INODE"
        if [[ $_AGENTS_LINK_WN -gt $_AGENTS_LINK_WANT_MAX ]]; then
            echo "agents link: $label: ${path##*/} not sent (more than $_AGENTS_LINK_WANT_MAX requests in $((_AGENTS_LINK_WANT_MUTE / 60)) minutes)" >&2
        elif ! _agents_link_consent "$label" "$real" </dev/null; then
            echo "agents link: $label: ${path##*/} not sent ($_AGENTS_LINK_WHY)" >&2
            _agents_now now; _AGENTS_LINK_WMUTE=$((now + _AGENTS_LINK_WANT_MUTE))
        # The dialog was open for a while: what is sent is the file you were
        # shown, by its real path, and only if it is still that file.
        elif ! _agents_link_may_send "$real" || [[ "$_AGENTS_LINK_REAL" != "$real" || "$_AGENTS_LINK_INODE" != "$inode" ]]; then
            _agents_link_complain "$label: ${path##*/} changed while you were asked: not sent"
        elif out="$(_agents_push_one "$real" 2>/dev/null </dev/null)"; then
            # shellcheck disable=SC2016,SC2029  # $HOME is the remote's; id and path are checked
            _agents_ssh "$target" '"$HOME/.local/bin/agents"' link reply "$id" ok "$out" </dev/null >/dev/null 2>&1 || true
            return 0
        else
            _agents_link_complain "$label: could not send ${path##*/}"
        fi
    fi
    # shellcheck disable=SC2016,SC2029
    _agents_ssh "$target" '"$HOME/.local/bin/agents"' link reply "$id" "$ans" </dev/null >/dev/null 2>&1 || true
}

# _agents_link_state LABEL STATE — the watcher's note about one machine.
_agents_link_state() {
    local now
    _agents_now now
    _agents_replace "$(_agents_link_dir)/h.$1" "$2"$'\t'"$now" 2>/dev/null || true
}

# _agents_link_complain TEXT — a refused or failed request: the watcher's log,
# and a banner (the click otherwise does nothing you can see).
_agents_link_complain() {
    echo "agents link: $1" >&2
    AGENTS_NOTIFY=true _agents_notify "$1" || true
}

# _agents_link_room LABEL — may one more requested file from LABEL be kept?
# Files it asked to show are viewed once: those older than a day go first,
# and past 500 MB nothing more is fetched until they have.
_AGENTS_LINK_STORE_MB=500
_agents_link_room() {
    local dir="$AGENTS_DATA_DIR/remote/$1" kb
    [[ -d "$dir" ]] || return 0
    find "$dir" -type f -mtime +0 -exec rm -f {} + 2>/dev/null
    kb="$(du -sk "$dir" 2>/dev/null | cut -f1)"
    [[ "$kb" =~ ^[0-9]+$ ]] || return 0
    [[ $((kb / 1024)) -lt $_AGENTS_LINK_STORE_MB ]]
}

# _agents_link_pruned — what agents_forward_open closed to make room under
# its cap (_AGENTS_FWD_PRUNED), on the watcher's log.
_agents_link_pruned() {
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] || echo "agents link: $line: to make room for a new request" >&2
    done <<<"${_AGENTS_FWD_PRUNED:-}"
}

# _agents_link_handle LABEL TARGET LINE — act on one request from LABEL.
# _AGENTS_LINK_T/_N (the caller's) count them: five in ten seconds.
_agents_link_handle() {
    local label="$1" target="$2" kind arg arg2 now scheme rport path
    IFS=$'\t' read -r kind arg arg2 <<<"$3"
    case "$kind" in open-url|open-file|want-file) ;; *) return 0 ;; esac
    _agents_now now
    if [[ $((now - ${_AGENTS_LINK_T:-0})) -ge 10 ]]; then _AGENTS_LINK_T="$now" _AGENTS_LINK_N=0; fi
    _AGENTS_LINK_N=$((${_AGENTS_LINK_N:-0} + 1))
    if [[ $_AGENTS_LINK_N -gt 5 ]]; then
        [[ $_AGENTS_LINK_N -ne 6 ]] || _agents_link_complain "$label asks to open too much at once: ignoring it for a few seconds"
        return 0
    fi
    if [[ "$kind" == want-file ]]; then
        _agents_link_want "$label" "$target" "$arg" "$arg2"
        return 0
    fi
    if [[ "$kind" == open-url ]]; then
        if [[ ! "$arg" =~ $_AGENTS_FORWARD_URL_RE ]]; then
            echo "agents link: $label: not a loopback URL, ignored" >&2; return 0
        fi
        scheme="${BASH_REMATCH[1]}" rport="${BASH_REMATCH[4]}" path="${BASH_REMATCH[5]}"
        [[ -n "$rport" ]] || { if [[ "$scheme" == https ]]; then rport=443; else rport=80; fi; }
        # "asked": a port of this machine's own choosing, and a cap. The tab
        # is 127.0.0.1, not localhost: another machine's page then shares no
        # cookies with what you run on localhost yourself.
        if agents_forward_open "$label" "$target" "$rport" asked 2>/dev/null </dev/null; then
            _agents_link_pruned
            # No tab onto nothing: a port nobody holds over there gets a
            # banner, and a forward this click made, or one a request made,
            # is not kept. One of yours it reused stays: you opened it.
            if _agents_forward_answers "$_AGENTS_FWD_LPORT" </dev/null; then
                _agents_forward_answered "$_AGENTS_FWD_LPORT"
                _agents_open_local "$scheme://127.0.0.1:$_AGENTS_FWD_LPORT$path" || true
            else
                [[ -z "$_AGENTS_FWD_NEW" && "$_AGENTS_FWD_KIND" == yours ]] || _agents_forward_drop "$_AGENTS_FWD_LPORT" "$target"
                _agents_link_complain "$label: nothing answers on its port $rport"
            fi
        else
            _agents_link_pruned
            _agents_link_complain "$label: no tunnel to its port $rport (agents forward open $label $rport says why)"
        fi
    else
        if [[ "$arg" != /* ]] || ! _agents_open_ext "$arg"; then
            echo "agents link: $label: not a file a viewer shows, ignored" >&2; return 0
        fi
        _AGENTS_M_LABEL="$label" _AGENTS_M_TARGET="$target"
        if ! _agents_link_room "$label"; then
            _agents_link_complain "$label: its fetched files already take $_AGENTS_LINK_STORE_MB MB here: not fetching more today"
            return 0
        fi
        _agents_remote_fetch_open "$arg" >/dev/null 2>&1 </dev/null \
            || _agents_link_complain "$label: could not fetch ${arg##*/} (agents open $label PATH says why)"
    fi
    return 0
}

# _agents_link_session LABEL TARGET — one ssh to TARGET's `agents link
# serve`, handling its requests until it ends.
_agents_link_session() {
    local label="$1" target="$2" line first=true over=false
    local _AGENTS_LINK_WMUTE=0 _AGENTS_LINK_WT=0 _AGENTS_LINK_WN=0
    local _AGENTS_LINK_T=0 _AGENTS_LINK_N=0
    _agents_link_state "$label" connecting
    # A line is read 2048 characters at a time, so one without an end can't
    # grow here; a piece that long is part of an overlong line, dropped with
    # the rest of that line.
    while IFS= read -r -n 2048 line; do
        if [[ ${#line} -ge 2048 ]]; then over=true; continue; fi
        if [[ "$over" == true ]]; then over=false; continue; fi
        if [[ "$first" == true ]]; then
            first=false
            if [[ "$line" == "tuidev-link none" ]]; then
                _agents_link_state "$label" "needs tuidev there (tuidev install --pack monitoring)"
                return 1
            elif [[ "$line" != "$_AGENTS_LINK_PROTO" ]]; then
                _agents_link_state "$label" "no agents there"
                return 1
            fi
            _agents_link_state "$label" connected
            continue
        fi
        [[ "$line" == ping ]] || _agents_link_handle "$label" "$target" "$line"
    done < <(_agents_ssh -T -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$target" "$_AGENTS_LINK_REMOTE" </dev/null 2>/dev/null)
    [[ "$first" == false ]] || { _agents_link_state "$label" unreachable; return 1; }
    _agents_link_state "$label" disconnected
}

# _agents_link_loop LABEL TARGET — sessions for ever: again 5 s after one
# that lasted a minute, else after twice the last wait, up to a minute. A
# wait that took far longer than it was (the machine slept: a lid closed
# for an hour) starts the doubling over, so the machines come back within
# a minute of waking, not one at a time at the cap.
_AGENTS_LINK_WAIT_MAX=60
_agents_link_loop() {
    local wait=5 t0 t1
    while :; do
        _agents_now t0
        _agents_link_session "$1" "$2" || true
        _agents_now t1
        if [[ $((t1 - t0)) -ge 60 ]]; then wait=5; else wait=$((wait * 2)); [[ $wait -le $_AGENTS_LINK_WAIT_MAX ]] || wait=$_AGENTS_LINK_WAIT_MAX; fi
        sleep "$wait"
        _agents_now t0
        [[ $((t0 - t1)) -le $((wait + 60)) ]] || wait=5
    done
}

# _agents_link_watch — a loop per machine, and every minute one for each
# machine added since, and a look at the forwards (_agents_forward_sweep:
# those that requests made and that nothing answers twice in a row, or whose
# ssh ended, are closed). One watcher a user (the lock); AGENTS_LINK=0 ends
# it at once, successfully, so its LaunchAgent stays down.
_agents_link_watch() {
    local lock known=" " label target
    if [[ "$AGENTS_LINK" == 0 ]]; then echo "agents: link is off (AGENTS_LINK=0)"; return 0; fi
    lock="$(_agents_link_dir)/watch.lock"
    { mkdir -p "$(_agents_link_dir)" && chmod 700 "$(_agents_link_dir)"; } 2>/dev/null || return 1
    # Up to 10 s for the lock: a restart starts this while the watcher it
    # replaces is still going down. Still held then: another watcher runs,
    # and this fails, so its LaunchAgent tries again later instead of
    # staying down for good.
    _agents_lock "$lock" 20 0.5 || { echo "agents: a link watcher is already running" >&2; return 1; }
    # shellcheck disable=SC2064  # this lock, now
    trap "_agents_unlock '$lock'; trap - TERM INT; kill \$(jobs -p) 2>/dev/null; exit 0" TERM INT
    rm -f "$(_agents_link_dir)"/h.*
    while :; do
        while IFS=$'\t' read -r label target _; do
            [[ -n "$label" ]] || continue
            case "$known" in *" $label "*) continue ;; esac
            known+="$label "
            _agents_link_loop "$label" "$target" &
        done < <(_agents_machines)
        _agents_forward_sweep </dev/null || true
        sleep 60 &
        wait $!
    done
}

# _agents_link_status — the watcher and each machine it follows; on a machine
# others attach to, how many are attached.
_agents_link_status() {
    local dir f label state at now n=0 h="" pid=""
    dir="$(_agents_link_dir)"
    _agents_now now
    { read -r h < "$dir/watch.lock/holder"; } 2>/dev/null
    read -r pid _ <<<"$h"
    if [[ "$AGENTS_LINK" == 0 ]]; then echo "link: off (AGENTS_LINK=0)"
    elif [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        echo "link: watching (pid $pid)"
        for f in "$dir"/h.*; do
            [[ -f "$f" ]] || continue
            label="${f##*/h.}"
            IFS=$'\t' read -r state at < "$f" || true
            [[ "$at" =~ ^[0-9]+$ ]] || at="$now"
            printf '  %-20s %s (%sm)\n' "$label" "$state" "$(( (now - at) / 60 ))"
            n=$((n + 1))
        done
        [[ $n -gt 0 ]] || echo "  no machines yet (herdr machine add HOST, or AGENTS_REMOTE_HOSTS)"
    else
        echo "link: not watching (agents link watch; macOS: agents link restart)"
    fi
    n="$(_agents_link_listeners | grep -c . || true)"
    [[ "$n" -eq 0 ]] || echo "attached to this machine: $n"
}

# agents_link [status | watch | serve | click URL | restart]
agents_link() {
    case "${1:-status}" in
        status)  _agents_link_status ;;
        watch)   _agents_link_watch ;;
        serve)   _agents_link_serve ;;
        click)   shift; agents_link_click "$@" ;;
        drop)    _agents_link_drop ;;
        reply)   shift; _agents_link_reply "$@" ;;
        restart)
            [[ "$OSTYPE" == darwin* ]] || { echo "agents: restart is for the macOS LaunchAgent; run 'agents link watch' in a tmux pane" >&2; return 2; }
            [[ -f "$HOME/Library/LaunchAgents/$_AGENTS_LINK_LABEL.plist" ]] \
                || { echo "agents: no LaunchAgent ($_AGENTS_LINK_LABEL): tuidev install --pack monitoring" >&2; return 1; }
            launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$_AGENTS_LINK_LABEL.plist" 2>/dev/null || true
            launchctl kickstart -k "gui/$UID/$_AGENTS_LINK_LABEL" ;;
        *) echo "usage: agents link [status|watch|restart|click URL]" >&2; return 2 ;;
    esac
}
