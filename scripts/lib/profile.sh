#!/bin/bash
# The globals defined below are the lib's public interface; consumers read
# them after calling load_tuidev_profile. Shellcheck would flag each one
# as unused from the lib's local perspective, which is wrong.
# shellcheck disable=SC2034
#
# scripts/lib/profile.sh - single source of truth for ~/.config/tuidev/profile.
#
# Sources ui.sh itself. Idempotent.
#
# Exposes:
#   load_tuidev_profile [PATH]        read the profile manifest into globals
#   tuidev_profile_write [PATH]       write those globals back (atomic)
#   tuidev_profile_add_pack PACK [PATH]     edit extra_packs in place
#   tuidev_profile_remove_pack PACK [PATH]  (other lines untouched)
#   tuidev_extra_packs [PROFILE]      optional packs (remote implies tmux)
#   tuidev_active_packs               built-in + optional packs, one per line
#   tuidev_is_valid_profile NAME / tuidev_is_valid_pack NAME
#
# Globals populated (always reset, even on missing manifest):
#   TUIDEV_PROFILE_NAME      "minimal" | "desktop" | "remote" | ""
#   TUIDEV_PACK_CORE         true|false   — core pack enabled
#   TUIDEV_PACK_REMOTE       true|false   — remote pack enabled
#   TUIDEV_PACK_SANDBOX      true|false   — sandbox pack enabled
#   TUIDEV_PACK_UI           true|false   — ui pack enabled
#   TUIDEV_PACK_EXTRAS       true|false   — extras pack enabled
#   TUIDEV_EXTRA_PACKS       space-separated string of optional pack names
#   TUIDEV_EXTRA_PACKS_ARR   array form of the above
#   TUIDEV_PROFILE_INSTALLED_AT  ISO 8601 timestamp from installer
#   TUIDEV_PROFILE_REPO      repo path recorded at install time
#   TUIDEV_PROFILE_FOUND     true if the manifest file was read
#
# Also, when the manifest's repo= path is set, exports TUIDEV_REPO.
#
# Manifest format (written by install.sh):
#   profile=desktop
#   core=true
#   remote=false
#   sandbox=true
#   ui=true
#   extras=false
#   extra_packs=herdr tmux
#   installed_at=2026-04-14T18:51:20Z
#   repo=/path/to/mactui_setup

if [[ -n "${_TUIDEV_PROFILE_LIB_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_PROFILE_LIB_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

TUIDEV_PROFILE_FILE_DEFAULT="$TUIDEV_STATE_DIR/profile"
TUIDEV_ENV_FILE_DEFAULT="$TUIDEV_STATE_DIR/env"

# Valid profile names — shared across install/update/health/test. One place.
TUIDEV_VALID_PROFILES=(minimal desktop remote)

# Valid pack names (non-profile packs exposed via --pack NAME).
TUIDEV_VALID_PACKS=(ai-clis orchestration opencode nvim vim tmux herdr cmux sandbox-container mosh fnm monitoring)

load_tuidev_profile() {
    local file="${1:-$TUIDEV_PROFILE_FILE_DEFAULT}"

    # Always reset so repeated calls reflect the current file state.
    TUIDEV_PROFILE_NAME=""
    TUIDEV_PACK_CORE=false
    TUIDEV_PACK_REMOTE=false
    TUIDEV_PACK_SANDBOX=false
    TUIDEV_PACK_UI=false
    TUIDEV_PACK_EXTRAS=false
    TUIDEV_EXTRA_PACKS=""
    TUIDEV_EXTRA_PACKS_ARR=()
    TUIDEV_PROFILE_INSTALLED_AT=""
    TUIDEV_PROFILE_REPO=""
    TUIDEV_PROFILE_FOUND=false

    if [[ ! -f "$file" ]]; then
        return 1
    fi
    TUIDEV_PROFILE_FOUND=true

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip comments + surrounding whitespace.
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        # Accept key=value (preferred) or key: value (legacy-friendly).
        if [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            value="${line#*=}"
        elif [[ "$line" == *:* ]]; then
            key="${line%%:*}"
            value="${line#*:}"
        else
            continue
        fi

        # Trim field whitespace.
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        # Strip surrounding quotes.
        if [[ ${#value} -ge 2 ]] && [[ "${value:0:1}" == "${value: -1}" ]] \
            && [[ "${value:0:1}" == '"' || "${value:0:1}" == "'" ]]; then
            value="${value:1:${#value}-2}"
        fi

        case "$key" in
            profile)       TUIDEV_PROFILE_NAME="$value" ;;
            core)          [[ "$value" == true ]] && TUIDEV_PACK_CORE=true ;;
            remote)        [[ "$value" == true ]] && TUIDEV_PACK_REMOTE=true ;;
            sandbox)       [[ "$value" == true ]] && TUIDEV_PACK_SANDBOX=true ;;
            ui)            [[ "$value" == true ]] && TUIDEV_PACK_UI=true ;;
            extras)        [[ "$value" == true ]] && TUIDEV_PACK_EXTRAS=true ;;
            extra_packs)
                # Accept either comma- or space-separated lists.
                TUIDEV_EXTRA_PACKS="${value//,/ }"
                # shellcheck disable=SC2206
                TUIDEV_EXTRA_PACKS_ARR=($TUIDEV_EXTRA_PACKS)
                ;;
            installed_at)  TUIDEV_PROFILE_INSTALLED_AT="$value" ;;
            repo)
                TUIDEV_PROFILE_REPO="$value"
                [[ -n "$value" ]] && export TUIDEV_REPO="$value"
                ;;
        esac
    done < "$file"

    return 0
}

# tuidev_extra_packs [PROFILE]
# Print the optional packs in effect, one per line: extra_packs, plus tmux for
# the remote profile (install.sh --profile remote adds --pack tmux, but a
# manifest written before 3.0 may not list it). PROFILE defaults to the loaded
# profile's name. The one place that expansion lives.
tuidev_extra_packs() {
    local profile="${1-$TUIDEV_PROFILE_NAME}" p has_tmux=false
    # ${arr[@]+...}: bash 3.2 under `set -u` rejects an empty "${arr[@]}".
    for p in ${TUIDEV_EXTRA_PACKS_ARR[@]+"${TUIDEV_EXTRA_PACKS_ARR[@]}"}; do
        [[ -n "$p" ]] || continue
        echo "$p"
        [[ "$p" == tmux ]] && has_tmux=true
    done
    if [[ "$profile" == remote ]] && ! $has_tmux; then
        echo tmux
    fi
    return 0
}

# Convenience: print the set of packs active for the loaded profile, one per
# line. Combines built-in packs that are true + tuidev_extra_packs.
tuidev_active_packs() {
    $TUIDEV_PACK_CORE    && echo core
    $TUIDEV_PACK_REMOTE  && echo remote
    $TUIDEV_PACK_SANDBOX && echo sandbox
    $TUIDEV_PACK_UI      && echo ui
    $TUIDEV_PACK_EXTRAS  && echo extras
    tuidev_extra_packs "$TUIDEV_PROFILE_NAME"
}

# Convenience: true if PROFILE_NAME arg is one of the valid profiles.
tuidev_is_valid_profile() {
    local p
    for p in "${TUIDEV_VALID_PROFILES[@]}"; do
        [[ "$1" == "$p" ]] && return 0
    done
    return 1
}

# Convenience: true if NAME is an optional pack (`--pack NAME`).
tuidev_is_valid_pack() {
    local p
    for p in "${TUIDEV_VALID_PACKS[@]}"; do
        [[ "$1" == "$p" ]] && return 0
    done
    return 1
}

# tuidev_profile_write [PATH]
# Writes the globals load_tuidev_profile populates back out, in the canonical
# key order. Callers load (or reset), adjust the globals, then write. Atomic
# (temp file + mv); a no-op under DRY_RUN.
tuidev_profile_write() {
    local file="${1:-$TUIDEV_PROFILE_FILE_DEFAULT}"
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would write profile manifest $file"
        return 0
    fi
    mkdir -p "$(dirname "$file")" || return 1
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-profile.XXXXXX")" || return 1
    {
        echo "profile=${TUIDEV_PROFILE_NAME:-custom}"
        echo "core=$TUIDEV_PACK_CORE"
        echo "remote=$TUIDEV_PACK_REMOTE"
        echo "sandbox=$TUIDEV_PACK_SANDBOX"
        echo "ui=$TUIDEV_PACK_UI"
        echo "extras=$TUIDEV_PACK_EXTRAS"
        echo "extra_packs=$TUIDEV_EXTRA_PACKS"
        echo "installed_at=$TUIDEV_PROFILE_INSTALLED_AT"
        echo "repo=$TUIDEV_PROFILE_REPO"
    } > "$tmp" && mv "$tmp" "$file"
}

# _tuidev_profile_set_packs FILE LIST — rewrite only the first extra_packs=
# line (appending one if absent); every other line is kept byte-for-byte.
_tuidev_profile_set_packs() {
    local file="$1" list="$2" tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-profile.XXXXXX")" || return 2
    awk -v v="$list" '
        /^extra_packs=/ && !done { print "extra_packs=" v; done=1; next }
        { print }
        END { if (!done) print "extra_packs=" v }
    ' "$file" > "$tmp" && cat "$tmp" > "$file"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# tuidev_profile_add_pack PACK [PATH]
# Appends PACK to extra_packs. Exit 0 = added, 1 = already recorded,
# 2 = no profile file (or a write error).
tuidev_profile_add_pack() {
    local pack="$1" file="${2:-$TUIDEV_PROFILE_FILE_DEFAULT}"
    [[ -f "$file" ]] || return 2
    load_tuidev_profile "$file" || return 2
    local p
    for p in ${TUIDEV_EXTRA_PACKS_ARR[@]+"${TUIDEV_EXTRA_PACKS_ARR[@]}"}; do
        [[ "$p" == "$pack" ]] && return 1
    done
    _tuidev_profile_set_packs "$file" "${TUIDEV_EXTRA_PACKS:+$TUIDEV_EXTRA_PACKS }$pack" || return 2
}

# tuidev_profile_remove_pack PACK [PATH]
# Drops PACK from extra_packs. Exit 0 = removed, 1 = was not recorded,
# 2 = no profile file (or a write error).
tuidev_profile_remove_pack() {
    local pack="$1" file="${2:-$TUIDEV_PROFILE_FILE_DEFAULT}"
    [[ -f "$file" ]] || return 2
    load_tuidev_profile "$file" || return 2
    local p kept="" found=false
    for p in ${TUIDEV_EXTRA_PACKS_ARR[@]+"${TUIDEV_EXTRA_PACKS_ARR[@]}"}; do
        if [[ "$p" == "$pack" ]]; then found=true; else kept="${kept:+$kept }$p"; fi
    done
    $found || return 1
    _tuidev_profile_set_packs "$file" "$kept" || return 2
}
