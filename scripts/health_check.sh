#!/usr/bin/env bash
# ============================================================================
# tuidev health check (`tuidev check`)
# ============================================================================
# Profile-aware health check. Probes are split into required vs. optional:
#
#   required  → failure is counted toward the pass/fail summary and the
#               script exits non-zero if any required probe fails.
#   optional  → failure prints a warning only; never affects the exit code.
#
# Categories (which categories are required depends on the active profile):
#
#   core     — shell/CLI staples (required in every profile; on Linux
#              without Homebrew, tools the distro may not package are optional)
#   remote   — tailscale, mosh (required only in the `remote` profile)
#   sandbox  — Seatbelt (macOS only; required in desktop, full & remote)
#   ui       — Ghostty + macOS GUI apps (required in `desktop` and `full`, macOS)
#   extras   — optional quality-of-life tools (never required)
#   packs    — optional packs listed in the profile manifest (never required)
#   runtime  — what runs, not only what is installed: each pack's jobs loaded
#              in launchd or systemd, the installed commands against these
#              files and PATH, hooks that start a program that is gone, the
#              manifest against the disk, and `agents doctor` (the sampler,
#              the memory guard). A failure here counts like a required one;
#              where a probe can't tell (an agent's sandbox, a tool that is
#              missing) it says "skipped" and counts as neither.
#
# Usage:
#   scripts/health_check.sh                      # auto-detect profile
#   scripts/health_check.sh --profile minimal    # force a profile
#   scripts/health_check.sh --profile desktop
#   scripts/health_check.sh --profile remote
#   scripts/health_check.sh --fix [--dry-run]    # repair what is safe to, then probe again
#
# Exit: 0 nothing failed (warnings or not), 1 a required or runtime probe
# failed (with --fix: still fails after the repairs), 2 a bad argument.
#
# Profile auto-detection reads ~/.config/tuidev/profile (the manifest written
# by the installer). When absent, falls back to the platform default:
#   macOS -> desktop, Linux -> minimal.
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/packs.sh disable=SC1091
. "$SCRIPT_DIR/lib/packs.sh"
# shellcheck source=lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/lib/pkg.sh"
# shellcheck source=lib/herdr.sh disable=SC1091
. "$SCRIPT_DIR/lib/herdr.sh"
# shellcheck source=lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/lib/config_write.sh"
# shellcheck source=lib/manifest.sh disable=SC1091
. "$SCRIPT_DIR/lib/manifest.sh"
# shellcheck source=lib/lock.sh disable=SC1091
. "$SCRIPT_DIR/lib/lock.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cache uname once. Probes run dozens of times across the suite.
TUIDEV_OS="$(uname -s)"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------

REQ_PASS=0
REQ_FAIL=0
OPT_WARN=0
RUN_FAIL=0

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

PROFILE="auto"
FIX=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--profile minimal|desktop|remote|full|auto] [--fix [--dry-run]]

  --profile P   Force a specific profile.
                Default: 'auto' (reads the tuidev profile, else
                macOS->desktop, Linux->minimal).
  --fix         Repair each runtime failure that has a safe repair (load a
                job, start a unit, install a tuidev file again, drop
                manifest records of files that are gone), then probe again.
                Never sudo, never a file of yours, never a hook that is not
                tuidev's; the rest is a command for you.
  --dry-run     With --fix: print what it would do, change nothing.
  -h, --help    Show this help.

Exit: 0 nothing failed, 1 a required or runtime probe failed (after --fix:
still fails), 2 a bad argument.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX=true
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --profile)
            [[ $# -ge 2 ]] || { print_error "--profile requires a value"; exit 2; }
            PROFILE="$2"
            shift 2
            ;;
        --profile=*)
            PROFILE="${1#--profile=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Profile manifest (scripts/lib/profile.sh)
# ---------------------------------------------------------------------------

platform_default_profile() {
    case "$TUIDEV_OS" in
        Darwin) echo "desktop" ;;
        *)      echo "minimal" ;;
    esac
}

resolve_profile() {
    load_tuidev_profile || true

    if [[ "$PROFILE" == "auto" ]]; then
        PROFILE="${TUIDEV_PROFILE_NAME:-$(platform_default_profile)}"
    fi

    if [[ "$PROFILE" == custom ]]; then
        # Pack-only installs record profile=custom; check the core baseline
        # (packs are covered by the extra_packs section).
        print_info "Profile is 'custom' (pack-only install): checking the minimal baseline."
        PROFILE="minimal"
    elif ! tuidev_is_valid_profile "$PROFILE"; then
        print_error "Invalid profile: $PROFILE (expected ${TUIDEV_VALID_PROFILES[*]}|auto)"
        exit 2
    fi
}

# ---------------------------------------------------------------------------
# Required/optional probe helpers
# ---------------------------------------------------------------------------

# check_required NAME PROBE_CMD
#   Runs PROBE_CMD via `eval`. On success, counts a required pass.
#   On failure, counts a required fail and contributes to the non-zero exit.
check_required() {
    local name="$1"
    local probe="$2"
    if eval "$probe" >/dev/null 2>&1; then
        print_success "$name"
        REQ_PASS=$((REQ_PASS + 1))
        return 0
    else
        print_error "$name (required)"
        REQ_FAIL=$((REQ_FAIL + 1))
        return 1
    fi
}

# check_optional NAME PROBE_CMD
#   On failure, emits a warning and never affects the exit code.
check_optional() {
    local name="$1"
    local probe="$2"
    if eval "$probe" >/dev/null 2>&1; then
        print_success "$name"
        return 0
    else
        print_warning "$name (optional)"
        OPT_WARN=$((OPT_WARN + 1))
        return 1
    fi
}

# Convenience probe: command is on PATH. Invoked indirectly via
# check_required/check_optional which pass probe commands as strings.
# shellcheck disable=SC2329
have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# App bundle probe (macOS GUI apps). Returns non-zero on non-macOS.
# Invoked indirectly, like have_cmd.
# shellcheck disable=SC2317,SC2329
have_app() {
    [[ "$TUIDEV_OS" == "Darwin" ]] || return 1
    [[ -d "/Applications/$1.app" || -d "$HOME/Applications/$1.app" ]]
}

# ---------------------------------------------------------------------------
# Category: core
# ---------------------------------------------------------------------------

# A core tool is required unless this is Linux without Homebrew and the tool
# is one a distribution may not package (pkg.sh points apt users at its
# upstream installer instead).
core_tool_check_fn() {
    if is_linux && ! command_exists brew && [[ -n "$(pkg_manual_hint "$1")" ]]; then
        echo check_optional
    else
        echo check_required
    fi
}

check_core() {
    print_header "Core (required in every profile)"

    local formula bin
    while IFS= read -r formula; do
        bin="$(tuidev_formula_binary "$formula")"
        [[ -n "$bin" ]] || continue
        "$(core_tool_check_fn "$formula")" "$bin on PATH" "have_cmd $bin"
    done < <(pack_array core formulae)

    if have_cmd zsh; then
        check_required "zsh completion directories pass compaudit" \
            "[[ -z \"\$(zsh -f -c 'autoload -Uz compaudit; compaudit' 2>/dev/null)\" ]]"
    else
        check_required "zsh on PATH" "have_cmd zsh"
    fi

    # API tokens belong in the secret store, not in shell startup files
    # (docs/secrets.md). `secret scan` prints FILE:LINE: NAME, never a value.
    check_optional "secret on PATH" "have_cmd secret"
    # Every hint the scripts print runs through it.
    check_optional "tuidev on PATH (missing: re-run the installer)" "have_cmd tuidev"
    if have_cmd secret; then
        local hits hit
        hits="$(secret scan 2>/dev/null)" || true
        if [[ -z "$hits" ]]; then
            print_success "no token-looking exports in shell startup files"
        else
            print_warning "token-looking exports in shell startup files (move them: secret import --dry-run --remove FILE)"
            while IFS= read -r hit; do print_info "    $hit"; done <<< "$hits"
            OPT_WARN=$((OPT_WARN + 1))
        fi
    fi
}

# ---------------------------------------------------------------------------
# Category: remote
# ---------------------------------------------------------------------------

check_remote() {
    local required="$1"   # "required" or "optional"
    print_header "Remote (Tailscale + mosh)"

    local fn="check_optional"
    [[ "$required" == "required" ]] && fn="check_required"

    # Tailscale: CLI must be on PATH (mac app adds a /usr/local symlink).
    "$fn" "tailscale on PATH" "have_cmd tailscale"
    "$fn" "mosh on PATH" "have_cmd mosh"
}

# ---------------------------------------------------------------------------
# Category: sandbox
# ---------------------------------------------------------------------------

check_sandbox() {
    local required="$1"
    print_header "Sandbox (Seatbelt)"

    if [[ "$TUIDEV_OS" != "Darwin" ]]; then
        print_info "Seatbelt is macOS-only; skipping sandbox probes."
        return 0
    fi

    local fn="check_optional"
    [[ "$required" == "required" ]] && fn="check_required"

    # Is Seatbelt itself functional? Probe with an inline allow-default profile
    # — stable across macOS versions (the built-in `no-profile` name was
    # removed on recent releases). Seatbelt does not nest: run from inside a
    # sandbox (an agent's), sandbox_apply is refused, which says nothing about
    # Seatbelt itself, so that one answer is a skip. Any other failure counts.
    local out rc=0
    out="$(sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>&1)" || rc=$?
    if [[ $rc -ne 0 && "$out" == *"sandbox_apply: Operation not permitted"* ]]; then
        print_info "sandbox-exec works (inline smoke profile): skipped, already inside a sandbox (Seatbelt does not nest)"
    else
        "$fn" "sandbox-exec works (inline smoke profile)" "[[ $rc -eq 0 ]]"
    fi

    # Does the strict profile exist where the installer puts it?
    "$fn" "sandbox profile present ($TUIDEV_STATE_DIR/sandbox/strict.sb)" \
        "[[ -f \"$TUIDEV_STATE_DIR/sandbox/strict.sb\" ]]"

    # Is the `sbx` wrapper on PATH?
    "$fn" "sbx wrapper on PATH" "have_cmd sbx"
}

# ---------------------------------------------------------------------------
# Category: ui (desktop GUI)
# ---------------------------------------------------------------------------

check_ui() {
    local required="$1"
    print_header "UI (Ghostty + macOS GUI apps)"

    if [[ "$TUIDEV_OS" != "Darwin" ]]; then
        print_info "GUI apps are macOS-only; skipping UI probes."
        return 0
    fi

    local fn="check_optional"
    [[ "$required" == "required" ]] && fn="check_required"

    # Ghostty: either the app bundle or the ghostty binary counts.
    "$fn" "Ghostty installed" \
        "have_app Ghostty || have_cmd ghostty"
    "$fn" "Ghostty config (~/.config/ghostty/config)" \
        "[[ -f \"$HOME/.config/ghostty/config\" ]]"

    local cask app
    while IFS= read -r cask; do
        app="$(tuidev_cask_app "$cask")"
        "$fn" "$app.app" "have_app '$app'"
    done < <(pack_array ui casks)
}

# ---------------------------------------------------------------------------
# Category: extras (never required)
# ---------------------------------------------------------------------------

check_extras() {
    print_header "Extras (optional quality-of-life tools)"

    local tool
    while IFS= read -r tool; do
        check_optional "$tool on PATH" "have_cmd $tool"
    done < <(pack_binaries extras)
}

# ---------------------------------------------------------------------------
# Category: shell: compinit more than once
# ---------------------------------------------------------------------------

# Each compinit call costs 20 to 100 ms on every new shell, and installers
# (oh-my-zsh, version managers, cloud SDKs) like to append their own after
# tuidev's. Counts the calls (a command word, not a comment or `autoload`) in
# ~/.zshrc and ~/.zshrc.local; the tuidev block counts once however many
# branches it has (it runs one). Warns only, with what to do; it never edits
# the file. ZDOTDIR, when set, is where zsh reads them.
check_zshrc_compinit() {
    local dir="${ZDOTDIR:-$HOME}" f n total=0 begin end where="" tilde='~'
    begin="$(tuidev_block_begin tuidev-zshrc)"; end="$(tuidev_block_end tuidev-zshrc)"
    for f in "$dir/.zshrc" "$dir/.zshrc.local"; do
        [[ -f "$f" ]] || continue
        n="$(LC_ALL=C awk -v b="$begin" -v e="$end" '
            $0 == b { inb = 1; if (!blk++) c++; next }
            $0 == e { inb = 0; next }
            inb { next }
            { s = $0; sub(/^[ \t]+/, "", s); if (s ~ /^#/) next; sub(/[ \t]#.*/, "", s) }
            s ~ /(^|[;&|({]|[ \t](then|else|do))[ \t]*compinit([ \t;)}]|$)/ { c++ }
            END { print c + 0 }' "$f")"
        [[ "$n" =~ ^[0-9]+$ && $n -gt 0 ]] || continue
        total=$((total + n)); where="${where:+$where, }${f/#"$HOME"/$tilde}: $n"
    done
    (( total > 1 )) || return 0
    print_header "Shell"
    print_warning "compinit runs $total times per new shell ($where): remove the ones an installer added after tuidev's, which already runs it once (each costs 20 to 100 ms; this check never edits the file)"
    OPT_WARN=$((OPT_WARN + 1))
}

# ---------------------------------------------------------------------------
# Category: power (macOS): sleep disabled and nothing will restore it
# ---------------------------------------------------------------------------

# `agents awake lid` disables sleep (pmset disablesleep 1) for a while and a
# root guard turns it back on. macOS keeps the setting across a reboot, which
# kills the guard: then the Mac never sleeps, lid closed or not.
check_power() {
    if ! is_macos || ! have_cmd pmset; then return 0; fi
    print_header "Power (macOS)"
    if ! LC_ALL=C pmset -g 2>/dev/null | awk '$1 == "SleepDisabled" && $2 == 1 { f = 1 } END { exit !f }'; then
        print_success "Sleep is enabled (a closed lid sleeps)"
        return 0
    fi
    if lid_guard_running; then
        print_info "Sleep disabled by 'agents awake lid'; its guard turns it back on"
        return 0
    fi
    print_warning "${RED}Lid sleep is disabled and nothing will restore it${NC} (pmset disablesleep 1, no agents awake lid guard)"
    print_info "Fix: sudo pmset -a disablesleep 0   (or: agents awake restore)"
    OPT_WARN=$((OPT_WARN + 1))
}

# The guard `agents awake lid` recorded is still running: root's, and named
# agents-lid-guard.
lid_guard_running() {
    local pid
    read -r pid _ < "${AGENTS_RUN_DIR:-$TUIDEV_STATE_DIR/run}/lid" 2>/dev/null || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    LC_ALL=C ps -ww -o ruid=,args= -p "$pid" 2>/dev/null | awk 'NR == 1 && $1 == 0 { r = 1 } / agents-lid-guard / { g = 1 } END { exit !(r && g) }'
}

# ---------------------------------------------------------------------------
# Category: packs (optional, manifest-driven)
# ---------------------------------------------------------------------------

check_packs() {
    print_header "Packs (manifest-declared extras)"

    # The remote profile includes --pack tmux, so checking a node as `remote`
    # checks tmux too, even when the manifest predates that.
    local packs=() p
    while IFS= read -r p; do
        packs+=("$p")
    done < <(tuidev_extra_packs "$PROFILE")

    if [[ ${#packs[@]} -eq 0 ]]; then
        print_info "No extra_packs declared in manifest (or manifest absent)."
        return 0
    fi

    # Each pack's own probe (<pack>_check in its file), else what it declares
    # (scripts/lib/packs.sh pack_check).
    local pack
    for pack in "${packs[@]}"; do
        check_optional "pack: $pack" "pack_check $pack"
    done

    # The monitoring pack: agents with its modules, and its SwiftBar plugin
    # (macOS), wherever the manifest put it.
    case " ${packs[*]} " in
        *" monitoring "*)
            check_optional "agents runs (its modules are in place)" agents_runs
            is_macos && check_optional "SwiftBar agents plugin" swiftbar_plugin_present
            is_macos && check_optional "terminal-notifier (a click on a notification jumps to its session)" "have_cmd terminal-notifier" ;;
    esac
    case " ${packs[*]} " in
        *" herdr "*) have_cmd herdr && check_herdr_upgrade ;;
    esac
    return 0
}

# After a Herdr upgrade: agent integrations the new binary would install
# differently (`herdr integration status` says `outdated`, e.g. 0.9.5 stopped
# installing Codex turn hooks), and a running server still on the old
# binary. Both are warnings with the command that fixes them. A stale server
# never needs a restart: `herdr update --handoff` moves it live (a systemd
# unit's own reload, for a server systemd runs), or it picks up the new
# binary whenever it next starts. Homebrew's herdr can't do the former, so
# it points at the commands that switch it to the release binary.
check_herdr_upgrade() {
    local status outdated fix="" name kind hint pid why
    # A wedged server is what this looks for: never wait on it for long.
    herdr_bounded() { if command -v timeout >/dev/null 2>&1; then timeout 5 herdr "$@"; else herdr "$@"; fi; }
    # Captured first: under pipefail, a reader that stops early would fail
    # the pipe. An integration's name is its first word ("letta (experimental)"),
    # kept only when it is a plain name (it goes into a command to run).
    status="$(herdr_bounded integration status 2>/dev/null)" || status=""
    outdated="$(printf '%s\n' "$status" | awk -F: '$2 ~ /^ outdated/ { split($1, w, " "); if (w[1] ~ /^[A-Za-z0-9_.-]+$/) print w[1] }')"
    if [[ -z "$status" ]]; then
        :   # nothing to judge by
    elif [[ -z "$outdated" ]]; then
        print_success "herdr integrations current"
    else
        for name in $outdated; do fix="${fix:+$fix; }herdr integration install $name"; done
        print_warning "herdr integrations outdated: ${outdated//$'\n'/ } (run: $fix)"
        OPT_WARN=$((OPT_WARN + 1))
    fi
    kind="$(herdr_install_kind)"
    if [[ "$kind" == brew ]]; then
        print_warning "herdr is Homebrew's, which can't hand a running server over to a new binary (run: tuidev install --pack herdr or tuidev update --packages, which install the release binary)"
        OPT_WARN=$((OPT_WARN + 1))
    fi
    status="$(herdr_bounded status 2>/dev/null)" || status=""
    if [[ "$status" == *"server_binary_stale: yes"* ]]; then
        hint="it picks up the new binary whenever it next starts"
        if [[ "$kind" == direct ]]; then
            why=""
            for pid in $(herdr_server_pids); do
                why="$(herdr_handoff_blocker "$pid")" && break
                why=""
            done
            if [[ -n "$why" ]]; then hint="no herdr update --handoff: $why; else $hint"
            else hint="herdr update --handoff, from a shell outside Herdr, moves it live; else $hint"
            fi
        fi
        print_warning "herdr server runs an older binary than the client ($hint)"
        OPT_WARN=$((OPT_WARN + 1))
    fi
    [[ "$kind" == direct ]] && herdr_cutover_hint
    check_herdr_logs
    return 0
}

# Herdr's logs (~/.config/herdr/herdr-{server,client}.log) grow for as long as
# the server lives; 0.9.5 leaves no rotated siblings behind. The running server
# holds its log open, so they are trimmed while it is stopped: the next time
# it restarts anyway, never as a reason to restart it. HERDR_LOG_WARN_MB
# (default 50) sets the bar.
check_herdr_logs() {
    local dir="${HERDR_CONFIG_DIR:-$HOME/.config/herdr}" limit f kb big=""
    limit="${HERDR_LOG_WARN_MB:-50}"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=50   # "50MB" or "abc" must not abort make check
    limit=$(( 10#$limit * 1024 ))
    for f in "$dir"/herdr-server.log "$dir"/herdr-client.log "$dir"/herdr.log; do
        [[ -f "$f" ]] || continue
        kb="$(du -k "$f" 2>/dev/null | awk '{ print $1 }')"
        [[ "$kb" =~ ^[0-9]+$ ]] || continue
        if (( kb > limit )); then big="${big:+$big, }${f##*/} $(( kb / 1024 ))M"; fi
    done
    [[ -n "$big" ]] || return 0
    print_warning "herdr logs are large: $big (trim them the next time the server is stopped anyway, before it starts again: in $dir: for f in herdr*.log; do tail -n 2000 \"\$f\" > \"\$f.tmp\" && mv \"\$f.tmp\" \"\$f\"; done)"
    OPT_WARN=$((OPT_WARN + 1))
}

# Probe: agents finds and loads its modules (when not, `agents --help` names
# what is missing).
# shellcheck disable=SC2317,SC2329  # invoked through check_optional's eval
agents_runs() {
    have_cmd agents && agents --help >/dev/null
}

# Probe: the SwiftBar plugin the monitoring pack recorded is in place.
# shellcheck disable=SC2317,SC2329  # invoked through check_optional's eval
swiftbar_plugin_present() {
    local p
    while IFS= read -r p; do
        [[ -x "$p" ]] && return 0
    done < <(tuidev_manifest_values file | grep -E '/agents\.[0-9]+[smhd]\.sh$')
    return 1
}

# ---------------------------------------------------------------------------
# Category: runtime (what runs, not only what is installed)
# ---------------------------------------------------------------------------
#
# A probe sets P_STATUS (ok, warn, fail, skip, or none: nothing to say),
# P_DETAIL, P_FIX (the command for a person) and P_ACTION (the repair --fix
# runs, through run_fix; "" when there is none). runtime_row runs a probe,
# and with --fix repairs a failure that has an action and runs the probe
# again, then prints the row. Every probe is read-only: launchctl print,
# systemctl is-enabled/is-active, jq, cmp, diff, file tests.

TILDE='~'
RT_ACTIVE=" "        # the active packs, " a b "
RT_JOB_FILES=$'\n'   # the plists and units of the active packs' jobs
FIX_DONE=" "         # the repairs --fix already ran

# shellcheck disable=SC2329  # run through runtime_row
_p() { P_STATUS="$1" P_DETAIL="${2:-}" P_FIX="${3:-}" P_ACTION="${4:-}"; }

pack_active() { [[ "$RT_ACTIVE" == *" $1 "* ]]; }

runtime_row() {
    "$@"
    if [[ "$FIX" == true && ( "$P_STATUS" == fail || "$P_STATUS" == warn ) && -n "$P_ACTION" ]]; then
        if run_fix "$P_ACTION" && [[ "$DRY_RUN" != true ]]; then "$@"; fi
    fi
    report_row
}

report_row() {
    local fix="$P_FIX"
    [[ -z "$P_ACTION" || "$FIX" == true ]] || fix="${fix:+$fix; }tuidev check --fix does it"
    case "$P_STATUS" in
        ok)   print_success "$P_DETAIL" ;;
        warn) print_warning "$P_DETAIL${fix:+ (fix: $fix)}"; OPT_WARN=$((OPT_WARN + 1)) ;;
        fail) print_error "$P_DETAIL${fix:+ (fix: $fix)}"; RUN_FAIL=$((RUN_FAIL + 1)) ;;
        skip) print_info "$P_DETAIL" ;;
    esac
    return 0
}

# run_fix ACTION — one repair, once a run: pack:PACK:FN (the pack's own
# function, which writes its files through install_config and starts what it
# runs), cli and notify (~/.local/bin/tuidev and notify.sh, as every install
# writes them), systemd:UNIT (enable and start it), drop-gone and
# record-jobs (the manifest). Under --dry-run each prints what it would do.
run_fix() {
    local a="$1" rest
    [[ "$FIX_DONE" != *" $a "* ]] || return 0
    FIX_DONE+="$a "
    case "$a" in
        pack:*)    rest="${a#pack:}"
                   fix_quiet "the ${rest%%:*} pack's step for its $(fix_name "${rest#*:}") (${rest#*:})" \
                       pack_call "${rest%%:*}" "${rest#*:}" ;;
        cli)       fix_quiet "$TILDE/.local/bin/tuidev, from these files" fix_cli ;;
        notify)    fix_quiet "$TILDE/.local/bin/notify.sh, from these files" tuidev_install_notify "$REPO_DIR" ;;
        systemd:*) print_step "--fix: start ${a#systemd:}"; run_cmd systemctl --user enable --now "${a#systemd:}" ;;
        drop-gone) print_step "--fix: drop the manifest records of files that are gone"; manifest_drop_gone ;;
        record-jobs) print_step "--fix: record tuidev's jobs in the manifest"; manifest_record_jobs ;;
        *)         return 1 ;;
    esac
}

# fix_cli — ~/.local/bin/tuidev from these files. Not tuidev_install_cli:
# that also writes the installed version, which says the configs of this
# release were applied (an unfinished update is finished by that difference).
fix_cli() {
    install_config "$HOME/.local/bin/tuidev" "$REPO_DIR/bin/tuidev" --overwrite || return 1
    [[ "$DRY_RUN" == true ]] || chmod +x "$HOME/.local/bin/tuidev"
}

# fix_quiet WHAT CMD... — run CMD, a step the installer runs (it writes
# through install_config): one line for it, and only its warnings after.
# Under --dry-run it says what it would run and runs nothing.
fix_quiet() {
    local what="$1" out line rc=0
    shift
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $what"
        return 0
    fi
    print_step "--fix: $what"
    out="$("$@" 2>&1)" || rc=$?
    while IFS= read -r line; do
        case "$line" in *"⚠ "*|*"✗ "*) printf '    %s\n' "$line" ;; esac
    done <<< "$out"
    [[ $rc -eq 0 ]] || print_warning "    it ended with status $rc"
    return "$rc"
}

# What a pack function repairs, for the --fix line.
fix_name() {
    case "$1" in
        _monitoring_agents) echo "agents command and modules" ;;
        _monitoring_sampler) echo "sampler" ;;
        _monitoring_memguard) echo "memory guard" ;;
        _monitoring_link) echo "link watcher" ;;
        _monitoring_linux_units) echo "sampler and memory guard units" ;;
        _herdr_core_launchagent|_herdr_core_systemd) echo "herdr-core job" ;;
        _core_install_secret) echo "secret command" ;;
        sandbox_install) echo "sbx and Seatbelt profiles" ;;
        *) echo "$1" ;;
    esac
}

# --- Jobs: loaded in launchd, enabled and active in systemd -------------------

# launchd_state DOMAIN/LABEL — REPLY: loaded, unloaded, or "skip WHY". Inside
# an agent's Seatbelt sandbox launchd answers a loaded job with "Operation
# not permitted" (and one it does not have with "Could not find service").
# shellcheck disable=SC2329  # run through runtime_row
launchd_state() {
    local out rc=0
    if ! command -v launchctl >/dev/null 2>&1; then REPLY="skip launchctl is not here"; return 0; fi
    out="$(launchctl print "$1" 2>&1 >/dev/null)" || rc=$?
    if [[ $rc -eq 0 ]]; then REPLY=loaded
    elif [[ "$out" == *"Could not find service"* ]]; then REPLY=unloaded
    elif [[ "$out" == *"Operation not permitted"* ]]; then REPLY="skip launchd can't be asked from inside a sandbox"
    else REPLY="skip launchctl print said: ${out%%$'\n'*}"
    fi
}

# systemd_ready — REPLY "" when a systemd user manager answers here, else why
# not (no systemctl; a container or a sandbox). Asked once a run.
# shellcheck disable=SC2329  # run through runtime_row
systemd_ready() {
    if [[ -z "${RT_SYSTEMD+x}" ]]; then
        RT_SYSTEMD=""
        if ! command -v systemctl >/dev/null 2>&1; then RT_SYSTEMD="systemctl is not here"
        elif ! systemctl --user show-environment >/dev/null 2>&1; then RT_SYSTEMD="no systemd user manager answers here (a container, or a sandbox)"
        fi
    fi
    REPLY="$RT_SYSTEMD"
    [[ -z "$REPLY" ]]
}

job_file() {
    case "$1" in
        launchd)        REPLY="$HOME/Library/LaunchAgents/$2.plist" ;;
        launchd-system) REPLY="/Library/LaunchDaemons/$2.plist" ;;
        *)              REPLY="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$2" ;;
    esac
}

# job_program FILE — REPLY: the program the job FILE (a plist or a unit)
# starts: the first of ProgramArguments or ExecStart (%h as $HOME), or the
# script when that is a shell; "" when it can't be told.
job_program() {
    local f="$1" a b
    REPLY=""
    [[ -r "$f" ]] || return 0
    case "$f" in
        *.plist) REPLY="$(awk '
                     /<key>ProgramArguments<\/key>/ { p = 1; next }
                     p && /<\/array>/ { exit }
                     p && /<string>/ { s = $0; sub(/.*<string>/, "", s); sub(/<\/string>.*/, "", s); a[++n] = s }
                     END { if (n) { x = a[1]; if (x ~ /\/(ba|z|da)?sh$/ && n > 1) x = a[2]; print x } }' "$f")" ;;
        *)       REPLY="$(awk '/^ExecStart=/ { sub(/^ExecStart=[-@+!:]*/, ""); print; exit }' "$f")"
                 read -r a b _ <<< "$REPLY"
                 case "${a##*/}" in bash|sh|zsh|dash) REPLY="$b" ;; *) REPLY="$a" ;; esac
                 REPLY="${REPLY//%h/$HOME}" ;;
    esac
    [[ "$REPLY" == /* ]] || REPLY=""
}

# job_program_gone NAME FILE ACTION — true, with a failure set, when the job
# FILE starts a program that is not there (the program's own repair when
# tuidev installs it, else ACTION).
# shellcheck disable=SC2329  # run through runtime_row
job_program_gone() {
    local prog act="$3"
    job_program "$2"; prog="$REPLY"
    [[ -n "$prog" && ! -e "$prog" ]] || return 1
    ! path_owner "$prog" || act="$REPLY"
    _p fail "$1 starts ${prog/#"$HOME"/$TILDE}, which is not there" "tuidev update --configs" "$act"
}

# probe_job PACK KIND NAME [FN] — one job a pack declares (pack_array PACK
# jobs). A fault is a failure: its file gone, or the program it starts gone.
# A job that is installed but not loaded, disabled or stopped is one you may
# have turned off (the units and docs/remote.md say how): a warning, with
# how to start it again; --fix starts it.
# shellcheck disable=SC2329  # run through runtime_row
probe_job() {
    local pack="$1" kind="$2" name="$3" fn="${4:-}" file shown act="" st unit
    job_file "$kind" "$name"; file="$REPLY"; shown="${file/#"$HOME"/$TILDE}"
    [[ -z "$fn" ]] || act="pack:$pack:$fn"
    case "$kind" in
        launchd|launchd-system)
            if [[ ! -f "$file" ]]; then
                # A LaunchDaemon that is not there is the pack's own check's to report.
                if [[ "$kind" == launchd ]]; then _p fail "$name: no LaunchAgent at $shown" "tuidev install --pack $pack" "$act"; else _p none; fi
                return 0
            fi
            ! job_program_gone "$name" "$file" "$act" || return 0
            if [[ "$kind" == launchd ]]; then launchd_state "gui/$UID/$name"; else launchd_state "system/$name"; fi
            case "$REPLY" in
                loaded)   _p ok "$name loaded (launchd)" ;;
                unloaded) if [[ "$kind" == launchd ]]; then
                              _p warn "$name is installed but not loaded (turned off?)" "launchctl bootstrap gui/$UID $shown" "$act"
                          else
                              _p warn "$name is installed but not loaded (turned off?)" "sudo launchctl bootstrap system $file"
                          fi ;;
                *)        _p skip "$name loaded: skipped: ${REPLY#skip }" ;;
            esac ;;
        systemd|systemd-enabled)
            if ! systemd_ready; then _p skip "$name enabled: skipped: $REPLY"; return 0; fi
            if [[ ! -f "$file" ]]; then _p fail "$name: no unit at $shown" "tuidev install --pack $pack" "$act"; return 0; fi
            unit="$file"; [[ "$name" != *.timer ]] || unit="${file%.timer}.service"
            ! job_program_gone "$name" "$unit" "$act" || return 0
            st="$(systemctl --user is-enabled "$name" 2>/dev/null)"
            if [[ "$st" != enabled ]]; then
                _p warn "$name is ${st:-not enabled} (turned off?)" "systemctl --user enable --now $name" "systemd:$name"
                return 0
            fi
            if [[ "$kind" == systemd ]]; then
                st="$(systemctl --user is-active "$name" 2>/dev/null)"
                if [[ "$st" != active ]]; then
                    _p warn "$name is enabled but ${st:-not active} (stopped?)" "systemctl --user enable --now $name" "systemd:$name"
                    return 0
                fi
                _p ok "$name enabled and active (systemd)"
            else
                _p ok "$name enabled (systemd)"
            fi ;;
        systemd-file)
            # The service half of a timer: there or not; nothing to ask systemd.
            if ! systemd_ready || [[ -f "$file" ]]; then _p none; return 0; fi
            _p fail "$name: no unit at $shown, so its timer starts nothing" "tuidev install --pack $pack" "$act" ;;
        *)  _p none ;;
    esac
}

# Each active pack's jobs for this platform, as "PACK KIND NAME [FN]" lines.
active_jobs() {
    local pack kind name fn
    for pack in $RT_ACTIVE; do
        while read -r kind name fn; do
            case "$kind" in
                launchd|launchd-system) [[ "$TUIDEV_OS" == Darwin ]] || continue ;;
                systemd|systemd-enabled|systemd-file) [[ "$TUIDEV_OS" == Linux ]] || continue ;;
                *) continue ;;
            esac
            printf '%s %s %s %s\n' "$pack" "$kind" "$name" "$fn"
        done < <(pack_array "$pack" jobs)
    done
}

check_jobs() {
    local pack kind name fn
    while read -r pack kind name fn; do
        [[ -n "$name" ]] || continue
        runtime_row probe_job "$pack" "$kind" "$name" "$fn"
    done <<< "$RT_JOBS"
}

# --- Versions: the installed commands against these files and PATH ----------

# bin_owner NAME — REPLY: the repair that installs NAME again; false when no
# active pack here installs it.
bin_owner() {
    case "$1" in
        tuidev)          REPLY=cli ;;
        notify.sh)       REPLY=notify ;;
        agents|mcp-lazy) pack_active monitoring || return 1; REPLY=pack:monitoring:_monitoring_agents ;;
        secret)          pack_active core || return 1; REPLY=pack:core:_core_install_secret ;;
        sbx)             [[ "$TUIDEV_OS" == Darwin ]] && pack_active sandbox || return 1
                         REPLY=pack:sandbox:sandbox_install ;;
        *)               return 1 ;;
    esac
}

# shellcheck disable=SC2329  # run through runtime_row
bin_source() {
    case "$1" in
        notify.sh) REPLY="$REPO_DIR/scripts/notify.sh" ;;
        *)         REPLY="$REPO_DIR/bin/$1" ;;
    esac
}

# shellcheck disable=SC2329  # run through runtime_row
probe_release() {
    local files="" applied=""
    [[ -r "$REPO_DIR/VERSION" ]] && read -r files < "$REPO_DIR/VERSION"
    [[ -r "$TUIDEV_STATE_DIR/version" ]] && read -r applied < "$TUIDEV_STATE_DIR/version"
    if [[ -z "$files" ]]; then _p none
    elif [[ -z "$applied" ]]; then
        _p warn "tuidev $files: no installed version recorded ($TUIDEV_STATE_DIR/version)" "tuidev update --configs"
    elif [[ "$applied" != "$files" ]]; then
        _p warn "tuidev: the configs applied are $applied's, the files in $REPO_DIR are $files" "tuidev update --configs"
    else
        _p ok "tuidev $files: the configs applied are this release's"
    fi
}

# probe_bin_copy NAME — ~/.local/bin/NAME is the copy of these files (agents:
# its modules too). One the manifest records and that is gone is the
# manifest probe's to report.
# shellcheck disable=SC2329  # run through runtime_row
probe_bin_copy() {
    local name="$1" dest="$HOME/.local/bin/$1" src act n
    bin_source "$name"; src="$REPLY"
    [[ -f "$src" ]] || { _p none; return 0; }
    if ! bin_owner "$name"; then
        [[ -e "$dest" ]] || { _p none; return 0; }
        act=""
    else
        act="$REPLY"
    fi
    if [[ ! -e "$dest" ]]; then
        if tuidev_manifest_has file "$dest"; then _p none; else _p fail "$name: ~/.local/bin/$name is not installed" "tuidev update --configs" "$act"; fi
        return 0
    fi
    n=0
    cmp -s "$dest" "$src" || n=1
    if [[ "$name" == agents && -d "$REPO_DIR/lib/agents" && ! -d "$TUIDEV_LIB_DIR/agents" ]]; then
        n=$((n + 1))
    elif [[ "$name" == agents && -d "$REPO_DIR/lib/agents" ]]; then
        modules_differ; n=$((n + REPLY))
    fi
    if (( n == 0 )); then
        _p ok "$name: ~/.local/bin/$name is the one in these files"
    else
        _p warn "$name: ~/.local/bin/$name is not the one in $REPO_DIR ($n file(s) differ)" "tuidev update --configs" "$act"
    fi
}

# modules_differ — REPLY: how many of the files the monitoring pack installs
# from lib/agents (its own list, _monitoring_agents_files) differ from the
# installed ones or are missing there. Anything else in either tree (a
# .DS_Store in a clone, a module a release dropped) is not compared.
# shellcheck disable=SC2329  # run through runtime_row
modules_differ() {
    local rels a b
    REPLY=0
    rels="$(pack_call monitoring _monitoring_agents_files)" || return 0
    [[ -n "$rels" ]] || return 0
    a="$(cd "$REPO_DIR/lib/agents" && printf '%s\n' "$rels" | xargs cksum 2>/dev/null)"
    b="$(cd "$TUIDEV_LIB_DIR/agents" 2>/dev/null && printf '%s\n' "$rels" | xargs cksum 2>/dev/null)"
    REPLY="$(_B="$b" awk 'BEGIN { n = split(ENVIRON["_B"], l, "\n"); for (i = 1; i <= n; i++) have[l[i]] = 1 }
                          !($0 in have) { c++ } END { print c + 0 }' <<< "$a")"
}

# probe_bin_path NAME — PATH finds ~/.local/bin/NAME, not another copy first.
# shellcheck disable=SC2329  # run through runtime_row
probe_bin_path() {
    local name="$1" dest="$HOME/.local/bin/$1" first
    [[ -e "$dest" ]] || { _p none; return 0; }
    first="$(command -v "$name" 2>/dev/null)" || first=""
    if [[ -z "$first" ]]; then
        _p warn "$name: ~/.local/bin is not on PATH, so $name is not found" "put ~/.local/bin on PATH (the tuidev-zshrc block does)"
    elif [[ "$first" -ef "$dest" ]]; then
        _p none
    else
        _p warn "$name: PATH finds $first before ~/.local/bin/$name" "remove $first, or put ~/.local/bin earlier in PATH"
    fi
}

check_versions() {
    local name
    runtime_row probe_release
    for name in tuidev agents sbx secret mcp-lazy notify.sh; do
        runtime_row probe_bin_copy "$name"
    done
    for name in tuidev agents sbx secret; do
        runtime_row probe_bin_path "$name"
    done
}

# --- Hooks that start a program that is not there ----------------------------

# hook_word S — REPLY: S's first shell word (its quotes removed), REST: what
# follows it.
hook_word() {
    local s="$1"
    case "$s" in
        \"*) s="${s#\"}"; REPLY="${s%%\"*}"; REST="${s#*\"}" ;;
        \'*) s="${s#\'}"; REPLY="${s%%\'*}"; REST="${s#*\'}" ;;
        *)   REPLY="${s%%[[:space:]\;\&\|\<\>\(\)]*}"; REST="${s#"$REPLY"}" ;;
    esac
}

# hook_program COMMAND — REPLY: the file COMMAND starts, when its first word
# is a path (absolute, ~ or $HOME), or an interpreter's script that is one;
# HOOK_MODE: exec (it must be executable) or read (an interpreter reads it).
# "" for anything else: a shell construct, a command found on PATH.
hook_program() {
    local c="$1"
    HOOK_MODE="exec"
    c="${c#"${c%%[![:space:]]*}"}"
    hook_word "$c"
    case "${REPLY##*/}" in
        bash|sh|zsh|dash|python|python3|node|perl|ruby)
            c="${REST#"${REST%%[![:space:]]*}"}"
            hook_word "$c"
            [[ "$REPLY" != -* ]] || REPLY=""
            HOOK_MODE="read" ;;
    esac
    case "$REPLY" in
        "$TILDE/"*)     REPLY="$HOME/${REPLY#"$TILDE/"}" ;;
        \$HOME/*)       REPLY="$HOME/${REPLY#\$HOME/}" ;;
        \$\{HOME\}/*)   REPLY="$HOME/${REPLY#\$\{HOME\}/}" ;;
    esac
    # An escaped space (My\ App) ends the word at a backslash: can't tell.
    [[ "$REPLY" == /* && "$REPLY" != *\\ ]] || REPLY=""
}

# tuidev_owned PATH — tuidev installed PATH: one of its commands, or a file
# the manifest records.
# shellcheck disable=SC2329  # run through runtime_row
tuidev_owned() {
    case "$1" in
        "$HOME/.local/bin/agents"|"$HOME/.local/bin/tuidev"|"$HOME/.local/bin/sbx"|"$HOME/.local/bin/secret"|\
        "$HOME/.local/bin/notify.sh"|"$HOME/.local/bin/mcp-lazy") return 0 ;;
    esac
    tuidev_manifest_has file "$1"
}

# probe_hook FILE WHAT PATH MODE — one hook's program is there.
# shellcheck disable=SC2329  # run through runtime_row
probe_hook() {
    local file="${1/#"$HOME"/$TILDE}" what="$2" path="$3" mode="$4" shown="${3/#"$HOME"/$TILDE}" why
    if [[ "$mode" == exec ]]; then
        [[ -f "$path" && -x "$path" ]] && { _p none; return 0; }
        if [[ -e "$path" ]]; then why="is not executable"; else why="is not there"; fi
    else
        [[ -f "$path" && -r "$path" ]] && { _p none; return 0; }
        why="is not there"
    fi
    if tuidev_owned "$path"; then
        if bin_owner "${path##*/}" && [[ "$path" == "$HOME/.local/bin/"* ]]; then
            _p fail "$file: the $what hook runs $shown, which $why" "tuidev update --configs" "$REPLY"
        else
            _p fail "$file: the $what hook runs $shown, which $why" "tuidev update --configs"
        fi
    else
        _p warn "$file: the $what hook runs $shown, which $why (not tuidev's: fix or remove it in $file yourself; tuidev never edits it)"
    fi
}

# hook_commands FILE — "WHAT<TAB>COMMAND" for each hook command (and the
# status line) in a Claude Code settings.json or a Codex hooks.json.
hook_commands() {
    jq -r '[((.hooks // {}) | objects | to_entries[] | .key as $e | .value | arrays | .[] | objects
              | (.hooks // []) | arrays | .[] | objects | .command? | strings | [$e, .]),
            (.statusLine? | objects | .command? | strings | ["statusLine", .])] | .[] | @tsv' "$1"
}

check_hook_file() {
    local file="$1" shown="${1/#"$HOME"/$TILDE}" list what cmd n=0 bad=0
    [[ -e "$file" ]] || return 0
    if [[ ! -r "$file" ]]; then print_info "$shown hooks: skipped: it can't be read here"; return 0; fi
    if ! list="$(hook_commands "$file" 2>/dev/null)"; then
        print_warning "$shown is not valid JSON (jq . $shown says where)"
        OPT_WARN=$((OPT_WARN + 1))
        return 0
    fi
    while IFS=$'\t' read -r what cmd; do
        [[ -n "$what" ]] || continue
        hook_program "$cmd"
        [[ -n "$REPLY" ]] || continue
        n=$((n + 1))
        runtime_row probe_hook "$file" "$what" "$REPLY" "$HOOK_MODE"
        [[ "$P_STATUS" == none ]] || bad=$((bad + 1))
    done <<< "$list"
    (( bad > 0 )) || print_success "$shown: every program its hooks start by path is there ($n)"
}

# Codex's notify program (config.toml, the top-level `notify = [...]`): its
# first word, when that is a path.
check_codex_notify() {
    local file="${CODEX_HOME:-$HOME/.codex}/config.toml" first
    [[ -r "$file" ]] || return 0
    first="$(awk '/^[ \t]*\[/ { exit } /^[ \t]*notify[ \t]*=[ \t]*\[/ { if (match($0, /"[^"]*"/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }' "$file")"
    [[ -n "$first" ]] || return 0
    hook_program "\"$first\""
    HOOK_MODE="exec"
    [[ -n "$REPLY" ]] || return 0
    runtime_row probe_hook "$file" notify "$REPLY" exec
    [[ "$P_STATUS" != none ]] || print_success "${file/#"$HOME"/$TILDE}: its notify program is there"
}

check_hooks() {
    if ! command -v jq >/dev/null 2>&1; then
        print_info "hooks: skipped: jq is not installed"
        return 0
    fi
    check_hook_file "$HOME/.claude/settings.json"
    check_hook_file "${CODEX_HOME:-$HOME/.codex}/hooks.json"
    check_codex_notify
}

# --- The manifest against the disk ----------------------------------------

# manifest_paths — "KIND<TAB>VALUE<TAB>PATH" for each record that names a
# path (file, dir, tool; a block's file).
manifest_paths() {
    awk '
        index($0, "#") == 1 { next }
        { k = $1; v = substr($0, length(k) + 2); p = v }
        k == "block" { p = substr(v, index(v, " ") + 1) }
        k == "file" || k == "dir" || k == "tool" || k == "block" { print k "\t" v "\t" p }
    ' "$TUIDEV_MANIFEST_FILE"
}

# path_owner PATH — REPLY: the repair that puts PATH back, for what an active
# pack installs and keeps (agents and its modules, tuidev's commands, the
# Seatbelt profiles); false for anything else.
path_owner() {
    case "$1" in
        "$HOME/.local/bin/agents"|"$HOME/.local/bin/mcp-lazy"|"$TUIDEV_LIB_DIR/agents/"*) bin_owner agents ;;
        "$HOME/.local/bin/tuidev"|"$HOME/.local/bin/notify.sh"|"$HOME/.local/bin/secret"|"$HOME/.local/bin/sbx")
            bin_owner "${1##*/}" ;;
        "$TUIDEV_STATE_DIR/sandbox/"*.sb) bin_owner sbx ;;
        *) return 1 ;;
    esac
}

# The records whose path is gone, as "ACTION<TAB>KIND<TAB>VALUE<TAB>PATH":
# ACTION the repair that puts it back, "-" for none (the record is dropped).
# The jobs of active packs are the job probe's.
manifest_gone() {
    local kind value path act
    while IFS=$'\t' read -r kind value path; do
        [[ -n "$path" && ! -e "$path" && ! -L "$path" ]] || continue
        [[ "$RT_JOB_FILES" != *$'\n'"$path"$'\n'* ]] || continue
        if path_owner "$path"; then act="$REPLY"; else act=-; fi
        printf '%s\t%s\t%s\t%s\n' "$act" "$kind" "$value" "$path"
    done < <(manifest_paths)
}

# A list, three at most and a count.
# shellcheck disable=SC2329  # run through runtime_row
some() {
    local n=0 out="" line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        n=$((n + 1))
        (( n > 3 )) || out+="${out:+, }${line/#"$HOME"/$TILDE}"
    done <<< "$1"
    (( n <= 3 )) || out+=" and $((n - 3)) more"
    REPLY="$out"
}

# probe_restore ACTION — the files the manifest records that ACTION puts back.
# shellcheck disable=SC2329  # run through runtime_row
probe_restore() {
    local paths
    paths="$(manifest_gone | awk -F '\t' -v a="$1" '$1 == a { print $4 }')"
    if [[ -z "$paths" ]]; then _p none; return 0; fi
    some "$paths"
    _p fail "gone, though tuidev installed them: $REPLY" "tuidev update --configs" "$1"
}

# shellcheck disable=SC2329  # run through runtime_row
probe_gone() {
    local paths
    paths="$(manifest_gone | awk -F '\t' '$1 == "-" { print $4 }')"
    if [[ -z "$paths" ]]; then _p none; return 0; fi
    some "$paths"
    _p warn "the manifest records files that are gone: $REPLY (uninstall skips them; nothing else depends on them)" "" drop-gone
}

manifest_drop_gone() {
    local act kind value path
    while IFS=$'\t' read -r act kind value path; do
        [[ "$act" == - ]] || continue
        run_cmd tuidev_manifest_drop "$kind" "$value"
    done < <(manifest_gone)
}

# The jobs any pack declares, by file (pack_array of every pack: --fix only).
all_job_files() {
    local pack kind name fn
    for pack in "${TUIDEV_VALID_PACKS[@]}"; do
        while read -r kind name fn; do
            [[ -n "$name" ]] || continue
            job_file "$kind" "$name"; printf '%s\n' "$REPLY"
        done < <(pack_array "$pack" jobs)
    done
}

# The LaunchAgents and user units on disk that are jobs some pack ships
# (all_job_files: read only when one of those names is unrecorded) and that
# the manifest lacks. A file of yours that only shares the prefix is not
# tuidev's business, and is never named.
unrecorded_jobs() {
    local f dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" cand="" known
    for f in "$HOME"/Library/LaunchAgents/dev.tuidev.*.plist "$dir"/tuidev-*.service "$dir"/tuidev-*.timer; do
        [[ -f "$f" ]] || continue
        tuidev_manifest_has file "$f" || cand+="$f"$'\n'
    done
    [[ -n "$cand" ]] || return 0
    known=$'\n'"$(all_job_files)"$'\n'
    while IFS= read -r f; do
        [[ -z "$f" || "$known" != *$'\n'"$f"$'\n'* ]] || printf '%s\n' "$f"
    done <<< "$cand"
}

# shellcheck disable=SC2329  # run through runtime_row
probe_unrecorded() {
    local files
    files="$(unrecorded_jobs)"
    if [[ -z "$files" ]]; then _p none; return 0; fi
    some "$files"
    _p warn "not in the manifest, so tuidev uninstall would leave them: $REPLY" "" record-jobs
}

manifest_record_jobs() {
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] || run_cmd tuidev_manifest_record file "$f"
    done <<< "$(unrecorded_jobs)"
}

check_manifest() {
    local act
    if ! tuidev_manifest_present; then
        print_info "manifest: skipped: there is none ($TUIDEV_MANIFEST_FILE)"
        return 0
    fi
    for act in $(manifest_gone | awk -F '\t' '$1 != "-" { print $1 }' | sort -u); do
        runtime_row probe_restore "$act"
    done
    runtime_row probe_gone
    runtime_row probe_unrecorded
}

# --- agents doctor: the sampler, the memory guard (monitoring pack) ---------

# `agents doctor --tsv` does these probes (one implementation, in
# lib/agents/doctor.sh); its rows are counted here like the others.
check_doctor() {
    local a args=(doctor --tsv) out rc=0 status name detail fix
    pack_active monitoring || return 0
    # The agents you run: PATH's (a copy found before ~/.local/bin is
    # probe_bin_path's to report), else the installed one.
    a="$(command -v agents 2>/dev/null)" || a=""
    [[ -n "$a" || ! -x "$HOME/.local/bin/agents" ]] || a="$HOME/.local/bin/agents"
    if [[ -z "$a" ]]; then print_info "agents doctor: skipped: agents is not installed"; return 0; fi
    if [[ "$FIX" == true ]]; then args+=(--fix); [[ "$DRY_RUN" != true ]] || args+=(-n); fi
    out="$("$a" "${args[@]}" 2>/dev/null)" || rc=$?
    if [[ $rc -eq 2 && "$out" != *$'\t'* ]]; then
        print_info "agents doctor: skipped: this agents has no doctor (tuidev update --configs brings it)"
        return 0
    elif [[ -z "$out" ]]; then
        print_warning "agents doctor gave no answer (exit $rc; agents --help says why)"
        OPT_WARN=$((OPT_WARN + 1))
        return 0
    fi
    while IFS=$'\t' read -r status name detail fix; do
        case "$status" in
            ok)     print_success "$name: $detail" ;;
            warn)   print_warning "$name: $detail${fix:+ (fix: $fix)}"; OPT_WARN=$((OPT_WARN + 1)) ;;
            fail)   [[ "$FIX" == true || -z "$fix" ]] || fix="$fix; tuidev check --fix does it"
                    print_error "$name: $detail${fix:+ (fix: $fix)}"; RUN_FAIL=$((RUN_FAIL + 1)) ;;
            skip)   print_info "$name: skipped: $detail" ;;
            did)    print_step "--fix: $detail ($name)" ;;
            would)  echo -e "${YELLOW}[DRY RUN]${NC} $detail ($name)" ;;
            failed) print_warning "--fix: $detail failed ($name)" ;;
        esac
    done <<< "$out"
}

check_runtime() {
    local p kind name
    print_header "Runtime (what runs now)"
    # What runs is an install's: with none recorded there is nothing to compare.
    if ! $TUIDEV_PROFILE_FOUND; then
        print_info "runtime: skipped: no install is recorded here ($TUIDEV_PROFILE_FILE_DEFAULT)"
        return 0
    fi
    # The packs the install recorded (the profile file), never a forced
    # --profile: --fix repairs only what was chosen here.
    RT_ACTIVE=" "
    for p in $(tuidev_active_packs); do
        [[ "$RT_ACTIVE" == *" $p "* ]] || RT_ACTIVE+="$p "
    done
    RT_JOBS="$(active_jobs)"
    RT_JOB_FILES=$'\n'
    while read -r _ kind name _; do
        [[ -n "$name" ]] || continue
        job_file "$kind" "$name"; RT_JOB_FILES+="$REPLY"$'\n'
    done <<< "$RT_JOBS"
    check_jobs
    check_versions
    check_hooks
    check_manifest
    check_doctor
}

# --fix takes the install's lock (one install, update or repair at a time)
# and records what the packs' functions write, as an install does.
fix_begin() {
    [[ "$FIX" == true && "$DRY_RUN" != true ]] || return 0
    tuidev_update_lock || exit 1
    trap tuidev_update_unlock EXIT
    tuidev_manifest_enable
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

show_profile_banner() {
    print_header "Health check — profile: $PROFILE"
    print_info "Platform: $(uname -s) $(uname -r)"
    if $TUIDEV_PROFILE_FOUND; then
        print_info "Manifest: $TUIDEV_PROFILE_FILE_DEFAULT"
        [[ -n "$TUIDEV_PROFILE_INSTALLED_AT" ]] && print_info "Installed at: $TUIDEV_PROFILE_INSTALLED_AT"
        [[ -n "$TUIDEV_PROFILE_REPO" ]]         && print_info "Repo: $TUIDEV_PROFILE_REPO"
    else
        print_info "Manifest: (not found; using platform defaults)"
    fi
    if [[ -f "$TUIDEV_ENV_FILE_DEFAULT" ]]; then
        print_info "Env file: $TUIDEV_ENV_FILE_DEFAULT"
    fi
}

run_checks() {
    # Core is always required.
    check_core

    # Remote: required only in the `remote` profile, optional elsewhere.
    case "$PROFILE" in
        remote)  check_remote required ;;
        *)       check_remote optional ;;
    esac

    # Sandbox: required in desktop, full and remote (macOS only); optional in minimal.
    case "$PROFILE" in
        desktop|full|remote) check_sandbox required ;;
        *)              check_sandbox optional ;;
    esac

    # UI: required in desktop and full (macOS only); skipped entirely on Linux.
    case "$PROFILE" in
        desktop|full) check_ui required ;;
        *)       check_ui optional ;;
    esac

    # Extras + packs are never required.
    check_extras
    check_packs
    check_zshrc_compinit
    check_power
    check_runtime
}

print_summary() {
    print_header "Summary"
    printf '  Required passed:   %b%d%b\n' "$GREEN"  "$REQ_PASS" "$NC"
    printf '  Required failed:   %b%d%b\n' "$RED"    "$REQ_FAIL" "$NC"
    printf '  Runtime failed:    %b%d%b\n' "$RED"    "$RUN_FAIL" "$NC"
    printf '  Optional warnings: %b%d%b\n' "$YELLOW" "$OPT_WARN" "$NC"
    echo

    if [[ $REQ_FAIL -eq 0 && $RUN_FAIL -eq 0 ]]; then
        printf '%bAll required and runtime checks passed for profile: %s%b\n' "$GREEN" "$PROFILE" "$NC"
        return 0
    fi
    if [[ $REQ_FAIL -gt 0 ]]; then
        printf '%b%d required check(s) failed for profile: %s%b\n' "$RED" "$REQ_FAIL" "$PROFILE" "$NC"
        printf '%bRun the installer for this profile or install the missing tools.%b\n' "$YELLOW" "$NC"
    fi
    if [[ $RUN_FAIL -gt 0 ]]; then
        printf '%b%d runtime check(s) failed%b\n' "$RED" "$RUN_FAIL" "$NC"
        if [[ "$FIX" == true && "$DRY_RUN" == true ]]; then
            printf '%bThat was a dry run: tuidev check --fix does what it printed.%b\n' "$YELLOW" "$NC"
        elif [[ "$FIX" == true ]]; then
            printf '%bWhat --fix could not repair is yours to run: the fix after each.%b\n' "$YELLOW" "$NC"
        else
            printf '%btuidev check --fix repairs what it safely can; the rest names its fix.%b\n' "$YELLOW" "$NC"
        fi
    fi
    return 1
}

main() {
    resolve_profile
    fix_begin
    show_profile_banner
    run_checks
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Sourced (scripts/lib/test_health_check.sh), it only defines the probes.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
