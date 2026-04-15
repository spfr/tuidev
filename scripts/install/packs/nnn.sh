#!/bin/bash
#
# Optional pack: nnn
#
# Installs the nnn TUI file manager. No config shipped.
#
# Entrypoint: nnn_install
# Invoked via: ./install.sh --pack nnn
#
# The repo standardizes on one file manager per machine for muscle-memory
# reasons. If yazi is already installed we warn the user but do not refuse.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

nnn_install() {
    print_header "Pack: nnn"
    command_exists brew || die "Homebrew is required. Install it first: https://brew.sh"

    # Dual-file-manager warning — non-fatal.
    if command_exists yazi || brew_has_formula yazi; then
        print_warning "yazi is already installed. You can have both, but we recommend picking one for muscle memory."
    fi

    brew_install_formula nnn
    print_info "nnn ships with sensible defaults; no config written."
    print_success "nnn pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    nnn_install "$@"
fi
