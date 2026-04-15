#!/bin/bash
# The globals defined below are the lib's public interface; consumers read
# them after calling load_tuidev_profile. Shellcheck would flag each one
# as unused from the lib's local perspective, which is wrong.
# shellcheck disable=SC2034
#
# scripts/lib/profile.sh - single source of truth for ~/.config/tuidev/profile.
#
# Source after ui.sh. Idempotent.
#
# Exposes:
#   load_tuidev_profile [PATH]   read the profile manifest into globals
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
#   extra_packs=zellij yazi
#   installed_at=2026-04-14T18:51:20Z
#   repo=/path/to/mactui_setup

if [[ -n "${_TUIDEV_PROFILE_LIB_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_PROFILE_LIB_LOADED=1

TUIDEV_PROFILE_FILE_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/tuidev/profile"
TUIDEV_ENV_FILE_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/tuidev/env"

# Valid profile names — shared across install/update/health/test. One place.
TUIDEV_VALID_PROFILES=(minimal desktop remote)

# Valid pack names (non-profile packs exposed via --pack NAME).
TUIDEV_VALID_PACKS=(zellij yazi nnn monitoring sandbox-container mosh)

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

# Convenience: print the set of packs active for the loaded profile, one per
# line. Combines built-in packs that are true + extra_packs list.
tuidev_active_packs() {
    $TUIDEV_PACK_CORE    && echo core
    $TUIDEV_PACK_REMOTE  && echo remote
    $TUIDEV_PACK_SANDBOX && echo sandbox
    $TUIDEV_PACK_UI      && echo ui
    $TUIDEV_PACK_EXTRAS  && echo extras
    local p
    for p in "${TUIDEV_EXTRA_PACKS_ARR[@]}"; do
        [[ -n "$p" ]] && echo "$p"
    done
}

# Convenience: true if PROFILE_NAME arg is one of the valid profiles.
tuidev_is_valid_profile() {
    local p
    for p in "${TUIDEV_VALID_PROFILES[@]}"; do
        [[ "$1" == "$p" ]] && return 0
    done
    return 1
}
