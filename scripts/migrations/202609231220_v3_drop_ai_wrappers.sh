#!/bin/bash
# Migration: the cc / cx wrappers were removed (tuidev 3.0).
#
# --pack ai-clis used to drop $TUIDEV_STATE_DIR/shell.d/ai-clis.zsh, which
# defined cc and cx and routed claude / codex through sbx. The shipped configs
# now turn on each CLI's native sandbox instead, so the fragment goes. It is
# tuidev's own file (written with --overwrite), so it is backed up and deleted.
# ~/.claude and ~/.codex are never touched here: this only reports whether
# Claude Code's settings.json has the sandbox block yet, and how to get it.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

fragment="$TUIDEV_STATE_DIR/shell.d/ai-clis.zsh"

if [[ ! -e "$fragment" ]]; then
    print_info "no ai-clis shell fragment — nothing to remove"
    exit 0
fi

backup="$(tuidev_backup "$fragment" ai-clis.zsh)" \
    || { print_error "could not back up $fragment"; exit 1; }
rm -f "$fragment"
print_success "removed the cc/cx wrappers ($fragment, backup: $backup)"
print_info "Open a new shell to drop cc and cx from it."

# Plain `claude` is sandboxed only once ~/.claude/settings.json carries the
# sandbox block. A 2.x copy doesn't, and nothing here rewrites it: the ai-clis
# pack upgrades an unmodified shipped copy when update.sh --configs re-runs it.
settings="$HOME/.claude/settings.json"
claude_src="$MIGRATION_DIR/../../configs/claude"
if [[ -f "$settings" ]] && grep -q '"sandbox"' "$settings"; then
    print_info "Run claude directly: $settings turns on its native sandbox."
elif tuidev_is_shipped "$settings" "$claude_src/settings.json" "$claude_src/shipped.sha256"; then
    print_warning "$settings is an unmodified 2.x copy without the sandbox settings."
    print_info "Run ./scripts/update.sh --configs to upgrade it (backup first); until then claude runs unsandboxed."
elif [[ -f "$settings" ]]; then
    print_warning "$settings (yours, kept as it is) has no sandbox settings: claude runs unsandboxed."
    print_info "Merge the sandbox block from configs/claude/settings.json (see docs/sandboxing.md)."
fi
