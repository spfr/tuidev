#!/bin/bash
# scripts/install/sandbox.sh - install pack: Seatbelt sandbox (Tier 1).
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: sandbox_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'sandbox':
#   Copy Seatbelt policy files (configs/sandbox/profiles/*.sb) to
#   ~/.config/tuidev/sandbox/, install the `sbx` wrapper to ~/.local/bin,
#   and add a managed PATH block to ~/.zshrc. macOS-only (Tier 1); on Linux
#   we point the user at the future Tier 2 pack.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../lib/config_write.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SANDBOX_DIR="$HOME/.config/tuidev/sandbox"
SBX_DEST="$HOME/.local/bin/sbx"

_install_profile() {
    # Plain cp, --adopt-existing semantics: if the user has customized a
    # profile in-place, leave their copy alone (docs say user overrides win).
    local src="$1"
    local base
    base="$(basename "$src")"
    local dest="$SANDBOX_DIR/$base"

    if [[ -e "$dest" ]]; then
        print_info "adopt-existing: leaving $dest untouched"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would copy $src -> $dest"
        return 0
    fi

    cp "$src" "$dest"
    chmod 0644 "$dest" 2>/dev/null || true
    print_success "installed profile $base"
}

sandbox_install() {
    print_header "Pack: sandbox"

    if is_linux; then
        print_warning "sandbox (Tier 1 / Seatbelt) is macOS-only."
        print_info "Linux users: use '--pack sandbox-container' once the bubblewrap/Podman pack ships."
        return 0
    fi

    if ! is_macos; then
        print_warning "sandbox pack skipped: unsupported platform"
        return 0
    fi

    # 1. Copy Seatbelt profiles.
    local profiles_src="$REPO_ROOT/configs/sandbox/profiles"
    if [[ ! -d "$profiles_src" ]]; then
        print_error "sandbox profiles missing in repo: $profiles_src"
        return 1
    fi

    print_step "installing Seatbelt profiles -> $SANDBOX_DIR"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$SANDBOX_DIR"
    fi

    local found_profile=false
    while IFS= read -r -d '' profile; do
        found_profile=true
        _install_profile "$profile"
    done < <(find "$profiles_src" -maxdepth 1 -type f -name '*.sb' -print0 2>/dev/null)

    if [[ "$found_profile" != true ]]; then
        print_warning "no *.sb profiles found under $profiles_src"
    fi

    # 2. Install sbx wrapper.
    local sbx_src="$REPO_ROOT/bin/sbx"
    if [[ ! -f "$sbx_src" ]]; then
        print_error "sbx wrapper missing in repo: $sbx_src"
        return 1
    fi

    print_step "installing sbx wrapper -> $SBX_DEST"
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$HOME/.local/bin"
    fi
    run_cmd cp "$sbx_src" "$SBX_DEST"
    if [[ "$DRY_RUN" != true ]]; then
        chmod 0755 "$SBX_DEST"
    fi
    print_success "sbx installed"

    # 3. The ~/.local/bin PATH export used to live here, in a `tuidev-sandbox-path`
    #    block. That was the wrong owner: this pack is macOS-only and skipped on
    #    Linux, yet core.sh (Debian fd/bat shims) and install.sh (notify.sh) both
    #    put binaries in that directory on every platform. The export now ships
    #    in the tuidev-zshrc block. Drop the old block so existing installs
    #    converge instead of carrying a duplicate PATH entry.
    remove_managed_block "$HOME/.zshrc" "tuidev-sandbox-path"

    # 4. Verification hint.
    print_info "verify Seatbelt is available:"
    print_info "    sandbox-exec -p '(version 1)(allow default)' /usr/bin/true   # should succeed silently"
    print_info "then try: sbx --help"

    print_success "sandbox pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sandbox_install "$@"
fi
