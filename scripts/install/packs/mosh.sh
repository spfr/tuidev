#!/bin/bash
#
# Optional pack: mosh
#
# Installs mosh (mobile shell) on its own, without the full --remote pack
# (which also pulls in Tailscale and writes SSH config). Useful on hosts
# where you want roaming-friendly SSH but aren't managing a Tailscale node.
#
# Entrypoint: mosh_install
# Invoked via: ./install.sh --pack mosh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"

# Declared so `update.sh --packages` can discover/upgrade it; pkg.sh maps
# the name for apt/dnf/pacman.
MOSH_FORMULAE=(mosh)

mosh_install() {
    print_header "Pack: mosh"

    pkg_install "${MOSH_FORMULAE[@]}" || print_warning "mosh not installed (continuing)"

    print_info "mosh listens on UDP ports 60000–61000 — open them on your firewall."
    print_info "Connect with: mosh HOST   (requires ssh access + matching mosh on the remote)"
    print_success "mosh pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mosh_install "$@"
fi
