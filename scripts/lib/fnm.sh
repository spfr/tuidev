#!/bin/bash
# scripts/lib/fnm.sh - the Node versions fnm manages: which are installed,
# which majors are behind nodejs.org, and which older patches linger.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/fnm.sh"
#
# Exposes:
#   fnm_bin                       the fnm binary, even before it is on PATH
#   fnm_installed FNM             installed versions (vX.Y.Z), oldest first
#   fnm_default FNM               the version the `default` alias points at
#   fnm_newest FNM MAJOR          the newest installed version of MAJOR
#   fnm_stale FNM                 "MAJOR HAVE LATEST" per installed major whose
#                                 newest patch is behind nodejs.org; returns 1
#                                 when the remote list can't be fetched
#   fnm_superseded FNM            installed versions with a newer patch of
#                                 their major installed beside them
#
# Homebrew upgrades fnm itself, never the Node versions it installed, so these
# are how a security release reaches them. Only majors already installed are
# considered: a newer major is a choice for the project, not an update.

if [[ -n "${_TUIDEV_FNM_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_FNM_LOADED=1

fnm_bin() {
    if command -v fnm >/dev/null 2>&1; then
        command -v fnm
        return 0
    fi
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$prefix" && -x "$prefix/bin/fnm" ]]; then
        printf '%s\n' "$prefix/bin/fnm"
    fi
}

# fnm prints versions as `* v26.12.1 default`; take the vX.Y.Z of each line,
# oldest first (numeric fields, not sort -V, which BusyBox lacks). Finding
# none is no error: callers run under set -eo pipefail.
_fnm_versions() {
    { grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true; } | sort -u -t. -k1.2,1n -k2,2n -k3,3n
}

fnm_installed() { { "$1" ls 2>/dev/null || true; } | _fnm_versions; }

fnm_default() {
    { "$1" ls 2>/dev/null || true; } | awk '/ default( |$)/' | _fnm_versions | head -1
}

fnm_newest() {
    fnm_installed "$1" | awk -v p="v$2." 'index($0, p) == 1' | tail -1
}

# Last version per major, read from sorted "TAG vX.Y.Z" lines; TAG is I
# (installed) or R (remote). Prints "MAJOR HAVE LATEST" where they differ.
_fnm_compare() {
    awk '{
        major = $2; sub(/^v/, "", major); sub(/\..*/, "", major)
        if ($1 == "R") { remote[major] = $2; next }
        if (!(major in have)) order[++n] = major
        have[major] = $2
    } END {
        for (i = 1; i <= n; i++) {
            m = order[i]
            if ((m in remote) && remote[m] != have[m]) print m, have[m], remote[m]
        }
    }'
}

fnm_stale() {
    local remote
    remote="$("$1" ls-remote 2>/dev/null | _fnm_versions)" || return 1
    [[ -n "$remote" ]] || return 1
    {
        printf '%s\n' "$remote" | sed 's/^/R /'
        fnm_installed "$1" | sed 's/^/I /'
    } | _fnm_compare
}

fnm_superseded() {
    fnm_installed "$1" | awk '{
        major = $1; sub(/^v/, "", major); sub(/\..*/, "", major)
        if (major in last) print last[major]
        last[major] = $1
    }'
}
