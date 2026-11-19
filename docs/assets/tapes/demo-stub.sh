#!/bin/bash
# Multi-call stub for the screenshot demo (docs/assets/tapes/README.md).
# bin/agents (the demo wrapper) puts symlinks named ps, lsof, launchctl,
# sysctl, memory_pressure, pmset, notifyutil and herdr to this file first on
# PATH, so `agents` reads the fixtures in fixtures/ instead of this machine.
# @HOME@ in a fixture becomes $HOME, the demo's throwaway home.
set -eo pipefail

FIX="${DEMO_FIXTURES:?DEMO_FIXTURES is not set: run the demo through docs/assets/tapes/bin/agents}"

# With DEMO_HOG=1 (clip-hog.tape), the hog/ fixtures add a runaway test to
# the table and its working directory to cwds.tsv.
fixture() {
    { cat "$FIX/$1"; [[ -z "${DEMO_HOG:-}" || ! -f "$FIX/hog/$1" ]] || cat "$FIX/hog/$1"; } | sed "s|@HOME@|$HOME|g"
}

# ps axww -o ...: the whole table. ps -o FIELDS -p PIDS: those columns
# (pid, stat, etime and lstart are the ones bin/agents asks for by pid).
stub_ps() {
    local fields="" pids="" a
    while [[ $# -gt 0 ]]; do
        a="$1"; shift
        case "$a" in
            axww) fixture ps.txt; return 0 ;;
            -o) fields="${1:-}"; shift ;;
            -p) pids="${1:-}"; shift ;;
        esac
    done
    [[ -n "$pids" ]] || return 1
    fixture ps.txt | awk -v want=",$pids," -v fields="$fields" '
        index(want, "," $1 ",") {
            out = ""; n = split(fields, f, ",")
            for (i = 1; i <= n; i++) {
                if (f[i] == "pid=") out = out (out == "" ? "" : " ") $1
                else if (f[i] == "stat=") out = out (out == "" ? "" : " ") "S"
                else if (f[i] == "etime=") out = out (out == "" ? "" : " ") $8
                else if (f[i] == "lstart=") out = out (out == "" ? "" : " ") $9 " " $10 " " $11 " " $12 " " $13
            }
            print out; found = 1
        }
        END { exit !found }'
}

# lsof -iTCP -sTCP:LISTEN -Fpn: listeners. (Working directories come from the
# wrapper's own _agents_cwds, so no lsof cwd query reaches here.)
stub_lsof() {
    [[ " $* " == *" -iTCP "* ]] || return 1
    fixture listeners.txt | awk 'NF == 2 { print "p" $1; print "n*:" $2 }'
}

# herdr agent list: Herdr's JSON answer, from herdr.tsv. With DEMO_PANES=1
# (board.tape) each agent also has a pane and a task title (panes.tsv, a line
# an agent, in herdr.tsv's order: PANE, PID, TITLE), `herdr pane process-info`
# says which pane holds a pid, and `herdr pane read` prints that pane's
# made-up screen (panes/PANE.txt, ":" as "-").
stub_herdr() {
    local pane
    case "${1:-} ${2:-}" in
        "agent list")
            fixture herdr.tsv | awk -F '\t' -v panes="${DEMO_PANES:+$FIX/panes.tsv}" '
                BEGIN {
                    while (panes != "" && (getline l < panes) > 0) { split(l, f, "\t"); id[++k] = f[1]; title[k] = f[3] }
                    printf "{\"result\":{\"agents\":["
                }
                NF == 3 {
                    n++
                    printf "%s{\"agent\":\"%s\",\"agent_status\":\"%s\",\"cwd\":\"%s\"", (n > 1 ? "," : ""), $1, $2, $3
                    if (n in id) printf ",\"pane_id\":\"%s\",\"terminal_title_stripped\":\"%s\"", id[n], title[n]
                    printf "}"
                }
                END { print "]}}" }' ;;
        "pane process-info")
            [[ -n "${DEMO_PANES:-}" && "${3:-}" == --pane ]] || return 1
            awk -F '\t' -v p="${4:-}" '$1 == p { printf "{\"result\":{\"process_info\":{\"shell_pid\":%d,\"foreground_processes\":[{\"pid\":%d}]}}}\n", $2, $2; found = 1 }
                END { exit !found }' "$FIX/panes.tsv" ;;
        "pane read")
            pane="${3:-}"
            [[ -n "${DEMO_PANES:-}" && "$pane" =~ ^[A-Za-z0-9:_-]+$ && -r "$FIX/panes/${pane//:/-}.txt" ]] || return 1
            cat "$FIX/panes/${pane//:/-}.txt" ;;
        *) return 1 ;;
    esac
}

# top -l 1 -stats pid,mem [-o mem -n N | -pid PID...]: each process's MEM
# (macOS's footprint, what `agents mem` reads), here its RSS from ps.txt,
# biggest first.
stub_top() {
    local n=0 pids="" a
    while [[ $# -gt 0 ]]; do
        a="$1"; shift
        case "$a" in
            -n) n="${1:-0}"; shift ;;
            -pid) pids="$pids,${1:-}"; shift ;;
        esac
    done
    printf 'Processes: demo\n\nPID    MEM\n'
    fixture ps.txt | awk -v want="$pids," '$1 ~ /^[0-9]+$/ && (want == "," || index(want, "," $1 ",")) { print $1, $6 }' \
        | sort -k2,2nr | awk -v n="$n" 'n == 0 || NR <= n { printf "%-6s %dK\n", $1, $2 }'
}

stub_pmset() {
    case "${1:-} ${2:-}" in
        "-g batt")       printf "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1234567)\t86%%; charging; 0:41 remaining present: true\n" ;;
        "-g assertions") printf 'Assertion status system-wide:\n   PreventUserIdleSystemSleep    1\nListed by owning process:\n' ;;
        "-g ")           printf 'System-wide power settings:\nCurrently in use:\n lowpowermode         0\n powermode            0\n' ;;
    esac
}

case "$(basename "$0")" in
    ps)              stub_ps "$@" ;;
    lsof)            stub_lsof "$@" ;;
    herdr)           stub_herdr "$@" ;;
    pmset)           stub_pmset "$@" ;;
    top)             stub_top "$@" ;;
    launchctl)       printf 'PID\tStatus\tLabel\n' ;;
    sysctl)          printf '12\n1\n{ 3.84 3.51 3.20 }\n' ;;
    memory_pressure) echo "System-wide memory free percentage: 41%" ;;
    notifyutil)      echo "com.apple.system.thermalpressurelevel 0" ;;
    *)               echo "demo-stub: no stub for $(basename "$0")" >&2; exit 1 ;;
esac
