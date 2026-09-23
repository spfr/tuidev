#!/bin/bash
#
# Optional pack: opencode
#
# OpenCode support, split out of --pack ai-clis in 3.0: tuidev's primary AI
# CLIs are Claude Code and Codex; OpenCode is an optional support line. This
# pack:
#   - drops the `oc` wrapper (and ~/.opencode/bin on PATH) into
#     ~/.config/tuidev/shell.d/opencode.zsh — sourced by the managed ~/.zshrc;
#   - adopts (never clobbers) the shipped opencode.json + tui.json.
#
# Like ai-clis it does NOT install the CLI itself — OpenCode self-updates. The
# installer never pipes a remote script into a shell, so the official install
# command is printed instead.
#
# Entrypoint: opencode_install
# Invoked via: ./install.sh --pack opencode
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

_opencode_install_fragment() {
    local src="$REPO_ROOT/configs/zsh/opencode.zsh"
    local dest="$TUIDEV_STATE_DIR/shell.d/opencode.zsh"
    [[ -f "$src" ]] || { print_warning "opencode fragment missing: $src"; return 0; }
    install_config "$dest" "$src" --overwrite
}

# Adopt the shipped configs — present only if the user has none.
_opencode_install_configs() {
    [[ -f "$REPO_ROOT/configs/opencode/opencode.json" ]] || return 0
    install_config "$HOME/.config/opencode/opencode.json" \
        "$REPO_ROOT/configs/opencode/opencode.json" --adopt-existing
    # TUI settings (theme, scroll, attention) live in a sibling tui.json.
    if [[ -f "$REPO_ROOT/configs/opencode/tui.json" ]]; then
        install_config "$HOME/.config/opencode/tui.json" \
            "$REPO_ROOT/configs/opencode/tui.json" --adopt-existing
    fi
}

opencode_install() {
    print_header "Pack: opencode"
    _opencode_install_fragment
    _opencode_install_configs
    if command_exists opencode || [[ -x "$HOME/.opencode/bin/opencode" ]]; then
        print_success "opencode found — open a new shell for the oc wrapper"
    else
        print_info "OpenCode is not installed. Install it yourself, then open a new shell:"
        print_info "    curl -fsSL https://opencode.ai/install | bash   # see https://opencode.ai/docs"
    fi
    print_success "opencode pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    opencode_install "$@"
fi
