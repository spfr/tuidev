# shellcheck shell=bash
# lib/agents/forward.sh — `agents forward`: a port of another machine, here.
#
# A forward is one `ssh -N -L` of its own, listening on this machine's
# 127.0.0.1 and connecting to the other machine's localhost: nothing is ever
# bound to a public address at either end. Each has a control socket and a
# record in $AGENTS_RUN_DIR/forward, named by the local port:
#   f.LPORT.sock   ssh's control socket (-O check says alive, -O exit closes)
#   f.LPORT        LPORT<TAB>LABEL<TAB>TARGET<TAB>RPORT<TAB>EPOCH
# so no pid is stored and none can go stale: a forward is alive when its
# socket answers.
#
# Owns: the forwards, their records, `agents forward`.
# Uses: config.sh (AGENTS_RUN_DIR), util.sh, remote.sh (_agents_machine,
#   _agents_ssh, _agents_open_local).
# Public: agents_forward, agents_forward_open, _agents_forward_records.

# A loopback http(s) URL: 1 the scheme, 4 the port, 5 the path and query, of
# characters no shell or URL parser reads as anything else.
_AGENTS_FORWARD_URL_RE='^(https?)://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:([0-9]{1,5}))?(/[A-Za-z0-9._~:/?#@!&()*+,;=%-]*)?$'

_agents_forward_dir() { printf '%s\n' "$AGENTS_RUN_DIR/forward"; }

# _agents_forward_records — every record, one a line (alive or not).
_agents_forward_records() {
    local f line dir
    dir="$(_agents_forward_dir)"
    for f in "$dir"/f.*; do
        [[ -f "$f" && "$f" != *.sock && "$f" != *.err ]] || continue
        IFS= read -r line < "$f" || true
        [[ "$line" =~ ^[0-9]+$'\t'[A-Za-z0-9._-]+$'\t'[^$'\t']+$'\t'[0-9]+$'\t'[0-9]+$ ]] && printf '%s\n' "$line"
    done
    return 0
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

# _agents_forward_drop LPORT TARGET — close that forward and forget it.
_agents_forward_drop() {
    local dir
    dir="$(_agents_forward_dir)"
    _agents_ssh -S "$dir/f.$1.sock" -O exit "$2" >/dev/null 2>&1 || true
    rm -f "$dir/f.$1" "$dir/f.$1.sock"
}

# How many forwards one machine's requests may hold at once (link.sh), and
# where their local ports start.
_AGENTS_FORWARD_ASKED_MAX=8
_AGENTS_FORWARD_ASKED_BASE=47000

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
#   and at most eight for one machine.
agents_forward_open() {
    local label="$1" target="$2" rport="$3" asked="${4:-}" dir l lab tgt rp _e lport try=0 err now n=0
    _AGENTS_FWD_LPORT=""
    [[ "$rport" =~ ^[0-9]{1,5}$ && "$rport" -ge 1 && "$rport" -le 65535 ]] || { echo "agents: not a port: $rport" >&2; return 2; }
    dir="$(_agents_forward_dir)"
    if ! { mkdir -p "$dir" && chmod 700 "$dir"; } 2>/dev/null; then
        echo "agents: can't write $dir" >&2; return 1
    fi
    while IFS=$'\t' read -r l lab tgt rp _e; do
        [[ "$lab" == "$label" ]] || continue
        if [[ "$rp" == "$rport" ]]; then
            if _agents_forward_alive "$l" "$tgt"; then _AGENTS_FWD_LPORT="$l"; return 0; fi
            _agents_forward_drop "$l" "$tgt"
        else
            n=$((n + 1))
        fi
    done < <(_agents_forward_records)
    if [[ -n "$asked" ]]; then
        if [[ $n -ge $_AGENTS_FORWARD_ASKED_MAX ]]; then
            echo "agents: $label already has $n forwards (agents forward close --dead, or close one)" >&2; return 1
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
    rm -f "$dir/f.$lport.sock"    # one left by a forward that is gone: ssh would not replace it
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
    printf '%s\t%s\t%s\t%s\t%s\n' "$lport" "$label" "$target" "$rport" "$now" > "$dir/f.$lport"
    _AGENTS_FWD_LPORT="$lport"
}

# _agents_forward_ls — the forwards as a table; a dead one says so.
_agents_forward_ls() {
    local recs l lab tgt rp e now state age out=""
    recs="$(_agents_forward_records)"
    if [[ -z "$recs" ]]; then echo "no forwards (agents forward open MACHINE PORT)"; return 0; fi
    _agents_now now
    while IFS=$'\t' read -r l lab tgt rp e; do
        if _agents_forward_alive "$l" "$tgt"; then state=active; else state=dead; fi
        age=$(( (now - e) / 60 ))
        if [[ $age -ge 60 ]]; then age="$((age / 60))h$((age % 60))m"; else age="${age}m"; fi
        out+="http://localhost:$l"$'\t'"$lab:$rp"$'\t'"$state"$'\t'"$age"$'\n'
    done <<<"$recs"
    printf 'LOCAL\tREMOTE\tSTATE\tAGE\n%s' "$out" | awk -F '\t' '
        { for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
        END { fmt = "%-" w[1] "s  %-" w[2] "s  %-" w[3] "s  %s\n"   # no %-*s: not every awk has it
              for (r = 1; r <= NR; r++) printf fmt, c[r, 1], c[r, 2], c[r, 3], c[r, 4] }'
}

# _agents_forward_close ARGS — --all, --dead, a local port, or MACHINE PORT.
_agents_forward_close() {
    local what="${1:-}" port="${2:-}" l lab tgt rp _e n=0
    case "$what" in
        --all|--dead) [[ $# -eq 1 ]] || what="" ;;
        "")           ;;
        *)            if [[ $# -eq 1 && "$what" =~ ^[0-9]+$ ]]; then port="$what"; what=--local
                      elif [[ $# -eq 2 && "$port" =~ ^[0-9]+$ ]]; then :
                      else what=""; fi ;;
    esac
    [[ -n "$what" ]] || { echo "usage: agents forward close --all | --dead | LOCALPORT | MACHINE PORT" >&2; return 2; }
    while IFS=$'\t' read -r l lab tgt rp _e; do
        [[ -n "$l" ]] || continue
        case "$what" in
            --all)   ;;
            --dead)  ! _agents_forward_alive "$l" "$tgt" || continue ;;
            --local) [[ "$l" == "$port" ]] || continue ;;
            *)       [[ ( "$lab" == "$what" || "$tgt" == "$what" ) && "$rp" == "$port" ]] || continue ;;
        esac
        _agents_forward_drop "$l" "$tgt"
        echo "closed localhost:$l ($lab:$rp)"
        n=$((n + 1))
    done < <(_agents_forward_records)
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
            _agents_forward_answers "$_AGENTS_FWD_LPORT" \
                || echo "agents: nothing answers on $_AGENTS_M_LABEL:$rport yet (the forward stays for when it does)" >&2
            [[ "$noopen" == true ]] || _agents_open_local "$url" || true ;;
        *) echo "usage: agents forward [ls | open [--no-open] MACHINE PORT|URL | close --all|--dead|LOCALPORT|MACHINE PORT]" >&2; return 2 ;;
    esac
}
