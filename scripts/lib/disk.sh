#!/bin/bash
# scripts/lib/disk.sh — what developer and agent work has left on disk: the
# caches, stores, runtimes, VM disks, transcripts and build trees, each with
# its size, a verdict, what it is, why it has that verdict, what reclaiming it
# costs, and the command that reclaims it.
#
# disk_collect finds the items and measures them (one du each, a few at a
# time), saying on stderr what it looks at and how; disk_report prints them
# grouped by verdict; disk_explain prints one in full; disk_json prints one
# object for an agent planning a cleanup; disk_apply prints a plan, then asks
# before each of the tools' own cleanup commands, and logs what it ran.
#
# Safety, enforced here (and tested in test_disk.sh). The rule when in doubt
# is to offer nothing: an item that cannot be shown safe is report-only.
#   - Reading writes nothing under $HOME: no tool that writes when asked is
#     run (go, pnpm, fnm), npm runs with its debug log off, uv with
#     --no-cache, git with --no-optional-locks and core.fsmonitor off.
#   - disk_apply is the only path that changes anything. It runs only a
#     tool's own cleanup command from a fixed list (_disk_allowed): the
#     caches of go (build), npm, pnpm, bun, uv, pip and CocoaPods, fnm
#     uninstall and uv python uninstall. Never rm, never a `yours` or
#     `managed` item, never a worktree, never Homebrew: those are report-only.
#   - _disk_fix_reason decides, for the report, the JSON and the run alike,
#     whether an item may run now: a block (global npm packages in a Node
#     version, a venv on a Python, a pnpm store that cannot be confirmed),
#     the path (inside $HOME, not $HOME, /, a symlink or a repo root), and
#     what uses it (its tool running, a fresh write, a process from it, a
#     running shell's fnm link). Right before each command, after the yes,
#     it is asked again with a fresh process table, and a runtime's block is
#     worked out again from the disk.
#   - Each command is asked for separately, default No; without a terminal
#     nothing runs unless DISK_ASSUME_YES (--yes) says so.
#   - Each command run is logged (perf_log, $TUIDEV_STATE_DIR/disk.log) with
#     the bytes before and after; a failure stops that item only.
#
# It is not a Mac cleaner: no app leftovers, browser or system caches,
# Downloads or Trash. Only what dev tools and agents leave behind.
#
# Called by scripts/disk.sh (`make disk`). Source after ui.sh; it sources
# perf.sh (the code folders, the go and pnpm locations, sizes, the log) and
# fnm.sh. Honors DRY_RUN.
#
# Verdicts, one word each:
#   regenerable  a cache a tool rebuilds; safe to clear
#   stale        superseded or unused; safe after a look
#   managed      another tool owns the cleanup; its command is printed
#   yours        never offered for deletion; listed when large, as information
#
# Settings (environment):
#   TUIDEV_PERF_DIRS        extra code folders, colon-separated (shared with perf)
#   TUIDEV_DISK_STALE_DAYS  days without a change before a repo's build output
#                           or a worktree is stale (30)
#   TUIDEV_DISK_DEPTH       how deep to look for repos in a code folder (4)
#   TUIDEV_DISK_JOBS        du processes at a time (8)

_DISK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./perf.sh disable=SC1091
declare -F perf_code_dirs >/dev/null || . "$_DISK_LIB_DIR/perf.sh"
# shellcheck source=./fnm.sh disable=SC1091
. "$_DISK_LIB_DIR/fnm.sh"

# One item per index, across parallel arrays (bash 3.2). KB is du's size.
# WHAT, WHY and COST explain it; RECLAIM is the command a person would run;
# FIX, when set, is the tool's own cleanup command disk_apply may run (words,
# no paths, except a worktree's, which come from REPO and PATH); BLOCK, when
# set, is why --fix must not offer it even so. VERDICT `active` marks build
# output of a repo in use: counted, never listed.
DISK_ID=()
DISK_LABEL=()
DISK_PATH=()
DISK_KB=()
DISK_VERDICT=()
DISK_WHAT=()
DISK_WHY=()
DISK_COST=()
DISK_RECLAIM=()
DISK_FIX=()
DISK_REPO=()
DISK_BLOCK=()
DISK_ACTIVE_REPOS=0
DISK_REPO_ACTIVE=0
DISK_FREE_BYTES=0
DISK_TOTAL_BYTES=0
_DISK_SEEN=$'\n'

# What the report and the JSON list: items from DISK_MIN_KB up (scripts/disk.sh
# sets it from --min), and `yours` items only from DISK_YOURS_MIN_KB, 1 GB
# unless --min names a size.
DISK_MIN_KB=102400
DISK_YOURS_MIN_KB=1048576

# Set by scripts/disk.sh: progress on stderr (and "not present" lines with
# DISK_VERBOSE), whether stdin is a terminal, and --yes.
DISK_PROGRESS=false
DISK_VERBOSE=false
DISK_INTERACTIVE=false
DISK_ASSUME_YES=false

# The fd to find repos with: `auto` looks for fd or fdfind, empty uses find.
# Tests set it.
DISK_FD="${DISK_FD-auto}"

# The ignored folders a worktree may hold and still be removed: build output
# and caches a build or test run recreates. Anything else ignored (a local
# database, a .env, notes) makes the worktree yours.
DISK_BUILD_DIRS="node_modules target .venv dist .next .turbo __pycache__ .pytest_cache coverage"

# The process table (`PID ARGS` lines), read once per collect and again
# before each command; DISK_PS_OK=false when it could not be read, and then
# nothing that depends on it is offered.
DISK_PS=""
DISK_PS_OK=false
# Every venv found (`PYVENV_CFG<TAB>HOME` lines), and whether the search ran
# (not with --quick, and only when a Python is a candidate).
DISK_VENVS=""
DISK_VENVS_SCANNED=false
DISK_QUICK=false

# disk_parse_size SIZE — SIZE (100M, 1.5G, 500MB, 1GiB, 0; plain numbers are
# bytes) in KB; returns 1 when it is not a size.
disk_parse_size() {
    printf '%s\n' "$1" | awk '{
        s = toupper($0); sub(/I?B$/, "", s)
        if (s !~ /^[0-9]+(\.[0-9]+)?[KMGT]?$/) exit 1
        n = s + 0; u = s; sub(/^[0-9.]+/, "", u); m = 1 / 1024
        if (u == "K") m = 1; else if (u == "M") m = 1024; else if (u == "G") m = 1048576; else if (u == "T") m = 1073741824
        printf "%.0f\n", n * m
    }'
}

# _disk_git ARGS... — git that never writes while reading: no optional locks
# (status leaves the index alone), no fsmonitor daemon or hook started.
_disk_git() { git -c core.fsmonitor=false --no-optional-locks "$@"; }

# _disk_say TEXT — a progress line on stderr; --json stays clean.
_disk_say() { if [[ "$DISK_PROGRESS" == true ]]; then echo "  $1" >&2; fi; return 0; }

# _disk_add ID LABEL PATH VERDICT WHAT WHY COST RECLAIM [FIX [KB [REPO]]] —
# once per path; says on stderr what it found and how it will be measured.
_disk_add() {
    case "$_DISK_SEEN" in *$'\n'"$3"$'\n'*) return 0 ;; esac
    _DISK_SEEN="$_DISK_SEEN$3"$'\n'
    DISK_ID+=("$1")
    DISK_LABEL+=("$2")
    DISK_PATH+=("$3")
    DISK_VERDICT+=("$4")
    DISK_WHAT+=("$5")
    DISK_WHY+=("$6")
    DISK_COST+=("$7")
    DISK_RECLAIM+=("$8")
    DISK_FIX+=("${9:-}")
    DISK_KB+=("${10:-}")
    DISK_REPO+=("${11:-}")
    DISK_BLOCK+=("")
    if [[ -n "${10:-}" ]]; then
        _disk_say "$2: $(_perf_tilde "$3") (size from its own tool)"
    else
        _disk_say "$2: $(_perf_tilde "$3") (du -sk $(_disk_q "$3"))"
    fi
    return 0
}

# _disk_block REASON — the item just added must not be offered: REASON says why.
_disk_block() { DISK_BLOCK[${#DISK_BLOCK[@]} - 1]="$1"; }

# _disk_absent LABEL PATH — a place looked at and not there (--verbose).
_disk_absent() {
    if [[ "$DISK_VERBOSE" == true ]]; then _disk_say "not present: $1 ($(_perf_tilde "$2"))"; fi
    return 0
}

# _disk_q PATH — PATH for a command line, quoted for the shell, with $HOME
# written as ~ (outside the quoting, so the shell still expands it).
# shellcheck disable=SC2088  # a literal ~ is the point
_disk_q() {
    local hs
    hs="$(printf '%s' "$HOME" | tr -s /)"   # as _perf_tilde: a doubled slash in $HOME
    case "$1" in
        "$HOME"/*) printf '~/%q\n' "${1#"$HOME"/}" ;;
        "$hs"/*)   printf '~/%q\n' "${1#"$hs"/}" ;;
        *)         printf '%q\n' "$1" ;;
    esac
}

# _disk_home_path PATH — PATH under $HOME as $HOME spells it: git prints
# worktree paths resolved, which differ when the home folder is a symlink.
_DISK_HOME_REAL=""
_disk_home_path() {
    if [[ -n "$_DISK_HOME_REAL" && "$_DISK_HOME_REAL" != "$HOME" && "$1" == "$_DISK_HOME_REAL"/* ]]; then
        printf '%s\n' "$HOME/${1#"$_DISK_HOME_REAL"/}"
    else
        printf '%s\n' "$1"
    fi
}

_disk_mtime() { _stat_fmt '%Y' '%m' "$1" 2>/dev/null || true; }

# _disk_written PATH — when anything in PATH (two levels deep) was last
# written, in words.
_disk_written() {
    local spec
    for spec in "-mmin -60:in the last hour" "-mtime -1:in the last day" "-mtime -7:in the last week" \
        "-mtime -30:in the last month" "-mtime -90:in the last 3 months"; do
        # shellcheck disable=SC2086  # the test is two words on purpose
        if [[ -n "$(find "$1" -maxdepth 2 ${spec%%:*} -print 2>/dev/null | head -n 1)" ]]; then
            echo "written to ${spec#*:}"
            return 0
        fi
    done
    echo "nothing in it written to in 3 months"
}

_disk_cache_home() {
    if is_macos; then echo "$HOME/Library/Caches"; else echo "${XDG_CACHE_HOME:-$HOME/.cache}"; fi
}

# _disk_ask TOOL ARGS... — the first line TOOL prints, run from $HOME;
# nothing when TOOL is missing or fails. Only for tools that write nothing
# when asked (checked: uv cache dir, pip3 cache dir, brew --cache, and npm
# with npm_config_logs_max=0).
_disk_ask() {
    command_exists "$1" || return 0
    (cd "$HOME" && "$@" 2>/dev/null) | awk 'NF { print; exit }' || true
}

# _disk_cache ID LABEL TOOL OWNER FROM PATH WHAT COST RECLAIM [FIX] — a cache
# OWNER rebuilds. FROM says how PATH was found. With TOOL gone, what it left
# is stale and report-only.
_disk_cache() {
    local path="$6"
    if [[ -z "$path" || ! -d "$path" ]]; then
        _disk_absent "$2" "${path:-?}"
        return 0
    fi
    [[ -z "$5" ]] || _disk_say "$2: found with $5"
    if [[ -n "$3" ]] && ! command_exists "$3"; then
        _disk_add "$1" "$2" "$path" stale "$7" "$3 is not installed any more, so nothing uses this; $(_disk_written "$path")" \
            "nothing: $3 is gone" "rm -rf $(_disk_q "$path")"
        return 0
    fi
    _disk_add "$1" "$2" "$path" regenerable "$7" "a cache $4 owns and rebuilds; $(_disk_written "$path")" "$8" "$9" "${10:-}"
}

# ----------------------------------------------------------------------------
# What to look at
# ----------------------------------------------------------------------------

_disk_scan_caches() {
    local c p n
    c="$(_disk_cache_home)"
    _disk_cache go-build "Go build cache" go go "GOCACHE, go's env file or its default (go is not run)" "$(perf_go_env GOCACHE)" \
        "Compiled Go packages, kept so the next build can skip compiling them." \
        "the next build recompiles every package it needs: minutes on a large module" "go clean -cache" "go clean -cache"
    # Report only: the module cache also holds the Go toolchains GOTOOLCHAIN
    # downloaded and private modules that may need credentials to fetch again.
    _disk_cache go-mod "Go module cache" go go "GOMODCACHE, GOPATH, go's env file or its default (go is not run)" "$(perf_go_env GOMODCACHE)" \
        "Every Go module version any build downloaded, and the Go toolchains GOTOOLCHAIN fetched." \
        "every module downloads again (network, minutes), toolchains too, and a private module needs your credentials to fetch; --fix leaves it to you" \
        "go clean -modcache"
    if command_exists npm; then p="$(_disk_ask env npm_config_logs_max=0 npm config get cache)"; else p=""; fi
    _disk_cache npm "npm cache" npm npm "npm config get cache (its debug log off)" "${p:-$HOME/.npm}/_cacache" \
        "Package tarballs npm downloaded, kept for the next install." \
        "the next npm install downloads packages again" "npm cache clean --force" "npm cache clean --force"
    _disk_cache pnpm "pnpm store" pnpm pnpm "npm_config_store_dir, store-dir in pnpm's rc, or pnpm's default (pnpm is not run: it writes when asked; ~/.npmrc is not read: it holds tokens)" "$(perf_pnpm_store)" \
        "Every package your projects' node_modules link to; prune removes only what no project uses, so it frees less than this." \
        "little: only packages no project links to go; an install fetches them again if needed. A store-dir in a project's own .npmrc is not seen" \
        "pnpm store prune" "pnpm store prune"
    # pnpm store prune acts on the store pnpm is configured with. ~/.npmrc can
    # name another one and is never read (it holds registry tokens), so its
    # presence alone holds prune back unless the environment names the store;
    # so does a pnpm rc file that cannot be read.
    if (( ${#DISK_ID[@]} > 0 )) && [[ "${DISK_ID[${#DISK_ID[@]} - 1]}" == pnpm ]]; then
        if [[ -z "${npm_config_store_dir:-}" && -e "$HOME/.npmrc" ]]; then
            _disk_block "pnpm's store could not be confirmed: ~/.npmrc may name another one, and it is not read (it holds tokens)"
        else
            while IFS= read -r p; do
                if [[ -f "$p" ]] && ! cat "$p" >/dev/null 2>&1; then
                    _disk_block "pnpm's store could not be confirmed: $(_perf_tilde "$p") could not be read"
                    break
                fi
            done < <(perf_pnpm_rc_files)
        fi
    fi
    p="${BUN_INSTALL_CACHE_DIR:-$HOME/.bun/install/cache}"
    _disk_cache bun "bun cache" bun bun "" "$p" \
        "Package tarballs bun downloaded, kept for the next install." \
        "the next bun install downloads packages again" "bun pm cache rm" "bun pm cache rm"
    p="$(_disk_ask uv cache dir)"
    _disk_cache uv "uv cache" uv uv "uv cache dir" "${p:-${XDG_CACHE_HOME:-$HOME/.cache}/uv}" \
        "Wheels, sources and environments uv downloaded or built; prune removes the entries nothing uses." \
        "little: only unused entries go; uv fetches them again if needed" "uv cache prune" "uv cache prune"
    p="$(_disk_ask pip3 cache dir)"
    _disk_cache pip "pip cache" pip3 pip "pip3 cache dir" "${p:-$c/pip}" \
        "Wheels and downloads pip kept for the next install." \
        "the next pip install downloads them again" "pip3 cache purge" "pip3 cache purge"
    # Report only: brew cleanup also removes old versions from Homebrew's
    # prefix, outside your home, and even its dry run talks to Homebrew's
    # analytics server.
    p="$(_disk_ask brew --cache)"
    _disk_cache brew "Homebrew downloads" brew Homebrew "brew --cache" "${p:-$c/Homebrew}" \
        "Bottles and source archives Homebrew downloaded, including old versions'." \
        "every download goes, and old versions of installed formulae and casks are removed from Homebrew's prefix (outside your home); current versions stay, and nothing is autoremoved (HOMEBREW_NO_AUTOREMOVE=1); --fix leaves it to you" \
        "HOMEBREW_NO_AUTOREMOVE=1 brew cleanup -s --prune=all"
    p="${CARGO_HOME:-$HOME/.cargo}/registry"
    _disk_cache cargo "Cargo registry" cargo cargo "" "$p" \
        "Crates cargo downloaded and unpacked; cargo has no command that clears them." \
        "the next build downloads the crates it needs again (the index stays)" \
        "rm -rf $(_disk_q "$p/cache") $(_disk_q "$p/src")"
    p="$HOME/.gradle/caches"
    _disk_cache gradle "Gradle caches" "" Gradle "" "$p" \
        "Dependencies and build caches Gradle downloaded or built; Gradle has no command that clears them." \
        "the next build downloads and rebuilds: minutes (stop its daemons first)" "rm -rf $(_disk_q "$p")"
    _disk_cache playwright "Playwright browsers" "" Playwright "" "${PLAYWRIGHT_BROWSERS_PATH:-$c/ms-playwright}" \
        "Browser builds Playwright downloaded for tests." \
        "tests need 'npx playwright install' again: a download per browser" "npx playwright uninstall --all"
    _disk_cache cypress "Cypress binaries" "" Cypress "" "${CYPRESS_CACHE_FOLDER:-$c/Cypress}" \
        "Test runner builds Cypress downloaded, one per version." \
        "nothing for old versions; prune keeps the one in use" "npx cypress cache prune"
    is_macos || return 0
    _disk_cache cocoapods "CocoaPods cache" pod CocoaPods "" "$c/CocoaPods" \
        "Pods CocoaPods downloaded, kept for the next pod install." \
        "the next pod install downloads them again" "pod cache clean --all" "pod cache clean --all"
    p="$HOME/Library/Developer/Xcode/DerivedData"
    _disk_cache xcode-derived "Xcode DerivedData" "" Xcode "" "$p" \
        "Xcode's build products and indexes, per project; Xcode has no command that clears them." \
        "Xcode rebuilds and reindexes each project: minutes (quit Xcode first)" "rm -rf $(_disk_q "$p")"
    p="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    if [[ -d "$p" ]]; then
        n="$(find "$p" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" || true
        _disk_cache xcode-devicesupport "iOS DeviceSupport" "" Xcode "" "$p" \
            "Debug symbols for ${n:-0} iOS version(s), copied from devices you debugged on." \
            "Xcode copies them again when a device on that version connects: minutes per version" \
            "rm -rf $(_disk_q "$p")"
    fi
    p="$HOME/Library/Developer/CoreSimulator"
    if [[ -d "$p" ]]; then
        _disk_add coresimulator "Simulators" "$p" managed "Simulator devices, their runtimes' data and their apps." \
            "Xcode owns them; its command removes only simulators whose runtime is gone" \
            "nothing for unavailable simulators: their runtime is already gone" "xcrun simctl delete unavailable"
    else
        _disk_absent Simulators "$p"
    fi
    return 0
}

# _disk_engine_df ENGINE — "SIZE_BYTES RECLAIMABLE_BYTES" from ENGINE system df
# (docker and podman print decimal units: 1.2GB); nothing when it does not answer.
_disk_engine_df() {
    "$1" system df --format '{{.Size}}|{{.Reclaimable}}' 2>/dev/null | awk -F'|' '
        function bytes(s,   n, u) {
            n = s + 0; u = s; sub(/^[0-9.]+/, "", u); sub(/[ (].*/, "", u)
            if (u == "kB" || u == "KB") return n * 1e3
            if (u == "MB") return n * 1e6
            if (u == "GB") return n * 1e9
            if (u == "TB") return n * 1e12
            return n
        }
        NF >= 2 { s += bytes($1); r += bytes($2); seen = 1 }
        END { if (seen) printf "%.0f %.0f\n", s, r }' || true
}

_disk_scan_containers() {
    local p df size recl
    if command_exists podman; then
        if is_macos; then
            p="${XDG_DATA_HOME:-$HOME/.local/share}/containers/podman/machine"
        else
            p="${XDG_DATA_HOME:-$HOME/.local/share}/containers/storage"
        fi
        if [[ -d "$p" ]]; then
            _disk_say "Podman: asked 'podman system df' what is reclaimable"
            df="$(_disk_engine_df podman)"
            if [[ -n "$df" ]]; then
                recl="$(_perf_human "${df#* }") of the images and containers in it is reclaimable by podman's own prune (podman system df)"
            else
                recl="podman did not answer (is its machine running?); 'podman system df' says what is reclaimable"
            fi
            if is_macos; then
                _disk_add podman "Podman storage" "$p" managed "The disk image of podman's Linux VM, which holds its images and containers." \
                    "podman owns it; $recl" "images re-download on the next pull; the VM's disk may not shrink" "podman image prune -a"
            else
                _disk_add podman "Podman storage" "$p" managed "Podman's images, containers and volumes." \
                    "podman owns it; $recl" "images re-download on the next pull" "podman image prune -a"
            fi
        else
            _disk_absent "Podman storage" "$p"
        fi
    fi
    # Docker's own, when docker is not podman under another name.
    if command_exists docker && ! docker --version 2>/dev/null | grep -qi podman; then
        _disk_say "Docker: asked 'docker system df' for its size and what is reclaimable"
        df="$(_disk_engine_df docker)"
        if [[ -n "$df" ]]; then
            size="${df%% *}"; recl="${df#* }"
            if is_macos; then p="$HOME/Library/Containers/com.docker.docker"; else p="/var/lib/docker"; fi
            _disk_add docker "Docker storage" "$p" managed "Docker's images, containers, volumes and build cache." \
                "docker owns it; $(_perf_human "$recl") of it is reclaimable by docker's own prune (docker system df)" \
                "images re-download on the next pull" "docker image prune -a" "" "$((size / 1024))"
        fi
    fi
    if is_macos; then
        p="$HOME/Library/Application Support/com.apple.container"
        if [[ -d "$p" ]]; then
            _disk_add apple-container "Apple container storage" "$p" managed \
                "Images and containers of Apple's container CLI." \
                "Apple's container CLI owns this storage ('container image --help'); reported, never touched" \
                "images re-download on the next pull" ""
        else
            _disk_absent "Apple container storage" "$p"
        fi
    fi
    return 0
}

_disk_fnm_dir() {
    local d
    for d in "${FNM_DIR:-}" "${XDG_DATA_HOME:-$HOME/.local/share}/fnm" "$HOME/.fnm" "$HOME/Library/Application Support/fnm"; do
        if [[ -n "$d" && -d "$d/node-versions" ]]; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    return 0
}

# fnm is never run to read: `fnm ls` creates its aliases folder when it is
# missing. The versions are the node-versions folder's entries, the default
# and the other aliases are the links in aliases/.

# _disk_fnm_versions DIR — the installed versions (vX.Y.Z), oldest first.
_disk_fnm_versions() {
    local d
    for d in "$1/node-versions"/v*; do
        if [[ -d "$d" ]]; then printf '%s\n' "${d##*/}"; fi
    done | _fnm_versions
}

# _disk_fnm_alias_version LINK — the version an alias link points at.
_disk_fnm_alias_version() {
    readlink "$1" 2>/dev/null | sed -n 's#.*node-versions/\(v[0-9][0-9.]*\).*#\1#p' || true
}

# _disk_fnm_aliases DIR VERSION — the aliases other than default that point
# at VERSION, comma-separated.
_disk_fnm_aliases() {
    local l out=""
    for l in "$1/aliases"/*; do
        [[ -L "$l" && "${l##*/}" != default ]] || continue
        [[ "$(_disk_fnm_alias_version "$l")" == "$2" ]] && out="${out:+$out, }${l##*/}"
    done
    printf '%s\n' "$out"
}

# _disk_node_globals DIR — the global npm packages installed with the Node
# version in DIR (installation/lib/node_modules), besides npm and corepack,
# comma-separated. fnm uninstall deletes them with the version.
_disk_node_globals() {
    local m="$1/installation/lib/node_modules" e s out=""
    [[ -d "$m" ]] || return 0
    for e in "$m"/* "$m"/@*/*; do
        [[ -e "$e" ]] || continue
        s="${e#"$m"/}"
        # npm and corepack ship with Node; a bare @scope is listed by its packages.
        case "$s" in npm|corepack) continue ;; @*/*) ;; @*) continue ;; esac
        out="${out:+$out, }$s"
    done
    printf '%s\n' "$out"
}

# fnm's per-shell links: `fnm env` makes one, named PID_TIME, for every shell
# that starts, and never removes it. The folders they live in.
_disk_fnm_link_dirs() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/fnm_multishells" "$HOME/Library/Caches/fnm_multishells" \
        "${XDG_RUNTIME_DIR:-/nonexistent}/fnm_multishells"
}

# _disk_fnm_links — one pass over those links, with the live pids from
# DISK_PS as a set (one awk, not one per link): DISK_FNM_LIVE holds
# "PID TARGET" for the links whose shell still runs (only those are read with
# readlink), DISK_FNM_DEAD and DISK_FNM_DEAD_DIR count the others and name
# the folder with the most.
DISK_FNM_LIVE=""
DISK_FNM_DEAD=0
DISK_FNM_DEAD_DIR=""
_disk_fnm_links() {
    local d l pid n best=0 live=""
    DISK_FNM_LIVE=""; DISK_FNM_DEAD=0; DISK_FNM_DEAD_DIR=""
    [[ "$DISK_PS_OK" == true ]] || return 0
    while IFS= read -r d; do
        [[ -d "$d" ]] || continue
        n=0
        while IFS=' ' read -r kind l; do
            if [[ "$kind" == dead ]]; then n="$l"; continue; fi
            pid="${l##*/}"; pid="${pid%%_*}"
            live="$live$pid $(readlink "$l" 2>/dev/null || true)"$'\n'
        done < <({
            printf '%s\n' "$DISK_PS" | awk '{ print "P " $1 }'
            for l in "$d"/*_*; do printf 'L %s\n' "$l"; done
        } | awk '
            $1 == "P" { up[$2] = 1; next }
            {
                p = substr($0, 3); n = p; sub(/.*\//, "", n); sub(/_.*/, "", n)
                if (n in up) print "live " p; else if (p !~ /\*_\*$/) dead++
            }
            END { print "dead " dead + 0 }')
        DISK_FNM_DEAD=$((DISK_FNM_DEAD + n))
        if (( n > best )); then best=$n; DISK_FNM_DEAD_DIR="$d"; fi
    done < <(_disk_fnm_link_dirs)
    DISK_FNM_LIVE="$live"
    return 0
}

# _disk_uv_superseded — reads managed Python keys, prints "KEY NEWER" for each
# one with a newer patch of the same series (implementation, minor, variant,
# platform) installed beside it. A prerelease sorts below its final release.
_disk_uv_superseded() {
    awk '
        function series(key,   n, p, v, m, s, i) {
            n = split(key, p, "-"); v = p[2]
            sub(/^[0-9]+\.[0-9]+\.[0-9a-z]+/, "", v)
            split(p[2], m, ".")
            s = p[1] "-" m[1] "." m[2] v
            for (i = 3; i <= n; i++) s = s "-" p[i]
            return s
        }
        function rank(key,   p, m, v, pre) {
            split(key, p, "-"); split(p[2], m, "."); v = m[3]
            sub(/\+.*/, "", v); pre = (v ~ /[a-z]/) ? 0 : 1
            sub(/[^0-9].*/, "", v)
            return (v + 0) * 2 + pre
        }
        NF {
            s = series($1); keys[++n] = $1; ser[n] = s; r = rank($1)
            if (!(s in best) || r > top[s]) { best[s] = $1; top[s] = r }
        }
        END { for (i = 1; i <= n; i++) if (best[ser[i]] != keys[i]) print keys[i], best[ser[i]] }'
}

# _disk_uv_managed — the Pythons uv installed, by key. --no-cache: listing
# with the cache on takes its lock and writes into it.
_disk_uv_managed() {
    { uv --no-cache python list --managed-python 2>/dev/null || true; } | awk '$2 != "<download" { print $1 }' | sort -u
}

# _disk_find_venvs — every pyvenv.cfg in the places a venv usually lives: the
# code folders (to TUIDEV_DISK_DEPTH + 3, past node_modules and .git), uv's
# tools, pipx, ~/.virtualenvs, poetry and hatch. Fills DISK_VENVS with
# `CFG<TAB>HOME` lines.
_disk_find_venvs() {
    local d depth=$(( ${TUIDEV_DISK_DEPTH:-4} + 3 )) cache cfg places=()
    cache="$(_disk_cache_home)"
    while IFS= read -r d; do places+=("$d/"); done < <(perf_code_dirs)
    _disk_say "venvs: pyvenv.cfg in the code folders to depth $depth, uv tools, pipx, ~/.virtualenvs, poetry, hatch"
    DISK_VENVS="$(
        {
            for d in ${places[@]+"${places[@]}"}; do
                find "$d" -maxdepth "$depth" \( -name node_modules -o -name .git \) -prune -o -name pyvenv.cfg -type f -print 2>/dev/null
            done
            for d in "$(uv tool dir 2>/dev/null || true)" "$HOME/.local/pipx/venvs" "${XDG_DATA_HOME:-$HOME/.local/share}/pipx/venvs" \
                "$HOME/.virtualenvs" "$cache/pypoetry/virtualenvs" "$HOME/Library/Application Support/hatch/env" \
                "${XDG_DATA_HOME:-$HOME/.local/share}/hatch/env"; do
                [[ -n "$d" && -d "$d" ]] || continue
                find "$d/" -maxdepth 5 -name pyvenv.cfg -type f -print 2>/dev/null
            done
        } | sed 's#//*#/#g' | sort -u | while IFS= read -r cfg; do
            printf '%s\t%s\n' "$cfg" "$(awk -F' *= *' '$1 == "home" { print $2; exit }' "$cfg" 2>/dev/null || true)"
        done
    )" || true
    DISK_VENVS_SCANNED=true
}

# _disk_runtime_block I — why runtime item I must not be removed, from what
# is on disk now, or nothing: global npm packages in a Node version, a venv
# on a Python (or venvs not searched). Asked at the scan, and again right
# before the command.
_disk_runtime_block() {
    local id="${DISK_ID[$1]}" path="${DISK_PATH[$1]}" g venv
    case "$id" in
        node:*)
            g="$(_disk_node_globals "$path")"
            [[ -z "$g" ]] || echo "global npm packages installed with it would go too: $g" ;;
        python:*)
            if [[ "$DISK_VENVS_SCANNED" != true ]]; then
                echo "venvs were not searched (--quick), so one may use it"
                return 0
            fi
            venv="$(printf '%s\n' "$DISK_VENVS" | P="$path" awk -F'\t' 'BEGIN { p = ENVIRON["P"] } index($2, p "/") == 1 || $2 == p { print $1; exit }')" || true
            [[ -z "$venv" ]] || echo "a venv uses it: $(_perf_tilde "${venv%/pyvenv.cfg}")" ;;
    esac
    return 0
}

# Node versions fnm installed with a newer patch of their major beside them
# (never the default), uv's Pythons likewise within a minor, and fnm's
# per-shell links of shells that have ended, when there are many.
_disk_scan_runtimes() {
    local dir def v newer aliases key globals cands versions
    dir="$(_disk_fnm_dir)"
    if [[ -n "$dir" ]]; then
        def="$(_disk_fnm_alias_version "$dir/aliases/default")"
        versions="$(_disk_fnm_versions "$dir")"
        _disk_say "Node: the versions in $(_perf_tilde "$dir/node-versions") and the links in aliases/ (fnm is not run; default: ${def:-none})"
        while IFS=' ' read -r v newer; do
            [[ -n "$v" && "$v" != "$def" ]] || continue
            aliases="$(_disk_fnm_aliases "$dir" "$v")"
            globals="$(_disk_node_globals "$dir/node-versions/$v")"
            _disk_add "node:$v" "Node $v (fnm)" "$dir/node-versions/$v" stale \
                "Node.js $v, installed by fnm${globals:+, with global npm packages: $globals}." \
                "superseded by $newer, the same major, and not fnm's default (${def:-none})${aliases:+; the alias $aliases points at it and goes with it}" \
                "the version and every global npm package installed with it${globals:+ ($globals)}; a project pinned to exactly $v needs 'fnm install ${v#v}' again" \
                "fnm uninstall $v" "fnm uninstall $v"
            _disk_block "$(_disk_runtime_block $((${#DISK_ID[@]} - 1)))"
        done < <(printf '%s\n' "$versions" | awk 'NF {
                major = $1; sub(/^v/, "", major); sub(/\..*/, "", major)
                v[++n] = $1; m[n] = major; newest[major] = $1
            } END { for (i = 1; i <= n; i++) if (newest[m[i]] != v[i]) print v[i], newest[m[i]] }')
    fi
    if (( DISK_FNM_DEAD > 1000 )); then
        _disk_add fnm-links "fnm links of ended shells" "$DISK_FNM_DEAD_DIR" stale \
            "Links fnm makes for every shell that starts (fnm env), one each, which it never removes." \
            "$DISK_FNM_DEAD of them belong to shells that are no longer running (their pid is not in ps)" \
            "nothing: a link whose shell has ended is never used again; links of running shells stay" \
            "for l in $(_disk_q "$DISK_FNM_DEAD_DIR")/*_*; do p=\${l##*/}; kill -0 \"\${p%%_*}\" 2>/dev/null || rm \"\$l\"; done"
    fi
    if command_exists uv; then
        dir="$(uv python dir 2>/dev/null)" || true
        _disk_say "Python: asked 'uv --no-cache python list --managed-python' for superseded patches"
        cands="$(_disk_uv_managed | _disk_uv_superseded || true)"
        if [[ -n "$cands" && "$DISK_QUICK" != true ]]; then _disk_find_venvs; fi
        while read -r key newer; do
            [[ -n "$key" && -n "$dir" && -d "$dir/$key" ]] || continue
            _disk_add "python:$key" "Python $key (uv)" "$dir/$key" stale \
                "A Python build uv installed." \
                "superseded by $newer, the same minor; uv's minor link and new venvs use the newer one" \
                "the build; a venv made against this exact patch breaks, and venvs outside the code folders, uv tools, pipx, ~/.virtualenvs, poetry and hatch are not searched" \
                "uv python uninstall $key" "uv python uninstall $key"
            _disk_block "$(_disk_runtime_block $((${#DISK_ID[@]} - 1)))"
        done <<< "$cands"
    fi
    return 0
}

# _disk_transcripts ID LABEL DIR NOTE — an agent's transcript folder: yours.
_disk_transcripts() {
    local dir="$3" n old
    if [[ ! -d "$dir" ]]; then
        _disk_absent "$2" "$dir"
        return 0
    fi
    _disk_say "$2: counted *.jsonl and the files older than 90 days (find -mtime +90)"
    n="$(find "$dir" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')" || true
    old="$(find "$dir" -type f -mtime +90 -exec du -k {} + 2>/dev/null | awk '{ s += $1 } END { printf "%.0f\n", s * 1024 }')" || true
    _disk_add "$1" "$2" "$dir" yours "Your agent sessions, one transcript per session: ${n:-0} of them." \
        "$(_perf_human "${old:-0}") is in files older than 90 days; $4" \
        "your session history; 'agents report' loses those sessions" ""
}

_disk_scan_agents() {
    local b n=0 oldest=0 now f t
    _disk_transcripts claude "Claude Code transcripts" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" \
        "'agents report' reads them; Claude Code deletes those idle past cleanupPeriodDays (settings.json, default 30)"
    _disk_transcripts codex "Codex sessions" "${CODEX_HOME:-$HOME/.codex}/sessions" \
        "'agents report' reads them; Codex keeps every one"
    b="$TUIDEV_STATE_DIR/backups"
    if [[ ! -d "$b" ]]; then
        _disk_absent "tuidev backups" "$b"
        return 0
    fi
    now="$(date +%s)"
    while IFS= read -r f; do
        n=$((n + 1))
        t="$(_disk_mtime "$f")"
        if [[ "$t" =~ ^[0-9]+$ ]] && (( now - t > oldest )); then oldest=$((now - t)); fi
    done < <(find "$b" -type f 2>/dev/null || true)
    _disk_add backups "tuidev backups" "$b" yours "Copies tuidev took of your files before changing them: $n of them." \
        "the oldest is $((oldest / 86400)) days old; they are how you get a file back" \
        "the copies of your files from before tuidev changed them" ""
}

# _disk_find_repos DIR — git repos under DIR, to TUIDEV_DISK_DEPTH, without
# walking into build output, agents' worktree folders or a repo's .git. The
# trailing slash makes find follow DIR when DIR is a symlink.
_disk_find_repos() {
    local dir="$1" depth="${TUIDEV_DISK_DEPTH:-4}" fd="$DISK_FD"
    if [[ "$fd" == auto ]]; then
        fd="$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)"
    fi
    if [[ -n "$fd" ]]; then
        "$fd" --hidden --no-ignore --type d --max-depth "$depth" --prune --glob \
            --exclude node_modules --exclude .venv --exclude target --exclude .claude --exclude Library \
            '.git' "$dir/" 2>/dev/null || true
    else
        find "$dir/" -maxdepth "$depth" \
            \( -name node_modules -o -name .venv -o -name target -o -name .claude -o -name Library \) -prune \
            -o -name .git -type d -print -prune 2>/dev/null || true
    fi | sed 's#/$##; s#/\.git$##; s#//#/#g'
}

# _disk_last_change DIR GITDIR — the latest of DIR's last commit, its index
# (rewritten by status, add and commit) and DIR itself, as an epoch.
_disk_last_change() {
    local t best=0 c
    c="$(_disk_git -C "$1" log -1 --format=%ct 2>/dev/null)" || true
    for t in "$c" "$(_disk_mtime "$2/index")" "$(_disk_mtime "$1")"; do
        if [[ "$t" =~ ^[0-9]+$ ]] && (( t > best )); then best=$t; fi
    done
    echo "$best"
}

# _disk_merged_into REPO COMMIT — the branch COMMIT is merged into: origin's
# default, main or master; nothing when none.
_disk_merged_into() {
    local b
    for b in "$(_disk_git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)" main master; do
        [[ -n "$b" ]] || continue
        if _disk_git -C "$1" merge-base --is-ancestor "$2" "$b" 2>/dev/null; then
            echo "$b"
            return 0
        fi
    done
    return 0
}

# _disk_is_build_name NAME — whether one path component is a build folder
# (DISK_BUILD_DIRS, compared literally).
_disk_is_build_name() {
    case "$1" in
        node_modules|target|.venv|dist|.next|.turbo|__pycache__|.pytest_cache|coverage) return 0 ;;
    esac
    return 1
}

# _disk_wt_risk WT REPO BRANCH — why removing worktree WT could lose
# something, or nothing. git worktree remove deletes the folder with its
# ignored files, and with untracked files when git does not show them, so:
# any change, any untracked file (whatever status.showUntrackedFiles says),
# any ignored entry that is not build output, and a detached HEAD no branch,
# tag or remote contains. A branch survives the removal with its commits.
#
# git status -z (no quoting, any bytes) with --ignored=matching, which shows
# an ignored folder as one entry. An ignored entry is build output when its
# own last component is a build folder name, or it lies under an ignored
# build folder already seen; the path is split on / with read -a, so spaces,
# * and non-ASCII names are taken literally. Anything else ignored is yours.
_disk_wt_risk() {
    local wt="$1" repo="$2" branch="$3" entry xy p last rc="" untracked="" ignored="" changed="" refs builds=$'\n' skip=0 b
    local -a parts
    while IFS= read -r -d '' entry; do
        if (( skip == 1 )); then skip=0; continue; fi
        case "$entry" in "##rc:"*) rc="${entry#\#\#rc:}"; continue ;; esac
        xy="${entry:0:2}"; p="${entry:3}"
        case "$xy" in
            "??") untracked="${untracked:+$untracked, }$p" ;;
            "!!")
                last=""
                if [[ "$p" != *$'\n'* ]]; then
                    IFS=/ read -r -a parts <<< "${p%/}"
                    (( ${#parts[@]} == 0 )) || last="${parts[${#parts[@]} - 1]}"
                fi
                if [[ -n "$last" ]] && _disk_is_build_name "$last"; then
                    [[ "$p" != */ ]] || builds="$builds$p"$'\n'
                    continue
                fi
                while IFS= read -r b; do
                    [[ -n "$b" ]] || continue
                    case "$p" in "$b"*) last=build; break ;; esac
                done <<< "$builds"
                [[ "$last" == build ]] || ignored="${ignored:+$ignored, }$p" ;;
            R*|C*|?R|?C) changed="${changed:+$changed, }$p"; skip=1 ;;   # the original path follows
            *) changed="${changed:+$changed, }$p" ;;
        esac
    done < <(r=0
        _disk_git -c status.showUntrackedFiles=all -C "$wt" status --porcelain -z \
            --untracked-files=all --ignored=matching --ignore-submodules=none 2>/dev/null || r=$?
        printf '##rc:%s\0' "$r")
    if [[ "$rc" != 0 ]]; then
        echo "git status failed in it, so what it holds is unknown"
        return 0
    fi
    if [[ -n "$changed" ]]; then echo "uncommitted changes: $(_disk_first3 "$changed")"; return 0; fi
    if [[ -n "$untracked" ]]; then echo "untracked files git worktree remove would delete: $(_disk_first3 "$untracked")"; return 0; fi
    if [[ -n "$ignored" ]]; then echo "ignored files that are not build output, which git worktree remove would delete: $(_disk_first3 "$ignored")"; return 0; fi
    if [[ -z "$branch" ]]; then
        refs="$(_disk_git -C "$repo" for-each-ref --contains "$(_disk_git -C "$wt" rev-parse HEAD 2>/dev/null)" \
            --count=1 --format='%(refname:short)' refs/heads refs/tags refs/remotes 2>/dev/null)" || refs=""
        if [[ -z "$refs" ]]; then
            echo "a detached HEAD with commits no branch, tag or remote contains: removing it leaves them to garbage collection"
            return 0
        fi
    fi
    return 0
}

# _disk_first3 LIST — the first three of a comma-separated list, and how many more.
_disk_first3() {
    printf '%s\n' "$1" | awk -F', ' '{ s = $1; for (i = 2; i <= NF && i <= 3; i++) s = s ", " $i; if (NF > 3) s = s " and " NF - 3 " more"; print s }'
}

# _disk_worktree REPO WT HEAD BRANCH NOW DAYS — a linked worktree. Stale when
# nothing changed in DAYS, or when its commit is merged and a day has passed
# (a fresh worktree of main is merged by definition), and _disk_wt_risk finds
# nothing it could lose; otherwise yours. Either way report-only: --fix never
# removes a worktree. The command shown makes git itself refuse untracked
# files, whatever the repo's status.showUntrackedFiles says.
_disk_worktree() {
    local repo="$1" wt="$2" head="$3" branch="${4:-}" now="$5" days="$6" gitdir age into why label id risk keeps refs
    gitdir="$(_disk_git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)" || true
    age=$(( (now - $(_disk_last_change "$wt" "${gitdir:-$wt/.git}")) / 86400 ))
    into=""
    [[ -n "$head" ]] && into="$(_disk_merged_into "$repo" "$head")"
    label="$(basename "$repo") worktree $(basename "$wt")"
    id="worktree:$(_perf_tilde "$wt")"
    _disk_say "worktree $(_perf_tilde "$wt"): branch ${branch:-(detached)}, last change $age day(s) ago, merged: ${into:-no}"
    if (( age >= days )); then
        why="no commit, status or file change in $age days"
    elif [[ -n "$into" ]] && (( age >= 1 )); then
        why="${branch:-its commit} is merged into $into, and nothing changed in $age day(s)"
    else
        _disk_add "$id" "$label" "$wt" active "" "" "" ""
        DISK_REPO_ACTIVE=1
        return 0
    fi
    risk="$(_disk_wt_risk "$wt" "$repo" "$branch")"
    if [[ -n "$risk" ]]; then
        _disk_add "$id" "$label" "$wt" yours "A git worktree of $(_perf_tilde "$repo"), on ${branch:-a detached HEAD}." \
            "$why, but it has $risk (git status -z --ignored=matching --untracked-files=all)" \
            "what is listed above would be lost" ""
        return 0
    fi
    if [[ -n "$branch" ]]; then
        keeps="branch $branch stays in the repo with all its commits (git worktree remove never deletes a branch)"
    else
        refs="$(_disk_git -C "$repo" for-each-ref --contains "$head" --count=1 --format='%(refname:short)' refs/heads refs/tags refs/remotes 2>/dev/null)" || refs=""
        keeps="its commit stays reachable from $refs"
    fi
    _disk_add "$id" "$label" "$wt" stale "A git worktree of $(_perf_tilde "$repo"), on ${branch:-a detached HEAD}." \
        "$why; no changes, no untracked files, and ignored only build folders (git status -z --ignored=matching --untracked-files=all)" \
        "the folder goes, with its build folders ($DISK_BUILD_DIRS) and everything inside them: git shows such a folder as one entry, so what is in it is not looked at; $keeps" \
        "git -c status.showUntrackedFiles=all -C $(_disk_q "$repo") worktree remove $(_disk_q "$wt")"
}

# _disk_scan_worktrees REPO NOW DAYS — its linked worktrees (not locked, not
# prunable), and folders under .claude/worktrees git does not list. Folders
# are compared with git's list by device:inode, never by spelling.
_disk_scan_worktrees() {
    local repo="$1" now="$2" days="$3" line wt="" head="" branch="" skip=0 n=0 registered=$'\n' d id
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) wt="$(_disk_home_path "${line#worktree }")"; head=""; branch=""; skip=0 ;;
            "HEAD "*)     head="${line#HEAD }" ;;
            "branch "*)   branch="${line#branch refs/heads/}" ;;
            locked*|prunable*|bare) skip=1 ;;
            "")
                if [[ -n "$wt" ]]; then
                    n=$((n + 1))
                    if [[ -d "$wt" ]]; then
                        registered="$registered$(_perf_file_id "$wt")"$'\n'
                        if (( n > 1 && skip == 0 )); then
                            _disk_worktree "$repo" "$wt" "$head" "$branch" "$now" "$days"
                        fi
                    fi
                fi
                wt="" ;;
        esac
    done < <(_disk_git -C "$repo" worktree list --porcelain 2>/dev/null || true; echo "")
    (( n > 0 )) && [[ -d "$repo/.claude/worktrees" ]] || return 0
    for d in "$repo/.claude/worktrees"/*; do
        [[ -d "$d" && ! -L "$d" ]] || continue
        id="$(_perf_file_id "$d")"
        [[ -n "$id" ]] || continue
        case "$registered" in *$'\n'"$id"$'\n'*) continue ;; esac
        if [[ -e "$d/.git" ]]; then
            _disk_add "leftover:$(_perf_tilde "$d")" "$(basename "$repo") folder $(basename "$d")" "$d" yours \
                "A folder under $(_perf_tilde "$repo")/.claude/worktrees with its own .git." \
                "git worktree list for $(_perf_tilde "$repo") does not include it, but it has a .git entry: a worktree of another repo, a clone, or one git lost track of" \
                "whatever is in it: never offered" ""
        else
            _disk_add "leftover:$(_perf_tilde "$d")" "$(basename "$repo") leftover $(basename "$d")" "$d" stale \
                "A folder under $(_perf_tilde "$repo")/.claude/worktrees, without a .git entry." \
                "git worktree list does not include it and it has no .git: what is left after a worktree was pruned or half removed" \
                "whatever is in it: git does not track it any more, so look first" "rm -rf $(_disk_q "$d")"
        fi
    done
    return 0
}

# _disk_scan_repo REPO NOW DAYS — build output at the repo's root that git
# does not track, and its worktrees. Stale when the repo has not changed in
# DAYS; otherwise counted as active and not listed.
_disk_scan_repo() {
    local repo="$1" now="$2" days="$3" age art tracked name
    name="$(basename "$repo")"
    age=$(( (now - $(_disk_last_change "$repo" "$repo/.git")) / 86400 ))
    _disk_say "repo $(_perf_tilde "$repo"): last change $age day(s) ago (git log -1, the index's and the folder's times)"
    DISK_REPO_ACTIVE=0
    tracked="$(_disk_git -C "$repo" ls-files -- node_modules target .next .turbo dist .venv 2>/dev/null | cut -d/ -f1 | sort -u)" || true
    for art in node_modules target .next .turbo dist .venv; do
        [[ -d "$repo/$art" && ! -L "$repo/$art" ]] || continue
        printf '%s\n' "$tracked" | grep -Fxq -- "$art" && continue
        if (( age >= days )); then
            _disk_add "build:$(_perf_tilde "$repo/$art")" "$name/$art" "$repo/$art" stale \
                "Build output or dependencies of $(_perf_tilde "$repo"), which git does not track." \
                "$name has had no commit or change in $age days (git log -1, index and folder times)" \
                "the next install or build in $name recreates it: minutes" "rm -rf $(_disk_q "$repo/$art")"
        else
            _disk_add "build:$(_perf_tilde "$repo/$art")" "$name/$art" "$repo/$art" active "" "" "" ""
            DISK_REPO_ACTIVE=1
        fi
    done
    _disk_scan_worktrees "$repo" "$now" "$days"
    (( DISK_REPO_ACTIVE == 0 )) || DISK_ACTIVE_REPOS=$((DISK_ACTIVE_REPOS + 1))
    return 0
}

# Repos are visited once each, by device:inode: a code folder reached twice
# (a symlink, two spellings on a case-insensitive disk) lists its repos once.
_disk_scan_trees() {
    command_exists git || return 0
    local now days repo d id seen=$'\n'
    now="$(date +%s)"
    days="${TUIDEV_DISK_STALE_DAYS:-30}"
    while IFS= read -r d; do
        _disk_say "code folder $(_perf_tilde "$d"): repos to depth ${TUIDEV_DISK_DEPTH:-4}, skipping node_modules, .venv, target, .claude"
    done < <(perf_code_dirs)
    while IFS= read -r repo; do
        [[ -n "$repo" && -d "$repo" ]] || continue
        id="$(_perf_file_id "$repo")"
        [[ -n "$id" ]] || id="$repo"
        case "$seen" in *$'\n'"$id"$'\n'*) continue ;; esac
        seen="$seen$id"$'\n'
        _disk_scan_repo "$repo" "$now" "$days"
    done < <(perf_code_dirs | while IFS= read -r d; do _disk_find_repos "$d"; done)
    return 0
}

# _disk_measure — du -sk once per item not yet sized, TUIDEV_DISK_JOBS at a
# time. Each du gets its item's index beside it, so paths need no parsing.
_disk_measure() {
    local i kb n=0 list=()
    for i in ${DISK_ID[@]+"${!DISK_ID[@]}"}; do
        [[ -z "${DISK_KB[$i]}" ]] || continue
        list+=("$i" "${DISK_PATH[$i]}")
        n=$((n + 1))
    done
    if (( n > 0 )); then
        _disk_say "measuring $n place(s) with du -sk, ${TUIDEV_DISK_JOBS:-8} at a time"
        local par=(-P "${TUIDEV_DISK_JOBS:-8}")
        printf 'x\0' | xargs -0 -n 1 -P 2 true 2>/dev/null || par=()
        # shellcheck disable=SC2016  # $0 and $1 belong to the sh xargs starts
        while IFS=$'\t' read -r i kb; do
            [[ "$i" =~ ^[0-9]+$ ]] || continue
            DISK_KB[i]="$kb"
        done < <(printf '%s\0' "${list[@]}" | xargs -0 -n 2 ${par[@]+"${par[@]}"} sh -c \
            'printf "%s\t%s\n" "$0" "$(du -sk "$1" 2>/dev/null | cut -f1 | head -n 1)"' 2>/dev/null || true)
    fi
    for i in ${DISK_ID[@]+"${!DISK_ID[@]}"}; do
        [[ "${DISK_KB[$i]}" =~ ^[0-9]+$ ]] || DISK_KB[i]=0
    done
    return 0
}

# _disk_read_ps — the process table, once: `PID ARGS` per line; and with it
# which of fnm's per-shell links belong to running shells (_disk_fnm_links).
_disk_read_ps() {
    if DISK_PS="$(ps -Ao pid=,args= 2>/dev/null)" && [[ -n "$DISK_PS" ]]; then
        DISK_PS_OK=true
    else
        DISK_PS=""; DISK_PS_OK=false
    fi
    _disk_fnm_links
}

# _disk_proc KIND ARG — the first running process KIND matches, as "pid N:
# ARGS". KIND is a tool's id (its own processes), or `path` (ARG appears in
# the command line).
_disk_proc() {
    printf '%s\n' "$DISK_PS" | K="$1" P="${2:-}" awk '
        BEGIN { k = ENVIRON["K"]; p = ENVIRON["P"] }
        {
            pid = $1; a = $0; sub(/^ *[0-9]+ +/, "", a)
            split(a, w, " "); b = w[1]; sub(/.*\//, "", b)
            hit = 0
            if (k == "go") hit = (b == "go" || b == "gopls" || w[1] ~ /\/pkg\/tool\//)
            else if (k == "npm") hit = (b == "npm" || b == "npx" || a ~ /np[mx]-cli\.js/)
            else if (k == "pnpm") hit = (b == "pnpm" || b == "pnpx" || a ~ /pnpm\.c?js/)
            else if (k == "bun") hit = (b == "bun" || b == "bunx")
            else if (k == "uv") hit = (b == "uv" || b == "uvx")
            else if (k == "pip") hit = (b ~ /^pip[0-9.]*$/ || a ~ / -m pip( |$)/)
            else if (k == "brew") hit = (b == "brew" || a ~ /Homebrew\/(brew\.rb|brew\.sh)/)
            else if (k == "cocoapods") hit = (b == "pod")
            else if (k == "path") hit = (p != "" && index(a, p) > 0)
            if (hit) { print "pid " pid ": " substr(a, 1, 70); exit }
        }' || true
}

# _disk_fnm_shell_using VERSION — a running shell whose fnm link points at
# VERSION (`fnm use` in it), as "pid N: ..."; nothing otherwise. Reads
# DISK_FNM_LIVE, which holds only the links of running shells.
_disk_fnm_shell_using() {
    printf '%s\n' "$DISK_FNM_LIVE" | awk -v v="$1" '{
        t = $0; sub(/^[0-9]+ /, "", t)
        if (t ~ ("/node-versions/" v "$") || index(t, "/node-versions/" v "/") > 0) {
            print "pid " $1 ": a shell whose fnm use points at it"; exit
        } }' || true
}

# _disk_busy I — why item I must not be touched now, or nothing: its tool
# running, it being written to this minute, a process running from it, a
# running shell using it. Reads DISK_PS and DISK_FNM_LIVE.
_disk_busy() {
    local id="${DISK_ID[$1]}" path="${DISK_PATH[$1]}" r=""
    [[ "$DISK_PS_OK" == true ]] || { echo "the process table could not be read (ps), so nothing can be checked"; return 0; }
    case "$id" in
        go-build|go-mod) r="$(_disk_proc go)" ;;
        npm|pnpm|bun|uv|pip|cocoapods) r="$(_disk_proc "$id")" ;;
        node:*)
            r="$(_disk_proc path "/node-versions/${id#node:}/")"
            [[ -n "$r" ]] || r="$(_disk_fnm_shell_using "${id#node:}")" ;;
        python:*)
            r="$(_disk_proc path "$path/")" ;;
    esac
    if [[ -n "$r" ]]; then
        printf 'in use: %s\n' "$r"
        return 0
    fi
    case "$id" in
        go-build|go-mod|npm|pnpm|bun|uv|pip|cocoapods)
            if [[ -n "$(find "$path" -maxdepth 2 -mmin -2 -print 2>/dev/null | head -n 1)" ]]; then
                echo "being written: something in it changed in the last 2 minutes"
            fi ;;
    esac
    return 0
}

# disk_collect [--quick] — find and measure everything. --quick leaves out the
# repos in the code folders (and so the search for venvs).
disk_collect() {
    local line
    DISK_ID=(); DISK_LABEL=(); DISK_PATH=(); DISK_KB=(); DISK_VERDICT=(); DISK_WHAT=(); DISK_WHY=()
    DISK_COST=(); DISK_RECLAIM=(); DISK_FIX=(); DISK_REPO=(); DISK_BLOCK=(); DISK_ACTIVE_REPOS=0
    DISK_VENVS=""; DISK_VENVS_SCANNED=false; _DISK_SEEN=$'\n'
    DISK_QUICK=false; [[ "${1:-}" == --quick ]] && DISK_QUICK=true
    _DISK_HOME_REAL="$(cd "$HOME" 2>/dev/null && pwd -P)" || _DISK_HOME_REAL=""
    _disk_say "Looking, read-only: each place below is sized with one du -sk; nothing under your home is written."
    line="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { printf "%.0f %.0f\n", $2 * 1024, $4 * 1024 }')" || true
    read -r DISK_TOTAL_BYTES DISK_FREE_BYTES <<< "${line:-0 0}" || true
    [[ "$DISK_TOTAL_BYTES" =~ ^[0-9]+$ ]] || DISK_TOTAL_BYTES=0
    [[ "$DISK_FREE_BYTES" =~ ^[0-9]+$ ]] || DISK_FREE_BYTES=0
    _disk_read_ps
    if [[ "$DISK_PS_OK" == true ]]; then
        _disk_say "processes: read once with ps -Ao pid,args, to tell what is in use"
    else
        _disk_say "processes: ps could not be read, so nothing will be offered for --fix"
    fi
    _disk_scan_caches
    _disk_scan_containers
    if [[ "$DISK_QUICK" == true ]]; then
        _disk_say "repos: skipped (--quick)"
    else
        _disk_scan_trees
    fi
    _disk_scan_runtimes
    _disk_scan_agents
    _disk_measure
    _disk_say "Not looked at: the rest of your home folder (there is no home-wide walk), app data, browser and system caches, Downloads, Trash, anything outside the places above, and repos deeper than ${TUIDEV_DISK_DEPTH:-4} levels in the code folders."
    return 0
}

# ----------------------------------------------------------------------------
# Totals, the one decision, report, explain, JSON
# ----------------------------------------------------------------------------

# disk_sum VERDICT — KB of every item with VERDICT, listed or not.
disk_sum() {
    local i s=0
    for i in ${DISK_ID[@]+"${!DISK_ID[@]}"}; do
        if [[ "${DISK_VERDICT[$i]}" == "$1" ]]; then s=$((s + DISK_KB[i])); fi
    done
    echo "$s"
}

# _disk_order — indices of the listed items: grouped by verdict (regenerable,
# stale, managed, yours), largest first.
_disk_order() {
    local i r kb
    for i in ${DISK_ID[@]+"${!DISK_ID[@]}"}; do
        kb="${DISK_KB[$i]:-0}"
        case "${DISK_VERDICT[$i]}" in
            regenerable) r=1 ;;
            stale)       r=2 ;;
            managed)     r=3 ;;
            yours)       r=4; (( kb >= DISK_YOURS_MIN_KB )) || continue ;;
            *)           continue ;;
        esac
        (( kb >= DISK_MIN_KB )) || [[ "${DISK_ID[$i]}" == fnm-links ]] || continue
        printf '%s\t%s\t%s\n' "$r" "$kb" "$i"
    done | sort -t "$(printf '\t')" -k1,1n -k2,2nr | cut -f3
}

# _disk_allowed COMMAND — the only cleanup commands disk_apply will ever run:
# each tool's own, never rm.
_disk_allowed() {
    case "$1" in
        "go clean -cache"|"npm cache clean --force"|"pnpm store prune"|"bun pm cache rm" \
        |"uv cache prune"|"pip3 cache purge"|"pod cache clean --all")
            return 0 ;;
    esac
    [[ "$1" =~ ^fnm\ uninstall\ v[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 0
    [[ "$1" =~ ^uv\ python\ uninstall\ [a-z]+-[0-9][0-9a-z.+]*-[a-z0-9_]+-[a-z0-9_]+-[a-z0-9_]+$ ]] && return 0
    return 1
}

# _disk_offerable I — whether --fix may consider item I at all: a regenerable
# cache or a stale runtime, with an allowed command. Never managed or yours,
# never a worktree, never Homebrew.
_disk_offerable() {
    if [[ -z "${DISK_FIX[$1]}" ]] || ! _disk_allowed "${DISK_FIX[$1]}"; then return 1; fi
    case "${DISK_VERDICT[$1]}:${DISK_ID[$1]}" in
        regenerable:*|stale:node:*|stale:python:*) return 0 ;;
    esac
    return 1
}

# _disk_unsafe I — why item I's path must not be acted on, or nothing: not a
# folder, a symlink, outside $HOME once resolved, $HOME or / itself, or a
# repo root (a worktree must be a linked one).
_disk_unsafe() {
    local path="${DISK_PATH[$1]}" real home
    [[ -d "$path" ]] || { echo "it is gone"; return 0; }
    [[ ! -L "$path" ]] || { echo "it is a symlink; only a real folder is acted on"; return 0; }
    real="$(cd "$path" 2>/dev/null && pwd -P)" || { echo "it cannot be resolved"; return 0; }
    home="$(cd "$HOME" 2>/dev/null && pwd -P)" || home="$HOME"
    case "$real" in
        /|"$home") echo "it resolves to $real"; return 0 ;;
        "$home"/*) ;;
        *) echo "it resolves outside your home ($real)"; return 0 ;;
    esac
    case "${DISK_ID[$1]}" in
        worktree:*) [[ -f "$path/.git" ]] || { echo "it is not a linked worktree (its .git is not a file)"; return 0; } ;;
        *)          [[ ! -e "$path/.git" ]] || { echo "it is a repo root"; return 0; } ;;
    esac
    return 0
}

# _disk_fix_reason I [--recheck] — the one decision: nothing when --fix may
# run item I's command now, else why not. The report, the JSON's fix_offered,
# --explain, the plan and the last check before each command all use it.
# --recheck looks again at what the scan decided for a runtime: the Node
# version's global packages, the venvs that may use a Python.
_disk_fix_reason() {
    local r
    if ! _disk_offerable "$1"; then
        case "${DISK_VERDICT[$1]}" in
            yours)   echo "it is yours" ;;
            managed) echo "its own tool owns the cleanup" ;;
            *)       echo "no tool has a cleanup command for it that --fix runs, and --fix never runs rm" ;;
        esac
        return 0
    fi
    if [[ "${2:-}" == --recheck ]]; then
        case "${DISK_ID[$1]}" in
            node:*)   DISK_BLOCK[$1]="$(_disk_runtime_block "$1")" ;;
            python:*) [[ "$DISK_QUICK" == true ]] || _disk_find_venvs; DISK_BLOCK[$1]="$(_disk_runtime_block "$1")" ;;
        esac
    fi
    r="${DISK_BLOCK[$1]}"
    [[ -n "$r" ]] || r="$(_disk_unsafe "$1")"
    [[ -n "$r" ]] || r="$(_disk_busy "$1")"
    printf '%s' "$r"
    [[ -z "$r" ]] || echo ""
    return 0
}

# _disk_why_full I — the why, with what stops --fix now, for an item --fix
# would otherwise consider.
_disk_why_full() {
    local r=""
    if _disk_offerable "$1"; then r="$(_disk_fix_reason "$1")"; fi
    printf '%s%s\n' "${DISK_WHY[$1]}" "${r:+; --fix skips it now: $r}"
}

_disk_heading() {
    case "$1" in
        regenerable) echo "regenerable: caches a tool rebuilds; safe to clear" ;;
        stale)       echo "stale: superseded or unused; safe after a look" ;;
        managed)     echo "managed: another tool owns the cleanup; use its command" ;;
        yours)       echo "yours: never offered for deletion; listed for information" ;;
    esac
}

# _disk_run_label I REASON — how the command line is introduced.
_disk_run_label() {
    if _disk_offerable "$1"; then
        if [[ -z "$2" ]]; then echo "run (--fix offers this)"; else echo "run (--fix skips it now)"; fi
    elif [[ "${DISK_VERDICT[$1]}" == managed ]]; then echo "its tool"
    else echo "by hand (--fix never runs this)"
    fi
}

disk_report() {
    local i v last="" shown=0 hidden=0 offered=0 regen stale active pct=0 order reason
    order="$(_disk_order)"
    if (( DISK_TOTAL_BYTES > 0 )); then
        pct=$(( DISK_FREE_BYTES * 100 / DISK_TOTAL_BYTES ))
        print_info "Free: $(_perf_human "$DISK_FREE_BYTES") of $(_perf_human "$DISK_TOTAL_BYTES") ($pct%) on the volume your home is on"
    fi
    while IFS= read -r i; do
        [[ -n "$i" ]] || continue
        v="${DISK_VERDICT[$i]}"
        if [[ "$v" != "$last" ]]; then
            echo ""
            echo -e "${BOLD}$(_disk_heading "$v")${NC}   $(_perf_human $(( $(disk_sum "$v") * 1024 ))) in all"
            last="$v"
        fi
        reason=""
        _disk_offerable "$i" && reason="$(_disk_fix_reason "$i")"
        printf '  %9s  %s   %s\n' "$(_perf_human $((DISK_KB[i] * 1024)))" "${DISK_LABEL[$i]}" "$(_perf_tilde "${DISK_PATH[$i]}")"
        printf '             what: %s\n' "${DISK_WHAT[$i]}"
        printf '             why:  %s%s\n' "${DISK_WHY[$i]}" "${reason:+; --fix skips it now: $reason}"
        [[ -z "${DISK_COST[$i]}" ]] || printf '             cost: %s\n' "${DISK_COST[$i]}"
        if [[ -n "${DISK_RECLAIM[$i]}" ]]; then
            if _disk_offerable "$i" && [[ -z "$reason" ]]; then offered=$((offered + 1)); fi
            printf '             %s: %s\n' "$(_disk_run_label "$i" "$reason")" "${DISK_RECLAIM[$i]}"
        fi
        shown=$((shown + 1))
    done <<< "$order"
    for i in ${DISK_ID[@]+"${!DISK_ID[@]}"}; do
        [[ "${DISK_VERDICT[$i]}" == active ]] && continue
        printf '%s\n' "$order" | grep -Fxq -- "$i" || hidden=$((hidden + 1))
    done
    regen="$(disk_sum regenerable)"; stale="$(disk_sum stale)"; active="$(disk_sum active)"
    echo ""
    if (( shown == 0 )); then
        print_success "Nothing over $(_perf_human $((DISK_MIN_KB * 1024))) that dev tools or agents left behind"
    fi
    print_info "Reclaimable now: $(_perf_human $(( (regen + stale) * 1024 ))) (regenerable $(_perf_human $((regen * 1024))), stale $(_perf_human $((stale * 1024))))"
    if (( DISK_ACTIVE_REPOS > 0 )); then
        print_info "In use: $(_perf_human $((active * 1024))) of build output and worktrees in $DISK_ACTIVE_REPOS repo(s) changed in the last ${TUIDEV_DISK_STALE_DAYS:-30} days, not listed"
    fi
    if (( hidden > 0 )); then
        print_info "$hidden smaller item(s) not shown ('--min 0' lists them; 'yours' shows from 1 GB unless --min is given)"
    fi
    if (( offered > 0 )); then
        print_info "'./scripts/disk.sh --fix' shows the plan for the $offered 'run (--fix offers this)' line(s), then asks for each. '--explain ID' says more about one; '--json' lists the IDs."
    fi
    return 0
}

_disk_index_of() {
    local i
    for i in ${DISK_ID[@]+"${!DISK_ID[@]}"}; do
        if [[ "${DISK_ID[$i]}" == "$1" ]]; then echo "$i"; return 0; fi
    done
    return 1
}

# disk_explain ID — one item in full: what, why, cost, the command, and
# whether --fix would offer it now, or why not. Returns 1 for an unknown ID.
disk_explain() {
    local i reason
    i="$(_disk_index_of "$1")" || {
        print_error "No item '$1'. The IDs: $(printf '%s ' ${DISK_ID[@]+"${DISK_ID[@]}"})"
        return 1
    }
    reason="$(_disk_fix_reason "$i")"
    echo -e "${BOLD}${DISK_LABEL[$i]}${NC}   (${DISK_ID[$i]})"
    echo "  where:   $(_perf_tilde "${DISK_PATH[$i]}")"
    echo "  size:    $(_perf_human $((DISK_KB[i] * 1024))) (du -sk)"
    echo "  verdict: $(_disk_heading "${DISK_VERDICT[$i]}")"
    echo "  what:    ${DISK_WHAT[$i]}"
    echo "  why:     ${DISK_WHY[$i]}"
    echo "  cost:    ${DISK_COST[$i]:-none stated}"
    [[ -z "${DISK_RECLAIM[$i]}" ]] || echo "  command: ${DISK_RECLAIM[$i]}   ($(_disk_run_label "$i" "$reason"))"
    if [[ -z "$reason" ]]; then
        echo "  --fix:   would ask before running the command above"
    elif _disk_offerable "$i"; then
        echo "  --fix:   would skip it now: $reason"
    else
        echo "  --fix:   never: $reason"
    fi
}

# _disk_json_str S — S as a JSON string.
_disk_json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s="${s//[[:cntrl:]]/ }"
    printf '"%s"' "$s"
}

# disk_json — fix_offered is _disk_fix_reason's answer, the same --fix uses
# (false without a readable process table); fix_reason says why not.
disk_json() {
    local i sep="" safe offered why reason
    printf '{"generated_at":"%s","free_bytes":%s,"total_bytes":%s,"items":[' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$DISK_FREE_BYTES" "$DISK_TOTAL_BYTES"
    while IFS= read -r i; do
        [[ -n "$i" ]] || continue
        safe=false; [[ "${DISK_VERDICT[$i]}" == regenerable ]] && safe=true
        reason="$(_disk_fix_reason "$i")"
        offered=false; [[ -n "$reason" ]] || offered=true
        why="$(_disk_why_full "$i")"
        printf '%s{"id":%s,"label":%s,"path":%s,"bytes":%s,"verdict":%s,"what":%s,"why":%s,"cost":%s,"evidence":%s,"reclaim":%s,"safe":%s,"fix_offered":%s,"fix_reason":%s}' "$sep" \
            "$(_disk_json_str "${DISK_ID[$i]}")" "$(_disk_json_str "${DISK_LABEL[$i]}")" \
            "$(_disk_json_str "${DISK_PATH[$i]}")" "$((DISK_KB[i] * 1024))" \
            "$(_disk_json_str "${DISK_VERDICT[$i]}")" "$(_disk_json_str "${DISK_WHAT[$i]}")" \
            "$(_disk_json_str "$why")" "$(_disk_json_str "${DISK_COST[$i]}")" "$(_disk_json_str "$why")" \
            "$(_disk_json_str "${DISK_RECLAIM[$i]}")" "$safe" "$offered" "$(_disk_json_str "$reason")"
        sep=","
    done <<< "$(_disk_order)"
    printf '],"reclaimable_bytes":%s,"in_use":{"bytes":%s,"repos":%s}}\n' \
        "$(( ($(disk_sum regenerable) + $(disk_sum stale)) * 1024 ))" "$(( $(disk_sum active) * 1024 ))" "$DISK_ACTIVE_REPOS"
}

# ----------------------------------------------------------------------------
# Fix: plan, ask, check again, run, log
# ----------------------------------------------------------------------------

# _disk_drain — throw away what was typed at the terminal while the scan ran,
# so a stray key never answers a question.
_disk_drain() {
    [[ -t 0 ]] || return 0
    perl -MPOSIX=tcflush,TCIFLUSH -e 'tcflush(0, TCIFLUSH)' 2>/dev/null && return 0
    local _junk
    while IFS= read -r -t 1 -n 1 _junk; do :; done
    return 0
}

# disk_confirm QUESTION — yes only for y or yes typed (then Enter) at a
# terminal, or --yes. Anything else, an empty answer included, is no.
disk_confirm() {
    [[ "$DISK_ASSUME_YES" == true ]] && return 0
    [[ "$DISK_INTERACTIVE" == true ]] || return 1
    local reply=""
    _disk_drain
    read -r -p "  $1 [y/N] " reply || true
    case "$reply" in y|Y|yes|Yes|YES) return 0 ;; esac
    return 1
}

# _disk_argv I — item I's command as words in _DISK_ARGV. Every allowed
# command is a tool's own, with no paths, so splitting it is safe.
_DISK_ARGV=()
_disk_argv() {
    read -r -a _DISK_ARGV <<< "${DISK_FIX[$1]}"
}

# _disk_du_kb PATH — du -sk of PATH now, 0 when it is gone.
_disk_du_kb() {
    local kb
    kb="$(du -sk "$1" 2>/dev/null | cut -f1 | head -n 1)" || true
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    echo "$kb"
}

# disk_apply [CONFIRM_FN] — the only thing that changes anything. It reads the
# process table again, sorts the listed items into a plan and a skip list
# (each with its reason, from _disk_fix_reason), prints the plan, then asks
# CONFIRM_FN (default disk_confirm) once per command. After each yes it reads
# the process table again and asks _disk_fix_reason --recheck: anything that
# changed since the plan skips the item. Each command runs from $HOME through
# run_cmd; its output is shown when it fails; the item is re-measured and the
# run logged with bytes before and after. Without a terminal and without
# --yes it stops after the plan.
disk_apply() {
    local confirm_fn="${1:-disk_confirm}" i n=0 total=0 reason after rc out f cmd freed=0 plan=() skip=() done_lines=()
    _disk_read_ps
    while IFS= read -r i; do
        [[ -n "$i" ]] || continue
        _disk_offerable "$i" || continue
        reason="$(_disk_fix_reason "$i")"
        if [[ -n "$reason" ]]; then
            skip+=("${DISK_LABEL[$i]} ($(_perf_tilde "${DISK_PATH[$i]}")): $reason")
        else
            plan+=("$i")
            total=$((total + DISK_KB[i]))
        fi
    done <<< "$(_disk_order)"
    if (( ${#plan[@]} == 0 )); then
        print_info "Nothing to run: no listed item has a tool's own cleanup command that is safe to run now."
    else
        print_step "Plan: ${#plan[@]} command(s), up to $(_perf_human $((total * 1024))) in all. Each is asked separately; the default is No."
        for i in "${plan[@]}"; do
            n=$((n + 1))
            printf '  %2d. %-9s %s\n      %s\n' "$n" "$(_perf_human $((DISK_KB[i] * 1024)))" \
                "${DISK_RECLAIM[$i]}" "$(_perf_tilde "${DISK_PATH[$i]}"): ${DISK_COST[$i]}"
        done
    fi
    if (( ${#skip[@]} > 0 )); then
        print_info "Not offered now:"
        for f in "${skip[@]}"; do echo "    - $f"; done
    fi
    (( ${#plan[@]} > 0 )) || return 0
    if [[ "$confirm_fn" == disk_confirm && "$DISK_ASSUME_YES" != true && "$DISK_INTERACTIVE" != true && "$DRY_RUN" != true ]]; then
        print_info "Not a terminal and no --yes: nothing ran. Run it in a terminal to be asked, or add --yes to run the plan above."
        return 0
    fi
    echo ""
    for i in "${plan[@]}"; do
        _disk_argv "$i"
        cmd="$(printf '%q ' "${_DISK_ARGV[@]}")"; cmd="${cmd% }"
        if [[ "$DRY_RUN" == true ]]; then
            run_cmd "${_DISK_ARGV[@]}"
            perf_log disk "${DISK_ID[$i]}" "$cmd" dry-run "$((DISK_KB[i] * 1024))" - -
            continue
        fi
        if ! "$confirm_fn" "Run '${DISK_RECLAIM[$i]}' ($(_perf_human $((DISK_KB[i] * 1024))))?"; then
            skip+=("${DISK_RECLAIM[$i]}: you said no")
            continue
        fi
        # Minutes may have passed since the plan: look again.
        _disk_read_ps
        reason="$(_disk_fix_reason "$i" --recheck)"
        if [[ -n "$reason" ]]; then
            print_warning "skipped, changed since the plan: ${DISK_RECLAIM[$i]}: $reason"
            skip+=("${DISK_RECLAIM[$i]}: changed since the plan: $reason")
            continue
        fi
        rc=0
        out="$(cd "$HOME" && run_cmd "${_DISK_ARGV[@]}" 2>&1)" || rc=$?
        after="$(_disk_du_kb "${DISK_PATH[$i]}")"
        perf_log disk "${DISK_ID[$i]}" "$cmd" "$rc" "$((DISK_KB[i] * 1024))" "$((after * 1024))" -
        if (( rc != 0 )); then
            print_warning "failed (exit $rc): ${DISK_RECLAIM[$i]}. Nothing else is tried for this item. Its output:"
            printf '%s\n' "$out" | tail -n 20 | sed 's/^/      /'
            skip+=("${DISK_RECLAIM[$i]}: failed with exit $rc")
            continue
        fi
        f=$(( DISK_KB[i] - after ))
        (( f > 0 )) || f=0
        freed=$((freed + f))
        DISK_KB[i]="$after"
        print_success "freed $(_perf_human $((f * 1024))): ${DISK_RECLAIM[$i]}"
        done_lines+=("${DISK_RECLAIM[$i]}: freed $(_perf_human $((f * 1024)))")
    done
    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Dry run: nothing changed."
        return 0
    fi
    print_step "Done"
    if (( ${#done_lines[@]} == 0 )); then echo "    nothing ran"; fi
    for f in ${done_lines[@]+"${done_lines[@]}"}; do echo "    ✓ $f"; done
    if (( ${#skip[@]} > 0 )); then
        echo "  Skipped:"
        for f in "${skip[@]}"; do echo "    - $f"; done
    fi
    print_success "Freed $(_perf_human $((freed * 1024))) in all (re-measured with du -sk). Log: $(_perf_tilde "$TUIDEV_STATE_DIR/disk.log")"
    return 0
}
