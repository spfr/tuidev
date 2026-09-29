#!/bin/bash
#
# Optional pack: monitoring
#
# Installs container and system monitoring TUIs: lazydocker, bottom.
# No configs shipped — both use sensible defaults.
#
# Entrypoint: monitoring_install
# Invoked via: ./install.sh --pack monitoring

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"

MONITORING_FORMULAE=(lazydocker bottom)

monitoring_install() {
    print_header "Pack: monitoring"

    pkg_install "${MONITORING_FORMULAE[@]}" || print_warning "monitoring: not everything installed (continuing)"

    print_info "bottom installs as 'btm' on your PATH."
    print_info "lazydocker requires a running Docker (or Podman) daemon."

    print_success "monitoring pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitoring_install "$@"
fi
