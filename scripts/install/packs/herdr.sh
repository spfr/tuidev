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
    _herdr_install_sidebar "$dest"
}

# The sidebar's workspace and agent rows (configs/herdr/sidebar.toml), a
# managed block, unless the config already has its own [ui.sidebar.spaces] or
# [ui.sidebar.agents] outside that block: a second table of either kind would
# be a TOML error that stops Herdr reading the file. (A block an older tuidev
# wrote stays as it is then: it is valid beside your own agent rows.)
_herdr_install_sidebar() {
    local dest="$1" src="$REPO_ROOT/configs/herdr/sidebar.toml"
    [[ -f "$src" ]] || return 0
    if herdr_has_own_sidebar "$dest"; then
        print_info "herdr: your config sets [ui.sidebar.spaces] or [ui.sidebar.agents] itself, so tuidev's rows were not added;"
        print_info "  add \"\$tuidev_agents\" to your spaces rows for each workspace's sessions (agents herdr sync)."
        return 0
    fi
    install_config "$dest" "$src" --managed-block tuidev-sidebar || true
}

# tuidev's Herdr plugin (configs/herdr/plugins/tuidev-link): a Ctrl-click on a
# localhost or file link opens on the machine you sit at, and a Ports popup.
# Copied to $TUIDEV_LIB_DIR and linked from there, so it runs without the
# repo; linking again after an update is how Herdr reads a changed manifest.
_herdr_install_plugin() {
    local src="$REPO_ROOT/configs/herdr/plugins/tuidev-link" dest="$TUIDEV_LIB_DIR/herdr-plugins/tuidev-link" f
    [[ -f "$src/herdr-plugin.toml" ]] || return 0
    # Did the plugin change? Asked before the copy: an unchanged plugin that
    # is linked is left linked, so an update costs Herdr nothing.
    local changed=false
    for f in "$src"/*; do
        cmp -s "$f" "$dest/${f##*/}" || changed=true
    done
    print_step "installing the tuidev.link Herdr plugin -> $dest"
    for f in "$src"/*; do
        install_config "$dest/${f##*/}" "$f" --overwrite
    done
    # The binary this pack just placed: ~/.local/bin may not be on PATH yet.
    local herdr; herdr="$(herdr_direct_path)"; [[ -x "$herdr" ]] || herdr="herdr"
    if [[ "$changed" == false && "$DRY_RUN" != true ]] && "$herdr" plugin list 2>/dev/null | grep -q 'tuidev\.link'; then
        install_config "$HOME/.config/herdr/config.toml" "$REPO_ROOT/configs/herdr/keys.toml" --managed-block tuidev-keys
        return 0
    fi
    # Linking closes the plugin's own popups: an update started from one
    # (prefix+u, the palette) leaves that to a run outside it.
    if [[ -n "${TUIDEV_PLUGIN_PANE:-}" && "$DRY_RUN" != true ]]; then
        if [[ "$changed" == true ]]; then
            print_warning "the tuidev.link plugin changed: run 'tuidev update --configs' from a shell outside this popup to load it"
        else
            print_warning "the tuidev.link plugin is not linked: run 'tuidev update --configs' from a shell outside this popup to link it"
        fi
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        run_cmd "$herdr" plugin link "$dest"
        return 0
    fi
    # Linked again so Herdr reads a changed manifest; a link that was there
    # and can't be made again is put back as it was (the files are the new
    # ones either way), and without one the keys are not written.
    local had=false
    ! "$herdr" plugin list 2>/dev/null | grep -q 'tuidev\.link' || had=true
    "$herdr" plugin unlink tuidev.link >/dev/null 2>&1 || true
    if ! "$herdr" plugin link "$dest" >/dev/null 2>&1; then
        [[ "$had" == false ]] || "$herdr" plugin link "$dest" >/dev/null 2>&1 || true
        print_warning "could not link the tuidev.link plugin: herdr plugin link $dest (continuing)"
        return 0
    fi
    # Its keys, as a managed block in your config (the plugin first: a key
    # for an action Herdr does not know would be an error).
    install_config "$HOME/.config/herdr/config.toml" "$REPO_ROOT/configs/herdr/keys.toml" --managed-block tuidev-keys
    "$herdr" server reload-config >/dev/null 2>&1 || true
    print_info "tuidev.link: prefix+a is the palette (everything tuidev can do), prefix+u its updates,"
    print_info "  prefix+space the board (every session, by who needs you; ? lists its keys),"
    print_info "  prefix+m the map (what runs where, and stop it), prefix+shift+o the ports."
    print_info "  Ctrl-click a localhost link in a pane of another machine to open it here (needs --pack monitoring on both; docs/remote.md)."
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
    _herdr_install_plugin
    print_info "Run 'herdr' to attach."
    [[ "$HERDR_INSTALLED_NOW" == true ]] && _herdr_first_run_hints
    if [[ -n "$(herdr_systemd_units)" ]]; then
        print_info "Upgrade: tuidev update --packages (it reloads the systemd units that hand over; never herdr update --handoff here)."
    else
        print_info "Upgrade: herdr update --handoff from a shell outside Herdr (or tuidev update --packages)."
    fi
    print_info "After an upgrade: tuidev check names outdated integrations and a stale server."
    herdr_path_note
    herdr_cutover_hint
    print_success "herdr pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    herdr_install "$@"
fi
