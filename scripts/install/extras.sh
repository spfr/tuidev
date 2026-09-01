#!/bin/bash
# scripts/install/extras.sh - install pack: optional CLI niceties.
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: extras_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'extras':
#   Quality-of-life CLI tools — shell history, disk viz, network monitors,
#   benchmarking, code stats, man-page helpers. All Homebrew formulae. No
#   casks, no configs.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../lib/brew.sh"

# Formula list (Homebrew). Alphabetized for drift-diff friendliness.
EXTRAS_FORMULAE=(
    atuin
    bandwhich
    broot
    duf
    dust
    fastfetch
    glow
    hyperfine
    ncdu
    procs
    sd
    tealdeer
    tokei
)
# bottom lives in --pack monitoring; kept out of extras to avoid double-count.

extras_install() {
    print_header "Pack: extras"

    # extras are never required (see health_check.sh). On a Linux box without
    # Homebrew — e.g. aarch64, which brew does not support — skip gracefully
    # instead of killing the whole install.
    if ! command_exists brew; then
        if is_macos; then
            die "Homebrew is required on macOS; install from https://brew.sh"
        fi
        print_warning "extras pack needs Homebrew, which is not installed."
        print_info "These are optional quality-of-life tools; core is unaffected."
        print_info "Install them from your distribution instead, e.g.:"
        print_info "    sudo apt-get install -y ${EXTRAS_FORMULAE[*]}"
        print_info "(names and availability vary by release; skip what apt lacks)"
        return 0
    fi

    brew_update_once
    brew_install_formulae "${EXTRAS_FORMULAE[@]}"
    print_success "extras pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    extras_install "$@"
fi
