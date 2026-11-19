# shellcheck shell=bash
# lib/agents/doctor.sh — `agents doctor`: is what the monitoring pack runs
# actually running, here and now?
#
# Owns: the doctor's probes (ps readable, the sampler's last sample, the
#   memory guard's state, Claude Code's hooks calling this agents, the data
#   and run dirs writable), its repairs (--fix: the sampler's job and the
#   guard restarted through the commands that already do it), and its two
#   outputs: lines for you, and rows for `tuidev check` (--tsv).
# Uses: config.sh, util.sh, palette.sh, history.sh (_agents_sample_when,
#   _agents_sample_at, _agents_sampler_line, _AGENTS_SAMPLE_STALE: when a
#   sample is too old is decided there, once), memory.sh
#   (_agents_mem_guard_state, _agents_mem_ps_ok, _agents_mem_unit, agents_mem
#   restart).
# Public: agents_doctor.
#
# A row is STATUS<TAB>NAME<TAB>DETAIL<TAB>FIX: STATUS ok, warn, fail or skip
# (the probe can't tell here: a sandbox, a tool that is missing; never a
# failure), FIX the command that repairs it ("" for none). With --fix, a
# repair is a row too: did, would (-n) or failed, NAME, the command. The
# doctor reads files and asks ps, launchd or systemd; only --fix changes
# anything, and only what `agents mem restart` and the sampler's own job do.

_AGENTS_DOCTOR_SAMPLE_LABEL="dev.tuidev.sample"
# Seconds --fix waits for a restarted guard to look again (its heartbeat).
_AGENTS_DOCTOR_WAIT="${_AGENTS_DOCTOR_WAIT:-5}"

_agents_doctor_row() { _AGENTS_DOCTOR_ROWS+="$1"$'\t'"$2"$'\t'"$3"$'\t'"${4:-}"$'\n'; }

# _agents_doctor_sandboxed — inside an agent's sandbox: Codex says so, or ps
# can't read the process table (Claude Code's Seatbelt). Asked once a run.
_agents_doctor_sandboxed() {
    if [[ -z "${_AGENTS_DOCTOR_SBX:-}" ]]; then
        _AGENTS_DOCTOR_SBX=no
        if [[ -n "${CODEX_SANDBOX:-}" ]] || ! _agents_mem_ps_ok; then _AGENTS_DOCTOR_SBX=yes; fi
    fi
    [[ "$_AGENTS_DOCTOR_SBX" == yes ]]
}

_agents_doctor_ps() {
    if _agents_mem_ps_ok; then
        _agents_doctor_row ok ps "the process table can be read"
    else
        _agents_doctor_row skip ps "the process table can't be read from inside a sandbox"
    fi
}

# _agents_doctor_sampler_fix — the command that starts the sampler's job
# again: the LaunchAgent (macOS) or the systemd timer (Linux) the monitoring
# pack installed; "" when neither is installed (the pack brings one).
_agents_doctor_sampler_fix() {
    REPLY=""
    if [[ "$OSTYPE" == darwin* ]]; then
        [[ ! -f "$HOME/Library/LaunchAgents/$_AGENTS_DOCTOR_SAMPLE_LABEL.plist" ]] \
            || REPLY="launchctl kickstart -k gui/$UID/$_AGENTS_DOCTOR_SAMPLE_LABEL"
    else
        [[ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tuidev-sample.timer" ]] \
            || REPLY="systemctl --user enable --now tuidev-sample.timer"
    fi
}

# _agents_doctor_sampler NOW — how old the newest sample is, by history.sh's
# own rule (_agents_sampler_line: older than _AGENTS_SAMPLE_STALE, or none).
_agents_doctor_sampler() {
    local now="$1" t age
    if [[ "$AGENTS_HISTORY" != 1 ]]; then
        _agents_doctor_row skip sampler "history is off (AGENTS_HISTORY=0)"
        return 0
    fi
    _agents_sampler_line "$now"
    if [[ -z "$REPLY" ]]; then
        _agents_sample_when; t="$REPLY"
        age=$(( now - t )); (( age >= 0 )) || age=0
        _agents_sample_at "$t" "$now"
        _agents_doctor_row ok sampler "last sample at $REPLY (${age}s ago)"
        return 0
    fi
    local line="$REPLY"
    if [[ "$AGENTS_SAMPLER" == 0 ]]; then
        _agents_doctor_row warn sampler "$line"
        return 0
    fi
    _agents_doctor_sampler_fix
    _agents_doctor_row fail sampler "$line" "${REPLY:-tuidev install --pack monitoring}"
}

_agents_doctor_guard() {
    local st pid age
    read -r st pid age <<<"$(_agents_mem_guard_state)"
    case "$st" in
        on)       _agents_doctor_row ok "memory guard" "on (pid $pid)" ;;
        stalled)  _agents_doctor_row fail "memory guard" "stalled: pid $pid has not looked for ${age}s" "agents mem restart" ;;
        stopped)  _agents_doctor_row fail "memory guard" "installed, but no guard runs" "agents mem restart" ;;
        off)      _agents_doctor_row skip "memory guard" "off (AGENTS_MEM_GUARD=off)" ;;
        unknown)  _agents_doctor_row skip "memory guard" "the process table can't be read from inside a sandbox" ;;
        *)        _agents_doctor_row warn "memory guard" "nothing runs one here ($(_agents_mem_unit) is not installed)" "tuidev install --pack monitoring" ;;
    esac
}

# _agents_doctor_hooks — Claude Code's hooks and status line that call
# ~/.local/bin/agents, and whether that is this agents. Read with jq, never
# written.
_agents_doctor_hooks() {
    local f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" n bin="$HOME/.local/bin/agents"
    local t="~"; local shown="${f/#"$HOME"/$t}"
    if ! command -v jq >/dev/null 2>&1; then _agents_doctor_row skip hooks "jq is not installed"; return 0; fi
    if [[ ! -e "$f" ]]; then _agents_doctor_row skip hooks "no $shown"; return 0; fi
    if [[ ! -r "$f" ]]; then _agents_doctor_row skip hooks "$shown can't be read here"; return 0; fi
    n="$(jq -r '[((.hooks // {}) | .. | objects | .command? | strings), (.statusLine.command? | strings)]
                | map(select(test("local/bin/agents"))) | length' "$f" 2>/dev/null)"
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
        _agents_doctor_row warn hooks "$shown is not valid JSON" "jq . $shown"
    elif [[ "$n" == 0 ]]; then
        _agents_doctor_row warn hooks "no hook or status line in $shown calls agents" "tuidev update --configs"
    elif [[ ! -x "$bin" ]]; then
        _agents_doctor_row fail hooks "$n command(s) in $shown call ~/.local/bin/agents, which is not there" "tuidev install --pack monitoring"
    elif [[ "$bin" -ef "$AGENTS_PATH" ]]; then
        _agents_doctor_row ok hooks "$n command(s) in $shown (hooks, status line) call this agents"
    else
        _agents_doctor_row warn hooks "$n command(s) in $shown call ~/.local/bin/agents, not this one ($AGENTS_PATH)"
    fi
}

# _agents_doctor_dirs — the data and run dirs can be written (or made). A
# sandbox says no to every write outside the project, so there it is skipped.
_agents_doctor_dirs() {
    local d e bad="" t="~"
    for d in "$AGENTS_DATA_DIR" "$AGENTS_RUN_DIR"; do
        e="$d"
        while [[ -n "$e" && ! -e "$e" ]]; do e="${e%/*}"; done
        if [[ -z "$e" || ! -d "$e" || ! -w "$e" || ! -x "$e" ]]; then bad+="${bad:+, }${d/#"$HOME"/$t}"; fi
    done
    if [[ -z "$bad" ]]; then
        _agents_doctor_row ok dirs "the data and run dirs can be written"
    elif _agents_doctor_sandboxed; then
        _agents_doctor_row skip dirs "can't be told from inside a sandbox"
    else
        _agents_doctor_row fail dirs "not writable: $bad" "ls -ld $bad   (they must be yours)"
    fi
}

_agents_doctor_probe() {
    local now
    _AGENTS_DOCTOR_ROWS=""
    _agents_now now
    _agents_doctor_ps
    _agents_doctor_sampler "$now"
    _agents_doctor_guard
    _agents_doctor_hooks
    _agents_doctor_dirs
}

# _agents_doctor_restart_sampler — the sampler's job started again, then one
# sample taken now (the job's first run races the re-probe).
_agents_doctor_restart_sampler() {
    if [[ "$OSTYPE" == darwin* ]]; then
        launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$_AGENTS_DOCTOR_SAMPLE_LABEL.plist" 2>/dev/null || true
        launchctl kickstart -k "gui/$UID/$_AGENTS_DOCTOR_SAMPLE_LABEL" || return 1
    else
        systemctl --user enable --now tuidev-sample.timer || return 1
    fi
    "${BASH:-bash}" "$AGENTS_PATH" sample >/dev/null 2>&1 || true
}

# _agents_doctor_restart_guard — agents mem restart, then up to
# _AGENTS_DOCTOR_WAIT seconds for the new guard to take its lock.
_agents_doctor_restart_guard() {
    local i=0 st
    agents_mem restart >/dev/null || return 1
    while (( i < _AGENTS_DOCTOR_WAIT * 4 )); do
        read -r st _ <<<"$(_agents_mem_guard_state)"
        [[ "$st" != on ]] || return 0
        sleep 0.25
        i=$((i + 1))
    done
    return 0
}

# _agents_doctor_repair — each failing row the doctor can repair: run (or,
# with -n, name) its command, as a did/would/failed row.
_agents_doctor_repair() {
    local status name detail fix fn acts=""
    while IFS=$'\t' read -r status name detail fix; do
        [[ "$status" == fail && -n "$fix" ]] || continue
        case "$name" in
            sampler)        [[ "$fix" == launchctl* || "$fix" == systemctl* ]] || continue
                            fn=_agents_doctor_restart_sampler ;;
            "memory guard") fn=_agents_doctor_restart_guard ;;
            *)              continue ;;
        esac
        if [[ "$AGENTS_DRY_RUN" == true ]]; then
            acts+="would"$'\t'"$name"$'\t'"$fix"$'\t'$'\n'
        elif "$fn"; then
            acts+="did"$'\t'"$name"$'\t'"$fix"$'\t'$'\n'
        else
            acts+="failed"$'\t'"$name"$'\t'"$fix"$'\t'$'\n'
        fi
    done <<<"$_AGENTS_DOCTOR_ROWS"
    REPLY="$acts"
}

# _agents_doctor_print ROWS — the rows for a person: a mark, the name, the
# detail, and the fix under it.
_agents_doctor_print() {
    local status name detail fix mark
    while IFS=$'\t' read -r status name detail fix; do
        [[ -n "$status" ]] || continue
        case "$status" in
            ok)     mark="${C_DONE}✓${C_0}" ;;
            warn)   mark="${C_WARN}⚠${C_0}" ;;
            fail)   mark="${C_NEED}✗${C_0}" ;;
            skip)   mark="${C_DIM}-${C_0}"; detail="skipped: $detail" ;;
            did)    mark="${C_ACC}>${C_0}"; detail="ran: $detail" ;;
            would)  mark="${C_ACC}>${C_0}"; detail="would run: $detail" ;;
            failed) mark="${C_NEED}>${C_0}"; detail="failed: $detail" ;;
            *)      continue ;;
        esac
        printf '%s %-13s %s\n' "$mark" "$name" "$detail"
        [[ -z "$fix" || "$status" == ok || "$status" == skip ]] || printf '  %s%-13s fix: %s%s\n' "$C_DIM" "" "$fix" "$C_0"
    done <<<"$1"
}

# agents_doctor [--fix] [-n] [--tsv] — exit 0 when nothing failed, 1 when a
# probe still fails (after --fix: once repaired and probed again), 2 usage.
agents_doctor() {
    local a fix=false tsv=false acts=""
    for a in "$@"; do
        case "$a" in
            --fix)        fix=true ;;
            -n|--dry-run) AGENTS_DRY_RUN=true ;;
            --tsv)        tsv=true ;;
            *) echo "usage: agents doctor [--fix [-n]] [--tsv]" >&2; return 2 ;;
        esac
    done
    _agents_doctor_probe
    if [[ "$fix" == true ]]; then
        _agents_doctor_repair; acts="$REPLY"
        # Probed again only when something ran.
        [[ "$acts" != *did$'\t'* && "$acts" != *failed$'\t'* ]] || _agents_doctor_probe
    fi
    if [[ "$tsv" == true ]]; then
        printf '%s%s' "$acts" "$_AGENTS_DOCTOR_ROWS"
    else
        [[ -z "$acts" ]] || _agents_doctor_print "$acts"
        _agents_doctor_print "$_AGENTS_DOCTOR_ROWS"
    fi
    [[ "$_AGENTS_DOCTOR_ROWS" != fail$'\t'* && "$_AGENTS_DOCTOR_ROWS" != *$'\n'fail$'\t'* ]]
}
