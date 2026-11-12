#!/bin/bash
#
# Optional pack: ci
#
# Installs the checks an agent runs before it commits CI changes or any code:
#   actionlint   lints GitHub Actions workflows (syntax, expressions, shellcheck)
#   zizmor       audits workflows for security problems (injection, over-broad
#                permissions, unpinned actions)
#   betterleaks  scans for committed secrets; reads .gitleaks.toml
# Agents write workflows and commit code, and nothing else in the set checks
# either. Nothing is written into $HOME.
#
# Entrypoint: ci_install
# Invoked via: ./install.sh --pack ci
#
# Upstream: https://github.com/rhysd/actionlint
#           https://github.com/zizmorcore/zizmor
#           https://github.com/betterleaks/betterleaks

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"

# Homebrew formulae (homebrew-core), declared so `update.sh --packages` can
# discover and upgrade them. Distributions package them unevenly; pkg_install
# lists whatever is missing with pkg_manual_hint's pointer and returns non-zero.
CI_FORMULAE=(actionlint zizmor betterleaks)

ci_install() {
    print_header "Pack: ci"

    if ! pkg_install "${CI_FORMULAE[@]}"; then
        print_warning "some ci tools not installed (continuing)"
    fi

    print_info "Before a commit:  actionlint  |  zizmor .github/workflows  |  betterleaks git"
    print_success "ci pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ci_install "$@"
fi
