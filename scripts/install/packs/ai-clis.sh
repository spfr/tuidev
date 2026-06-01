#!/bin/bash
#
# Optional pack: ai-clis
#
# AI coding-CLI integration, kept OUT of the core terminal-tools bundle so the
# repo stays CLI-agnostic and current as CLIs churn. This pack:
#   - drops the shell wrappers (cc/cx/oc, sbx auto-routing) into
#     ~/.config/tuidev/shell.d/ai-clis.zsh — sourced by the managed ~/.zshrc;
#   - adopts (never clobbers) the shipped AI CLI configs.
#
# It does NOT install the CLIs themselves — they self-update and manage their
# own install. Pair with `--pack sandbox` (or `--profile desktop`) so the
# wrappers route through Seatbelt; without sbx they call the CLI directly.
#
# Entrypoint: ai_clis_install
# Invoked via: ./install.sh --pack ai-clis
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

# Drop a repo-owned shell fragment into the shell.d/ dir the managed ~/.zshrc
# sources. Overwrite (it lives in our dir, not a user file); back up first.
_ai_clis_install_fragment() {
    local src="$REPO_ROOT/configs/zsh/ai-clis.zsh"
    local dest_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tuidev/shell.d"
    local dest="$dest_dir/ai-clis.zsh"
    [[ -f "$src" ]] || { print_warning "ai-clis fragment missing: $src"; return 0; }

    if [[ "${DRY_RUN:-false}" == true ]]; then
        print_info "[dry-run] would install $dest"
        return 0
    fi
    mkdir -p "$dest_dir"
    install_config "$dest" "$src" --overwrite
}

# Adopt the shipped AI CLI configs — present only if the user has none.
_ai_clis_install_configs() {
    [[ -f "$REPO_ROOT/configs/claude/settings.json" ]] &&
        install_config "$HOME/.claude.json" \
            "$REPO_ROOT/configs/claude/settings.json" --adopt-existing

    if [[ -f "$REPO_ROOT/configs/opencode/opencode.json" ]]; then
        [[ "${DRY_RUN:-false}" == true ]] || mkdir -p "$HOME/.config/opencode"
        install_config "$HOME/.config/opencode/opencode.json" \
            "$REPO_ROOT/configs/opencode/opencode.json" --adopt-existing
    fi

    if [[ -f "$REPO_ROOT/configs/codex/config.toml" ]]; then
        [[ "${DRY_RUN:-false}" == true ]] || mkdir -p "$HOME/.codex"
        install_config "$HOME/.codex/config.toml" \
            "$REPO_ROOT/configs/codex/config.toml" --adopt-existing
    fi
}

ai_clis_install() {
    print_header "Pack: ai-clis"
    _ai_clis_install_fragment
    _ai_clis_install_configs
    command_exists sbx || print_info "No sbx on PATH — wrappers call CLIs directly. Add --pack sandbox for Seatbelt."
    print_info "Open a new shell: cc (claude), cx (codex), oc (opencode) are now available."
    print_success "ai-clis pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ai_clis_install "$@"
fi
