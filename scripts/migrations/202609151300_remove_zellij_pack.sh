#!/bin/bash
# Migration: the zellij pack was removed in tuidev 2.3.0.
#
# tmux is the only multiplexer now. This retires what `--pack zellij` placed:
#   - ~/.config/zellij/  — backed up, then removed, but ONLY when the manifest
#     shows tuidev installed the pack. A zellij config the user set up
#     themselves is never touched.
#   - the `zellij` formula is left installed either way; removing a brew
#     package on the user's behalf is uninstall.sh's job, not a migration's.
#     We print the command instead.
#   - `zellij` is dropped from the profile's extra_packs so
#     update.sh stops trying to re-apply a pack that no longer exists.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"

zdir="$HOME/.config/zellij"

if tuidev_manifest_has pack zellij; then
    if [[ -d "$zdir" ]]; then
        backup="$(tuidev_backup "$zdir" "zellij")" \
            || { print_error "could not back up $zdir"; exit 1; }
        rm -rf "$zdir"
        print_success "removed $zdir (backup: $backup)"
    fi
    if command -v zellij >/dev/null 2>&1; then
        print_info "zellij binary left in place — remove it with: brew uninstall zellij"
    fi
else
    print_info "tuidev never installed the zellij pack here — nothing removed"
fi

# Drop the pack from the recorded profile so update.sh stops re-applying it.
if tuidev_profile_remove_pack zellij; then
    print_success "dropped zellij from extra_packs in $TUIDEV_PROFILE_FILE_DEFAULT"
fi
