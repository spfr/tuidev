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
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

mosh_install() {
    print_header "Pack: mosh"

    if command_exists brew; then
        brew_install_formula mosh
    elif is_linux && command_exists apt-get; then
        run_cmd sudo apt-get update -y || print_warning "apt-get update failed (continuing)"
        if dpkg -s mosh &>/dev/null; then
            print_success "mosh (already present)"
        else
            run_cmd sudo apt-get install -y mosh || die "apt-get install mosh failed"
            print_success "mosh"
        fi
    elif is_linux && command_exists dnf; then
        run_cmd sudo dnf install -y mosh || die "dnf install mosh failed"
    elif is_linux && command_exists pacman; then
        run_cmd sudo pacman -S --noconfirm mosh || die "pacman -S mosh failed"
    else
        die "No supported package manager for mosh; install from https://mosh.org/#getting"
    fi

    print_info "mosh listens on UDP ports 60000–61000 — open them on your firewall."
    print_info "Connect with: mosh HOST   (requires ssh access + matching mosh on the remote)"
    print_success "mosh pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mosh_install "$@"
fi
