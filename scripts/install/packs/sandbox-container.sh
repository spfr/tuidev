#!/bin/bash
#
# Optional pack: sandbox-container (Tier 2)
#
# Picks a container runtime in tuidev's order — Apple `container` (macOS 26+,
# native, nothing to install beyond Apple's pkg) → Podman → Docker — brings its
# VM/service up, builds the tuidev/agent-sandbox image, and drops the
# sbx-container helper onto PATH. Intended for running AI agents inside a
# container for stronger isolation than bare host execution. Podman is only
# installed when no runtime is present at all.
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
# shellcheck source=../../lib/container.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/container.sh"

RUNTIME=""

# --- Resolve the runtime; install podman only if nothing is present ---------
_sbx_resolve_runtime() {
    if RUNTIME="$(tuidev_container_runtime)"; then
        print_success "container runtime: $(tuidev_container_label "$RUNTIME")"
        return 0
    fi
    if is_macos; then
        print_info "Apple's native 'container' CLI (macOS 26+) is preferred and needs no VM manager."
        print_info "  Install the signed pkg from https://github.com/apple/container/releases, then re-run this pack."
        print_info "  Falling back to Podman now so the pack still works."
    fi
    _sbx_install_podman
    RUNTIME="$(tuidev_container_runtime)" || die "no container runtime after podman install"
}

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

# --- Bring the runtime's VM / service up -------------------------------------
_sbx_init_machine() {
    case "$RUNTIME" in
        container)
            if container system status >/dev/null 2>&1; then
                print_success "container services already running"
            else
                print_step "Starting Apple container services..."
                run_cmd container system start || die "container system start failed"
                print_success "container services started"
            fi
            return 0
            ;;
        docker)
            if docker info >/dev/null 2>&1; then
                print_success "docker daemon reachable"
            else
                print_warning "docker daemon not reachable — start Docker before building"
            fi
            return 0
            ;;
    esac
    # podman: only macOS (and some Linux setups) need a VM. On native Linux,
    # podman runs directly — `podman machine` is a no-op in that case.
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

    [[ -n "$RUNTIME" ]] || { print_warning "no container runtime — skipping image build"; return 0; }

    print_step "Building tuidev/agent-sandbox image with $(tuidev_container_label "$RUNTIME")..."
    run_cmd tuidev_container_build "$RUNTIME" tuidev/agent-sandbox "$containerfile" "$REPO_ROOT" \
        || die "Failed to build tuidev/agent-sandbox image"
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

    _sbx_resolve_runtime
    _sbx_init_machine
    _sbx_build_image
    _sbx_install_helper

    print_info "Runtime: $(tuidev_container_label "$RUNTIME"). Stop it when idle: 'make sandbox-down'; start: 'make sandbox-up'."
    print_info "Force another runtime with TUIDEV_CONTAINER_RUNTIME=container|podman|docker."
    print_success "sandbox-container pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sandbox_container_install "$@"
fi
