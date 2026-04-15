#!/bin/bash
#
# Optional pack: sandbox-container (Tier 2)
#
# Installs Podman, initializes its VM (macOS), builds the tuidev/agent-sandbox
# container image, and drops the sbx-container helper onto PATH. Intended for
# running AI agents inside a rootless container for stronger isolation than
# bare host execution.
#
# Entrypoint: sandbox_container_install
# Invoked via: ./install.sh --pack sandbox-container

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"

# --- Install podman on the host OS ------------------------------------------
_sbx_install_podman() {
    if command_exists podman; then
        print_success "podman already installed"
        return 0
    fi

    if is_macos; then
        command_exists brew || die "Homebrew is required on macOS. Install it first: https://brew.sh"
        brew_install_cask podman
    elif is_linux; then
        print_step "Installing Podman on Linux..."
        if command_exists apt-get; then
            run_cmd sudo apt-get update
            run_cmd sudo apt-get install -y podman || die "apt-get install podman failed"
        elif command_exists dnf; then
            run_cmd sudo dnf install -y podman || die "dnf install podman failed"
        elif command_exists pacman; then
            run_cmd sudo pacman -S --noconfirm podman || die "pacman -S podman failed"
        elif command_exists brew; then
            run_cmd brew install podman || die "brew install podman failed"
        else
            die "No supported package manager found. See https://podman.io/docs/installation"
        fi
    else
        die "Unsupported OS. See https://podman.io/docs/installation"
    fi

    print_success "podman installed"
}

# --- Initialize and start the podman machine (macOS mostly) -----------------
_sbx_init_machine() {
    # Only macOS (and some Linux setups) need a VM. On native Linux, podman
    # runs directly — `podman machine` is a no-op in that case.
    if ! command_exists podman; then
        return 0
    fi

    local existing
    existing="$(podman machine list --format '{{.Name}}' 2>/dev/null || true)"

    if [[ -n "$existing" ]]; then
        print_success "podman machine already exists: $(echo "$existing" | head -n1 | tr -d '[:space:]')"
        return 0
    fi

    print_step "Initializing podman machine (creates and starts the default VM)..."
    if run_cmd podman machine init --now; then
        print_success "podman machine initialized and started"
    else
        # On Linux with rootless podman, `machine init` may not apply.
        print_warning "podman machine init failed — if you're on native Linux this is expected (no VM needed)."
    fi
}

# --- Build the agent-sandbox image ------------------------------------------
_sbx_build_image() {
    local containerfile="$REPO_ROOT/docker/agent-sandbox/Containerfile"

    if [[ ! -f "$containerfile" ]]; then
        print_info "Containerfile not shipped yet — skipping image build (Phase 4 scope)"
        return 0
    fi

    if ! command_exists podman; then
        print_warning "podman not on PATH — skipping image build"
        return 0
    fi

    print_step "Building tuidev/agent-sandbox image..."
    (
        cd "$REPO_ROOT" && \
        run_cmd podman build -t tuidev/agent-sandbox -f "$containerfile" .
    ) || die "Failed to build tuidev/agent-sandbox image"
    print_success "tuidev/agent-sandbox image built"
}

# --- Install sbx-container helper -------------------------------------------
_sbx_install_helper() {
    local src="$REPO_ROOT/bin/sbx-container"
    local dst_dir="$HOME/.local/bin"
    local dst="$dst_dir/sbx-container"

    if [[ ! -f "$src" ]]; then
        print_info "bin/sbx-container not shipped yet — skipping helper install"
        return 0
    fi

    run_cmd mkdir -p "$dst_dir"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        print_success "sbx-container helper already up to date"
    else
        run_cmd cp "$src" "$dst"
        run_cmd chmod 0755 "$dst"
        print_success "Installed $dst"
    fi
}

sandbox_container_install() {
    print_header "Pack: sandbox-container (Tier 2)"

    _sbx_install_podman
    _sbx_init_machine
    _sbx_build_image
    _sbx_install_helper

    print_info "Podman allocates a VM (on macOS). Stop it when idle: 'podman machine stop'"
    print_info "Start it back up with: 'podman machine start'"
    print_success "sandbox-container pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sandbox_container_install "$@"
fi
