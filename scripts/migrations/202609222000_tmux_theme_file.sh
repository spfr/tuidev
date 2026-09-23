#!/bin/bash
# Migration: the tmux theme moves out of tmux.conf into its own file (3.0).
#
# scripts/theme.sh used to append its tuidev-theme block to the end of
# ~/.config/tmux/tmux.conf (the only tmux config tuidev installs or themes),
# i.e. after TPM's `run` line. That resets status-right after the plugins have
# hooked it, which silently stops tmux-continuum's autosave. The theme now
# lives in ~/.config/tmux/theme.conf, which the shipped tmux.conf sources
# above its TPM block.
#
# This moves an existing block across: tmux.conf is backed up, the block's
# content goes to theme.conf (unless a newer apply already wrote one there),
# and the block is removed from tmux.conf. A tmux.conf that is the user's own
# (no tuidev-tmux block to refresh, e.g. adopt-existing installs) also gets a
# commented `source-file` line for theme.conf, above TPM's run line when there
# is one, so the theme keeps applying. Nothing else is touched.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

conf="$HOME/.config/tmux/tmux.conf"
theme_file="$HOME/.config/tmux/theme.conf"
block_id="tuidev-theme"

if ! block="$(read_managed_block "$conf" "$block_id")"; then
    print_info "no theme block in $conf — nothing to move"
    exit 0
fi

backup="$(tuidev_backup "$conf" "tmux.conf")" \
    || { print_error "could not back up $conf"; exit 1; }

if read_managed_block "$theme_file" "$block_id" >/dev/null; then
    print_info "$theme_file already holds a theme — keeping it"
elif [[ -n "$block" ]]; then
    write_managed_block "$theme_file" "$block_id" "$block" >/dev/null
fi

remove_managed_block "$conf" "$block_id" >/dev/null
print_success "moved the tmux theme from $conf to $theme_file (backup: $backup)"

# _source_theme_file — insert the source-file line before the first TPM
# `run`/`if-shell` line (plugins hook status-right when TPM runs, and a theme
# sourced after that would undo it), or append it when there is none.
_source_theme_file() {
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-migrate.XXXXXX")"
    awk '
        function emit() {
            print "# Added by tuidev 3.0: the tuidev theme now lives in theme.conf."
            print "# Keep this above TPM'"'"'s run line; delete it to drop the theme."
            print "source-file -q ~/.config/tmux/theme.conf"
            done = 1
        }
        !done && /^[[:space:]]*(run(-shell)?|if(-shell)?)[[:space:]].*tpm\/tpm/ { emit(); print ""; }
        { print }
        END { if (!done) { print ""; emit() } }
    ' "$conf" > "$tmp"
    mv "$tmp" "$conf"
}

if grep -qE '^[[:space:]]*source-file.*tmux/theme\.conf' "$conf"; then
    :
elif read_managed_block "$conf" tuidev-tmux >/dev/null; then
    print_info "tmux shows its default colors until the shipped tmux.conf is refreshed (make update-configs)"
else
    _source_theme_file
    print_success "added 'source-file -q ~/.config/tmux/theme.conf' to $conf"
fi
