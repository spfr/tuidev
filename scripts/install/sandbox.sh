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
#   Adopt Seatbelt policy files (configs/sandbox/profiles/*.sb) into
#   $TUIDEV_STATE_DIR/sandbox/ and install the `sbx` wrapper to ~/.local/bin,
#   both through config_write.sh so the manifest records them. macOS-only
#   (Tier 1); on Linux we point the user at the Tier 2 container pack.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../lib/config_write.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SANDBOX_DIR="$TUIDEV_STATE_DIR/sandbox"
SBX_DEST="$HOME/.local/bin/sbx"

sandbox_install() {
    print_header "Pack: sandbox"

    if is_linux; then
        print_warning "sandbox (Tier 1 / Seatbelt) is macOS-only."
        print_info "Linux users: '--pack sandbox-container' runs agents in a container instead."
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

    # A profile the user edited in place wins. One that is an unmodified copy
    # of any version we shipped (shipped.sha256) is upgraded, so policy fixes
    # reach existing installs.
    print_step "installing Seatbelt profiles -> $SANDBOX_DIR"
    local found_profile=false profile
    while IFS= read -r -d '' profile; do
        found_profile=true
        install_config "$SANDBOX_DIR/$(basename "$profile")" "$profile" \
            --upgrade-shipped "$profiles_src/shipped.sha256"
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
    install_config "$SBX_DEST" "$sbx_src" --overwrite
    [[ "$DRY_RUN" == true ]] || chmod 0755 "$SBX_DEST"

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
