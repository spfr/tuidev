#!/bin/bash
#
# Optional pack: zellij
#
# Installs the zellij terminal multiplexer and syncs the opinionated config
# + layouts from configs/zellij/ into ~/.config/zellij/.
#
# Entrypoint: zellij_install
# Invoked via: ./install.sh --pack zellij
#
# NOTE: zellij's config.kdl is KDL — `#` is part of hash-prefixed strings, not
# a comment. The write_managed_block helper currently emits `#`-style marker
# lines, which would corrupt KDL. Until write_managed_block learns to emit
# KDL-safe `// >>> tuidev managed (...) >>>` markers, we install config.kdl
# via `install_config --adopt-existing` (no inline markers). Layout files are
# plain copies — they have no managed-block semantics.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

zellij_install() {
    print_header "Pack: zellij"
    command_exists brew || die "Homebrew is required. Install it first: https://brew.sh"

    brew_install_formula zellij

    run_cmd mkdir -p "$HOME/.config/zellij/layouts"

    local src_config="$REPO_ROOT/configs/zellij/config.kdl"
    local dst_config="$HOME/.config/zellij/config.kdl"
    if [[ -f "$src_config" ]]; then
        # KDL's `#` is hash-prefixed-string syntax, not a comment; managed-block
        # markers would corrupt the file. Use --adopt-existing so we only drop
        # in the shipped config on fresh installs and preserve user edits.
        run_cmd install_config "$dst_config" "$src_config" --adopt-existing
    else
        print_warning "Source config not found: $src_config (skipping config.kdl)"
    fi

    local src_layouts="$REPO_ROOT/configs/zellij/layouts"
    local dst_layouts="$HOME/.config/zellij/layouts"
    if [[ -d "$src_layouts" ]]; then
        print_step "Syncing zellij layouts..."
        local layout_file dst_file
        shopt -s nullglob
        for layout_file in "$src_layouts"/*.kdl; do
            dst_file="$dst_layouts/$(basename "$layout_file")"
            [[ -f "$dst_file" ]] && cmp -s "$layout_file" "$dst_file" && continue
            run_cmd cp "$layout_file" "$dst_file"
            print_success "Layout: $(basename "$layout_file")"
        done
        shopt -u nullglob
    fi

    print_success "zellij pack complete"
    print_info "Try: zellij --layout dev"
}

# Only auto-run when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    zellij_install "$@"
fi
