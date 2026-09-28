#!/bin/bash
#
# Optional pack: hunk
#
# Installs hunk (https://hunk.dev), a review-first terminal diff viewer for
# agent-written changesets: multi-file review, watch mode, inline agent notes,
# and a pager mode for git. It is 0.x, so it stays opt-in. Nothing is written
# into $HOME: hunk's git pager wiring is a one-line opt-in printed below.
#
# Entrypoint: hunk_install
# Invoked via: ./install.sh --pack hunk
#
# Upstream: https://github.com/modem-dev/hunk

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"

# Homebrew formula (homebrew-core) — declared so `update.sh --packages` can
# discover and upgrade it. Not packaged by apt/dnf/pacman; pkg_install then
# prints pkg_manual_hint's pointer and returns non-zero.
HUNK_FORMULAE=(hunk)

hunk_install() {
    print_header "Pack: hunk"

    if ! pkg_install "${HUNK_FORMULAE[@]}"; then
        print_warning "hunk not installed (continuing)"
        print_info "Install it yourself: brew install hunk  |  npm i -g hunkdiff  (see https://github.com/modem-dev/hunk#install)"
    fi

    print_info "Review changes:  hunk diff [--watch]   |   hunk show [REV]"
    print_info "Opt in as git's pager:  git config --global core.pager \"hunk pager\""
    print_success "hunk pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    hunk_install "$@"
fi
