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
#   - `pack zellij` is dropped from ~/.config/tuidev/profile's extra_packs so
#     update.sh stops trying to re-apply a pack that no longer exists.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

state_dir="$HOME/.config/tuidev"
manifest="$state_dir/manifest"
profile="$state_dir/profile"
zdir="$HOME/.config/zellij"

if [[ -f "$manifest" ]] && grep -qx 'pack zellij' "$manifest"; then
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
if [[ -f "$profile" ]] && grep -q '^extra_packs=' "$profile"; then
    old="$(grep '^extra_packs=' "$profile" | head -n1 | cut -d= -f2-)"
    new=""
    for p in ${old//,/ }; do
        [[ "$p" == zellij ]] && continue
        new="${new:+$new }$p"
    done
    if [[ "$new" != "$old" ]]; then
        tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
        awk -v v="$new" '/^extra_packs=/ && !done {print "extra_packs=" v; done=1; next} {print}' "$profile" > "$tmp"
        cp "$tmp" "$profile"
        print_success "dropped zellij from extra_packs in $profile"
    fi
fi
