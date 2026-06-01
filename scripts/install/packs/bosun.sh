#!/bin/bash
#
# Optional pack: bosun
#
# Installs bosun — a tmux-native orchestrator for AI agent sessions (Rust +
# ratatui). It lists, previews, creates, and manages tmux sessions running
# Claude Code, Codex, or a plain shell from a single TUI. bosun runs its
# sessions on a dedicated `tmux -L bosun` socket, so it never touches your main
# tmux state, and Claude Code's macOS Keychain auth flows through correctly.
# Unlike cmux (a GUI app), bosun stays inside the terminal — it aligns with the
# tmux-primary workflow. See docs/agent-workflows.md.
#
# Entrypoint: bosun_install
# Invoked via: ./install.sh --pack bosun
#
# Upstream: https://github.com/yetidevworks/bosun

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

BOSUN_REPO="https://github.com/yetidevworks/bosun"

bosun_install() {
    print_header "Pack: bosun"

    if command_exists bosun; then
        print_success "bosun (already present)"
        return 0
    fi

    # Prefer a Homebrew formula if upstream publishes one; otherwise build from
    # source with cargo. Mirrors remote.sh's graceful-degradation pattern.
    if command_exists brew && brew info bosun >/dev/null 2>&1; then
        brew_update_once
        brew_install_formula bosun
    elif command_exists cargo; then
        # Single-package repo (crate `bosun-tmux`, binary `bosun`); omit the
        # package name so cargo installs the only package regardless of its name.
        print_step "installing bosun via cargo (from $BOSUN_REPO)"
        run_cmd cargo install --git "$BOSUN_REPO" \
            || print_warning "cargo install from $BOSUN_REPO failed (continuing)"
    else
        print_warning "bosun needs Homebrew (with a formula) or a Rust toolchain (cargo)."
        print_info "Install Rust: https://rustup.rs"
        print_info "Then:        cargo install --git $BOSUN_REPO"
        return 0
    fi

    command_exists tmux || print_warning "bosun drives tmux; install it with --core to use bosun."
    print_info "Run 'bosun' to manage agent sessions. See docs/agent-workflows.md."
    print_success "bosun pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bosun_install "$@"
fi
