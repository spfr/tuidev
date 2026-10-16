#!/bin/bash
#
# Optional pack: herdr
#
# Installs herdr — an agent-aware terminal runtime (Rust). A background
# server owns panes so agents keep running after detach; a sidebar marks
# each detected agent working / blocked / done. The CLI and socket API are
# the same surface agents drive. herdr is its own multiplexer, an alternative
# to --pack tmux for durable agent sessions.
#
# Prefix is ctrl+b (tmux in this setup is ctrl+a). See docs/agent-workflows.md.
#
# Install policy: the release binary, in ~/.local/bin, checked against the
# sha256 its GitHub release lists (scripts/lib/herdr.sh). That is the install
# `herdr update --handoff` upgrades live; Homebrew's refuses to update itself.
# No package array: update.sh runs `herdr update`, never brew.
#
# Entrypoint: herdr_install
# Invoked via: ./install.sh --pack herdr
#
# Upstream: https://herdr.dev  (Apache-2.0)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"
# shellcheck source=../../lib/herdr.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/herdr.sh"

_herdr_install_config() {
    local src="$REPO_ROOT/configs/herdr/config.toml"
    local dest="$HOME/.config/herdr/config.toml"
    if [[ ! -f "$src" ]]; then
        print_warning "herdr config missing in repo: $src"
        return 0
    fi
    print_step "installing herdr config (adopt-existing)"
    install_config "$dest" "$src" --adopt-existing
}

_herdr_first_run_hints() {
    print_info "Prefix is ctrl+b (tmux is ctrl+a). See docs/agent-workflows.md."
    print_info "Optional: herdr integration install claude (and codex): agent state hooks."
    print_info "Agents under sbx strict cannot reach herdr's socket;"
    print_info "  sbx --allow-herdr opens it for agents you trust (herdr panes run unsandboxed)."
    print_info "Remote nodes: herdr machine add HOST (saved sidebar entry; pick its session)."
}

herdr_install() {
    print_header "Pack: herdr"

    if ! herdr_ensure_direct; then
        print_warning "herdr not installed (continuing)."
        print_info "Download $(herdr_asset 2>/dev/null || echo "your platform's binary") from https://github.com/herdrdev/herdr/releases,"
        print_info "  check it against the sha256 the release lists, put it at $(herdr_direct_path), then re-run this pack."
        return 0
    fi

    _herdr_install_config
    print_info "Run 'herdr' to attach."
    [[ "$HERDR_INSTALLED_NOW" == true ]] && _herdr_first_run_hints
    if [[ -n "$(herdr_systemd_units)" ]]; then
        print_info "Upgrade: ./scripts/update.sh --packages (it reloads the systemd units that hand over; never herdr update --handoff here)."
    else
        print_info "Upgrade: herdr update --handoff from a shell outside Herdr (or ./scripts/update.sh --packages)."
    fi
    print_info "After an upgrade: make check names outdated integrations and a stale server."
    herdr_path_note
    herdr_cutover_hint
    print_success "herdr pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    herdr_install "$@"
fi
