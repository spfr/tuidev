# shellcheck shell=bash
# lib/agents/forward.sh — `agents forward`: a port of another machine, here.
#
# A forward is one `ssh -N -L` of its own, listening on this machine's
# 127.0.0.1 and connecting to the other machine's localhost: nothing is ever
# bound to a public address at either end. Each has a control socket and a
# record in $AGENTS_RUN_DIR/forward, named by the local port:
#   f.LPORT.sock   ssh's control socket (-O check says alive, -O exit closes)
#   f.LPORT        LPORT<TAB>LABEL<TAB>TARGET<TAB>RPORT<TAB>EPOCH<TAB>KIND
#   f.LPORT.miss   COUNT<TAB>EPOCH: how many of the link watcher's checks
#                  in a row found nothing answering over there, and when the
#                  last of them counted (none: the last check found something)
# so no pid is stored and none can go stale: a forward is alive when its
# socket answers. KIND is "yours" (agents forward open) or "asked" (a click
# on another machine, link.sh); for a record written before it had the
# field, see _agents_forward_read.
#
# A forward is in one of three states:
#   active      its ssh is alive, and something answers over there
#   unanswered  its ssh is alive, and nothing answers ("nothing answers")
#   dead        its ssh is gone
#
# Owns: the forwards, their records, `agents forward`.
# Uses: config.sh (AGENTS_RUN_DIR), util.sh, remote.sh (_agents_machine,
#   _agents_ssh, _agents_open_local).
# Public: agents_forward, agents_forward_open, _agents_forward_records,
#   _agents_forward_states, _agents_forward_prune, _agents_forward_sweep.

# A loopback http(s) URL: 1 the scheme, 4 the port, 5 the path and query, of
# characters no shell or URL parser reads as anything else.
_AGENTS_FORWARD_URL_RE='^(https?)://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:([0-9]{1,5}))?(/[A-Za-z0-9._~:/?#@!&()*+,;=%-]*)?$'

_agents_forward_dir() { printf '%s\n' "$AGENTS_RUN_DIR/forward"; }

# How many forwards one machine's requests may hold at once (link.sh), and
# where their local ports start.
_AGENTS_FORWARD_ASKED_MAX=8
_AGENTS_FORWARD_ASKED_BASE=47000

# _agents_forward_read LPORT — set _AGENTS_FWD_REC to that forward's record,
# always with its KIND, or to nothing (false) when there is none. A record
# written before KIND existed is asked when its local port is one requests
# get (47000 up) and is not its remote port (yours takes the same number
# first, so a forward of yours to a high port keeps it).
_agents_forward_read() {
    local line=""
    _AGENTS_FWD_REC=""
    [[ "$1" =~ ^[0-9]{1,5}$ && -f "$AGENTS_RUN_DIR/forward/f.$1" ]] || return 1
    { IFS= read -r line < "$AGENTS_RUN_DIR/forward/f.$1"; } 2>/dev/null || true
    [[ "$line" =~ ^([0-9]{1,5})$'\t'[A-Za-z0-9._-]+$'\t'[^$'\t']+$'\t'([0-9]{1,5})$'\t'[0-9]+($'\t'(asked|yours))?$ ]] || return 1
    [[ "${BASH_REMATCH[1]}" == "$1" ]] || return 1
    if [[ -z "${BASH_REMATCH[3]}" ]]; then
        if [[ ${BASH_REMATCH[1]} -ge $_AGENTS_FORWARD_ASKED_BASE && ${BASH_REMATCH[1]} -ne ${BASH_REMATCH[2]} ]]; then line+=$'\t'asked; else line+=$'\t'yours; fi
    fi
    _AGENTS_FWD_REC="$line"
}

# _agents_forward_records — every record, one a line (alive or not), always
# with its KIND (_agents_forward_read).
_agents_forward_records() {
    local f p
    for f in "$AGENTS_RUN_DIR/forward"/f.*; do
        p="${f##*/f.}"
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        ! _agents_forward_read "$p" || printf '%s\n' "$_AGENTS_FWD_REC"
    done
    return 0
}

# _agents_forward_same LPORT RECORD — is that forward's record still RECORD?
# What checked a forward and then acts on it asks this first: in the second
# a probe takes, a click can close a dead forward and open a new one on the
# same local port, or reuse it.
_agents_forward_same() {
    _agents_forward_read "$1" && [[ "$_AGENTS_FWD_REC" == "$2" ]]
}

# _agents_forward_any — is there a record at all? (No process: the link
# watcher asks this every minute.)
_agents_forward_any() {
    local f
    for f in "$AGENTS_RUN_DIR/forward"/f.*; do
        [[ -f "$f" && "${f##*/f.}" =~ ^[0-9]+$ ]] && return 0
    done
    return 1
}

# _agents_forward_alive LPORT TARGET — does that forward's ssh still answer?
_agents_forward_alive() {
    local sock
    sock="$(_agents_forward_dir)/f.$1.sock"
    [[ -S "$sock" || -n "${AGENTS_TESTING:-}" ]] || return 1
    _agents_ssh -S "$sock" -O check "$2" >/dev/null 2>&1
}

# _agents_port_busy PORT — does something on this machine's loopback, IPv4 or
# IPv6 (a dev server may be on ::1 alone), accept connections on PORT?
# (bash's /dev/tcp: no fork but the subshell.)
_agents_port_busy() {
    if [[ -n "${AGENTS_TESTING:-}" && -n "${AGENTS_BUSY_PORTS+set}" ]]; then
        case " $AGENTS_BUSY_PORTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
    fi
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null || (exec 3<>"/dev/tcp/::1/$1") 2>/dev/null
}

# _agents_forward_answers LPORT — does anything answer at the far end of that
# forward? ssh listens here whether or not a server runs over there, and a
# connection to a port nobody holds is reset at once: curl tells the two
# apart (any HTTP reply, a TLS handshake or a slow server counts as an
# answer). True when curl is missing: unknown is not "dead".
_agents_forward_answers() {
    local rc=0 curl=curl
    [[ -z "${AGENTS_TESTING:-}" ]] || curl="${AGENTS_CURL:-}"
    [[ -n "$curl" ]] && command -v "$curl" >/dev/null 2>&1 || return 0
    "$curl" -s -o /dev/null --max-time 4 "http://127.0.0.1:$1/" 2>/dev/null || rc=$?
    case "$rc" in 7|52|56) return 1 ;; esac   # refused, empty reply, reset
    return 0
}

# _agents_forward_served LPORT — is anything served at the far end of that
# forward? The check that runs without being asked (the watcher, ls, the
# map), so it sends nothing: no HTTP request reaches a server for it. A test
# answers with AGENTS_PROBE, a command given LPORT (true: served), and
# without one everything is served.
_agents_forward_served() {
    if [[ -n "${AGENTS_TESTING:-}" ]]; then
        [[ -n "${AGENTS_PROBE:-}" ]] || return 0
        "$AGENTS_PROBE" "$1"; return
    fi
    _agents_forward_held "$1"
}

# _agents_forward_held PORT — connect to 127.0.0.1:PORT, send nothing, and
# see whether the connection is kept. ssh -L takes every connection here
# whether or not anything listens over there, and closes it as soon as the
# far end refuses (a round trip); a server keeps it open, waiting for a
# request, or speaks first. So: closed within a second is false, still open
# then (or a byte read) is true, and so is everything this cannot tell
# (nothing here to connect to, any error): doubt never closes a forward.
# The reader runs on its own and is looked at after 0.2 s and after 1 s: a
# timed-out read and a closed connection look the same to bash 3.2's
# read -t (both are 1), and a running reader does not.
_agents_forward_held() {
    (
        exec 3<>"/dev/tcp/127.0.0.1/$1" || exit 0
        ( IFS= read -r -n 1 _ <&3 ) &
        r=$!
        exec 3>&-
        for w in 0.2 0.8; do
            sleep "$w" || break
            kill -0 "$r" 2>/dev/null || { wait "$r"; exit; }   # 0: it spoke; else closed
        done
        kill "$r" 2>/dev/null; wait "$r" 2>/dev/null
        exit 0
    ) 2>/dev/null
}

# _agents_forward_drop LPORT TARGET — close that forward and forget it.
_agents_forward_drop() {
    local dir
    dir="$(_agents_forward_dir)"
    _agents_ssh -S "$dir/f.$1.sock" -O exit "$2" >/dev/null 2>&1 || true
    rm -f "$dir/f.$1" "$dir/f.$1.sock" "$dir/f.$1.miss"
}

# The link watcher's miss mark, f.LPORT.miss: COUNT<TAB>EPOCH, the checks in
# a row that found nothing answering and when the last one counted. A
# second miss counts only _GAP seconds after the first (a watcher that
# restarts looks at once, and two looks seconds apart are not two minutes
# of silence), and the menu bar trusts a mark only while it is _FRESH: one
# the watcher stopped keeping says nothing.
_AGENTS_FORWARD_MISS_GAP=50
_AGENTS_FORWARD_MISS_FRESH=150

# _agents_forward_miss LPORT — set _AGENTS_FWD_MISS and _AGENTS_FWD_MISSAT
# from that forward's mark (0 and 0 without one; false then).
_agents_forward_miss() {
    local c="" at=""
    _AGENTS_FWD_MISS=0 _AGENTS_FWD_MISSAT=0
    [[ -f "$AGENTS_RUN_DIR/forward/f.$1.miss" ]] || return 1
    { IFS=$'\t' read -r c at < "$AGENTS_RUN_DIR/forward/f.$1.miss"; } 2>/dev/null || true
    [[ ! "$c" =~ ^[0-9]{1,3}$ ]] || _AGENTS_FWD_MISS="$c"
    [[ ! "$at" =~ ^[0-9]{1,12}$ ]] || _AGENTS_FWD_MISSAT="$at"
    return 0
}

# _agents_forward_states [--cached] [LABEL] — every record (only LABEL's,
# with one) followed by its state, active, unanswered or dead, as a seventh
# field, in the records' order. A probe that finds something waits about a
# second, so every forward is checked at the same time. --cached probes
# nothing (the menu bar's board): unanswered is then a miss mark the link
# watcher wrote in the last _FRESH seconds, and active otherwise.
_agents_forward_states() {
    local cached="" only recs i=0 l lab tgt rp e k now="" pids=""
    if [[ "${1:-}" == --cached ]]; then cached=1; shift; _agents_now now; fi
    only="${1:-}"
    recs="$(_agents_forward_records)"
    [[ -n "$recs" ]] || return 0
    {
        while IFS=$'\t' read -r l lab tgt rp e k; do
            [[ -n "$l" && ( -z "$only" || "$lab" == "$only" ) ]] || continue
            i=$((i + 1))
            ( s=dead
              if _agents_forward_alive "$l" "$tgt"; then
                  if [[ -n "$cached" ]]; then
                      s=active
                      if _agents_forward_miss "$l" && [[ $((now - _AGENTS_FWD_MISSAT)) -lt $_AGENTS_FORWARD_MISS_FRESH ]]; then s=unanswered; fi
                  elif _agents_forward_served "$l"; then s=active
                  else s=unanswered; fi
              fi
              printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$l" "$lab" "$tgt" "$rp" "$e" "$k" "$s" ) </dev/null &
            pids+=" $!"
        done <<<"$recs"
        # These pids only: the link watcher, which calls this, has jobs of its own.
        # shellcheck disable=SC2086  # a list of pids
        [[ -z "$pids" ]] || wait $pids
    } | LC_ALL=C sort -t $'\t' -k1,1n | cut -f2-
}

# _agents_forward_still LPORT RECORD STATE — after a check found STATE, is
# that forward still the one checked, and still not answering? The same
# record (not closed and reopened on that port, not reused and made yours),
# and for a dead one, an ssh that is still gone.
_agents_forward_still() {
    local tgt
    _agents_forward_same "$1" "$2" || return 1
    [[ "$3" == dead ]] || return 0
    IFS=$'\t' read -r _ _ tgt _ <<<"$2"
    ! _agents_forward_alive "$1" "$tgt"
}

# _agents_forward_prune LABEL — check LABEL's forwards now, and close those
# its requests made (asked) that are dead or that nothing answers; yours
# stay. Says each it closed.
_agents_forward_prune() {
    local l lab tgt rp e k s
    while IFS=$'\t' read -r l lab tgt rp e k s; do
        [[ -n "$l" && "$k" == asked && "$s" != active ]] || continue
        _agents_forward_still "$l" "$l"$'\t'"$lab"$'\t'"$tgt"$'\t'"$rp"$'\t'"$e"$'\t'"$k" "$s" || continue
        _agents_forward_drop "$l" "$tgt"
        echo "closed localhost:$l ($lab:$rp)"
    done < <(_agents_forward_states "$1")
}

# _agents_forward_sweep — the link watcher's minute. A dead forward that a
# request made is dropped. A live one is checked: something answers clears
# its miss mark, nothing adds one (_GAP seconds after the last at the
# soonest), and one a request made is closed at its second miss in a row (a
# line on stderr, the watcher's log, and nothing else). Yours are never
# closed here: they only carry the mark, which ls, the map and the menu bar
# show. Each acts only on the forward it checked (_agents_forward_still).
# No record: no work at all.
_agents_forward_sweep() {
    local dir l lab tgt rp e k s rec now
    _agents_forward_any || return 0
    dir="$(_agents_forward_dir)"
    while IFS=$'\t' read -r l lab tgt rp e k s; do
        [[ -n "$l" ]] || continue
        rec="$l"$'\t'"$lab"$'\t'"$tgt"$'\t'"$rp"$'\t'"$e"$'\t'"$k"
        case "$s" in
            active) rm -f "$dir/f.$l.miss" ;;
            dead)
                [[ "$k" == asked ]] || continue
                _agents_forward_still "$l" "$rec" dead || continue
                _agents_forward_drop "$l" "$tgt"
                echo "agents link: closed localhost:$l ($lab:$rp): its ssh had ended" >&2 ;;
            unanswered)
                _agents_now now
                _agents_forward_miss "$l" || true
                # Too soon after the last miss that counted: this look adds nothing.
                [[ $((now - _AGENTS_FWD_MISSAT)) -ge $_AGENTS_FORWARD_MISS_GAP ]] || continue
                _agents_forward_still "$l" "$rec" unanswered || continue
                _AGENTS_FWD_MISS=$((_AGENTS_FWD_MISS + 1)); [[ $_AGENTS_FWD_MISS -le 99 ]] || _AGENTS_FWD_MISS=99
                if [[ "$k" == asked && $_AGENTS_FWD_MISS -ge 2 ]]; then
                    _agents_forward_drop "$l" "$tgt"
                    echo "agents link: closed localhost:$l ($lab:$rp): nothing answered there twice in a row" >&2
                else
                    printf '%s\t%s\n' "$_AGENTS_FWD_MISS" "$now" > "$dir/f.$l.miss" 2>/dev/null || true
                fi ;;
        esac
    done < <(_agents_forward_states)
}

# agents_forward_open LABEL TARGET RPORT [asked] — bring TARGET's RPORT (on
# its localhost, IPv4 or IPv6) here and set _AGENTS_FWD_LPORT to the local
# port. A live forward of that port is reused. False, with ssh's own words
# on stderr, when the tunnel did not come up.
#   Yours (`agents forward open`): the same number when it is free here (so
#   the URL a program printed works as it stands), else the next free of
#   twenty; a port under 1024 starts at 10000 + RPORT.
#   asked (a request from that machine, link.sh): never the same number, so
#   no request can put that machine behind a port your own tools use
#   (localhost:5432 while your database is down): the first free from 47000,
#   and at most eight asked ones for one machine. At eight, that machine's
#   asked forwards that are dead or that nothing answers now are closed
#   first, and only then is the request refused.
# A forward of yours that a request asks for again stays yours; one a
# request made becomes yours when you open it yourself. Also sets
# _AGENTS_FWD_NEW (1: made now, empty: reused), _AGENTS_FWD_KIND, and
# _AGENTS_FWD_PRUNED (the "closed ..." lines of what the cap closed).
agents_forward_open() {
    local label="$1" target="$2" rport="$3" asked="${4:-}" dir l lab tgt rp e k lport try=0 err now n=0
    _AGENTS_FWD_LPORT="" _AGENTS_FWD_NEW="" _AGENTS_FWD_KIND="" _AGENTS_FWD_PRUNED=""
    [[ "$rport" =~ ^[0-9]{1,5}$ && "$rport" -ge 1 && "$rport" -le 65535 ]] || { echo "agents: not a port: $rport" >&2; return 2; }
    dir="$(_agents_forward_dir)"
    if ! { mkdir -p "$dir" && chmod 700 "$dir"; } 2>/dev/null; then
        echo "agents: can't write $dir" >&2; return 1
    fi
    while IFS=$'\t' read -r l lab tgt rp e k; do
        [[ "$lab" == "$label" ]] || continue
        if [[ "$rp" == "$rport" ]]; then
            if _agents_forward_alive "$l" "$tgt"; then
                if [[ -z "$asked" && "$k" == asked ]]; then
                    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$l" "$lab" "$tgt" "$rp" "$e" yours > "$dir/f.$l"
                    k=yours
                fi
                _AGENTS_FWD_LPORT="$l" _AGENTS_FWD_KIND="$k"; return 0
            fi
            _agents_forward_drop "$l" "$tgt"
        elif [[ "$k" == asked ]]; then
            n=$((n + 1))
        fi
    done < <(_agents_forward_records)
    if [[ -n "$asked" ]]; then
        if [[ $n -ge $_AGENTS_FORWARD_ASKED_MAX ]]; then
            _AGENTS_FWD_PRUNED="$(_agents_forward_prune "$label")"
            [[ -z "$_AGENTS_FWD_PRUNED" ]] || printf '%s\n' "$_AGENTS_FWD_PRUNED" >&2
            n="$(_agents_forward_records | awk -F '\t' -v l="$label" '$2 == l && $6 == "asked" { n++ } END { print n + 0 }')"
        fi
        if [[ $n -ge $_AGENTS_FORWARD_ASKED_MAX ]]; then
            echo "agents: $label already has $n forwards it asked for, all answering: close one (agents forward ls, then agents forward close LOCALPORT)" >&2; return 1
        fi
        lport="$_AGENTS_FORWARD_ASKED_BASE"
    else
        lport="$rport"
        [[ "$lport" -ge 1024 ]] || lport=$((10000 + rport))
    fi
    while [[ -e "$dir/f.$lport" ]] || _agents_port_busy "$lport"; do
        try=$((try + 1)); lport=$((lport + 1))
        if [[ $try -ge 20 || $lport -gt 65535 ]]; then
            echo "agents: no free local port near ${lport} for $label:$rport" >&2; return 1
        fi
    done
    rm -f "$dir/f.$lport.sock" "$dir/f.$lport.miss"   # left by a forward that is gone: ssh would not replace a socket
    # -f: ssh goes to the background once the forward is up, and fails here
    # (ExitOnForwardFailure) when it is not. Its stderr goes to a file, never
    # a $( ): the ssh that stays would hold that pipe open for as long as the
    # forward lives.
    err="$dir/f.$lport.err"
    if ! _agents_ssh_fwd -f -N -M -S "$dir/f.$lport.sock" -o ControlPersist=no -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
            -L "127.0.0.1:$lport:localhost:$rport" "$target" >/dev/null 2>"$err" </dev/null; then
        try="$(tail -n 1 "$err" 2>/dev/null)"
        rm -f "$dir/f.$lport.sock" "$err"
        echo "agents: no tunnel to $label:$rport: ${try:-ssh failed} (does 'ssh $target true' work without a prompt?)" >&2
        return 1
    fi
    rm -f "$err"
    _agents_now now
    k=yours; [[ -z "$asked" ]] || k=asked
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$lport" "$label" "$target" "$rport" "$now" "$k" > "$dir/f.$lport"
    _AGENTS_FWD_LPORT="$lport" _AGENTS_FWD_NEW=1 _AGENTS_FWD_KIND="$k"
}

# _agents_forward_answered LPORT — something answered there just now (a
# click's check, agents forward open's): the watcher's misses are forgotten.
_agents_forward_answered() { rm -f "$AGENTS_RUN_DIR/forward/f.$1.miss"; }

# _agents_forward_close_server LABEL RPORT — close every forward to that
# machine's port (by its label alone: another machine's ssh target may be
# spelled the same), yours too, saying each: a server you stopped there.
_agents_forward_close_server() {
    local l lab tgt rp _e _k
    while IFS=$'\t' read -r l lab tgt rp _e _k; do
        [[ -n "$l" && "$lab" == "$1" && "$rp" == "$2" ]] || continue
        _agents_forward_drop "$l" "$tgt"
        echo "closed localhost:$l ($lab:$rp)"
    done < <(_agents_forward_records)
}

# _agents_forward_ls — the forwards as a table, each with its state: active,
# nothing answers, or dead (all checked at once: about a second).
_agents_forward_ls() {
    local recs l lab tgt rp e _k now state age out=""
    recs="$(_agents_forward_states)"
    if [[ -z "$recs" ]]; then echo "no forwards (agents forward open MACHINE PORT)"; return 0; fi
    _agents_now now
    while IFS=$'\t' read -r l lab tgt rp e _k state; do
        [[ "$state" != unanswered ]] || state="nothing answers"
        age=$(( (now - e) / 60 ))
        if [[ $age -ge 60 ]]; then age="$((age / 60))h$((age % 60))m"; else age="${age}m"; fi
        out+="http://localhost:$l"$'\t'"$lab:$rp"$'\t'"$state"$'\t'"$age"$'\n'
    done <<<"$recs"
    printf 'LOCAL\tREMOTE\tSTATE\tAGE\n%s' "$out" | awk -F '\t' '
        { for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
        END { fmt = "%-" w[1] "s  %-" w[2] "s  %-" w[3] "s  %s\n"   # no %-*s: not every awk has it
              for (r = 1; r <= NR; r++) printf fmt, c[r, 1], c[r, 2], c[r, 3], c[r, 4] }'
}

# _agents_forward_close ARGS — --all, --dead (dead, or nothing answers: all
# checked now, at once), a local port, or MACHINE PORT.
_agents_forward_close() {
    local what="${1:-}" port="${2:-}" l lab tgt rp e k s n=0
    case "$what" in
        --all|--dead) [[ $# -eq 1 ]] || what="" ;;
        "")           ;;
        *)            if [[ $# -eq 1 && "$what" =~ ^[0-9]+$ ]]; then port="$what"; what=--local
                      elif [[ $# -eq 2 && "$port" =~ ^[0-9]+$ ]]; then :
                      else what=""; fi ;;
    esac
    [[ -n "$what" ]] || { echo "usage: agents forward close --all | --dead | LOCALPORT | MACHINE PORT" >&2; return 2; }
    while IFS=$'\t' read -r l lab tgt rp e k s; do
        [[ -n "$l" ]] || continue
        case "$what" in
            --all)   ;;
            --dead)  [[ "$s" != active ]] || continue
                     _agents_forward_still "$l" "$l"$'\t'"$lab"$'\t'"$tgt"$'\t'"$rp"$'\t'"$e"$'\t'"$k" "$s" || continue ;;
            --local) [[ "$l" == "$port" ]] || continue ;;
            *)       [[ ( "$lab" == "$what" || "$tgt" == "$what" ) && "$rp" == "$port" ]] || continue ;;
        esac
        _agents_forward_drop "$l" "$tgt"
        echo "closed localhost:$l ($lab:$rp)"
        n=$((n + 1))
    done < <(if [[ "$what" == --dead ]]; then _agents_forward_states; else _agents_forward_records; fi)
    [[ $n -gt 0 || "$what" == --dead || "$what" == --all ]] || { echo "agents: no such forward" >&2; return 1; }
}

# agents_forward [ls | open [--no-open] MACHINE PORT|URL | close ...]
agents_forward() {
    local cmd="${1:-ls}" noopen=false scheme=http rport path="" url
    [[ $# -eq 0 ]] || shift
    case "$cmd" in
        ls|list) _agents_forward_ls ;;
        close)   _agents_forward_close "$@" ;;
        open)
            [[ "${1:-}" != --no-open ]] || { noopen=true; shift; }
            [[ $# -eq 2 ]] || { echo "usage: agents forward open [--no-open] MACHINE PORT|URL" >&2; return 2; }
            if [[ "$2" =~ ^[0-9]{1,5}$ ]]; then
                rport="$2"
            elif [[ "$2" =~ $_AGENTS_FORWARD_URL_RE ]]; then
                scheme="${BASH_REMATCH[1]}" rport="${BASH_REMATCH[4]}" path="${BASH_REMATCH[5]}"
                [[ -n "$rport" ]] || { if [[ "$scheme" == https ]]; then rport=443; else rport=80; fi; }
            else
                echo "agents: need a port or a localhost URL, got: $2" >&2; return 2
            fi
            _agents_machine "$1" || return 1
            agents_forward_open "$_AGENTS_M_LABEL" "$_AGENTS_M_TARGET" "$rport" || return
            url="$scheme://localhost:$_AGENTS_FWD_LPORT$path"
            echo "$url  ->  $_AGENTS_M_LABEL:$rport"
            if _agents_forward_answers "$_AGENTS_FWD_LPORT"; then _agents_forward_answered "$_AGENTS_FWD_LPORT"
            else echo "agents: nothing answers on $_AGENTS_M_LABEL:$rport yet (the forward stays for when it does)" >&2; fi
            [[ "$noopen" == true ]] || _agents_open_local "$url" || true ;;
        *) echo "usage: agents forward [ls | open [--no-open] MACHINE PORT|URL | close --all|--dead|LOCALPORT|MACHINE PORT]" >&2; return 2 ;;
    esac
}
