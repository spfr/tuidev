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
    command_exists brew || die "Homebrew is required; install from https://brew.sh"
    brew_update_once
    for f in "${EXTRAS_FORMULAE[@]}"; do
        brew_install_formula "$f"
    done
    print_success "extras pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    extras_install "$@"
fi
