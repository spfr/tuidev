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
#   Tailscale (mesh VPN, macOS cask), mosh (roaming SSH, via scripts/lib/pkg.sh),
#   SSH client config snippet (managed block), and optional sshd_config.d
#   hardening when we have write permission. System packages go through
#   pkg.sh (root or `sudo -n` only); if /etc/ssh is not writable, we print a
#   manual pointer instead.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../lib/pkg.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../lib/config_write.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Casks (macOS only).
REMOTE_CASKS=(
    tailscale
)

# Formulae (Homebrew names; pkg.sh maps them for apt/dnf/pacman).
REMOTE_FORMULAE=(
    mosh
)

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
        if command_exists brew; then
            brew_update_once
            brew_install_casks "${REMOTE_CASKS[@]}"
        fi
    else
        # Tailscale ships its own Linux repos and installer; we point at it
        # rather than pipe a remote script into a shell.
        print_info "Tailscale on Linux: use the official installer — https://tailscale.com/download/linux"
    fi
    pkg_install "${REMOTE_FORMULAE[@]}" || print_warning "mosh not installed (continuing)"

    _install_ssh_client_config
    _install_sshd_snippets

    print_success "remote pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    remote_install "$@"
fi
