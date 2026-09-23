#!/bin/bash
#
# Optional pack: sandbox-container (Tier 2)
#
# Makes a container runtime available for running AI agents with stronger
# isolation than bare host execution. Picks one in tuidev's order — Apple
# `container` (macOS 26+, native, nothing to install beyond Apple's pkg) →
# Podman → Docker (scripts/lib/container.sh) — and brings its VM/service up.
# Podman is installed only when no runtime is present at all.
#
# Entrypoint: sandbox_container_install
# Invoked via: ./install.sh --pack sandbox-container

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"
# shellcheck source=../../lib/container.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/container.sh"

# The fallback runtime, installed only when none is present. Declared so
# `update.sh --packages` upgrades a Homebrew-installed podman.
SANDBOX_CONTAINER_FORMULAE=(podman)

# No runtime at all: point at Apple's native one, then install podman.
_sbx_install_fallback_runtime() {
    if is_macos; then
        print_info "Apple's native 'container' CLI (macOS 26+) is preferred and needs no VM manager:"
        print_info "  install the signed pkg from https://github.com/apple/container/releases"
        print_info "Falling back to Podman now so the pack still works."
    fi
    pkg_install "${SANDBOX_CONTAINER_FORMULAE[@]}" || true
}

sandbox_container_install() {
    print_header "Pack: sandbox-container (Tier 2)"

    local rt
    if ! rt="$(tuidev_container_runtime)"; then
        _sbx_install_fallback_runtime
        if ! rt="$(tuidev_container_runtime)"; then
            print_warning "no container runtime available — install one, then re-run this pack."
            return 0
        fi
    fi
    print_success "container runtime: $(tuidev_container_label "$rt")"

    print_step "starting the $(tuidev_container_label "$rt") VM/service"
    run_cmd tuidev_container_up "$rt" \
        || print_warning "could not start it now (continuing); retry with: make sandbox-up"

    print_info "Stop it when idle: 'make sandbox-down'; start: 'make sandbox-up'."
    print_info "Force another runtime with TUIDEV_CONTAINER_RUNTIME=container|podman|docker."
    print_success "sandbox-container pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sandbox_container_install "$@"
fi
