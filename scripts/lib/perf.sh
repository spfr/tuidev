#!/bin/bash
# scripts/lib/perf.sh — the performance audit: what the OS does in the
# background that competes with agents, and what to change.
#
# perf_collect runs every check for this platform and fills the PERF_* arrays;
# perf_report prints them; perf_apply runs the fixes that need no root and can
# be undone. Everything else is printed as the command or the setting, for you
# to run. Reading is always safe: perf_collect changes nothing.
#
# Every finding says how it was measured (the command, and the threshold it
# is compared against); every fix says how to undo it. perf_apply prints the
# whole plan before it asks anything, asks once per fix, and logs each change
# with its undo in $TUIDEV_STATE_DIR/disk.log (perf_log).
#
# Called by scripts/perf.sh (`make perf`), `update.sh --check|--perf|--all`
# and the end of install.sh. The reasoning behind each check, with sources, is
# in docs/performance.md.
#
# Source after ui.sh, manifest.sh and gitconfig.sh. Honors DRY_RUN.
#
# Besides the settings it checks, it measures: background daemons' CPU since
# boot, memory pressure and swap, free disk, a corporate endpoint agent, and on
# Linux load and a /tmp in RAM. Those report their numbers even when all is
# well, so the full report says how the machine is doing, not only what to fix.
#
# Settings (environment):
#   TUIDEV_PERF_DIRS       extra folders to check, colon-separated (your repos)
#   TUIDEV_PERF_INDEX_MIN  indexed files in a store before it is flagged (1000)

# One finding per index, across parallel arrays (bash 3.2: no associative
# arrays). LEVEL is ok, warn or note. FIX_FN, when set, is a function perf_apply
# calls with FIX_ARG; FIX_TEXT is what the person reads either way. HOW is what
# the check ran and compared against (from _perf_how); UNDO reverses the fix.
PERF_LEVEL=()
PERF_TITLE=()
PERF_FIX_TEXT=()
PERF_FIX_FN=()
PERF_FIX_ARG=()
PERF_HOW=()
PERF_UNDO=()
_PERF_HOW=""
PERF_WARN_TOTAL=0
PERF_AUTO_TOTAL=0

# Where the Linux checks read kernel settings and system config; tests point
# these at fixtures.
PERF_PROC="${PERF_PROC:-/proc}"
PERF_ETC="${PERF_ETC:-/etc}"

# _perf_how TEXT — how the check that follows measures, and its threshold;
# every finding it adds carries this.
_perf_how() { _PERF_HOW="$1"; }

# _perf_add LEVEL TITLE [FIX_TEXT [FIX_FN [FIX_ARG [UNDO]]]]
_perf_add() {
    PERF_LEVEL+=("$1")
    PERF_TITLE+=("$2")
    PERF_FIX_TEXT+=("${3:-}")
    PERF_FIX_FN+=("${4:-}")
    PERF_FIX_ARG+=("${5:-}")
    PERF_UNDO+=("${6:-}")
    PERF_HOW+=("$_PERF_HOW")
    if [[ "$1" == warn ]]; then
        PERF_WARN_TOTAL=$((PERF_WARN_TOTAL + 1))
        [[ -n "${4:-}" ]] && PERF_AUTO_TOTAL=$((PERF_AUTO_TOTAL + 1))
    fi
    return 0
}

# _perf_tilde PATH — PATH with $HOME written as ~, for display.
# shellcheck disable=SC2088  # a literal ~ is the point
_perf_tilde() {
    # $HOME as given, and with doubled slashes squeezed (a HOME built from a
    # TMPDIR that ends in / has one, and the paths found under it do not).
    local h="$HOME" hs
    hs="$(printf '%s' "$HOME" | tr -s /)"
    case "$1" in
        "$h"/*)  printf '~/%s\n' "${1#"$h"/}" ;;
        "$hs"/*) printf '~/%s\n' "${1#"$hs"/}" ;;
        *)       printf '%s\n' "$1" ;;
    esac
}

# perf_log SOURCE ITEM COMMAND EXIT BYTES_BEFORE BYTES_AFTER UNDO — one line
# per change made, appended to $TUIDEV_STATE_DIR/disk.log, tab-separated:
#   TIME SOURCE ITEM COMMAND EXIT BYTES_BEFORE BYTES_AFTER UNDO
# ("-" where a field does not apply). Under DRY_RUN the line is printed, not
# written. Shared by the perf and disk fixes.
perf_log() {
    local line f
    line="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for f in "$1" "$2" "$3" "$4" "${5:--}" "${6:--}" "${7:--}"; do
        f="${f//$'\t'/ }"
        line="$line"$'\t'"${f//$'\n'/ }"
    done
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [DRY RUN] would log: $line"
        return 0
    fi
    mkdir -p "$TUIDEV_STATE_DIR" 2>/dev/null || true
    printf '%s\n' "$line" >> "$TUIDEV_STATE_DIR/disk.log" 2>/dev/null \
        || print_warning "could not write $(_perf_tilde "$TUIDEV_STATE_DIR/disk.log")"
    return 0
}

# perf_go_env NAME — GOCACHE or GOMODCACHE without running go, which updates
# its telemetry counters on every run: the environment, then the file
# `go env -w` writes, then go's defaults. Empty when the cache is off.
# _perf_go_file FILE KEY — KEY's value in go's env file, if it is readable.
_perf_go_file() {
    if [[ "$1" != off && -r "$1" ]]; then
        awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$1" 2>/dev/null || true
    fi
    return 0
}

perf_go_env() {
    local v="" f gp
    case "$1" in
        GOCACHE)    v="${GOCACHE:-}" ;;
        GOMODCACHE) v="${GOMODCACHE:-}" ;;
    esac
    if is_macos; then f="${GOENV:-$HOME/Library/Application Support/go/env}"; else f="${GOENV:-${XDG_CONFIG_HOME:-$HOME/.config}/go/env}"; fi
    [[ -n "$v" ]] || v="$(_perf_go_file "$f" "$1")"
    if [[ -z "$v" && "$1" == GOMODCACHE ]]; then
        gp="${GOPATH:-$(_perf_go_file "$f" GOPATH)}"
        v="${gp%%:*}"; v="${v:-$HOME/go}/pkg/mod"
    fi
    if [[ -z "$v" && "$1" == GOCACHE ]]; then
        if is_macos; then v="$HOME/Library/Caches/go-build"; else v="${XDG_CACHE_HOME:-$HOME/.cache}/go-build"; fi
    fi
    [[ "$v" == off ]] && v=""
    printf '%s\n' "$v"
}

# perf_pnpm_rc_files — pnpm's own rc file, where a global store-dir can be
# set. ~/.npmrc can set one too, but it holds registry tokens: it is a
# credential path and is never read here.
perf_pnpm_rc_files() {
    if is_macos; then printf '%s\n' "$HOME/Library/Preferences/pnpm/rc"
    else printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/pnpm/rc"
    fi
}

# perf_pnpm_store — pnpm's store folder without running pnpm, which writes
# under its home when asked (`pnpm store path`): npm_config_store_dir, then
# store-dir in perf_pnpm_rc_files (read as text, that one key only, nothing
# run), then pnpm's defaults: $PNPM_HOME/store, $XDG_DATA_HOME/pnpm/store,
# ~/Library/pnpm/store on macOS, ~/.local/share/pnpm/store on Linux. A
# store-dir in ~/.npmrc (never read) or a project's own .npmrc is not seen.
perf_pnpm_store() {
    local v="${npm_config_store_dir:-}" f
    while IFS= read -r f; do
        [[ -z "$v" && -f "$f" ]] || continue
        v="$(awk '{
                k = $0; sub(/=.*/, "", k); gsub(/[ \t]/, "", k)
                if (k == "store-dir") { sub(/^[^=]*=[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }
            }' "$f" 2>/dev/null)" || v=""
    done < <(perf_pnpm_rc_files)
    case "$v" in \~/*) v="$HOME/${v#\~/}" ;; esac
    if [[ -z "$v" ]]; then
        if [[ -n "${PNPM_HOME:-}" ]]; then v="$PNPM_HOME/store"
        elif [[ -n "${XDG_DATA_HOME:-}" ]]; then v="$XDG_DATA_HOME/pnpm/store"
        elif is_macos; then v="$HOME/Library/pnpm/store"
        else v="$HOME/.local/share/pnpm/store"
        fi
    fi
    printf '%s\n' "$v"
}

# perf_store_dirs — the package stores and caches on this machine, one per
# line: the directories installers fill with hundreds of thousands of files
# that no one searches and no backup needs. Only ones that exist. Asks no
# tool that writes when asked: npm runs with its debug log off.
perf_store_dirs() {
    local d
    {
        command_exists pnpm && perf_pnpm_store
        command_exists go && perf_go_env GOMODCACHE
        command_exists uv && uv cache dir 2>/dev/null
        command_exists npm && npm_config_logs_max=0 npm config get cache 2>/dev/null
        printf '%s\n' "${BUN_INSTALL_CACHE_DIR:-$HOME/.bun/install/cache}" \
            "${CARGO_HOME:-$HOME/.cargo}/registry" "$HOME/.gradle/caches" "$HOME/.m2/repository"
    } | while IFS= read -r d; do
        if [[ -n "$d" && -d "$d" ]]; then printf '%s\n' "$d"; fi
    done | awk '!seen[$0]++'
    return 0
}

# _perf_file_id PATH — device:inode, so two spellings of one folder (a
# symlink, ~/Projects and ~/projects on a case-insensitive disk) are one.
# stat describes a symlink itself, so the folder is resolved first.
_perf_file_id() {
    local real
    real="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
    _stat_fmt '%d:%i' '%d:%i' "$real" 2>/dev/null || true
}

# _perf_human BYTES — "8.1 GB", "374 GB", "512 MB": 1024-based, as du counts,
# one decimal below 10. awk's %d is 32-bit in some mawk builds, so %.0f.
_perf_human() {
    awk -v b="${1:-0}" 'BEGIN {
        split("B KB MB GB TB PB", u, " "); i = 1
        while (b >= 1024 && i < 6) { b /= 1024; i++ }
        if (i == 1 || b >= 10) printf "%.0f %s\n", b, u[i]; else printf "%.1f %s\n", b, u[i]
    }'
}

# perf_code_dirs — folders that usually hold repos, plus TUIDEV_PERF_DIRS;
# each folder once, by device:inode (a case-insensitive disk has ~/projects
# and ~/Projects as one folder).
perf_code_dirs() {
    local d id seen=$'\n' extra=()
    if [[ -n "${TUIDEV_PERF_DIRS:-}" ]]; then
        IFS=: read -r -a extra <<< "$TUIDEV_PERF_DIRS"
    fi
    for d in ${extra[@]+"${extra[@]}"} "$HOME/workspace" "$HOME/code" "$HOME/Code" "$HOME/src" \
        "$HOME/dev" "$HOME/Developer" "$HOME/projects" "$HOME/Projects" "$HOME/repos" "$HOME/work"; do
        [[ -n "$d" && -d "$d" ]] || continue
        id="$(_perf_file_id "$d")"
        [[ -n "$id" ]] || id="$d"
        case "$seen" in *$'\n'"$id"$'\n'*) continue ;; esac
        seen="$seen$id"$'\n'
        printf '%s\n' "$d"
    done
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
    _perf_how "looks for a 'ulimit -n' line in ~/.zshrc, ~/.zshrc.local, ~/.zshenv, ~/.zprofile, ~/.bashrc, ~/.profile (not a live shell)"
    local f
    for f in "$HOME/.zshrc" "$HOME/.zshrc.local" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.profile"; do
        if [[ -f "$f" ]] && grep -Eq '^[^#]*ulimit .*-[SH]*n' "$f"; then
            _perf_add ok "Open files: your shell raises the limit ($(_perf_tilde "$f"))"
            return 0
        fi
    done
    _perf_add warn "Open files: your shell starts at the system's soft limit (256 on macOS, 1024 on Linux)" \
        "./scripts/update.sh --configs   (the shipped .zshrc raises it to 65536), or add 'ulimit -n 65536' to your shell profile" \
        "" "" "delete the ulimit line"
}

_perf_fix_git() { tuidev_git_default "$1" true; }

_perf_check_git() {
    command_exists git || return 0
    _perf_how "git config --global --includes --get core.fsmonitor and core.untrackedCache: wants fsmonitor off globally, untrackedCache set"
    if [[ "$(git config --global --includes --get core.fsmonitor 2>/dev/null)" == true ]]; then
        _perf_add warn "git: core.fsmonitor is on globally, so every worktree starts a daemon that outlives it" \
            "git config --global --unset core.fsmonitor   (set it per repo, in the large ones)" \
            "" "" "git config --global core.fsmonitor true"
    fi
    if [[ -z "$(git config --global --includes --get core.untrackedCache 2>/dev/null)" ]]; then
        _perf_add warn "git: core.untrackedCache is unset (about 2x faster status on a large tree)" \
            "git config --global core.untrackedCache true" _perf_fix_git core.untrackedCache \
            "git config --global --unset core.untrackedCache"
    else
        _perf_add ok "git: core.untrackedCache is set"
    fi
}

# _perf_duration SECONDS — "3 d 4 h", "5 h 12 m", "42 m".
_perf_duration() {
    local s="$1"
    if (( s >= 86400 )); then echo "$((s / 86400)) d $((s % 86400 / 3600)) h"
    elif (( s >= 3600 )); then echo "$((s / 3600)) h $((s % 3600 / 60)) m"
    else echo "$((s / 60)) m"
    fi
}

# Free space on the volume home is on. Below 10% free, APFS (copy-on-write,
# snapshots) and ext4 alike slow down on writes, and a build's temp files are
# the first to hit the wall. Local Time Machine snapshots hold the space of
# files deleted since they were taken, for about a day.
_perf_check_disk_free() {
    _perf_how "df -Pk ~ for free space (warns below 10%); tmutil listlocalsnapshots / for local snapshots"
    local line total="" avail="" pct snaps=0 text
    line="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $2, $4 }')" || true
    read -r total avail <<< "$line" || true
    [[ "$total" =~ ^[1-9][0-9]*$ && "$avail" =~ ^[0-9]+$ ]] || return 0
    pct=$(( avail * 100 / total ))
    if is_macos && command_exists tmutil; then
        snaps="$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com\.apple\.TimeMachine')" || true
    fi
    text="Disk: $pct% free on the volume your home is on ($(_perf_human $((avail * 1024))) of $(_perf_human $((total * 1024))))"
    if [[ "$snaps" =~ ^[1-9][0-9]*$ ]]; then
        text="$text; $snaps local Time Machine snapshot(s) hold deleted files' space for about a day"
    fi
    if (( pct < 10 )); then
        _perf_add warn "$text. Below 10% free, writes and builds slow down" \
            "make disk   (what dev tools and agents left on disk, with the command to reclaim each)"
    else
        _perf_add ok "$text"
    fi
}

# The process table as `TIME COMM` lines, read once by perf_collect and shared
# by the daemon and endpoint checks. Empty when ps is denied (a sandbox): those
# checks then say nothing.
_PERF_PS=""

# awk: secs(TIME) — ps's cumulative CPU time in seconds. macOS prints MM:SS.ss,
# minutes past 59 included (123:45.67); procps prints [DD-]HH:MM:SS.
_PERF_AWK_SECS='
function secs(t,   d, k, n, p) {
    d = 0; k = index(t, "-")
    if (k > 0) { d = substr(t, 1, k - 1) + 0; t = substr(t, k + 1) }
    n = split(t, p, ":")
    if (n == 3) return d * 86400 + p[1] * 3600 + p[2] * 60 + p[3]
    if (n == 2) return d * 86400 + p[1] * 60 + p[2]
    return d * 86400 + t
}'

# _perf_cpu_seconds TIME — one ps TIME field, in whole seconds.
_perf_cpu_seconds() {
    printf '%s\n' "$1" | awk "$_PERF_AWK_SECS"' { printf "%d\n", secs($1) }'
}

# _perf_daemon_times — "KIND<TAB>SECONDS<TAB>LABEL" per background service
# worth timing, most CPU first. KIND is sys for the OS's own, edr for a
# corporate endpoint security agent. The name is the last part of ps's COMM,
# which on macOS is the executable's full path (spaces included).
_perf_daemon_times() {
    [[ -n "$_PERF_PS" ]] || return 0
    printf '%s\n' "$_PERF_PS" | awk "$_PERF_AWK_SECS"'
        function edr(n) {
            if (n == "falcond" || n == "falcon-sensor" || n ~ /^com\.crowdstrike\./) return "CrowdStrike Falcon"
            if (n ~ /^[Ss]ophos/) return "Sophos"
            if (n == "sentineld" || n ~ /^SentinelAgent/) return "SentinelOne"
            if (n == "JamfProtect" || n ~ /^com\.jamf\.protect/) return "Jamf Protect"
            if (n ~ /^wdavdaemon/) return "Microsoft Defender"
            return ""
        }
        $1 == "TIME" { next }
        {
            t = $1; n = $0
            sub(/^[ \t]*[^ \t]+[ \t]+/, "", n); sub(/.*\//, "", n)
            k = "sys"; g = ""
            if (n == "mds" || n == "mds_stores" || n ~ /^mdworker/) g = "Spotlight"
            else if (n == "fseventsd" || n == "syspolicyd" || n == "logd") g = n
            else if (n == "XprotectService" || n == "xprotectd") g = "XProtect"
            else { k = "edr"; g = edr(n) }
            if (g == "") next
            if (!(g in sum)) { order[++m] = g; kind[g] = k }
            sum[g] += secs(t)
        }
        END { for (i = 1; i <= m; i++) printf "%s\t%.0f\t%s\n", kind[order[i]], sum[order[i]], order[i] }' \
        | sort -t "$(printf '\t')" -k2,2nr || true
}

# _perf_uptime — seconds since boot, from kern.boottime; empty when sysctl
# cannot be asked.
_perf_uptime() {
    local boot
    boot="$(sysctl -n kern.boottime 2>/dev/null | awk -F'[=,]' '{ print $2 + 0; exit }')" || true
    [[ "$boot" =~ ^[1-9][0-9]*$ ]] || return 0
    echo $(( $(date +%s) - boot ))
}

_perf_daemon_fix() {
    case "$1" in
        Spotlight) echo "a rebuild after a macOS update settles within a day; otherwise keep package stores and repos out of the index (docs/performance.md#1-spotlight)" ;;
        fseventsd) echo "fewer file watchers: stop dev servers and watch-mode tests in idle worktrees ('agents' flags them)" ;;
        syspolicyd|XProtect) echo "first-run scans of freshly built binaries (docs/performance.md#2-xprotect-and-freshly-built-binaries)" ;;
        logd) echo "a process is logging heavily: 'log stream' for a minute shows which" ;;
        *) echo "ask IT for exclusions on your repos folder and package stores (docs/performance.md#9-endpoint-security-agents)" ;;
    esac
}

# Spotlight on the test Mac, with agents running, averaged about 4% of one
# core (docs/performance.md#first-look). Averaged over the whole uptime, 15%
# means a service spent a seventh of every hour flat out: an index rebuild,
# a package store churning inside the index, a scanner chasing every file a
# build writes. Within an hour of boot the average is still the post-boot
# indexing burst, so nothing is judged then; the numbers are still shown.
PERF_DAEMON_PCT=15

_perf_check_daemons() {
    _perf_how "ps -Ao time,comm (CPU time since boot) over sysctl -n kern.boottime: warns from ${PERF_DAEMON_PCT}% of one core, judged after the first hour"
    local up times secs label pct summary="" shown=0 hot=0
    up="$(_perf_uptime)" || true
    [[ "$up" =~ ^[1-9][0-9]*$ ]] || return 0
    times="$(_perf_daemon_times)" || true
    [[ -n "$times" ]] || return 0
    while IFS=$'\t' read -r _ secs label; do
        [[ -n "$label" ]] || continue
        pct="$(awk -v s="$secs" -v u="$up" 'BEGIN { printf "%.1f", s * 100 / u }')"
        if (( up >= 3600 )) && awk -v p="$pct" -v t="$PERF_DAEMON_PCT" 'BEGIN { exit !(p >= t) }'; then
            hot=1
            _perf_add warn "$label has used $pct% of a core since boot ($(_perf_duration "$up") ago)" "$(_perf_daemon_fix "$label")"
        fi
        if (( shown < 3 )); then
            summary="${summary:+$summary, }$label $pct%"
            shown=$((shown + 1))
        fi
    done <<< "$times"
    (( hot == 1 )) || _perf_add ok "Background daemons, share of one core since boot ($(_perf_duration "$up")): $summary"
    return 0
}

# A corporate endpoint agent scans every file a build or an install writes.
# It is not yours to turn off; IT can exclude the repos and the stores.
_perf_check_endpoint() {
    _perf_how "ps -Ao time,comm, names matched: falcond, falcon-sensor, Sophos*, sentineld, SentinelAgent, JamfProtect, wdavdaemon"
    local names
    names="$(_perf_daemon_times | awk -F'\t' '$1 == "edr" { s = s (s == "" ? "" : ", ") $3 } END { print s }')" || true
    [[ -n "$names" ]] || return 0
    _perf_add note "Endpoint security: $names is running, and scans what builds and installs write" \
        "ask IT for exclusions on your repos folder and package stores; don't turn it off (docs/performance.md#9-endpoint-security-agents)"
}

# _perf_memory_report LABEL PRESSURE RAM_BYTES SWAP_USED_BYTES — PRESSURE is
# normal, warn, critical or empty. A little swap is routine on macOS and with
# zram; swap past a quarter of RAM means the working set has outgrown memory.
_perf_memory_report() {
    local label="$1" pressure="$2" ram="${3:-0}" swap="${4:-0}" text
    text="$(_perf_human "$swap") of swap in use"
    if (( ram > 0 )); then text="$text, $(_perf_human "$ram") RAM"; fi
    case "$pressure" in
        warn|critical)
            _perf_add warn "$label pressure is $pressure now; $text" "agents mem   (who holds the memory, by footprint)"
            return 0 ;;
    esac
    if (( ram > 0 && swap * 4 >= ram )); then
        _perf_add note "$label $text, a quarter of RAM or more: the working set has outgrown memory" \
            "agents mem   (who holds the memory, by footprint)"
    else
        _perf_add ok "$label ${pressure:+pressure $pressure, }$text"
    fi
}

# vm.swapusage reads "total = 2048.00M  used = 1024.50M  free = ...".
_perf_check_memory_mac() {
    command_exists sysctl || return 0
    _perf_how "sysctl -n kern.memorystatus_vm_pressure_level, vm.swapusage, hw.memsize: warns on pressure warn or critical, notes swap from a quarter of RAM"
    local level ram swap pressure=""
    level="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" || true
    ram="$(sysctl -n hw.memsize 2>/dev/null)" || true
    swap="$(sysctl -n vm.swapusage 2>/dev/null | awk '{
        for (i = 1; i < NF; i++) if ($i == "used") {
            v = $(i + 2); m = 1
            if (v ~ /G$/) m = 1024; else if (v ~ /K$/) m = 1 / 1024
            sub(/[A-Za-z]+$/, "", v); printf "%.0f\n", v * m * 1048576; exit
        } }')" || true
    case "$level" in 1) pressure=normal ;; 2) pressure=warn ;; 4) pressure=critical ;; esac
    [[ -n "$pressure" || -n "$swap" ]] || return 0
    [[ "$ram" =~ ^[0-9]+$ ]] || ram=0
    [[ "$swap" =~ ^[0-9]+$ ]] || swap=0
    _perf_memory_report "Memory:" "$pressure" "$ram" "$swap"
}

# Clones and hardlinks cannot cross a volume: a store on another one makes
# every install a full copy.
_perf_check_store_volume() {
    _perf_how "df -P on your home and on each package store: wants the same device"
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
    _perf_how "mdfind -onlyin DIR -count for each package store and code folder: flags ${TUIDEV_PERF_INDEX_MIN:-1000} indexed files or more"
    local d n min="${TUIDEV_PERF_INDEX_MIN:-1000}" flagged=0 asked=0
    while IFS= read -r d; do
        n="$(_perf_indexed "$d")" || true
        [[ -n "$n" ]] || continue
        asked=1
        if (( n >= min )); then
            flagged=1
            _perf_add warn "Spotlight indexes $n files in $(_perf_tilde "$d"), a package store no one searches" \
                "System Settings > Spotlight > Search Privacy > + > $(_perf_tilde "$d")   (macOS has no command for this list)" \
                "" "" "System Settings > Spotlight > Search Privacy > select it > -"
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
    _perf_how "tmutil destinationinfo, then tmutil isexcluded for each package store: wants them excluded"
    local info d bad=0
    info="$(tmutil destinationinfo 2>&1)" || return 0
    case "$info" in *"No destinations"*|"") return 0 ;; esac
    while IFS= read -r d; do
        case "$(tmutil isexcluded "$d" 2>/dev/null)" in
            "[Included]"*)
                bad=1
                _perf_add warn "Time Machine backs up $(_perf_tilde "$d")" \
                    "tmutil addexclusion $(printf '%q' "$d")" _perf_fix_tm "$d" \
                    "tmutil removeexclusion $(printf '%q' "$d")" ;;
        esac
    done < <(perf_store_dirs)
    (( bad == 0 )) && _perf_add ok "Time Machine: package stores are excluded"
    return 0
}

# Low Power Mode about halves CPU throughput. On battery that is a fair trade.
_perf_check_power() {
    command_exists pmset || return 0
    _perf_how "pmset -g batt (on the charger?) and pmset -g (lowpowermode, powermode): wants it off on AC"
    pmset -g batt 2>/dev/null | grep -q "AC Power" || return 0
    if pmset -g 2>/dev/null | grep -Eq '^ *(lowpowermode|powermode) +1( |$)'; then
        _perf_add warn "Low Power Mode is on while plugged in (about half the CPU throughput)" \
            "System Settings > Battery > Low Power Mode > Only on Battery" \
            "" "" "System Settings > Battery > Low Power Mode > Always"
    else
        _perf_add ok "Power: Low Power Mode is off on the charger"
    fi
}

# Repos inside a folder iCloud Drive syncs: the sync daemons chase every file
# git writes.
_perf_check_icloud() {
    command_exists defaults || return 0
    _perf_how "defaults read com.apple.finder FXICloudDriveDesktop and FXICloudDriveDocuments, then find .git to depth 3 outside *.nosync"
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
    _perf_how "reads $dir/max_user_instances and max_user_watches: wants 1024 and $want_watches or more"
    inst="$(cat "$dir/max_user_instances" 2>/dev/null)" || true
    watches="$(cat "$dir/max_user_watches" 2>/dev/null)" || true
    # Only the keys that are low: a drop-in must never lower a value another
    # file (or a large machine's default) already raised.
    (( ${inst:-0} < 1024 )) && lines="fs.inotify.max_user_instances = 1024\\n"
    (( ${watches:-0} < want_watches )) && lines="${lines}fs.inotify.max_user_watches = 524288\\n"
    # sysctl applies drop-ins in name order and the last one wins, so the file
    # is named to sort after every NN-name.conf; any that set these keys today
    # are named, since one of them is where the low value comes from.
    local f="$PERF_ETC/sysctl.d/zz-tuidev-inotify.conf" setters=""
    if [[ -n "$lines" ]]; then
        setters="$(grep -l '^[[:space:]]*fs\.inotify\.max_user_' "$PERF_ETC"/sysctl.d/*.conf 2>/dev/null \
            | while IFS= read -r p; do basename "$p"; done | tr '\n' ' ')" || true
        _perf_add warn "inotify: $inst instances and $watches watches per user; watchers in several worktrees run out${setters:+ (set today by: ${setters% })}" \
            "printf '$lines' | sudo tee $f && sudo sysctl --system" \
            "" "" "sudo rm $f && sudo sysctl --system"
    else
        _perf_add ok "inotify: $inst instances, $watches watches"
    fi
}

_perf_check_swap() {
    [[ -r "$PERF_PROC/swaps" ]] || return 0
    _perf_how "reads $PERF_PROC/swaps and $PERF_PROC/meminfo: wants swap present; notes swap in use from a quarter of RAM"
    if (( $(wc -l < "$PERF_PROC/swaps") <= 1 )); then
        _perf_add warn "No swap: under memory pressure the kernel kills without warning" \
            "add compressed swap in RAM: zram-tools (Debian, Ubuntu) or zram-generator (Fedora, Arch)" \
            "" "" "remove the package you installed"
        return 0
    fi
    local mem
    mem="$(awk '$1 == "MemTotal:" { r = $2 } $1 == "SwapTotal:" { t = $2 } $1 == "SwapFree:" { f = $2 }
        END { if (r > 0) printf "%.0f %.0f\n", r * 1024, (t - f) * 1024 }' "$PERF_PROC/meminfo" 2>/dev/null)" || true
    if [[ -n "$mem" ]]; then
        # shellcheck disable=SC2086  # two numbers, split on purpose
        _perf_memory_report "Swap is present:" "" $mem
    else
        _perf_add ok "Swap is present"
    fi
}

# Load over five minutes against the cores: above it, work waits for a CPU.
_perf_check_load() {
    [[ -r "$PERF_PROC/loadavg" ]] || return 0
    _perf_how "reads $PERF_PROC/loadavg (5-minute) against the processors in $PERF_PROC/cpuinfo: warns above one per core"
    local load cores
    load="$(awk '{ print $2; exit }' "$PERF_PROC/loadavg" 2>/dev/null)" || true
    cores="$(grep -c '^processor' "$PERF_PROC/cpuinfo" 2>/dev/null)" || true
    if ! [[ "$cores" =~ ^[0-9]+$ ]] || (( cores == 0 )); then
        cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" || true
    fi
    [[ -n "$load" && "$cores" =~ ^[0-9]+$ ]] || return 0
    if awk -v l="$load" -v c="$cores" 'BEGIN { exit !(l > c) }'; then
        _perf_add warn "Load: $load over 5 minutes on $cores cores, more work ready to run than cores" \
            "agents hogs   (who is using the CPU)"
    else
        _perf_add ok "Load: $load over 5 minutes on $cores cores"
    fi
}

# Debian 13 mounts /tmp as tmpfs, up to half the RAM by default. Not wrong,
# worth knowing: a build or a worktree there lives in memory.
_perf_check_tmp() {
    [[ -r "$PERF_PROC/mounts" ]] || return 0
    _perf_how "reads $PERF_PROC/mounts for /tmp"
    local opts size
    opts="$(awk '$2 == "/tmp" && $3 == "tmpfs" { print $4; exit }' "$PERF_PROC/mounts" 2>/dev/null)" || true
    [[ -n "$opts" ]] || return 0
    size="$(printf '%s\n' "$opts" | tr ',' '\n' | awk -F= '$1 == "size" { print $2; exit }')" || true
    case "$size" in
        "")       size="half the RAM" ;;
        *%)       size="$size of RAM" ;;
        *[kK])    size="$(_perf_human $(( ${size%?} * 1024 )))" ;;
        *[mM])    size="$(_perf_human $(( ${size%?} * 1048576 )))" ;;
        *[gG])    size="$(_perf_human $(( ${size%?} * 1073741824 )))" ;;
    esac
    _perf_add ok "/tmp is tmpfs, in RAM (up to $size): a build or worktree there uses memory"
}

# Debian ships PRUNENAMES commented out, so the nightly updatedb walks every
# node_modules.
_perf_check_updatedb() {
    local conf="$PERF_ETC/updatedb.conf"
    [[ -r "$conf" ]] || return 0
    _perf_how "reads PRUNENAMES in $conf: wants node_modules in it"
    if grep -Eq '^[[:space:]]*PRUNENAMES=.*node_modules' "$conf"; then
        _perf_add ok "locate: updatedb skips node_modules"
    else
        _perf_add note "locate: the nightly updatedb walks node_modules, .git and build output" \
            "in $conf: PRUNENAMES=\".git node_modules target .venv\"" \
            "" "" "put the previous PRUNENAMES line back"
    fi
}

# ----------------------------------------------------------------------------
# Collect, report, apply
# ----------------------------------------------------------------------------

perf_collect() {
    PERF_LEVEL=(); PERF_TITLE=(); PERF_FIX_TEXT=(); PERF_FIX_FN=(); PERF_FIX_ARG=(); PERF_HOW=(); PERF_UNDO=()
    PERF_WARN_TOTAL=0; PERF_AUTO_TOTAL=0
    _PERF_PS="$(ps -Ao time,comm 2>/dev/null)" || _PERF_PS=""
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
    # Measured: numbers even when nothing is wrong.
    if is_macos; then
        _perf_check_daemons
        _perf_check_memory_mac
    elif is_linux; then
        _perf_check_load
        _perf_check_tmp
    fi
    _perf_check_disk_free
    _perf_check_endpoint
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
        if ! $brief && [[ -n "${PERF_HOW[$i]}" ]]; then
            echo "    how: ${PERF_HOW[$i]}"
        fi
        if [[ "${PERF_LEVEL[$i]}" != ok && -n "${PERF_FIX_TEXT[$i]}" ]]; then
            if [[ -n "${PERF_FIX_FN[$i]}" ]]; then
                echo "    fix (--fix does this): ${PERF_FIX_TEXT[$i]}"
            else
                echo "    fix: ${PERF_FIX_TEXT[$i]}"
            fi
            [[ -z "${PERF_UNDO[$i]}" ]] || echo "    undo: ${PERF_UNDO[$i]}"
        fi
    done
    if (( PERF_WARN_TOTAL == 0 )); then
        $brief && print_success "Performance: nothing to change"
    else
        print_info "$PERF_WARN_TOTAL to change, $PERF_AUTO_TOTAL of them by './scripts/perf.sh --fix'. Why: docs/performance.md"
    fi
    # Sizing the caches takes du over each, too slow for every update, so the
    # report only names the command.
    $brief || print_info "Disk: 'make disk' lists what dev tools and agents left on disk, with the command to reclaim each"
    return 0
}

# perf_plan — print every fix --fix would offer, with its undo, before any
# question is asked. Returns 1 when there is none.
perf_plan() {
    local i n=0
    for i in ${PERF_LEVEL[@]+"${!PERF_LEVEL[@]}"}; do
        [[ "${PERF_LEVEL[$i]}" == warn && -n "${PERF_FIX_FN[$i]}" ]] || continue
        if (( n == 0 )); then print_step "Plan: the fixes --fix offers, each asked separately (default No)"; fi
        n=$((n + 1))
        echo "  $n. ${PERF_FIX_TEXT[$i]}"
        echo "     undo: ${PERF_UNDO[$i]:-none recorded}"
    done
    (( n > 0 ))
}

# perf_apply [CONFIRM_FN] — print the plan, then run each fix that needs no
# root. CONFIRM_FN, when given, is called with a question and decides (return
# 0 to go ahead). Each change is logged with its undo (perf_log).
perf_apply() {
    local confirm_fn="${1:-}" i rc done_n=0 offered=0 skipped=()
    if ! perf_plan; then
        print_info "Nothing here can be fixed without you: see the fix lines above."
        return 0
    fi
    for i in ${PERF_LEVEL[@]+"${!PERF_LEVEL[@]}"}; do
        [[ "${PERF_LEVEL[$i]}" == warn && -n "${PERF_FIX_FN[$i]}" ]] || continue
        offered=$((offered + 1))
        if [[ -n "$confirm_fn" ]] && ! "$confirm_fn" "${PERF_FIX_TEXT[$i]} ?"; then
            skipped+=("${PERF_FIX_TEXT[$i]}: you said no")
            continue
        fi
        rc=0
        "${PERF_FIX_FN[$i]}" "${PERF_FIX_ARG[$i]}" || rc=$?
        perf_log perf "${PERF_FIX_FN[$i]#_perf_fix_}" "${PERF_FIX_TEXT[$i]}" "$rc" - - "${PERF_UNDO[$i]}"
        if (( rc != 0 )); then
            print_warning "could not apply (exit $rc): ${PERF_FIX_TEXT[$i]}"
            continue
        fi
        done_n=$((done_n + 1))
    done
    for i in ${skipped[@]+"${skipped[@]}"}; do print_info "skipped: $i"; done
    if (( done_n == 0 )); then
        print_info "Nothing applied."
    elif [[ "$DRY_RUN" != true ]]; then
        print_success "$done_n of $offered applied; each is in $(_perf_tilde "$TUIDEV_STATE_DIR/disk.log") with its undo"
    fi
    return 0
}
