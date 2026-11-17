# shellcheck shell=bash
# lib/agents/remote.sh — your other machines: who they are, what listens
# there, and files to and from them.
#
# A machine is a saved Herdr machine (`herdr machine list`: its label and SSH
# target) or a host in AGENTS_REMOTE_HOSTS. Everything goes over plain ssh,
# with BatchMode: nothing here asks for a password, and a machine that needs
# one is reported, not prompted for. File contents travel on ssh's own
# stdin/stdout (`cat`), so no path is ever expanded by a remote scp.
#
# Owns: the machine list, the ssh command line, `agents ports`, `agents push`
#   and `agents open`.
# Uses: config.sh, util.sh, snapshot.sh (_agents_listeners, _agents_cwds),
#   forward.sh (the forwards a port list marks), link.sh (agents_link_click),
#   pick.sh (_agents_fzf).
# Public: agents_ports, agents_push, _agents_push_one, agents_remote_open, _agents_machines,
#   _agents_machine, _agents_ssh, _agents_ssh_mux, _agents_open_local, _agents_open_ext,
#   _agents_remote_fetch_open.

# What `agents open` and a clicked file link may hand to the desktop: formats a
# viewer shows. Nothing the desktop would run (.command, .app, .terminal…).
_AGENTS_OPEN_EXTS="md markdown txt log json csv tsv yaml yml toml html htm pdf png jpg jpeg gif webp svg"
_AGENTS_OPEN_MAX=$((50 * 1024 * 1024))   # bytes of one fetched file

# _agents_ssh ARGS... — ssh, never interactive (a test names a stand-in), and
# carrying nothing your ssh config would add for that host: no agent or X11
# forwarding, and none of its LocalForward/RemoteForward lines. These
# connections are opened for you in the background, some for hours; a
# machine should not get your ssh agent because a tunnel to it is up.
# _agents_ssh_fwd is the same for the one call that is itself a forward
# (ClearAllForwardings would clear its -L too).
_agents_ssh() { _agents_ssh_fwd -o ClearAllForwardings=yes "$@"; }
# _agents_ssh_mux ARGS... — the same for short commands asked again and again
# (a port list, a preview as the cursor moves): they share one connection a
# machine, kept two minutes after its last use, so only the first pays for
# the handshake. Never for a forward or its control commands: those name
# their own socket, and ssh takes the first ControlPath it is given.
_agents_ssh_mux() {
    local dir="$AGENTS_RUN_DIR/ssh"
    if { mkdir -p "$dir" && chmod 700 "$dir"; } 2>/dev/null; then
        _agents_ssh -o ControlMaster=auto -o "ControlPath=$dir/%C" -o ControlPersist=120 "$@"
    else
        _agents_ssh "$@"
    fi
}
_agents_ssh_fwd() {
    local ssh=ssh
    [[ -z "${AGENTS_TESTING:-}" || -z "${AGENTS_SSH:-}" ]] || ssh="$AGENTS_SSH"
    "$ssh" -o BatchMode=yes -o ConnectTimeout=8 -o ForwardAgent=no -o ForwardX11=no "$@"
}

# _agents_target_ok TARGET — an ssh destination that can't be read as an
# option or a command: a host, user@host or ssh://user@host:port.
_agents_target_ok() { [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._@:/-]*$ ]]; }

# _agents_label VAR TEXT — set VAR to TEXT as a machine's label: only
# [A-Za-z0-9._-], and never a name that means something else here ("local" is
# this machine in a port list; "." and ".." are directories; a leading "-"
# would read as an option).
_agents_label() {
    local _l="${2//[^A-Za-z0-9._-]/_}"
    case "$_l" in local|.|..|-*) _l="m-$_l" ;; esac
    printf -v "$1" '%s' "$_l"
}

# _agents_machines — "LABEL<TAB>TARGET<TAB>SELECTED" for each machine: Herdr's
# enabled saved machines (SELECTED 1 for the one its window shows), then
# AGENTS_REMOTE_HOSTS (label and target the same). A target that fails
# _agents_target_ok is left out.
_agents_machines() {
    local label target sel h seen=" "
    if [[ -z "${AGENTS_NO_HERDR:-}" ]] && command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        while IFS=$'\t' read -r label target sel; do
            _agents_label label "$label"
            if [[ -z "$label" ]] || ! _agents_target_ok "$target"; then continue; fi
            case "$seen" in *" $label "*) continue ;; esac
            seen+="$label "
            printf '%s\t%s\t%s\n' "$label" "$target" "$sel"
        done < <(_agents_timeout 5 herdr machine list --json 2>/dev/null \
            | jq -r '.[]? | select(.enabled != false) | [.label, .target, (if .selected then 1 else 0 end)] | @tsv' 2>/dev/null)
    fi
    for h in ${AGENTS_REMOTE_HOSTS:-}; do
        _agents_target_ok "$h" || continue
        _agents_label label "$h"
        case "$seen" in *" $label "*) continue ;; esac
        seen+="$label "
        printf '%s\t%s\t0\n' "$label" "$h"
    done
}

# _agents_machine NAME — set _AGENTS_M_LABEL and _AGENTS_M_TARGET for NAME: a
# machine's label, or any ssh host. Without NAME: the machine Herdr's window
# shows, else the only machine there is. False (with the reason on stderr)
# when it names nothing usable.
_agents_machine() {
    local name="${1:-}" label target sel list n=0
    list="$(_agents_machines)"
    _AGENTS_M_LABEL="" _AGENTS_M_TARGET=""
    while IFS=$'\t' read -r label target sel; do
        [[ -n "$label" ]] || continue
        n=$((n + 1))
        if [[ -n "$name" ]]; then
            [[ "$label" == "$name" || "$target" == "$name" ]] || continue
        else
            [[ "$sel" == 1 ]] || continue
        fi
        _AGENTS_M_LABEL="$label" _AGENTS_M_TARGET="$target"
        return 0
    done <<<"$list"
    if [[ -z "$name" ]]; then
        if [[ $n -eq 1 ]]; then
            IFS=$'\t' read -r _AGENTS_M_LABEL _AGENTS_M_TARGET _ <<<"$list"
            return 0
        fi
        echo "agents: which machine? ($(printf '%s' "$list" | cut -f1 | tr '\n' ' ' | sed 's/ $//'))" >&2
        return 1
    fi
    if ! _agents_target_ok "$name"; then
        echo "agents: '$name' is not a machine or an ssh host" >&2
        return 1
    fi
    _agents_label _AGENTS_M_LABEL "$name"
    _AGENTS_M_TARGET="$name"
}

# _agents_open_local WHAT — hand a URL or a file to the desktop (open,
# xdg-open; a test names a stand-in). False where there is no desktop.
_agents_open_local() {
    local o=""
    if [[ -n "${AGENTS_TESTING:-}" ]]; then o="${AGENTS_OPEN:-}"
    elif command -v open >/dev/null 2>&1 && [[ "$(uname -s)" == Darwin ]]; then o=open
    elif command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then o=xdg-open
    fi
    [[ -n "$o" ]] || return 1
    "$o" "$1" >/dev/null 2>&1
}

# _agents_ports_local — "PORT<TAB>PID<TAB>COMMAND<TAB>CWD" for each TCP port
# one of your processes listens on here, by port. A port one of `agents
# forward`'s tunnels holds is not a server of this machine: left out.
_agents_ports_local() {
    local lines pids fwd
    lines="$(_agents_listeners 2>/dev/null)" || true
    [[ -n "$lines" ]] || return 0
    pids="$(printf '%s\n' "$lines" | cut -d' ' -f1 | LC_ALL=C sort -un | tr '\n' ' ')"
    pids="${pids% }"
    fwd="$(_agents_forward_records | cut -f1 | tr '\n' ' ')"
    # shellcheck disable=SC2086  # a list of pids
    {
        printf '%s\n' "$lines" | sed 's/^/L /'
        LC_ALL=C ps -o pid=,comm= -p ${pids// /,} 2>/dev/null | sed 's/^ */C /'
        _agents_cwds $pids 2>/dev/null | sed 's/^/W /'
    } | LC_ALL=C awk -v fwd=" $fwd" '
        $1 == "L" { port[++n] = $3; pid[n] = $2; next }
        $1 == "C" { p = $2; c = $0; sub(/^C +[0-9]+ +/, "", c); sub(/.*\//, "", c); comm[p] = c; next }
        $1 == "W" { split($0, f, "\t"); p = f[1]; sub(/^W /, "", p); cwd[p] = f[2]; next }
        END {
            for (i = 1; i <= n; i++) {
                if (index(fwd, " " port[i] " ") || port[i] !~ /^[0-9]+$/) continue
                printf "%s\t%s\t%s\t%s\n", port[i], pid[i], (comm[pid[i]] == "" ? "-" : comm[pid[i]]), (cwd[pid[i]] == "" ? "-" : cwd[pid[i]])
            }
        }' | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -u
}

# The remote half of a port list: that machine's `agents ports --tsv`, and
# where agents isn't installed or is too old to know `ports`, the bare
# listening ports (ss, then lsof).
# shellcheck disable=SC2016  # the remote shell expands it
_AGENTS_PORTS_REMOTE='a="$HOME/.local/bin/agents"; if [ -x "$a" ] && "$a" ports --tsv 2>/dev/null; then exit 0; fi
if command -v ss >/dev/null 2>&1; then ss -Hltn 2>/dev/null | awk '"'"'{ p = $4; sub(/.*:/, "", p); if (!s[p]++) print p "\t-\t-\t-" }'"'"'
else lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '"'"'NR > 1 { p = $9; sub(/.*:/, "", p); if (!s[p]++) print p "\t" $2 "\t" $1 "\t-" }'"'"'; fi'

# _agents_ports_all [NAME] — "MACHINE<TAB>PORT<TAB>PID<TAB>COMMAND<TAB>CWD<TAB>URL"
# for this machine ("local") and each machine (or only NAME), asked at the
# same time, each given 10 s. URL is where a forward already brings that port
# here, "-" otherwise. A machine that did not answer gives one row with port
# "-" and the reason as its command.
_agents_ports_all() {
    local only="${1:-}" label target dir f port pid comm cwd recs url
    dir="$(mktemp -d "${TMPDIR:-/tmp}/agents-ports.XXXXXX")" || return 1
    if [[ -z "$only" || "$only" == local ]]; then
        _agents_ports_local > "$dir/0.local" &
    fi
    if [[ "$only" != local ]]; then
        if [[ -n "$only" ]]; then
            _agents_machine "$only" || { rm -rf "$dir"; return 1; }
            printf '%s\t%s\n' "$_AGENTS_M_LABEL" "$_AGENTS_M_TARGET"
        else
            _agents_machines
        fi > "$dir/machines"
        while IFS=$'\t' read -r label target _; do
            [[ -n "$label" ]] || continue
            ( _agents_timeout 10 _agents_ssh_mux "$target" "$_AGENTS_PORTS_REMOTE" > "$dir/1.$label" 2>/dev/null \
                || printf -- '-\t-\tno answer (ssh %s)\t-\n' "$target" > "$dir/1.$label" ) &
        done < "$dir/machines"
    fi
    wait
    recs="$(_agents_forward_records)"
    for f in "$dir"/[01].*; do
        [[ -f "$f" ]] || continue
        label="${f##*/[01].}"
        # Another machine wrote these rows: only a port and a pid of digits,
        # and no control character, reach your terminal; what follows the
        # fourth field is dropped.
        while IFS=$'\t' read -r port pid comm cwd _; do
            [[ "$port" =~ ^[0-9]{1,5}$|^-$ ]] || continue
            [[ "$pid" =~ ^[0-9]{1,10}$ ]] || pid=-
            comm="${comm//[[:cntrl:]]/}" cwd="${cwd//[[:cntrl:]]/}"
            url="$(printf '%s\n' "$recs" | awk -F '\t' -v l="$label" -v p="$port" '$2 == l && $4 == p { print "http://localhost:" $1; exit }')"
            [[ "$label" != local || "$port" == - ]] || url="http://localhost:$port"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$port" "${pid:--}" "${comm:--}" "${cwd:--}" "${url:--}"
        done < "$f"
    done
    rm -rf "$dir"
}

# agents_ports [--tsv | --pick | --go MACHINE PORT] [MACHINE|local]
#   what listens where: this machine and your others. --tsv: this machine
#   only, for another machine's `agents ports` to read. --pick: the list in
#   fzf (enter opens the port in your browser, forwarding it first when it
#   is remote). --go: that one action.
agents_ports() {
    local a mode=table name=""
    while [[ $# -gt 0 ]]; do
        a="$1"; shift
        case "$a" in
            --tsv)  mode=tsv ;;
            --pick) mode=pick ;;
            --list) mode=list ;;
            --go)   [[ $# -eq 2 ]] || { echo "usage: agents ports --go MACHINE PORT" >&2; return 2; }
                    _agents_ports_go "$1" "$2"; return ;;
            -*)     echo "usage: agents ports [--pick] [MACHINE|local]" >&2; return 2 ;;
            *)      [[ -z "$name" ]] || { echo "usage: agents ports [--pick] [MACHINE|local]" >&2; return 2; }
                    name="$a" ;;
        esac
    done
    case "$mode" in
        tsv)  _agents_ports_local ;;
        list) _agents_ports_all "$name" | _agents_ports_table ;;
        pick) _agents_ports_pick "$name" ;;
        *)    local out
              out="$(_agents_ports_all "$name")" || return 1
              if [[ -z "$out" ]]; then echo "nothing of yours is listening"; return 0; fi
              printf '%s\n' "$out" | _agents_ports_table | cut -f3- ;;
    esac
}

# _agents_ports_table — the rows of _agents_ports_all as the list: MACHINE and
# PORT (for fzf's {1} {2}), then one aligned line, under a header.
_agents_ports_table() {
    LC_ALL=C awk -F '\t' -v home="$HOME" '
        { m[NR] = $1; p[NR] = $2; c[NR] = $4; w[NR] = $5; u[NR] = $6
          if (home != "" && index(w[NR], home) == 1) w[NR] = "~" substr(w[NR], length(home) + 1)
          if (length($1) > lm) lm = length($1); if (length($4) > lc) lc = length($4) }
        END {
            if (lm < 7) lm = 7; if (lc < 7) lc = 7; if (lc > 28) lc = 28
            fmt = "%-" lm "s  %5s  %-" lc "s  %-24s  %s\n"   # no %-*s: not every awk has it
            printf "-\t-\t" fmt, "MACHINE", "PORT", "COMMAND", "OPEN AT", "CWD"
            for (i = 1; i <= NR; i++)
                printf "%s\t%s\t" fmt, m[i], p[i], m[i], p[i], substr(c[i], 1, lc), u[i], w[i]
        }'
}

# _agents_ports_go MACHINE PORT — open that port in your browser. A local
# port goes through agents_link_click: on a machine someone is attached to
# from elsewhere, that is their browser, through a tunnel.
_agents_ports_go() {
    [[ "$2" =~ ^[0-9]{1,5}$ ]] || { echo "agents: not a port: $2" >&2; return 2; }
    if [[ "$1" == local ]]; then
        agents_link_click "http://localhost:$2"
    else
        agents_forward open "$1" "$2"
    fi
}

_agents_ports_pick() {
    local a list
    if ! command -v "$(_agents_fzf)" >/dev/null 2>&1; then
        echo "agents: ports --pick needs fzf; here is the list" >&2
        agents_ports ${1:+"$1"}
        return
    fi
    a="$(printf '%q' "$AGENTS_PATH")"
    list="$a ports --list${1:+ $(printf '%q' "$1")}"
    _agents_ports_all "${1:-}" | _agents_ports_table | SHELL="${BASH:-/bin/bash}" "$(_agents_fzf)" \
        --delimiter "$(printf '\t')" --with-nth '3..' --header-lines 1 --layout reverse --no-sort \
        --prompt 'ports> ' \
        --header 'enter open in browser · ctrl-x close its forward · ctrl-r reload · esc quit' \
        --bind "enter:execute($a ports --go {1} {2}; sleep 1)+reload-sync($list)" \
        --bind "ctrl-x:execute-silent($a forward close {1} {2})+reload-sync($list)" \
        --bind "ctrl-r:reload-sync($list)" >/dev/null
    return 0
}

# _agents_push_one FILE — copy FILE into the drop folder of the machine in
# _AGENTS_M_LABEL and _AGENTS_M_TARGET, under its own name with only
# [A-Za-z0-9._-] kept, and print where it landed there. False, with the
# reason on stderr, when it did not.
_agents_push_one() {
    local f="$1" base dest out
    if [[ ! -f "$f" || ! -r "$f" ]]; then
        echo "agents: not a readable file: $f" >&2; return 1
    fi
    base="${f##*/}"; base="${base//[^A-Za-z0-9._-]/_}"; base="${base#.}"
    [[ -n "$base" ]] || base="file"
    # shellcheck disable=SC2016  # the remote shell expands $HOME
    dest='"$HOME/.cache/tuidev/drop"'
    if out="$(_agents_ssh "$_AGENTS_M_TARGET" "umask 077; mkdir -p $dest && cat > $dest/$base && printf '%s\n' $dest/$base" < "$f" 2>&1)" \
        && [[ "$out" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
        printf '%s\n' "$out"
    else
        echo "agents: could not copy $f to $_AGENTS_M_LABEL: ${out:-no answer}" >&2; return 1
    fi
}

# agents_push [-m MACHINE] FILE... — copy files to a machine's drop folder
# (~/.cache/tuidev/drop there) and print where each landed, one path a line;
# on a terminal the paths also go to the clipboard, ready to paste into a
# pane on that machine. MACHINE defaults as _agents_machine's.
agents_push() {
    local name="" files=() f out paths="" rc=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--machine) [[ $# -ge 2 ]] || { echo "usage: agents push [-m MACHINE] FILE..." >&2; return 2; }
                          name="$2"; shift 2 ;;
            --) shift; while [[ $# -gt 0 ]]; do files+=("$1"); shift; done ;;
            -*) echo "usage: agents push [-m MACHINE] FILE..." >&2; return 2 ;;
            *)  files+=("$1"); shift ;;
        esac
    done
    [[ ${#files[@]} -gt 0 ]] || { echo "usage: agents push [-m MACHINE] FILE..." >&2; return 2; }
    _agents_machine "$name" || return 1
    for f in "${files[@]}"; do
        if out="$(_agents_push_one "$f")"; then
            printf '%s\n' "$out"
            paths+="${paths:+ }$(_agents_quote "$out")"
        else
            rc=1
        fi
    done
    if [[ -n "$paths" && -t 1 ]] && command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$paths" | pbcopy && echo "(copied: paste into a pane on $_AGENTS_M_LABEL)" >&2
    fi
    return "$rc"
}

# _agents_open_ext PATH — true when PATH's extension is one a viewer shows.
_agents_open_ext() {
    local ext="${1##*.}" e
    [[ "$1" == *.* ]] || return 1
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
    for e in $_AGENTS_OPEN_EXTS; do [[ "$e" == "$ext" ]] && return 0; done
    return 1
}

# agents_remote_open [--no-open] MACHINE PATH — fetch one file from a machine
# into $AGENTS_DATA_DIR/remote/MACHINE/ and open it here; prints the local
# path. PATH is absolute, of plain characters, and at most 50 MB; only a
# format a viewer shows is opened (the rest is fetched and left).
agents_remote_open() {
    local noopen=false
    [[ "${1:-}" != --no-open ]] || { noopen=true; shift; }
    [[ $# -eq 2 ]] || { echo "usage: agents open [--no-open] MACHINE /PATH" >&2; return 2; }
    _agents_machine "$1" || return 1
    _agents_remote_fetch_open "$2" "$noopen"
}

# _agents_remote_fetch_open PATH [NOOPEN] — the same, for the machine in
# _AGENTS_M_LABEL and _AGENTS_M_TARGET.
_agents_remote_fetch_open() {
    local path="$1" noopen="${2:-false}" dir dest size q rc
    if [[ ! "$path" =~ ^/[A-Za-z0-9._\ @+,=/~-]+$ || "$path" == */ ]]; then
        echo "agents: need an absolute file path of plain characters, got: $path" >&2; return 2
    fi
    dir="$AGENTS_DATA_DIR/remote/$_AGENTS_M_LABEL"
    if ! { mkdir -p "$dir" && chmod 700 "$AGENTS_DATA_DIR/remote"; } 2>/dev/null; then
        echo "agents: can't write $dir" >&2; return 1
    fi
    dest="${path##*/}"; dest="$dir/${dest//[^A-Za-z0-9._-]/_}"
    q="$(_agents_quote "$path")"
    # The cap is applied here, not trusted to the other machine: head stops
    # reading at one byte past it, whatever is sent, and the fetch is given
    # two minutes. stdin is /dev/null: a caller may be reading its own.
    _agents_timeout 120 _agents_ssh "$_AGENTS_M_TARGET" "[ -f $q ] && cat < $q" 2>/dev/null \
        | head -c $((_AGENTS_OPEN_MAX + 1)) > "$dest.part"
    rc="${PIPESTATUS[0]}"
    size="$(wc -c < "$dest.part" | tr -d ' ')"
    if [[ "$size" -gt "$_AGENTS_OPEN_MAX" ]]; then
        rm -f "$dest.part"
        echo "agents: $path is larger than $((_AGENTS_OPEN_MAX / 1048576)) MB: not fetched" >&2; return 1
    fi
    if [[ "$rc" -ne 0 ]]; then
        rm -f "$dest.part"
        echo "agents: could not read $path on $_AGENTS_M_LABEL" >&2; return 1
    fi
    chmod 600 "$dest.part" && mv -f "$dest.part" "$dest" || return 1
    printf '%s\n' "$dest"
    [[ "$noopen" == false ]] || return 0
    if ! _agents_open_ext "$dest"; then
        echo "agents: fetched, not opened (only: $_AGENTS_OPEN_EXTS)" >&2; return 0
    fi
    _agents_open_local "$dest" || echo "agents: fetched; nothing here opens it" >&2
}
