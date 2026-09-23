#!/bin/bash
# Migration: Neovim and tmux moved out of core into --pack nvim and --pack tmux
# (tuidev 3.0).
#
# Core no longer installs neovim or tmux, deploys ~/.config/nvim, or writes the
# tuidev-tmux block. So nothing is ripped out of a machine that relies on them,
# carry each over into extra_packs where tuidev set it up:
#   - nvim: tuidev owns ~/.config/nvim — the manifest records it, or init.lua
#     is an unmodified copy of a version tuidev shipped;
#   - tmux: the profile is remote (which includes --pack tmux from 3.0 on),
#     or ~/.config/tmux/tmux.conf holds the tuidev-tmux managed block.
# A Neovim config or tmux.conf of your own is not tuidev's, so it is left out.
# The tools themselves are never touched either way.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

profile="$TUIDEV_PROFILE_FILE_DEFAULT"
nvim_src="$MIGRATION_DIR/../../configs/nvim"
nvim_dest="$HOME/.config/nvim"
tmux_conf="$HOME/.config/tmux/tmux.conf"

if [[ ! -f "$profile" ]]; then
    print_info "no tuidev profile — nothing to carry over"
    exit 0
fi

nvim_is_ours() {
    tuidev_manifest_has dir "$nvim_dest" && return 0
    tuidev_manifest_has file "$nvim_dest/init.lua" && return 0
    tuidev_is_shipped "$nvim_dest/init.lua" "$nvim_src/init.lua" "$nvim_src/shipped.sha256" init.lua
}

# The remote profile includes --pack tmux in 3.0, so a remote node gets it
# recorded whatever its tmux.conf holds (update.sh never adds a block to a
# tmux.conf of your own).
tmux_is_ours() {
    load_tuidev_profile "$profile" && [[ "$TUIDEV_PROFILE_NAME" == remote ]] && return 0
    [[ -f "$tmux_conf" ]] && grep -qxF "$(tuidev_block_begin tuidev-tmux)" "$tmux_conf"
}

carried=""
carry() {
    local pack="$1" rc=0
    tuidev_profile_add_pack "$pack" "$profile" || rc=$?
    case "$rc" in
        0) carried="${carried:+$carried }$pack"
           print_success "added $pack to extra_packs in $profile" ;;
        1) print_info "$pack pack already recorded" ;;
        *) print_error "could not update $profile"; exit 1 ;;
    esac
}

nvim_is_ours && carry nvim
tmux_is_ours && carry tmux

if [[ -z "$carried" ]]; then
    print_info "no tuidev-managed Neovim config or tmux.conf — nothing to carry over"
    exit 0
fi

print_info "Carried over: $carried. They keep updating with ./scripts/update.sh --configs."
print_info "Don't want one? Remove it from extra_packs in $profile (the tool stays installed)."
