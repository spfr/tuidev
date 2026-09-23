#!/bin/bash
#
# Optional pack: vim
#
# Plain Vim with a zero-plugin vimrc: the lightweight terminal editor for
# servers and small boxes (a Raspberry Pi, a VM) where `--pack nvim`'s LazyVim
# is more than you need. This pack:
#   - installs vim (on macOS the system /usr/bin/vim is Vim 9 already, so
#     Homebrew's vim and its language runtimes are skipped);
#   - deploys configs/vim/vimrc as ~/.vim/vimrc with --upgrade-shipped. Vim
#     reads ~/.vimrc first, so a ~/.vimrc of your own wins and is left alone.
#
# Entrypoint: vim_install
# Invoked via: ./install.sh --pack vim
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

VIM_FORMULAE=(vim)   # read by pack_array: update, health check, uninstall

_vim_install_config() {
    local src="$REPO_ROOT/configs/vim/vimrc" dest="$HOME/.vim/vimrc"
    [[ -f "$src" ]] || { print_warning "vimrc missing: $src"; return 0; }
    if [[ -e "$HOME/.vimrc" ]]; then
        print_info "keeping your own ~/.vimrc (Vim reads it before $dest; tuidev's is in $src)"
        return 0
    fi
    print_step "Vim config -> $dest"
    install_config "$dest" "$src" --upgrade-shipped "$REPO_ROOT/configs/vim/shipped.sha256"
}

vim_install() {
    print_header "Pack: vim"
    if is_macos && [[ -x /usr/bin/vim ]]; then
        print_success "vim (system /usr/bin/vim)"
    else
        pkg_install "${VIM_FORMULAE[@]}" || print_warning "vim not installed (continuing)"
    fi
    _vim_install_config
    print_success "vim pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vim_install "$@"
fi
