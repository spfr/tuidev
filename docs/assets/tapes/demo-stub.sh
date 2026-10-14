#!/bin/bash
# Multi-call stub for the screenshot demo (docs/assets/tapes/README.md).
# bin/agents (the demo wrapper) puts symlinks named ps, lsof, launchctl,
# sysctl, memory_pressure, pmset, notifyutil and herdr to this file first on
# PATH, so `agents` reads the fixtures in fixtures/ instead of this machine.
# @HOME@ in a fixture becomes $HOME, the demo's throwaway home.
set -eo pipefail

FIX="${DEMO_FIXTURES:?DEMO_FIXTURES is not set: run the demo through docs/assets/tapes/bin/agents}"

fixture() { sed "s|@HOME@|$HOME|g" "$FIX/$1"; }

# ps axww -o ...: the whole table. ps -o FIELDS -p PIDS: those columns
# (pid and lstart are the only ones bin/agents asks for by pid).
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
                else if (f[i] == "lstart=") out = out (out == "" ? "" : " ") $9 " " $10 " " $11 " " $12 " " $13
            }
            print out; found = 1
        }
        END { exit !found }'
}

# lsof -iTCP -sTCP:LISTEN -Fpn: listeners. lsof -a -d cwd -Fpn -p PIDS: cwds.
stub_lsof() {
    local pids="" listen=0 a
    while [[ $# -gt 0 ]]; do
        a="$1"; shift
        case "$a" in
            -iTCP) listen=1 ;;
            -p) pids="${1:-}"; shift ;;
        esac
    done
    if [[ $listen == 1 ]]; then
        fixture listeners.txt | awk 'NF == 2 { print "p" $1; print "n*:" $2 }'
    else
        fixture cwds.tsv | awk -F '\t' -v want=",$pids," 'index(want, "," $1 ",") { print "p" $1; print "n" $2 }'
    fi
}

# herdr agent list: Herdr's JSON answer, from herdr.tsv.
stub_herdr() {
    [[ "${1:-} ${2:-}" == "agent list" ]] || return 1
    fixture herdr.tsv | awk -F '\t' '
        BEGIN { printf "{\"result\":{\"agents\":[" }
        NF == 3 { printf "%s{\"agent\":\"%s\",\"agent_status\":\"%s\",\"cwd\":\"%s\"}", (n++ ? "," : ""), $1, $2, $3 }
        END { print "]}}" }'
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
    launchctl)       printf 'PID\tStatus\tLabel\n' ;;
    sysctl)          printf '12\n1\n{ 3.84 3.51 3.20 }\n' ;;
    memory_pressure) echo "System-wide memory free percentage: 41%" ;;
    notifyutil)      echo "com.apple.system.thermalpressurelevel 0" ;;
    *)               echo "demo-stub: no stub for $(basename "$0")" >&2; exit 1 ;;
esac
