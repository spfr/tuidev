#!/bin/bash
# Migration: tuidev's Claude Code settings moved to the file Claude reads.
#
# Releases up to 2.2.0 installed configs/claude/settings.json to ~/.claude.json.
# That path is Claude Code's own state file (onboarding, OAuth, per-project
# state), not its settings file — the hooks and permissions written there were
# silently ignored. Settings belong in ~/.claude/settings.json, which the
# ai-clis pack now installs (update.sh re-runs the pack right after this).
#
# This migration deliberately does NOT create ~/.claude/settings.json: the
# 2.2.0 keys are stale (undocumented env var, unsupported hook filter), and
# seeding the file would make the pack's --adopt-existing keep them forever.
# Instead it preserves the legacy keys as a backup for reference and lets the
# pack install the current shipped settings. ~/.claude.json is never modified:
# Claude Code owns it and the stray keys are harmless.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

state="$HOME/.claude.json"
settings="$HOME/.claude/settings.json"

[[ -f "$state" ]] || { print_info "no ~/.claude.json — nothing to migrate"; exit 0; }

if ! command -v jq >/dev/null 2>&1; then
    print_warning "jq not found; skipping the ~/.claude.json settings check (harmless)"
    exit 0
fi

if ! jq -e 'has("hooks")' "$state" >/dev/null 2>&1; then
    print_info "$HOME/.claude.json carries no tuidev settings keys — nothing to migrate"
    exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq '{permissions, env, hooks} | with_entries(select(.value != null))' "$state" > "$tmp"
backup="$(tuidev_backup "$tmp" "claude-settings-legacy.json")" \
    || { print_error "could not back up legacy Claude settings"; exit 1; }
print_success "legacy tuidev Claude settings (from ~/.claude.json) saved to $backup"

if [[ -f "$settings" ]]; then
    print_info "$settings already exists; leaving it alone"
else
    print_info "the ai-clis pack will now install the current settings to $settings"
fi
print_info "  (~/.claude.json keeps the stray hooks/permissions keys — Claude ignores them)"
