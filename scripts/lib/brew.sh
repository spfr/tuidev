#!/bin/bash
# scripts/lib/brew.sh - shared Homebrew helpers for install packs.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/brew.sh"
#
# Exposes:
#   brew_update_once        runs `brew update --quiet` at most once per process
#   brew_has_formula NAME   true if a formula is installed
#   brew_has_cask NAME      true if a cask is installed
#   brew_install_formula N  idempotent formula install via run_cmd
#   brew_install_cask N     idempotent cask install via run_cmd
#
# Caching: first `brew_has_formula` / `brew_has_cask` call populates a
# newline-separated list via `brew list` once instead of once per probe.
# Plain strings (not associative arrays) keep this compatible with the
# macOS-shipped bash 3.2.

if [[ -n "${_TUIDEV_BREW_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_BREW_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

export _TUIDEV_INSTALLED_FORMULAE=""
export _TUIDEV_INSTALLED_CASKS=""
export _TUIDEV_BREW_FORMULA_CACHED=0
export _TUIDEV_BREW_CASK_CACHED=0

_brew_cache_formulae() {
    [[ "$_TUIDEV_BREW_FORMULA_CACHED" = 1 ]] && return 0
    if command_exists brew; then
        _TUIDEV_INSTALLED_FORMULAE="$(brew list --formula -1 2>/dev/null)"
    fi
    _TUIDEV_BREW_FORMULA_CACHED=1
}

_brew_cache_casks() {
    [[ "$_TUIDEV_BREW_CASK_CACHED" = 1 ]] && return 0
    if command_exists brew; then
        _TUIDEV_INSTALLED_CASKS="$(brew list --cask -1 2>/dev/null)"
    fi
    _TUIDEV_BREW_CASK_CACHED=1
}

brew_has_formula() {
    _brew_cache_formulae
    [[ -n "$_TUIDEV_INSTALLED_FORMULAE" ]] && \
        printf '%s\n' "$_TUIDEV_INSTALLED_FORMULAE" | grep -qxF "$1"
}

brew_has_cask() {
    _brew_cache_casks
    [[ -n "$_TUIDEV_INSTALLED_CASKS" ]] && \
        printf '%s\n' "$_TUIDEV_INSTALLED_CASKS" | grep -qxF "$1"
}

# Run `brew update --quiet` at most once per process. Packs that need a
# fresh index just call this; the second+ callers are no-ops.
brew_update_once() {
    [[ -n "${_TUIDEV_BREW_UPDATED:-}" ]] && return 0
    if ! command_exists brew; then
        _TUIDEV_BREW_UPDATED=1
        return 0
    fi
    print_step "updating Homebrew metadata"
    run_cmd brew update --quiet || print_warning "brew update failed (continuing)"
    _TUIDEV_BREW_UPDATED=1
}

brew_install_formula() {
    local f="$1"
    if brew_has_formula "$f"; then
        print_success "$f (already present)"
    else
        print_step "installing $f"
        if run_cmd brew install "$f"; then
            print_success "$f"
            _TUIDEV_INSTALLED_FORMULAE="${_TUIDEV_INSTALLED_FORMULAE}"$'\n'"$f"
        else
            print_warning "failed: $f (continuing)"
        fi
    fi
}

brew_install_cask() {
    local c="$1"
    if brew_has_cask "$c"; then
        print_success "$c (already present)"
    else
        print_step "installing cask $c"
        if run_cmd brew install --cask "$c"; then
            print_success "$c"
            _TUIDEV_INSTALLED_CASKS="${_TUIDEV_INSTALLED_CASKS}"$'\n'"$c"
        else
            print_warning "failed: $c (continuing)"
        fi
    fi
}
