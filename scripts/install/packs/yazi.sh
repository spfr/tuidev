#!/bin/bash
#
# Optional pack: yazi
#
# Installs the yazi terminal file manager. No config shipped — yazi's defaults
# are excellent and opinionated themes belong in a later pack.
#
# Entrypoint: yazi_install
# Invoked via: ./install.sh --pack yazi

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

yazi_install() {
    print_header "Pack: yazi"
    command_exists brew || die "Homebrew is required. Install it first: https://brew.sh"
    brew_install_formula yazi
    print_info "yazi ships with sensible defaults; no config written."
    print_info "Optional alias (not shipped): add 'alias y=\"yazi\"' to your zshrc."
    print_success "yazi pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    yazi_install "$@"
fi
