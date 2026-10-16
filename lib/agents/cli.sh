# shellcheck shell=bash
# lib/agents/cli.sh — the `agents` command line.
#
# Owns: agents_main (options and the subcommand table), `agents cwd`, and
#   the terminal width.
# Uses: every other module.
# Public: agents_main, agents_token_cwd.

# agents_token_cwd PID@START — the working directory of exactly that process
# (refused when the pid is gone or now names another process). The menu
# passes only such tokens, never a path: paths are resolved here, at click time.
agents_token_cwd() {
    local pid start now c
    _agents_token "${1:-}" || { echo "usage: agents cwd PID@START" >&2; return 2; }
    pid="${BASH_REMATCH[1]}" start="${BASH_REMATCH[3]}"
    now="$(_agents_start "$pid")"
    [[ -n "$now" && "$now" == "$start" ]] || { echo "agents: pid $pid is gone or now names another process" >&2; return 1; }
    c="$(_agents_cwds "$pid" | cut -f2)"
    [[ "$c" == /* ]] || { echo "agents: no working directory for pid $pid" >&2; return 1; }
    printf '%s\n' "$c"
}

# _agents_term_cols — the terminal's width, 120 when there is none. Inside
# $( ) with stderr silenced, `tput cols` sees no terminal and answers 80.
_agents_term_cols() {
    local size
    size="$(stty size 2>/dev/null </dev/tty)"
    if [[ "$size" =~ ^[0-9]+\ ([0-9]+)$ && "${BASH_REMATCH[1]}" -gt 0 ]]; then echo "${BASH_REMATCH[1]}"; else echo 120; fi
}

# agents_main [COMMAND [ARGS...]] — the `agents` command. The run's options
# (AGENTS_DRY_RUN, AGENTS_YES…) and AGENTS_WIDTH are globals the other
# modules read.
# shellcheck disable=SC2034
agents_main() {
    local cmd="${1:-ls}"
    [[ $# -gt 0 ]] && shift
    AGENTS_DRY_RUN=false AGENTS_YES=false AGENTS_CONFIRM_GUI=false AGENTS_NOTIFY=false AGENTS_STUCK=false
    AGENTS_AUTO=false AGENTS_THROTTLE=false
    _agents_colors
    if [[ -t 1 ]]; then AGENTS_WIDTH="${COLUMNS:-$(_agents_term_cols)}"; else AGENTS_WIDTH=160; fi
    case "$cmd" in
        kill|reap|term)
            # As root every process is "yours": refuse rather than guess.
            if _agents_is_root; then
                echo "agents: refusing to $cmd as root; run it as yourself" >&2
                return 2
            fi
            local args=() a
            for a in "$@"; do
                case "$a" in
                    -n|--dry-run)  AGENTS_DRY_RUN=true ;;
                    -y|--yes)      AGENTS_YES=true ;;
                    --confirm-gui) AGENTS_CONFIRM_GUI=true ;;
                    --notify)      AGENTS_NOTIFY=true ;;
                    --stuck)       [[ "$cmd" == reap ]] || { echo "agents: --stuck is a reap option" >&2; return 2; }
                                   AGENTS_STUCK=true ;;
                    --auto|--throttle)
                                   [[ "$cmd" == reap ]] || { echo "agents: $a is a reap option" >&2; return 2; }
                                   if [[ "$a" == --auto ]]; then AGENTS_AUTO=true; else AGENTS_THROTTLE=true; fi ;;
                    -*)            echo "agents: unknown option $a" >&2; return 2 ;;
                    *)             args+=("$a") ;;
                esac
            done
            set -- ${args[@]+"${args[@]}"}
            ;;
    esac
    case "$cmd" in
        ls|list)  local r; _agents_awake_prime; r="$(agents_collect)" || return 1
                  printf '%s\n' "$r" | agents_render "agents stale hogs quiet"; echo; _agents_footer "$r" ;;
        ps)       [[ -z "${1:-}" || "$1" =~ ^[0-9]+$ ]] || { echo "usage: agents ps [PID]" >&2; return 2; }
                  local r; r="$(agents_collect)" || return 1
                  printf '%s\n' "$r" | AGENTS_FOCUS="${1:-}" agents_render "agents detail" ;;
        stale)    agents_collect | agents_render stale ;;
        hogs)     agents_collect | agents_render hogs ;;
        watch)    agents_watch "$@" ;;
        kill)     [[ $# -gt 0 ]] || { echo "usage: agents kill [-n] [-y] PID..." >&2; return 2; }
                  _AGENTS_EV_KIND="kill" agents_kill_tokens true "$@" ;;
        term)     [[ $# -gt 0 ]] || { echo "usage: agents term [-n] [-y] PID..." >&2; return 2; }
                  _AGENTS_EV_KIND="kill" agents_kill_tokens false "$@" ;;
        reap)     agents_reap ;;
        awake)    local aw=() a
                  for a in "$@"; do if [[ "$a" == --notify ]]; then AGENTS_NOTIFY=true; else aw+=("$a"); fi; done
                  agents_awake ${aw[@]+"${aw[@]}"} ;;
        thermal)  local lvl; lvl="$(agents_thermal_level)"
                  echo "thermal pressure: $(agents_thermal_name "${lvl:--}")${lvl:+ ($lvl)}"
                  echo "energy mode: $(agents_powermode)" ;;
        json)     local r; _agents_awake_prime; r="$(agents_collect)"
                  _agents_with_needs "$r" | agents_json ;;
        why)      agents_why "$@" ;;
        mcp)      agents_mcp "$@" ;;
        show)     agents_show "$@" ;;
        jump)     agents_jump "$@" ;;
        root-of)  agents_root_of "$@" ;;
        peek)     agents_peek "$@" ;;
        pick)     agents_pick "$@" ;;
        tsv)      agents_tsv ;;
        report)   agents_report "$@" ;;
        runs)     agents_runs "$@" ;;
        limits)   agents_limits "$@" ;;
        statusline) agents_statusline ;;   # Claude Code's statusLine: JSON on stdin
        sample)   agents_sample ;;
        config)   agents_config "$@" ;;
        cwd)      agents_token_cwd "$@" ;;
        copy-path) local c; c="$(agents_token_cwd "$@")" || return 1
                  printf '%s' "$c" | pbcopy ;;
        reveal)   local c; c="$(agents_token_cwd "$@")" || return 1
                  open -R "$c" ;;
        open-term) agents_open_term "$@" ;;
        _awake-loop) _agents_awake_loop ;;
        hook)     agents_hook "$@"; return 0 ;;   # Claude Code hooks: never fail
        -h|--help|help) agents_usage ;;
        *)        echo "agents: unknown command '$cmd' (agents --help)" >&2; return 2 ;;
    esac
}
