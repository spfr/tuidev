#!/bin/bash
# scripts/install/ui.sh - install pack: macOS UI/desktop niceties.
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: ui_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'ui':
#   Ghostty config, window/clipboard/menu-bar utilities, Hammerspoon. macOS
#   only — no-op + print_warning on Linux. Brew install helpers come from
#   scripts/lib/brew.sh.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../lib/brew.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../lib/config_write.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

UI_CASKS_MACOS=(
    rectangle
    stats
    maccy
    hiddenbar
    hammerspoon
)

ui_install() {
    print_header "Pack: ui"

    if ! is_macos; then
        print_warning "ui pack is macOS-only; skipping on this platform"
        return 0
    fi

    command_exists brew || die "Homebrew is required; install from https://brew.sh"
    brew_update_once

    # Ghostty config (terminal emulator).
    local ghostty_src="$REPO_ROOT/configs/ghostty/config"
    if [[ -f "$ghostty_src" ]]; then
        print_step "installing Ghostty config (managed block)"
        install_config "$HOME/.config/ghostty/config" "$ghostty_src" --managed-block tuidev-ghostty
    else
        print_warning "Ghostty config missing in repo: $ghostty_src"
    fi

    # Desktop utility casks.
    for c in "${UI_CASKS_MACOS[@]}"; do
        brew_install_cask "$c"
    done

    # Hammerspoon init script (if repo ships one).
    local hs_src="$REPO_ROOT/configs/hammerspoon/init.lua"
    if [[ -f "$hs_src" ]]; then
        print_step "installing Hammerspoon init.lua (managed block)"
        install_config "$HOME/.hammerspoon/init.lua" "$hs_src" --managed-block tuidev-hammerspoon
    fi

    print_success "ui pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ui_install "$@"
fi
