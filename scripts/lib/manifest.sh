#!/bin/bash
# scripts/lib/manifest.sh - the install manifest: what tuidev actually put on
# this machine.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/manifest.sh"
#
# ~/.config/tuidev/profile answers "which packs did the user pick?".
# ~/.config/tuidev/manifest answers the harder question uninstall needs:
# "which formulae, files and managed blocks did *we* actually write?" — so the
# uninstaller can remove what this machine got instead of a hardcoded superset
# that may not match this install.
#
# Format — one record per line, `<kind> <rest-of-line>`, greppable by design:
#
#   profile desktop
#   pack core
#   formula ripgrep
#   cask ghostty
#   block tuidev-zshrc /Users/NAME/.zshrc
#   file /Users/NAME/.local/bin/notify.sh
#   dir /Users/NAME/.config/nvim
#
# `block` puts the (space-free) block id first so the remaining field can be a
# path containing spaces. Comment lines start with `#`.
#
# The file is append-only and deduplicated: a second `install.sh --pack foo`
# adds foo's records without dropping the first run's. Records may therefore go
# stale (a formula the user later removed by hand); every consumer re-checks
# existence before acting, so stale records are inert.
#
# Recording is OFF unless a caller opts in with tuidev_manifest_enable — only
# install.sh and update.sh's config re-sync do. That keeps health checks, tests
# and anything else that merely sources these libs from writing to $HOME.
# DRY_RUN is always honored: nothing is written.

if [[ -n "${_TUIDEV_MANIFEST_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_MANIFEST_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

: "${TUIDEV_MANIFEST_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/tuidev/manifest}"
: "${TUIDEV_MANIFEST_ENABLED:=0}"

# Record kinds this lib knows about. Documented here so consumers (uninstall)
# and producers (install packs) share one vocabulary.
#   profile  the profile name the install resolved to
#   pack     a pack that ran (core, ui, zellij, …)
#   formula  a Homebrew formula we installed (not one already present)
#   cask     a Homebrew cask we installed
#   block    a managed block we wrote: `block <id> <path>`
#   file     a whole file we placed (helper scripts, adopted configs)
#   dir      a directory tree we placed (nvim config, …)

tuidev_manifest_enable() { TUIDEV_MANIFEST_ENABLED=1; export TUIDEV_MANIFEST_ENABLED; }
tuidev_manifest_disable() { TUIDEV_MANIFEST_ENABLED=0; export TUIDEV_MANIFEST_ENABLED; }

tuidev_manifest_present() { [[ -f "$TUIDEV_MANIFEST_FILE" ]]; }

# tuidev_manifest_record KIND VALUE...
# Appends `KIND VALUE...` unless the identical line is already present. No-op
# unless recording was enabled, and always a no-op under DRY_RUN. Returns 0 on
# a successful record or a deliberate no-op so callers can use it inline
# without guarding against `set -e`.
tuidev_manifest_record() {
    [[ "$TUIDEV_MANIFEST_ENABLED" == 1 ]] || return 0
    [[ "$DRY_RUN" == true ]] && return 0

    if [[ $# -lt 2 || -z "$1" || -z "$2" ]]; then
        print_error "tuidev_manifest_record: KIND and VALUE required"
        return 2
    fi

    local kind="$1"
    shift
    local line="$kind $*"

    local dir
    dir="$(dirname "$TUIDEV_MANIFEST_FILE")"
    mkdir -p "$dir" || return 1

    if [[ ! -f "$TUIDEV_MANIFEST_FILE" ]]; then
        {
            echo "# tuidev install manifest — one record per line: <kind> <value>"
            echo "# Written by install.sh; read by uninstall.sh. Append-only."
            echo "# Kinds: profile pack formula cask block file dir"
        } > "$TUIDEV_MANIFEST_FILE"
    fi

    grep -qxF -- "$line" "$TUIDEV_MANIFEST_FILE" 2>/dev/null && return 0
    printf '%s\n' "$line" >> "$TUIDEV_MANIFEST_FILE"
}

# tuidev_manifest_values KIND [FILE]
# Prints the rest-of-line for every record of KIND, one per line. Paths with
# spaces survive because only the leading kind token is stripped.
tuidev_manifest_values() {
    local kind="$1"
    local file="${2:-$TUIDEV_MANIFEST_FILE}"
    [[ -n "$kind" ]] || return 2
    [[ -f "$file" ]] || return 0
    awk -v k="$kind" '
        index($0, "#") == 1 { next }
        index($0, k " ") == 1 { print substr($0, length(k) + 2) }
    ' "$file"
}

# tuidev_manifest_has KIND VALUE [FILE] — exit 0 if that exact record exists.
tuidev_manifest_has() {
    local kind="$1" value="$2"
    local file="${3:-$TUIDEV_MANIFEST_FILE}"
    [[ -f "$file" ]] || return 1
    grep -qxF -- "$kind $value" "$file"
}
