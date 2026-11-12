#!/bin/bash
# scripts/lib/perf.sh — the performance audit: what the OS does in the
# background that competes with agents, and what to change.
#
# perf_collect runs every check for this platform and fills the PERF_* arrays;
# perf_report prints them; perf_apply runs the fixes that need no root and can
# be undone. Everything else is printed as the command or the setting, for you
# to run. Reading is always safe: perf_collect changes nothing.
#
# Called by scripts/perf.sh (`make perf`), `update.sh --check|--perf|--all`
# and the end of install.sh. The reasoning behind each check, with sources, is
# in docs/performance.md.
#
# Source after ui.sh, manifest.sh and gitconfig.sh. Honors DRY_RUN.
#
# Settings (environment):
#   TUIDEV_PERF_DIRS       extra folders to check, colon-separated (your repos)
#   TUIDEV_PERF_INDEX_MIN  indexed files in a store before it is flagged (1000)

# One finding per index, across parallel arrays (bash 3.2: no associative
# arrays). LEVEL is ok, warn or note. FIX_FN, when set, is a function perf_apply
# calls with FIX_ARG; FIX_TEXT is what the person reads either way.
PERF_LEVEL=()
PERF_TITLE=()
PERF_FIX_TEXT=()
PERF_FIX_FN=()
PERF_FIX_ARG=()
PERF_WARN_TOTAL=0
PERF_AUTO_TOTAL=0

# Where the Linux checks read kernel settings and system config; tests point
# these at fixtures.
PERF_PROC="${PERF_PROC:-/proc}"
PERF_ETC="${PERF_ETC:-/etc}"

# _perf_add LEVEL TITLE [FIX_TEXT [FIX_FN [FIX_ARG]]]
_perf_add() {
    PERF_LEVEL+=("$1")
    PERF_TITLE+=("$2")
    PERF_FIX_TEXT+=("${3:-}")
    PERF_FIX_FN+=("${4:-}")
    PERF_FIX_ARG+=("${5:-}")
    if [[ "$1" == warn ]]; then
        PERF_WARN_TOTAL=$((PERF_WARN_TOTAL + 1))
        [[ -n "${4:-}" ]] && PERF_AUTO_TOTAL=$((PERF_AUTO_TOTAL + 1))
    fi
    return 0
}

# _perf_tilde PATH — PATH with $HOME written as ~, for display.
# shellcheck disable=SC2088  # a literal ~ is the point
_perf_tilde() {
    case "$1" in
        "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
        *)         printf '%s\n' "$1" ;;
    esac
}

# perf_store_dirs — the package stores and caches on this machine, one per
# line: the directories installers fill with hundreds of thousands of files
# that no one searches and no backup needs. Only ones that exist.
perf_store_dirs() {
    local d
    {
        command_exists pnpm && pnpm store path 2>/dev/null
        command_exists go && go env GOMODCACHE 2>/dev/null
        command_exists uv && uv cache dir 2>/dev/null
        command_exists npm && npm config get cache 2>/dev/null
        printf '%s\n' "${BUN_INSTALL_CACHE_DIR:-$HOME/.bun/install/cache}" \
            "${CARGO_HOME:-$HOME/.cargo}/registry" "$HOME/.gradle/caches" "$HOME/.m2/repository"
    } | while IFS= read -r d; do
        [[ -n "$d" && -d "$d" ]] && printf '%s\n' "$d"
    done | awk '!seen[$0]++'
    return 0
}

# perf_code_dirs — folders that usually hold repos, plus TUIDEV_PERF_DIRS.
perf_code_dirs() {
    local d extra=()
    if [[ -n "${TUIDEV_PERF_DIRS:-}" ]]; then
        IFS=: read -r -a extra <<< "$TUIDEV_PERF_DIRS"
    fi
    for d in ${extra[@]+"${extra[@]}"} "$HOME/workspace" "$HOME/code" "$HOME/Code" "$HOME/src" \
        "$HOME/dev" "$HOME/Developer" "$HOME/projects" "$HOME/Projects" "$HOME/repos" "$HOME/work"; do
        [[ -n "$d" && -d "$d" ]] && printf '%s\n' "$d"
    done | awk '!seen[$0]++'
    return 0
}

# ----------------------------------------------------------------------------
# Checks shared by macOS and Linux
# ----------------------------------------------------------------------------

# The soft limit on open files is 256 on macOS and 1024 on Linux. The shipped
# .zshrc raises it; a shell profile without that line is still at the default.
# This reads the profiles, not a live shell: starting your interactive shell
# from here would run everything else in it.
_perf_check_nofile() {
    local f
    for f in "$HOME/.zshrc" "$HOME/.zshrc.local" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.profile"; do
        if [[ -f "$f" ]] && grep -Eq '^[^#]*ulimit .*-[SH]*n' "$f"; then
            _perf_add ok "Open files: your shell raises the limit ($(_perf_tilde "$f"))"
            return 0
        fi
    done
    _perf_add warn "Open files: your shell starts at the system's soft limit (256 on macOS, 1024 on Linux)" \
        "./scripts/update.sh --configs   (the shipped .zshrc raises it to 65536), or add 'ulimit -n 65536' to your shell profile"
}

_perf_fix_git() { tuidev_git_default "$1" true; }

_perf_check_git() {
    command_exists git || return 0
    if [[ "$(git config --global --includes --get core.fsmonitor 2>/dev/null)" == true ]]; then
        _perf_add warn "git: core.fsmonitor is on globally, so every worktree starts a daemon that outlives it" \
            "git config --global --unset core.fsmonitor   (set it per repo, in the large ones)"
    fi
    if [[ -z "$(git config --global --includes --get core.untrackedCache 2>/dev/null)" ]]; then
        _perf_add warn "git: core.untrackedCache is unset (about 2x faster status on a large tree)" \
            "git config --global core.untrackedCache true" _perf_fix_git core.untrackedCache
    else
        _perf_add ok "git: core.untrackedCache is set"
    fi
}

# Clones and hardlinks cannot cross a volume: a store on another one makes
# every install a full copy.
_perf_check_store_volume() {
    local home_dev dev d
    home_dev="$(df -P "$HOME" 2>/dev/null | awk 'NR == 2 { print $1 }')" || true
    [[ -n "$home_dev" ]] || return 0
    while IFS= read -r d; do
        dev="$(df -P "$d" 2>/dev/null | awk 'NR == 2 { print $1 }')" || true
        if [[ -n "$dev" && "$dev" != "$home_dev" ]]; then
            _perf_add warn "$(_perf_tilde "$d") is on another volume than your home, so installs copy instead of linking" \
                "keep the store on the volume your repos are on"
        fi
    done < <(perf_store_dirs)
    return 0
}

# ----------------------------------------------------------------------------
# macOS
# ----------------------------------------------------------------------------

# _perf_indexed DIR — files Spotlight has indexed under DIR; empty when it
# cannot be asked (no mdfind, or a sandbox in the way).
_perf_indexed() {
    command_exists mdfind || return 0
    mdfind -onlyin "$1" -count "kMDItemContentTypeTree == 'public.item'" 2>/dev/null | awk '/^[0-9]+$/ { print; exit }' || true
}

# Spotlight has no supported command to exclude a folder: the Search Privacy
# list in System Settings is the only one. So this check measures (a search
# scoped to the folder says how much of it is indexed) and names the folder.
_perf_check_spotlight() {
    command_exists mdfind || return 0
    local d n min="${TUIDEV_PERF_INDEX_MIN:-1000}" flagged=0 asked=0
    while IFS= read -r d; do
        n="$(_perf_indexed "$d")" || true
        [[ -n "$n" ]] || continue
        asked=1
        if (( n >= min )); then
            flagged=1
            _perf_add warn "Spotlight indexes $n files in $(_perf_tilde "$d"), a package store no one searches" \
                "System Settings > Spotlight > Search Privacy > + > $(_perf_tilde "$d")   (macOS has no command for this list)"
        fi
    done < <(perf_store_dirs)
    while IFS= read -r d; do
        n="$(_perf_indexed "$d")" || true
        [[ -n "$n" ]] || continue
        asked=1
        if (( n >= min )); then
            flagged=1
            _perf_add note "Spotlight indexes $n files in $(_perf_tilde "$d"). If you never search code with Spotlight, exclude it" \
                "System Settings > Spotlight > Search Privacy > + > $(_perf_tilde "$d")"
        fi
    done < <(perf_code_dirs)
    if (( asked == 1 && flagged == 0 )); then
        _perf_add ok "Spotlight: package stores and repo folders are out of the index"
    fi
    return 0
}

_perf_fix_tm() { run_cmd tmutil addexclusion "$1" && print_success "Time Machine skips $(_perf_tilde "$1")"; }

# Only when a backup destination is set up. A sticky exclusion is an attribute
# on the folder: no root, and `tmutil removeexclusion` undoes it.
_perf_check_time_machine() {
    command_exists tmutil || return 0
    local info d bad=0
    info="$(tmutil destinationinfo 2>&1)" || return 0
    case "$info" in *"No destinations"*|"") return 0 ;; esac
    while IFS= read -r d; do
        case "$(tmutil isexcluded "$d" 2>/dev/null)" in
            "[Included]"*)
                bad=1
                _perf_add warn "Time Machine backs up $(_perf_tilde "$d")" \
                    "tmutil addexclusion $(printf '%q' "$d")" _perf_fix_tm "$d" ;;
        esac
    done < <(perf_store_dirs)
    (( bad == 0 )) && _perf_add ok "Time Machine: package stores are excluded"
    return 0
}

# Low Power Mode about halves CPU throughput. On battery that is a fair trade.
_perf_check_power() {
    command_exists pmset || return 0
    pmset -g batt 2>/dev/null | grep -q "AC Power" || return 0
    if pmset -g 2>/dev/null | grep -Eq '^ *(lowpowermode|powermode) +1( |$)'; then
        _perf_add warn "Low Power Mode is on while plugged in (about half the CPU throughput)" \
            "System Settings > Battery > Low Power Mode > Only on Battery"
    else
        _perf_add ok "Power: Low Power Mode is off on the charger"
    fi
}

# Repos inside a folder iCloud Drive syncs: the sync daemons chase every file
# git writes.
_perf_check_icloud() {
    command_exists defaults || return 0
    local key dir n
    for key in Desktop Documents; do
        [[ "$(defaults read com.apple.finder "FXICloudDrive$key" 2>/dev/null)" == 1 ]] || continue
        dir="$HOME/$key"
        [[ -d "$dir" ]] || continue
        # Not inside a *.nosync folder: iCloud skips those, and it is the advice below.
        n="$(find "$dir" -maxdepth 3 -name '*.nosync' -prune -o -name .git -print 2>/dev/null | wc -l | tr -d ' ')" || true
        if (( ${n:-0} > 0 )); then
            _perf_add warn "$n git repo(s) under ~/$key, which iCloud Drive syncs" \
                "move them out of ~/$key, or into a folder whose name ends in .nosync"
        fi
    done
    return 0
}

# ----------------------------------------------------------------------------
# Linux
# ----------------------------------------------------------------------------

# Every file watcher draws on one per-user inotify budget; parallel agents hit
# the 128 instances first.
_perf_check_inotify() {
    local dir="$PERF_PROC/sys/fs/inotify" inst watches want_watches=262144 lines=""
    [[ -r "$dir/max_user_instances" ]] || return 0
    inst="$(cat "$dir/max_user_instances" 2>/dev/null)" || true
    watches="$(cat "$dir/max_user_watches" 2>/dev/null)" || true
    # Only the keys that are low: a drop-in must never lower a value another
    # file (or a large machine's default) already raised.
    (( ${inst:-0} < 1024 )) && lines="fs.inotify.max_user_instances = 1024\\n"
    (( ${watches:-0} < want_watches )) && lines="${lines}fs.inotify.max_user_watches = 524288\\n"
    if [[ -n "$lines" ]]; then
        _perf_add warn "inotify: $inst instances and $watches watches per user; watchers in several worktrees run out" \
            "printf '$lines' | sudo tee $PERF_ETC/sysctl.d/60-inotify.conf && sudo sysctl --system"
    else
        _perf_add ok "inotify: $inst instances, $watches watches"
    fi
}

_perf_check_swap() {
    [[ -r "$PERF_PROC/swaps" ]] || return 0
    if (( $(wc -l < "$PERF_PROC/swaps") <= 1 )); then
        _perf_add warn "No swap: under memory pressure the kernel kills without warning" \
            "add compressed swap in RAM: zram-tools (Debian, Ubuntu) or zram-generator (Fedora, Arch)"
    else
        _perf_add ok "Swap is present"
    fi
}

# Debian ships PRUNENAMES commented out, so the nightly updatedb walks every
# node_modules.
_perf_check_updatedb() {
    local conf="$PERF_ETC/updatedb.conf"
    [[ -r "$conf" ]] || return 0
    if grep -Eq '^[[:space:]]*PRUNENAMES=.*node_modules' "$conf"; then
        _perf_add ok "locate: updatedb skips node_modules"
    else
        _perf_add note "locate: the nightly updatedb walks node_modules, .git and build output" \
            "in $conf: PRUNENAMES=\".git node_modules target .venv\""
    fi
}

# ----------------------------------------------------------------------------
# Collect, report, apply
# ----------------------------------------------------------------------------

perf_collect() {
    PERF_LEVEL=(); PERF_TITLE=(); PERF_FIX_TEXT=(); PERF_FIX_FN=(); PERF_FIX_ARG=()
    PERF_WARN_TOTAL=0; PERF_AUTO_TOTAL=0
    if is_macos; then
        _perf_check_spotlight
        _perf_check_time_machine
        _perf_check_power
        _perf_check_icloud
    elif is_linux; then
        _perf_check_inotify
        _perf_check_swap
        _perf_check_updatedb
    fi
    _perf_check_nofile
    _perf_check_git
    _perf_check_store_volume
    return 0
}

# perf_report [--brief] — print the findings. --brief leaves out what is fine.
perf_report() {
    local brief=false i
    [[ "${1:-}" == --brief ]] && brief=true
    for i in ${PERF_LEVEL[@]+"${!PERF_LEVEL[@]}"}; do
        case "${PERF_LEVEL[$i]}" in
            ok)   $brief || print_success "${PERF_TITLE[$i]}" ;;
            warn) print_warning "${PERF_TITLE[$i]}" ;;
            note) print_info "${PERF_TITLE[$i]}" ;;
        esac
        if [[ "${PERF_LEVEL[$i]}" != ok && -n "${PERF_FIX_TEXT[$i]}" ]]; then
            if [[ -n "${PERF_FIX_FN[$i]}" ]]; then
                echo "    fix (--fix does this): ${PERF_FIX_TEXT[$i]}"
            else
                echo "    fix: ${PERF_FIX_TEXT[$i]}"
            fi
        fi
    done
    if (( PERF_WARN_TOTAL == 0 )); then
        $brief && print_success "Performance: nothing to change"
    else
        print_info "$PERF_WARN_TOTAL to change, $PERF_AUTO_TOTAL of them by './scripts/perf.sh --fix'. Why: docs/performance.md"
    fi
    return 0
}

# perf_apply [CONFIRM_FN] — run each fix that needs no root. CONFIRM_FN, when
# given, is called with a question and decides (return 0 to go ahead).
perf_apply() {
    local confirm_fn="${1:-}" i done_n=0 offered=0
    for i in ${PERF_LEVEL[@]+"${!PERF_LEVEL[@]}"}; do
        [[ "${PERF_LEVEL[$i]}" == warn && -n "${PERF_FIX_FN[$i]}" ]] || continue
        offered=$((offered + 1))
        if [[ -n "$confirm_fn" ]] && ! "$confirm_fn" "${PERF_FIX_TEXT[$i]} ?"; then
            continue
        fi
        "${PERF_FIX_FN[$i]}" "${PERF_FIX_ARG[$i]}" || print_warning "could not apply: ${PERF_FIX_TEXT[$i]}"
        done_n=$((done_n + 1))
    done
    if (( offered == 0 )); then
        print_info "Nothing here can be fixed without you: see the fix lines above."
    elif (( done_n == 0 )); then
        print_info "Nothing applied."
    fi
    return 0
}
