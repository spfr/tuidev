#!/bin/bash
# scripts/install/remote.sh - install pack: remote-access stack.
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: remote_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'remote':
#   Tailscale (mesh VPN, macOS cask), mosh (roaming SSH, formula or apt),
#   SSH client config snippet (managed block), and optional sshd_config.d
#   hardening when we have write permission. No sudo escalation here; if
#   /etc/ssh is not writable, we print a manual pointer instead.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../lib/brew.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../lib/config_write.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Casks (macOS-only).
REMOTE_CASKS_MACOS=(
    tailscale
)

# Formulae (macOS + Linux-via-brew).
REMOTE_FORMULAE=(
    mosh
)

_install_apt() {
    local pkg="$1"
    if dpkg -s "$pkg" &>/dev/null; then
        print_success "$pkg (already present)"
    else
        print_step "installing $pkg via apt"
        if run_cmd sudo apt-get install -y "$pkg"; then
            print_success "$pkg"
        else
            print_warning "failed: $pkg (continuing)"
        fi
    fi
}

_install_ssh_client_config() {
    local src="$REPO_ROOT/configs/ssh/config"
    local dest="$HOME/.ssh/config"
    if [[ ! -f "$src" ]]; then
        print_warning "ssh client config missing in repo: $src"
        return 0
    fi
    print_step "installing SSH client config (managed block)"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh" 2>/dev/null || true
    fi
    install_config "$dest" "$src" --managed-block tuidev-remote
    if [[ "$DRY_RUN" != true ]] && [[ -f "$dest" ]]; then
        chmod 600 "$dest" 2>/dev/null || true
    fi
}

_install_sshd_snippets() {
    local src_dir="$REPO_ROOT/configs/ssh/sshd_config.d"
    local dest_dir="/etc/ssh/sshd_config.d"
    if [[ ! -d "$src_dir" ]]; then
        return 0
    fi

    # Only proceed if snippets exist in repo.
    local snippets=()
    while IFS= read -r -d '' f; do
        snippets+=("$f")
    done < <(find "$src_dir" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)

    if [[ ${#snippets[@]} -eq 0 ]]; then
        return 0
    fi

    if [[ ! -d "$dest_dir" ]] || [[ ! -w "$dest_dir" ]]; then
        print_info "sshd snippets not installed: $dest_dir is not writable without sudo."
        print_info "To apply manually:"
        for f in "${snippets[@]}"; do
            print_info "    sudo cp '$f' '$dest_dir/'"
        done
        print_info "    sudo systemctl reload ssh   # or: sudo launchctl kickstart -k system/com.openssh.sshd"
        return 0
    fi

    for f in "${snippets[@]}"; do
        local base
        base="$(basename "$f")"
        local target="$dest_dir/$base"
        if [[ -f "$target" ]] && cmp -s "$f" "$target"; then
            print_success "sshd snippet $base (already current)"
            continue
        fi
        print_step "installing sshd snippet $base"
        run_cmd cp "$f" "$target"
    done
}

remote_install() {
    print_header "Pack: remote"

    if is_macos; then
        command_exists brew || die "Homebrew is required on macOS; install from https://brew.sh"
        brew_update_once

        for c in "${REMOTE_CASKS_MACOS[@]}"; do
            brew_install_cask "$c"
        done
        for f in "${REMOTE_FORMULAE[@]}"; do
            brew_install_formula "$f"
        done

    elif is_linux; then
        # Tailscale is not provided via the same channels on Linux and has its
        # own install script; we leave it to the user and only handle mosh.
        print_info "Tailscale on Linux: use the official installer — https://tailscale.com/download/linux"
        if command_exists brew; then
            print_info "brew detected on Linux; using brew for formulae"
            brew_update_once
            for f in "${REMOTE_FORMULAE[@]}"; do
                brew_install_formula "$f"
            done
        elif command_exists apt-get; then
            run_cmd sudo apt-get update -y || print_warning "apt-get update failed (continuing)"
            for f in "${REMOTE_FORMULAE[@]}"; do
                _install_apt "$f"
            done
        else
            print_warning "no supported package manager (brew or apt); install mosh manually"
        fi
    else
        print_warning "unsupported platform for remote pack; skipping package installs"
    fi

    _install_ssh_client_config
    _install_sshd_snippets

    print_success "remote pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    remote_install "$@"
fi
