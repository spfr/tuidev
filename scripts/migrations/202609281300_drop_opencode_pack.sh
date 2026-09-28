#!/bin/bash
# Migration: the opencode pack was removed (3.2.3).
#
# tuidev supports Claude Code and Codex only. This drops `opencode` from
# extra_packs so update, health check and uninstall stop looking for a pack
# script that no longer exists, and removes the `oc` wrapper fragment
# ($TUIDEV_STATE_DIR/shell.d/opencode.zsh, tuidev's own file written with
# --overwrite) after backing it up. ~/.config/opencode and the opencode
# binary are yours and are never touched.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"

profile="$TUIDEV_PROFILE_FILE_DEFAULT"
if [[ -f "$profile" ]]; then
    rc=0
    tuidev_profile_remove_pack opencode "$profile" || rc=$?
    case "$rc" in
        0) print_success "dropped opencode from extra_packs in $profile" ;;
        1) ;;
        *) print_error "could not update $profile"; exit 1 ;;
    esac
fi

fragment="$TUIDEV_STATE_DIR/shell.d/opencode.zsh"
if [[ -L "$fragment" ]]; then
    print_info "kept $fragment: it is a symlink of yours"
elif [[ -f "$fragment" ]]; then
    backup="$(tuidev_backup "$fragment" opencode.zsh)" \
        || { print_error "could not back up $fragment"; exit 1; }
    rm -f "$fragment"
    print_success "removed the oc wrapper ($fragment, backup: $backup)"
    print_info "OpenCode itself and ~/.config/opencode were left in place. If you still use it,"
    print_info "put ~/.opencode/bin on PATH in your own ~/.zshrc and run \`opencode\` directly."
else
    print_info "no opencode shell fragment — nothing to remove"
fi
