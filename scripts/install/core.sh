#!/bin/bash
# scripts/install/core.sh - install pack: essential CLI tools.
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: core_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'core':
#   terminal multiplexer, editor, search, nav, git UX, shell prompt, JSON/YAML,
#   shell plugins, shellcheck. No GUI apps, no remote stack, no sandbox tooling.
#   Ghostty is added on macOS only.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../lib/brew.sh"

# Formula list (Homebrew). Kept alphabetized for drift-diff friendliness.
CORE_FORMULAE=(
    bat
    eza
    fd
    fzf
    gh
    git
    git-delta
    jq
    lazygit
    neovim
    ripgrep
    shellcheck
    starship
    tmux
    yq
    zoxide
    zsh-autosuggestions
    zsh-completions
    zsh-syntax-highlighting
)

# Formula that require --cask on macOS only.
CORE_CASKS_MACOS=(
    ghostty
)

core_install() {
    print_header "Pack: core"
    command_exists brew || die "Homebrew is required; install from https://brew.sh"

    brew_update_once

    for f in "${CORE_FORMULAE[@]}"; do
        brew_install_formula "$f"
    done

    if is_macos; then
        for c in "${CORE_CASKS_MACOS[@]}"; do
            brew_install_cask "$c"
        done
    fi

    print_success "core pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    core_install "$@"
fi
