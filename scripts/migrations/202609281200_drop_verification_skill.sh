#!/bin/bash
# Migration: the orchestration pack's `verification` skill was removed (3.3).
#
# Current Claude and GPT models check their own work, and both vendors now say
# verification reminders cause over-verification, so the skill goes. The pack
# installed it with --overwrite into ~/.claude/skills/verification/ and
# ~/.agents/skills/verification/; each SKILL.md is backed up and deleted, and
# the folder removed once empty. A symlink there is yours and is left alone.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

removed=0
for root in claude agents; do
    dir="$HOME/.$root/skills/verification"
    skill="$dir/SKILL.md"
    if [[ -L "$dir" || -L "$skill" ]]; then
        print_info "kept $dir: it is a symlink of yours"
        continue
    fi
    [[ -f "$skill" ]] || continue
    backup="$(tuidev_backup "$skill" "$root-verification-SKILL.md")" \
        || { print_error "could not back up $skill"; exit 1; }
    rm -f "$skill"
    rmdir "$dir" 2>/dev/null || print_info "kept $dir: it holds files of yours"
    print_success "removed the verification skill ($skill, backup: $backup)"
    removed=1
done

[[ "$removed" == 1 ]] || print_info "no verification skill installed — nothing to remove"
