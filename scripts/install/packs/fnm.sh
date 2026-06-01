#!/bin/bash
#
# Optional pack: fnm
#
# Installs fnm (Fast Node Manager, Rust) — a drop-in, ~1ms-startup replacement
# for nvm. It reads .nvmrc / .node-version / package.json engines.node and, with
# `--use-on-cd` (already wired into the managed ~/.zshrc block), auto-switches
# Node per project. The shipped zsh config prefers fnm when it is present and
# falls back to the existing nvm setup otherwise — installing this pack is all
# you need.
#
# Entrypoint: fnm_install
# Invoked via: ./install.sh --pack fnm
#
# Upstream: https://github.com/Schniz/fnm

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

# Homebrew formula(e) this pack installs — declared so `update.sh --packages`
# can discover and upgrade it (see scripts/update.sh `pack_formulae`).
FNM_FORMULAE=(fnm)

# Resolve the fnm binary even if it was just installed and isn't on PATH yet in
# this non-interactive shell. Echoes the path (or nothing) on stdout.
_fnm_bin() {
    if command_exists fnm; then
        command -v fnm
        return 0
    fi
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    [[ -n "$prefix" && -x "$prefix/bin/fnm" ]] && printf '%s\n' "$prefix/bin/fnm"
}

# Ensure fnm manages at least one Node version so `fnm env` yields a usable node
# in new shells. Installs the latest LTS and marks it default. Non-fatal.
_fnm_ensure_node() {
    local fnm_bin="$1"
    [[ -z "$fnm_bin" ]] && return 0

    if [[ "${DRY_RUN:-false}" == true ]]; then
        print_info "[dry-run] would run: fnm install --lts && fnm default <version>"
        return 0
    fi
    if "$fnm_bin" ls 2>/dev/null | grep -qiE 'v[0-9]'; then
        print_success "fnm already manages a Node version"
        return 0
    fi

    print_step "installing latest LTS Node via fnm"
    "$fnm_bin" install --lts || print_warning "fnm install --lts failed (continuing)"
    local latest
    latest="$("$fnm_bin" ls 2>/dev/null | grep -oiE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)"
    [[ -n "$latest" ]] && "$fnm_bin" default "$latest" 2>/dev/null || true
}

fnm_install() {
    print_header "Pack: fnm"

    if command_exists brew; then
        brew_update_once
        brew_install_formulae "${FNM_FORMULAE[@]}"
    elif is_linux; then
        print_warning "Homebrew not found. Install fnm via the official script:"
        print_info "    https://github.com/Schniz/fnm#installation"
        return 0
    else
        die "Homebrew is required; install from https://brew.sh"
    fi

    _fnm_ensure_node "$(_fnm_bin)"

    print_info "Open a new shell — the managed ~/.zshrc prefers fnm automatically."
    print_info "fnm reads .nvmrc/.node-version and switches Node on cd."
    print_success "fnm pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    fnm_install "$@"
fi
