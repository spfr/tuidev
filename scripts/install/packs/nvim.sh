#!/bin/bash
#
# Optional pack: nvim
#
# Neovim with tuidev's LazyVim config, for a terminal editor next to (or
# instead of) a GUI one. Core no longer ships an editor: locally $EDITOR is
# VS Code or Cursor when present (see ~/.zshrc). This pack:
#   - installs neovim;
#   - deploys configs/nvim into ~/.config/nvim, file by file (below);
#   - drops the vim/vi/v → nvim aliases into
#     $TUIDEV_STATE_DIR/shell.d/nvim.zsh — sourced by the managed ~/.zshrc.
#
# Entrypoint: nvim_install
# Invoked via: ./install.sh --pack nvim
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

NVIM_FORMULAE=(neovim)   # read by pack_array: update, health check, uninstall

# Neovim (LazyVim) config, file by file into ~/.config/nvim. A file that is an
# unmodified copy of any version we shipped (configs/nvim/shipped.sha256) is
# upgraded with a backup; one you edited is kept; new files are added. Runs on
# install and on every `update.sh --configs`, so config fixes reach existing
# machines. Files you added yourself are never touched.
#
# Only a tree tuidev owns is managed: an absent ~/.config/nvim, or one whose
# init.lua is (a shipped version of) ours or that the manifest records. Your own
# Neovim config — a LazyVim starter, kickstart, anything — is left alone, so
# our plugin specs never land in its lua/plugins/.
_nvim_config_is_ours() {
    local src_root="$1" dest_root="$2" init="$2/init.lua"
    [[ -e "$dest_root" ]] || return 0
    [[ -f "$init" ]] || return 1
    cmp -s "$init" "$src_root/init.lua" && return 0
    tuidev_is_shipped "$init" "$src_root/init.lua" "$src_root/shipped.sha256" init.lua && return 0
    tuidev_manifest_has dir "$dest_root" || tuidev_manifest_has file "$init"
}

_nvim_install_config() {
    local src_root="$REPO_ROOT/configs/nvim" dest_root="$HOME/.config/nvim" src rel
    [[ -d "$src_root" ]] || return 0
    command_exists nvim || return 0
    if ! _nvim_config_is_ours "$src_root" "$dest_root"; then
        print_info "keeping your own Neovim config in $dest_root (tuidev's is in $src_root)"
        return 0
    fi
    print_step "Neovim config -> $dest_root"
    while IFS= read -r src; do
        rel="${src#"$src_root"/}"
        [[ "$rel" == shipped.sha256 ]] && continue
        install_config "$dest_root/$rel" "$src" \
            --upgrade-shipped "$src_root/shipped.sha256" --shipped-name "$rel"
    done < <(find "$src_root" -type f -not -name '.*' | LC_ALL=C sort)
}

# The vim/vi/v aliases live in our own shell.d dir, not the user's ~/.zshrc.
_nvim_install_fragment() {
    local src="$REPO_ROOT/configs/zsh/nvim.zsh"
    [[ -f "$src" ]] || { print_warning "nvim fragment missing: $src"; return 0; }
    install_config "$TUIDEV_STATE_DIR/shell.d/nvim.zsh" "$src" --overwrite
}

nvim_install() {
    print_header "Pack: nvim"
    pkg_install "${NVIM_FORMULAE[@]}" || print_warning "neovim not installed (continuing)"
    _nvim_install_config
    _nvim_install_fragment
    print_success "nvim pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    nvim_install "$@"
fi
