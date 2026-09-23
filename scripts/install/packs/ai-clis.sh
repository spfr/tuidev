#!/bin/bash
#
# Optional pack: ai-clis
#
# AI coding-CLI configs, kept OUT of the core terminal-tools bundle so the
# repo stays CLI-agnostic and current as CLIs churn. This pack adopts the
# shipped Claude Code and Codex configs: placed when absent, upgraded when
# still an unmodified copy of an earlier release
# (configs/{claude,codex}/shipped.sha256), never clobbered once edited.
#
# Both configs turn the CLI's NATIVE sandbox on (Claude Code: the `sandbox`
# block in settings.json; Codex: sandbox_mode = "workspace-write"), so a plain
# `claude` or `codex` is sandboxed — there are no wrappers. `sbx` (--sandbox)
# stays available for anything else; see docs/sandboxing.md.
#
# OpenCode is an optional support line with its own pack: --pack opencode.
#
# It does NOT install the CLIs themselves — they self-update and manage their
# own install.
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

# Adopt the shipped AI CLI configs. A copy the user edited is theirs; one that
# is byte-identical to a version we shipped is upgraded (backup first).
_ai_clis_install_configs() {
    # Claude Code reads settings from ~/.claude/settings.json. (~/.claude.json
    # is the CLI's own state file — never write settings there.)
    if [[ -f "$REPO_ROOT/configs/claude/settings.json" ]]; then
        [[ "${DRY_RUN:-false}" == true ]] || mkdir -p "$HOME/.claude"
        install_config "$HOME/.claude/settings.json" \
            "$REPO_ROOT/configs/claude/settings.json" \
            --upgrade-shipped "$REPO_ROOT/configs/claude/shipped.sha256"
    fi

    if [[ -f "$REPO_ROOT/configs/codex/config.toml" ]]; then
        [[ "${DRY_RUN:-false}" == true ]] || mkdir -p "$HOME/.codex"
        install_config "$HOME/.codex/config.toml" \
            "$REPO_ROOT/configs/codex/config.toml" \
            --upgrade-shipped "$REPO_ROOT/configs/codex/shipped.sha256"
    fi

    # Codex's counterpart of Claude's `ask` rules: git and gh writes prompt.
    # A file of its own, so tuidev owns it outright and the user's rules
    # (default.rules, where Codex saves approvals) are never touched.
    if [[ -f "$REPO_ROOT/configs/codex/rules/tuidev.rules" ]]; then
        install_config "$HOME/.codex/rules/tuidev.rules" \
            "$REPO_ROOT/configs/codex/rules/tuidev.rules" --overwrite
    fi
}

ai_clis_install() {
    print_header "Pack: ai-clis"
    _ai_clis_install_configs
    print_info "Run claude or codex directly: the shipped configs turn on each CLI's native sandbox."
    # A settings.json of the user's own is kept as it is; say so only when it
    # lacks the sandbox block (under --dry-run nothing was written, so skip).
    local settings="$HOME/.claude/settings.json"
    if [[ "${DRY_RUN:-false}" != true && -f "$settings" ]] && ! grep -q '"sandbox"' "$settings"; then
        print_warning "$settings (yours, kept) has no sandbox settings: merge the sandbox block by hand (docs/sandboxing.md)."
    fi
    print_success "ai-clis pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ai_clis_install "$@"
fi
