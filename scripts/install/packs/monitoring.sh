#!/bin/bash
#
# Optional pack: monitoring
#
# Installs container/cluster/system monitoring TUIs: lazydocker, k9s, bottom.
# No configs shipped — all three use sensible defaults.
#
# Entrypoint: monitoring_install
# Invoked via: ./install.sh --pack monitoring

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

MONITORING_FORMULAE=(lazydocker k9s bottom)

monitoring_install() {
    print_header "Pack: monitoring"
    command_exists brew || die "Homebrew is required. Install it first: https://brew.sh"

    for f in "${MONITORING_FORMULAE[@]}"; do
        brew_install_formula "$f"
    done

    print_info "bottom installs as 'btm' on your PATH."
    print_info "lazydocker requires a running Docker (or Podman) daemon."
    print_info "k9s requires a valid kubeconfig (~/.kube/config or \$KUBECONFIG)."

    print_success "monitoring pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitoring_install "$@"
fi
