#!/bin/bash
# Migration: remove artifacts a pre-2.0 tuidev install left in $HOME whose
# source has since been deleted from the repo.
#
# The 1.x installer (pre `feat: tuidev 2.0`) copied helpers and templates into
# $HOME unconditionally. Two of those no longer exist anywhere in the repo, so
# no amount of re-running install/update will ever refresh or remove them:
#
#   ~/.local/bin/ai-workflow.sh   from scripts/ai-workflow.sh, deleted in
#                                 "chore: remove ralph, gemini, MCP"
#   ~/.config/mcp-env.template    from configs/mcp/env.template, same commit
#
# The same commit also dropped MCP and Gemini support, leaving behind the empty
# scaffolding directories ~/.local/share/{gemini,mcp}. Those are removed only
# when empty — if the user has since put their own Gemini or MCP state there,
# it stays. ~/.gemini is deliberately untouched: it is the Gemini CLI's own
# config home, and the user may well still use that CLI.
#
# Everything removed here is backed up to ~/.config/tuidev/backups/ first.
# Safe to re-run by hand: every step checks before it mutates.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

changed=0

# Orphaned files: back up, then remove.
for orphan in \
    "$HOME/.local/bin/ai-workflow.sh" \
    "$HOME/.config/mcp-env.template"; do
    if [[ -e "$orphan" ]]; then
        backup="$(tuidev_backup "$orphan" "$(basename "$orphan")")" \
            || { print_error "could not back up $orphan"; exit 1; }
        rm -rf "$orphan"
        print_success "removed orphaned $orphan (backup: $backup)"
        changed=$((changed + 1))
    fi
done

# Scaffolding directories: remove only when the user put nothing in them.
# `rmdir` fails on a non-empty directory, which is exactly the guard we want.
for scaffold in \
    "$HOME/.local/share/gemini" \
    "$HOME/.local/share/mcp"; do
    if [[ -d "$scaffold" ]]; then
        if rmdir "$scaffold" 2>/dev/null; then
            print_success "removed empty $scaffold"
            changed=$((changed + 1))
        else
            print_info "kept $scaffold (not empty — contains your own files)"
        fi
    fi
done

if [[ $changed -eq 0 ]]; then
    print_info "no pre-2.0 orphans found — nothing to do"
fi
