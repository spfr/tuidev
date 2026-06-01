#!/bin/bash
#
# Optional pack: cmux
#
# Installs cmux — a Ghostty-based native macOS terminal built for running
# multiple AI coding agents in parallel: vertical tabs, notification rings
# (OSC 9/99/777), a built-in browser with Playwright-equivalent automation, and
# Claude Code Teams integration. Requires macOS 14+.
#
# Why opt-in: cmux is a native macOS GUI app. It complements — it does not
# replace — the tmux-primary workflow, which keeps session durability,
# SSH-reattach, mobile access, and Linux parity. See docs/agent-workflows.md.
#
# Entrypoint: cmux_install
# Invoked via: ./install.sh --pack cmux
#
# Upstream: https://github.com/manaflow-ai/cmux  (AGPL-3.0)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

# Homebrew cask(s) this pack installs — declared so `update.sh --packages` can
# discover and upgrade it (see scripts/update.sh `pack_casks`).
CMUX_CASKS=(cmux)

cmux_install() {
    print_header "Pack: cmux"

    if ! is_macos; then
        print_warning "cmux is macOS-only (requires macOS 14+); skipping on this platform."
        return 0
    fi
    command_exists brew || die "Homebrew is required on macOS; install from https://brew.sh"

    brew_update_once
    print_step "tapping manaflow-ai/cmux"
    run_cmd brew tap manaflow-ai/cmux || print_warning "brew tap failed (continuing)"
    brew_install_casks "${CMUX_CASKS[@]}"

    print_info "Launch via Spotlight or 'open -a cmux'. cmux runs your AI CLIs"
    print_info "(cc/cx/oc) in parallel panes. See docs/agent-workflows.md."
    print_success "cmux pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmux_install "$@"
fi
