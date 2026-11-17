# shellcheck shell=bash
# lib/agents/map.sh — `agents map`: what runs where, on every machine, and
# one key to go there or stop it.
#
# One list for this machine and your others, grouped by what you would do
# with a thing, not by where it is: previews and dev servers first (what was
# started to be looked at), then what was left behind, then the sessions
# (one line each), then the machines. In fzf:
#   enter   go: your session's pane (here), a peek at it (elsewhere), a
#           server or forward in your browser
#   ctrl-k  (or ctrl-x, or delete) stop what is under the cursor: a process tree (agents kill: its
#           refusals and its y/N question, on the machine that runs it), a
#           server's process, or a forward
#   ctrl-s  sweep that machine: agents reap (stale trees), asked first
#   ctrl-p  peek at its pane · ctrl-e what each session runs · ctrl-r reload
# The other machines answer `agents map --rows` over ssh; one without it is
# listed as needing tuidev. What they send is text: an id is used only when
# it has the shape of one, and no control character reaches the terminal.
#
# Owns: `agents map`, its rows, list, actions and preview.
# Uses: config.sh, util.sh, snapshot.sh (agents_collect), pick.sh
#   (_agents_pick_list, _agents_fzf), remote.sh (machines, ssh, ports),
#   forward.sh, link.sh (agents_link_click), system.sh (agents_system),
#   kill.sh/reap.sh/where.sh through agents_main.
# Public: agents_map.

# A process id as a list carries it: PID or PID@START.
_AGENTS_MAP_ID_RE='^[0-9]{1,10}(@[A-Za-z0-9_:+.-]{1,48})?$'
# shellcheck disable=SC2016  # the remote shell expands $HOME
_AGENTS_MAP_REMOTE='a="$HOME/.local/bin/agents"; [ -x "$a" ] && "$a" map --rows 2>/dev/null || printf "sys\tneeds tuidev there (./install.sh --pack monitoring)\n"'

# A file a row may name: absolute, of plain characters (remote.sh's fetch
# takes the same), as an ERE both bash and awk read.
_AGENTS_MAP_PATH_RE='^/[A-Za-z0-9._ @+,=/~-]+$'
_AGENTS_MAP_FILES_TAIL=2097152   # bytes of a transcript read for the files it wrote

# _agents_map_files < RECORDS — "file<TAB>PATH<TAB>SESSION" for what the
# sessions here wrote lately and a viewer shows: from the last 2 MiB of each
# Claude Code transcript (a few long command outputs fill less, so a file
# written before them is still found), the files its Write and Edit calls
# named, newest first, that still exist, changed in the last
# day; five a session. Nothing without jq.
_agents_map_files() {
    local pid kind age name tx key val f n seen
    command -v jq >/dev/null 2>&1 || return 0
    while IFS=$'\t' read -r pid kind age name; do
        [[ "$kind" == claude && "$pid" =~ ^[0-9]+$ ]] || continue
        tx=""
        while IFS=$'\t' read -r key val; do [[ "$key" != transcript ]] || tx="$val"; done < <(_agents_session_of "$pid" "$kind" "$age")
        [[ -n "$tx" && -r "$tx" ]] || continue
        n=0 seen=$'\n'
        while IFS= read -r f; do
            if [[ ! "$f" =~ $_AGENTS_MAP_PATH_RE ]] || ! _agents_open_ext "$f"; then continue; fi
            case "$seen" in *$'\n'"$f"$'\n'*) continue ;; esac
            seen+="$f"$'\n'
            [[ -f "$f" && -n "$(find "$f" -maxdepth 0 -mtime -1 2>/dev/null)" ]] || continue
            printf 'file\t%s\t%s\n' "$f" "${name:--}"
            n=$((n + 1)); [[ $n -lt 5 ]] || break
        done < <(tail -c "$_AGENTS_MAP_FILES_TAIL" "$tx" 2>/dev/null | sed 1d \
            | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and (.name == "Write" or .name == "Edit" or .name == "NotebookEdit")) | .input.file_path // .input.notebook_path // empty' 2>/dev/null \
            | awk '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) print l[i] }')
    done < <(awk -F '\t' '$1 == "agent" { print $2 "\t" $3 "\t" $4 "\t" ($15 == "" ? "-" : $15) }')
}

# _agents_map_rows — this machine, as rows another machine can read:
#   sys<TAB>SUMMARY
#   proc<TAB>PID@START<TAB>LINE          (agents pick's rows, in its order)
#   port<TAB>PORT<TAB>PID<TAB>COMMAND<TAB>CWD   (listeners with a project
#       directory: a dev server, not a system service at /)
#   file<TAB>PATH<TAB>SESSION            (_agents_map_files)
_agents_map_rows() {
    local r list _load cores memfree _level _batt _state na=0 ns=0 cpu line pid tok
    r="$(AGENTS_HERDR_MODE=async agents_collect)" || return 1
    # AGENTS_MAP_ROOT=DIR (the environment only; the screencast's fleet sets
    # it, docs/assets/tapes/remote-demo.sh): only what runs under DIR, so a
    # recording of a throwaway home never lists the sessions of the person
    # recording it.
    local root="${AGENTS_MAP_ROOT:-}"
    [[ "$root" == /* ]] || root=""
    if [[ -n "$root" ]]; then
        r="$(printf '%s\n' "$r" | awk -F '\t' -v root="${root%/}" '
            function under(p) { return p == root || index(p, root "/") == 1 }
            { l[NR] = $0; if ($1 == "agent" && under($13)) keep[$2] = 1 }
            END { for (i = 1; i <= NR; i++) { split(l[i], f, "\t")
                    if (f[1] == "agent") { if (keep[f[2]]) print l[i] }
                    else if (f[1] == "act") { if (keep[f[11]]) print l[i] }
                    else if (f[1] == "stale" || f[1] == "hog") { if (under(f[13])) print l[i] }
                    else print l[i] } }')"
    fi
    IFS=$'\t' read -r _load cores memfree _level _batt _state <<<"$(agents_system)"
    cpu="$(_agents_cpu_pct "$cores" "$r" 2>/dev/null)"
    na="$(printf '%s\n' "$r" | awk -F '\t' '$1 == "agent" && $3 != "daemon" { n++ } END { print n + 0 }')"
    ns="$(printf '%s\n' "$r" | awk -F '\t' '$1 == "stale" { n++ } END { print n + 0 }')"
    printf 'sys\tcpu %s%% · memory %s%% free · %s session%s · %s left behind\n' \
        "${cpu:--}" "${memfree:--}" "$na" "$([[ "$na" == 1 ]] || echo s)" "$ns"
    list="$(printf '%s\n' "$r" | _agents_awk "lib_fmt pick" -v home="$HOME")"
    while IFS=$'\t' read -r pid tok line; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        printf 'proc\t%s\t%s\n' "$tok" "$line"
    done <<<"$list"
    printf '%s\n' "$r" | _agents_map_files
    # A dev server: not a session's own port (the agent CLIs listen for
    # their tools), not an app or a system service (AGENTS_SYSTEM_PATTERN, by
    # its binary's path), and started in a project directory (not / and not
    # your home directory, where daemons live).
    local ports pids paths
    ports="$(_agents_ports_local)"
    [[ -n "$ports" ]] || return 0
    pids="$(printf '%s\n' "$ports" | cut -f2 | LC_ALL=C sort -un | tr '\n' ',')"
    paths="$(LC_ALL=C ps -o pid=,comm= -p "${pids%,}" 2>/dev/null)"
    { printf '%s\n' "$r" | awk -F '\t' '$1 == "agent" { print "A\t" $2 }'
      printf '%s\n' "$paths" | sed 's/^ *\([0-9][0-9]*\) */B\t\1\t/'
      printf '%s\n' "$ports" | sed 's/^/P\t/'
    } | _AGENTS_SYS="$AGENTS_SYSTEM_PATTERN" _AGENTS_ROOT="${root%/}" LC_ALL=C awk -F '\t' '
        $1 == "A" { agent[$2] = 1; next }
        $1 == "B" { if ($3 ~ ENVIRON["_AGENTS_SYS"]) sys[$2] = 1; next }
        $1 == "P" && ENVIRON["_AGENTS_ROOT"] != "" && $5 != ENVIRON["_AGENTS_ROOT"] && index($5, ENVIRON["_AGENTS_ROOT"] "/") != 1 { next }
        $1 == "P" && !agent[$3] && !sys[$3] && $5 != "/" && $5 != "-" && $5 != ENVIRON["HOME"] { print "port\t" $2 "\t" $3 "\t" $4 "\t" $5 }'
}

# _agents_map_all [MACHINE|local] — every machine's rows, each prefixed with
# its label: this one first, the others in the machine list's order, asked at
# the same time and given 12 s; then "fwd" rows for the forwards open here.
_agents_map_all() {
    local only="${1:-}" dir label target f l lab tgt rp e now state
    dir="$(mktemp -d "${TMPDIR:-/tmp}/agents-map.XXXXXX")" || return 1
    if [[ -z "$only" || "$only" == local ]]; then
        _agents_map_rows > "$dir/0.local" 2>/dev/null &
    fi
    if [[ "$only" != local ]]; then
        if [[ -n "$only" ]]; then
            _agents_machine "$only" || { rm -rf "$dir"; return 1; }
            printf '%s\t%s\n' "$_AGENTS_M_LABEL" "$_AGENTS_M_TARGET"
        else
            _agents_machines
        fi > "$dir/machines"
        local i=0
        while IFS=$'\t' read -r label target _; do
            [[ -n "$label" ]] || continue
            i=$((i + 1))
            # (At most 2 MiB of rows from one machine.)
            ( _agents_timeout 12 _agents_ssh_mux "$target" "$_AGENTS_MAP_REMOTE" 2>/dev/null | head -c 2097152 > "$dir/$i.$label"
              [[ -s "$dir/$i.$label" ]] || printf 'sys\tno answer (ssh %s)\n' "$target" > "$dir/$i.$label" ) &
        done < "$dir/machines"
    fi
    wait
    for f in "$dir"/[0-9]*.*; do
        [[ -f "$f" ]] || continue
        label="${f##*/}"; label="${label#*.}"
        awk -v l="$label" '{ print l "\t" $0 }' "$f"
    done
    rm -rf "$dir"
    _agents_now now
    while IFS=$'\t' read -r l lab tgt rp e; do
        [[ -n "$l" ]] || continue
        if _agents_forward_alive "$l" "$tgt"; then state=active; else state=dead; fi
        printf 'local\tfwd\t%s\t%s\t%s\t%s\t%s\n' "$l" "$lab" "$rp" "$state" "$(( (now - e) / 60 ))"
    done < <(_agents_forward_records)
}

# _agents_map_list [--all] [MACHINE] — the list fzf shows, one line a thing:
#   MACHINE<TAB>KIND<TAB>ID<TAB>TEXT     KIND: head, proc, port, file, fwd
# in groups, by what you would do with it rather than by machine:
#   PREVIEWS AND DEV SERVERS   what was started to be looked at: each port,
#       its command and project, whether a session still owns it, and where
#       it opens (a forward already here is on its row)
#   FILES SESSIONS JUST WROTE  reports, pages and images, to open here
#   LEFT BEHIND                stale processes and hogs: nobody is using them
#   SESSIONS                   one line a session, with a count of what it
#       runs (--all lists those under it)
#   FORWARDS                   only those that lead to no server listed above
#   MACHINES                   each machine's CPU, memory and counts
# Rows from another machine keep only an id of the right shape and printable
# text. Bold and dim come from the terminal's own colors, none with NO_COLOR.
_agents_map_list() {
    local all=0 b="" d="" n=""
    if [[ "${1:-}" == --all ]]; then all=1; shift; fi
    if [[ -z "${NO_COLOR:-}" ]]; then b=$'\033[1m' d=$'\033[2m' n=$'\033[0m'; fi
    _agents_map_all "${1:-}" | LC_ALL=C awk -F '\t' -v home="$HOME" -v all="$all" -v B="$b" -v D="$d" -v N="$n" '
        # No control character: C0, DEL, and C1 as UTF-8 writes it (U+009B is
        # another spelling of ESC [).
        function clean(s) { gsub(/[[:cntrl:]]/, " ", s); gsub(/\302[\200-\237]/, " ", s); return s }
        function trim(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
        function tilde(p) { return (home != "" && index(p, home) == 1) ? "~" substr(p, length(home) + 1) : p }
        function group(title, hint) { printf "-\thead\t-\t%s%s%s  %s%s%s\n", B, title, N, D, hint, N }
        # A pick row: TYPE PID CPU% MEM AGE, two spaces, NAME (22 wide), WHAT.
        function parse(line,    t, rest) {
            P_child = (line ~ /^  /)
            split(trim(line), t, / +/)
            P_type = t[1]; P_pid = t[2]; P_cpu = t[3]; P_mem = t[4]; P_age = t[5]
            rest = line; sub(/^ *[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+  /, "", rest)
            P_name = trim(substr(rest, 1, 22)); P_what = trim(substr(rest, 24))
        }
        $2 == "sys"  { if (!($1 in mseen)) { mseen[$1] = 1; mo[++nm] = $1 } msys[$1] = clean($3); next }
        $2 == "proc" {
            if ($3 !~ /^[0-9]+(@[A-Za-z0-9_:+.-]+)?$/ || length($3) > 60) next
            line = clean($4); parse(line)
            pid = $3; sub(/@.*/, "", pid)
            cpu[$1, pid] = P_cpu; mem[$1, pid] = P_mem; age[$1, pid] = P_age
            if (P_child) {
                if (cur != "") { kids[cur]++; ktype[cur, P_type]++; kid[cur, kids[cur]] = $1 "\tproc\t" $3 "\t" sprintf("     %-12s %-8s %-16s %-9s %6s %6s %7s  %s", "", P_type, substr(P_name, 1, 16), "", P_cpu, P_mem, P_age, P_what) }
                owner[$1, pid] = curname
                next
            }
            if (P_type == "stale" || P_type == "hog") {
                cur = ""; curname = ""
                lb[++nl] = $1 "\tproc\t" $3 "\t" sprintf("   %-12s %-8s %-16s %6s %6s %7s  %s", $1, (P_type == "hog" ? "heavy" : "stale"), substr(P_name, 1, 16), P_cpu, P_mem, P_age, P_what)
                isstale[$1, pid] = (P_type == "stale")
                next
            }
            status = "-"; what = P_what
            if (what ~ / · /) { status = what; sub(/ · .*/, "", status) }
            cur = $1 SUBSEP $3; curname = P_type " " P_name
            se[++ns] = cur; sm[ns] = $1; sid[ns] = $3
            stext[ns] = sprintf("%-12s %-8s %-16s %-9s %6s %6s %7s", $1, P_type, substr(P_name, 1, 16), substr(status, 1, 9), P_cpu, P_mem, P_age)
            next
        }
        $2 == "port" {
            if ($3 !~ /^[0-9]+$/ || length($3) > 5) next
            np++; pm[np] = $1; pp[np] = $3
            ppid[np] = ($4 ~ /^[0-9]+$/ && length($4) <= 10) ? $4 : "-"
            pc[np] = clean($5); pw[np] = tilde(clean($6))
            next
        }
        $2 == "file" {
            if ($3 !~ /^\/[A-Za-z0-9._ @+,=\/~-]+$/ || length($3) > 400) next
            nfi++; fim[nfi] = $1; fip[nfi] = $3; fis[nfi] = clean($4)
            next
        }
        # A forward is a row of this machine only: one another machine sends
        # is no row, and each field has its shape.
        $2 == "fwd" {
            if ($1 != "local" || $3 !~ /^[0-9]+$/ || length($3) > 5 || $4 !~ /^[A-Za-z0-9._-]+$/ || $5 !~ /^[0-9]+$/ || length($5) > 5 || $6 !~ /^(active|dead)$/ || $7 !~ /^[0-9]+$/) next
            nf++; fl[nf] = $3; fm[nf] = $4; fr[nf] = $5; fs[nf] = $6; fa[nf] = $7; fwd[$4, $5] = nf
        }
        END {
            group("PREVIEWS AND DEV SERVERS", "enter opens it in your browser · ctrl-k stops it")
            if (!np) printf "-\thead\t-\t   %snone running%s\n", D, N
            else printf "-\thead\t-\t   %s%-12s %-7s %-10s %-16s %6s %6s %7s  %s%s\n", D, "MACHINE", "PORT", "COMMAND", "PROJECT", "CPU%", "MEM", "AGE", "OPENS AT", N
            for (i = 1; i <= np; i++) {
                m = pm[i]; k = m SUBSEP ppid[i]
                proj = pw[i]; sub(/.*\//, "", proj)
                if (m == "local") opens = "http://localhost:" pp[i]
                else if ((m, pp[i]) in fwd) { f = fwd[m, pp[i]]; used[f] = 1; opens = "http://localhost:" fl[f] (fs[f] == "active" ? "  (forwarded)" : "  (forward is dead)") }
                else opens = "enter: forward it here"
                note = (k in isstale && isstale[k]) ? "  · left behind" : ((k in owner && owner[k] != "") ? "  · by " owner[k] : "")
                printf "%s\tport\t%s:%s\t   %-12s %-7s %-10s %-16s %6s %6s %7s  %s%s\n", m, pp[i], ppid[i], m, ":" pp[i], substr(pc[i], 1, 10), substr(proj, 1, 16), cpu[k], mem[k], age[k], opens, note
            }
            if (nfi) {
                print "-\thead\t-\t"
                group("FILES SESSIONS JUST WROTE", "enter opens it on this machine (fetched first when it is elsewhere)")
                for (i = 1; i <= nfi; i++) {
                    base = fip[i]; sub(/.*\//, "", base)
                    printf "%s\tfile\t%s\t   %-12s %-28s %-16s %s\n", fim[i], fip[i], fim[i], substr(base, 1, 28), substr(fis[i], 1, 16), tilde(fip[i])
                }
            }
            print "-\thead\t-\t"
            group("LEFT BEHIND", "nobody is using these · ctrl-k stops one · ctrl-s sweeps its machine")
            if (!nl) printf "-\thead\t-\t   %snothing%s\n", D, N
            for (i = 1; i <= nl; i++) print lb[i]
            print "-\thead\t-\t"
            group("SESSIONS", "enter goes to it · ctrl-p peeks · ctrl-e lists what each runs")
            if (!ns) printf "-\thead\t-\t   %snone%s\n", D, N
            else printf "-\thead\t-\t   %s%-12s %-8s %-16s %-9s %6s %6s %7s  %s%s\n", D, "MACHINE", "AGENT", "PROJECT", "STATUS", "CPU%", "MEM", "AGE", "RUNS", N
            for (i = 1; i <= ns; i++) {
                c = se[i]; runs = ""
                if (ktype[c, "mcp"]) runs = runs ktype[c, "mcp"] " mcp"
                if (ktype[c, "tool"]) runs = runs (runs == "" ? "" : " · ") ktype[c, "tool"] " command" (ktype[c, "tool"] > 1 ? "s" : "")
                o = kids[c] - ktype[c, "mcp"] - ktype[c, "tool"]
                if (o > 0) runs = runs (runs == "" ? "" : " · ") o " other"
                printf "%s\tproc\t%s\t   %s  %s\n", sm[i], sid[i], stext[i], (runs == "" ? "-" : runs)
                if (all) for (j = 1; j <= kids[c]; j++) print kid[c, j]
            }
            for (i = 1; i <= nf; i++) if (!used[i]) orphan++
            if (orphan) {
                print "-\thead\t-\t"
                group("FORWARDS", "open here, to a port not listed above · ctrl-k closes one")
                for (i = 1; i <= nf; i++) if (!used[i])
                    printf "local\tfwd\t%s\t   %-12s %-7s %-34s %6sm  %s\n", fl[i], fm[i], ":" fr[i], "http://localhost:" fl[i], fa[i], fs[i]
            }
            print "-\thead\t-\t"
            group("MACHINES", "ctrl-s sweeps what sessions left behind on one")
            for (i = 1; i <= nm; i++) printf "%s\thead\t-\t   %-12s %s\n", mo[i], mo[i], msys[mo[i]]
        }'
}

# _agents_map_target MACHINE — set _AGENTS_M_TARGET for a list row's machine;
# false for "local" (this machine) and for a label that is no machine now.
_agents_map_target() {
    [[ "$1" != local && "$1" != - ]] || return 1
    _agents_machine "$1" 2>/dev/null
}

# _agents_map_remote [-t] MACHINE ARGS... — `agents ARGS` on MACHINE; -t gives
# it a terminal (its y/N question). ARGS are ids and words checked by the
# caller: nothing a row said reaches the remote shell unchecked.
_agents_map_remote() {
    local tty=()
    if [[ "$1" == -t ]]; then tty=(-t); shift; fi
    _agents_map_target "$1" || return 1
    shift
    # A command with a terminal gets a connection of its own: a session with
    # a terminal asked of the shared one can be refused (ssh then ends 255
    # with nothing said), and a question must not depend on it.
    # shellcheck disable=SC2016,SC2029  # $HOME is the remote's; the words are checked ids
    if [[ ${#tty[@]} -gt 0 ]]; then
        _agents_ssh -t "$_AGENTS_M_TARGET" '"$HOME/.local/bin/agents"' "$@"
        local rc=$?
        [[ $rc -ne 255 ]] || echo "agents: could not reach $_AGENTS_M_LABEL (ssh $_AGENTS_M_TARGET)" >&2
        return "$rc"
    fi
    # shellcheck disable=SC2016,SC2029
    _agents_ssh_mux "$_AGENTS_M_TARGET" '"$HOME/.local/bin/agents"' "$@"
}

# _agents_map_plain — another machine's output as plain text: no escape and
# no other control character but the newline and the tab, so nothing it
# prints can restyle, retitle or link this terminal.
_agents_map_plain() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

# _agents_map_act ACTION MACHINE KIND ID — one key's action on one row.
# shellcheck disable=SC2086  # $PAGER is a command line
_agents_map_act() {
    local act="$1" m="$2" kind="$3" id="$4" pid port
    case "$kind" in
        proc) [[ "$id" =~ $_AGENTS_MAP_ID_RE ]] || { echo "agents: not a process id: $id" >&2; return 2; } ;;
        port) [[ "$id" =~ ^([0-9]{1,5}):([0-9]{1,10}|-)$ ]] || { echo "agents: not a port: $id" >&2; return 2; }
              port="${BASH_REMATCH[1]}" pid="${BASH_REMATCH[2]}" ;;
        fwd)  [[ "$id" =~ ^[0-9]{1,5}$ ]] || { echo "agents: not a forward: $id" >&2; return 2; } ;;
        file) if [[ ! "$id" =~ $_AGENTS_MAP_PATH_RE ]] || ! _agents_open_ext "$id"; then
                  echo "agents: not a file a viewer shows: $id" >&2; return 2
              fi ;;
        head) ;;
        *)    echo "agents: unknown row kind: $kind" >&2; return 2 ;;
    esac
    case "$act:$kind" in
        go:proc)
            if [[ "$m" == local ]]; then agents_main jump "$id"
            else _agents_map_remote "$m" peek "$id" 60 2>&1 | _agents_map_plain | ${PAGER:-less -R}; fi ;;
        peek:proc)
            if [[ "$m" == local ]]; then agents_main peek "$id" 200 | ${PAGER:-less -R}
            else _agents_map_remote "$m" peek "$id" 200 2>&1 | _agents_map_plain | ${PAGER:-less -R}; fi ;;
        stop:proc)
            if [[ "$m" == local ]]; then agents_main kill "$id"
            else _agents_map_remote -t "$m" kill "$id"; fi ;;
        go:port|peek:port)   _agents_ports_go "$m" "$port" ;;
        stop:port)
            [[ "$pid" != - ]] || { echo "agents: that machine did not say which process holds :$port" >&2; return 1; }
            if [[ "$m" == local ]]; then agents_main kill "$pid"
            else _agents_map_remote -t "$m" kill "$pid"; fi ;;
        go:file|peek:file)
            if [[ "$m" == local ]]; then _agents_open_local "$id"
            else _agents_map_target "$m" && _agents_remote_fetch_open "$id" >/dev/null; fi ;;
        go:fwd|peek:fwd)     _agents_open_local "http://localhost:$id" ;;
        stop:fwd)            _agents_forward_close "$id" ;;
        sweep:*)
            if [[ "$m" == local ]]; then agents_main reap
            elif [[ "$m" != - ]]; then _agents_map_remote -t "$m" reap; fi ;;
        *) return 0 ;;
    esac
}

# _agents_map_preview MACHINE KIND ID — the right-hand pane.
_agents_map_preview() {
    local m="$1" kind="$2" id="$3"
    case "$kind" in
        proc)
            [[ "$id" =~ $_AGENTS_MAP_ID_RE ]] || return 0
            if [[ "$m" == local ]]; then agents_main show "${id%%@*}"
            else _agents_map_remote "$m" show "${id%%@*}" 2>&1 | _agents_map_plain; fi ;;
        port)
            [[ "$id" =~ ^([0-9]{1,5}):([0-9]{1,10}|-)$ ]] || return 0
            echo "A server listening on $m, port ${BASH_REMATCH[1]}."
            echo
            if [[ "$m" == local ]]; then echo "enter   open http://localhost:${BASH_REMATCH[1]}"
            else echo "enter   forward it here and open it in your browser"; fi
            echo "ctrl-k  stop the process that holds it (asked first)" ;;
        file)
            [[ "$id" =~ $_AGENTS_MAP_PATH_RE ]] || return 0
            echo "$id"
            echo
            if [[ "$m" == local ]]; then
                case "$id" in *.md|*.markdown|*.txt|*.log|*.json|*.csv|*.tsv|*.yaml|*.yml|*.toml|*.html|*.htm)
                    head -c 4000 "$id" 2>/dev/null | LC_ALL=C tr -d '\000-\010\013-\037' ;; esac
            else
                echo "enter   fetch it from $m and open it here"
            fi ;;
        fwd)
            echo "A forward: http://localhost:$id on this machine leads to another machine's port."
            echo
            echo "enter   open it in your browser"
            echo "ctrl-k  close it" ;;
        head)
            [[ "$m" != - ]] || return 0
            echo "$m"
            echo
            echo "ctrl-s  sweep: stop what sessions left behind there (agents reap; asked first)" ;;
    esac
}

# agents_map [MACHINE|local] — the browser. Also:
#   --rows                      this machine's rows (what the others ask for)
#   --list [MACHINE]            the list, as fzf gets it
#   --act ACTION MACHINE KIND ID, --preview MACHINE KIND ID   fzf's bindings
agents_map() {
    local a list list_all name=""
    case "${1:-}" in
        --rows)    _agents_map_rows; return ;;
        --list)    shift; _agents_map_list "$@"; return ;;
        --act)     [[ $# -eq 5 ]] || { echo "usage: agents map --act go|peek|stop|sweep MACHINE KIND ID" >&2; return 2; }
                   _agents_map_act "$2" "$3" "$4" "$5"; return ;;
        --preview) [[ $# -eq 4 ]] || return 2
                   _agents_map_preview "$2" "$3" "$4"; return ;;
        -*)        echo "usage: agents map [MACHINE|local]" >&2; return 2 ;;
        *)         name="${1:-}" ;;
    esac
    if [[ ! -t 1 ]] || ! command -v "$(_agents_fzf)" >/dev/null 2>&1; then
        [[ ! -t 1 ]] || echo "agents: map's browser needs fzf (brew install fzf); here is the list" >&2
        NO_COLOR=1 _agents_map_list "$name" | cut -f4-
        return
    fi
    a="$(printf '%q' "$AGENTS_PATH")"
    list="$a map --list${name:+ $(printf '%q' "$name")}"
    list_all="$a map --list --all${name:+ $(printf '%q' "$name")}"
    _agents_map_list "$name" | SHELL="${BASH:-/bin/bash}" "$(_agents_fzf)" \
        --delimiter "$(printf '\t')" --with-nth '4..' --ansi --layout reverse --no-sort --height 100% \
        --prompt 'map> ' \
        --header 'enter open/go · ctrl-k stop · ctrl-s sweep machine · ctrl-p peek · ctrl-e details · ctrl-r reload · esc quit' \
        --preview "$a map --preview {1} {2} {3}" --preview-window 'down,30%,wrap,border-top' \
        --bind "enter:execute($a map --act go {1} {2} {3})+reload-sync($list)" \
        --bind "ctrl-p:execute($a map --act peek {1} {2} {3})" \
        --bind "ctrl-k,ctrl-x,del:execute($a map --act stop {1} {2} {3}; printf '\\n[press any key] '; read -r -s -n 1)+reload-sync($list)" \
        --bind "ctrl-s:execute($a map --act sweep {1} {2} {3}; printf '\\n[press any key] '; read -r -s -n 1)+reload-sync($list)" \
        --bind "ctrl-e:reload-sync($list_all)" \
        --bind "ctrl-r:reload-sync($list)+refresh-preview" >/dev/null
    return 0
}
