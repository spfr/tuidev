#!/bin/bash
#
# Optional pack: fnm
#
# Installs fnm (Fast Node Manager, Rust) — a drop-in, ~1ms-startup replacement
# for nvm. It reads .nvmrc / .node-version / package.json engines.node and, with
# `--use-on-cd` (already wired into the managed ~/.zshrc block), auto-switches
# Node per project. The shipped zsh config puts Node on PATH only through fnm
# (nvm is no longer wired in) — installing this pack is all you need.
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
# shellcheck source=../../lib/fnm.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/fnm.sh"

# Homebrew formula(e) this pack installs — declared so `update.sh --packages`
# can discover and upgrade it (see scripts/lib/packs.sh `pack_array`).
FNM_FORMULAE=(fnm)

# Ensure fnm manages at least one Node version so `fnm env` yields a usable node
# in new shells. Installs the latest LTS and marks it default. Non-fatal.
_fnm_ensure_node() {
    local fnm_bin="$1"
    [[ -z "$fnm_bin" ]] && return 0

    if [[ "${DRY_RUN:-false}" == true ]]; then
        print_info "[dry-run] would run: fnm install --lts && fnm default <version>"
        return 0
    fi
    if [[ -n "$(fnm_installed "$fnm_bin")" ]]; then
        print_success "fnm already manages a Node version"
        return 0
    fi

    print_step "installing latest LTS Node via fnm"
    "$fnm_bin" install --lts || print_warning "fnm install --lts failed (continuing)"
    local latest
    latest="$(fnm_installed "$fnm_bin" | tail -1)"
    if [[ -n "$latest" ]]; then
        "$fnm_bin" default "$latest" 2>/dev/null || true
    fi
}

fnm_install() {
    print_header "Pack: fnm"

    if ! command_exists brew; then
        print_warning "Homebrew not found. Install fnm yourself, then re-run this pack:"
        print_info "    https://github.com/Schniz/fnm#installation"
        return 0
    fi
    brew_update_once
    brew_install_formulae "${FNM_FORMULAE[@]}"

    _fnm_ensure_node "$(fnm_bin)"

    print_info "Open a new shell — the managed ~/.zshrc loads fnm automatically."
    print_info "fnm reads .nvmrc/.node-version and switches Node on cd."
    print_success "fnm pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    fnm_install "$@"
fi
