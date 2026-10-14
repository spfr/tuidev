#!/bin/bash
#
# Optional pack: monitoring
#
# Installs container and system monitoring TUIs (lazydocker, bottom) and
# `agents`, a command that shows and controls agentic-coding processes
# (sessions, orphaned MCP servers, CPU hogs, keep-awake, thermal pressure).
# On macOS it adds SwiftBar and a menu-bar plugin built on `agents`.
#
# Entrypoint: monitoring_install
# Invoked via: ./install.sh --pack monitoring

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

MONITORING_FORMULAE=(lazydocker bottom)
MONITORING_CASKS=(swiftbar)   # macOS only; casks are Homebrew-on-macOS

MONITORING_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MONITORING_SWIFTBAR_DOMAIN="com.ameba.SwiftBar"

# The plugin folder SwiftBar is set to, or the one this pack sets it to.
_monitoring_plugin_dir() {
    local dir
    dir="$(defaults read "$MONITORING_SWIFTBAR_DOMAIN" PluginDirectory 2>/dev/null || true)"
    if [[ -n "$dir" ]]; then
        printf '%s\n' "${dir/#\~/$HOME}"
    else
        printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/swiftbar/plugins"
    fi
}

MONITORING_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/agents.conf"

# The agents command is bin/agents plus its modules, lib/agents/, which go to
# $TUIDEV_LIB_DIR/agents: ~/.local/bin/agents finds them there, beside it.
# The modules go first, so an interrupted install never leaves a new
# agents without them (the old one needs none).
_monitoring_agents() {
    local dest="$HOME/.local/bin/agents" lib="$TUIDEV_LIB_DIR/agents" src
    print_step "installing the agents modules -> $lib"
    while IFS= read -r src; do
        install_config "$lib/${src#"$MONITORING_REPO/lib/agents/"}" "$src" --overwrite
    done < <(find "$MONITORING_REPO/lib/agents" -type f \( -name '*.sh' -o -name '*.awk' \) | LC_ALL=C sort)
    print_step "installing the agents command -> $dest"
    install_config "$dest" "$MONITORING_REPO/bin/agents" --overwrite
    [[ "$DRY_RUN" == true ]] || chmod 0755 "$dest"
    # Yours once placed: a commented example, never overwritten.
    install_config "$MONITORING_CONF" "$MONITORING_REPO/configs/agents/agents.conf" --adopt-existing
}

# The plugin's file name carries SwiftBar's refresh interval
# (AGENTS_BAR_REFRESH in agents.conf, read by agents' own parser).
_monitoring_plugin_name() {
    local refresh
    refresh="$(AGENTS_CONF="$MONITORING_CONF" bash "$MONITORING_REPO/bin/agents" config 2>/dev/null \
        | sed -n 's/^AGENTS_BAR_REFRESH=//p')"
    printf 'agents.%s.sh\n' "${refresh:-10s}"
}

# Drop a plugin this pack placed under another interval's name, so SwiftBar
# doesn't run two copies after AGENTS_BAR_REFRESH changes.
_monitoring_prune_plugins() {
    local dir="$1" keep="$2" old
    while IFS= read -r old; do
        [[ "$old" == "$dir"/agents.*.sh && "$old" != "$dir/$keep" && -f "$old" ]] || continue
        run_cmd rm -f "$old" && print_info "removed $old (refresh interval changed)"
    done < <(tuidev_manifest_values file 2>/dev/null)
}

_monitoring_swiftbar() {
    if command_exists brew; then
        brew_update_once
        brew_install_casks "${MONITORING_CASKS[@]}" || print_warning "SwiftBar not installed (continuing)"
    else
        print_warning "Homebrew not found: skipping SwiftBar (install from https://brew.sh)"
    fi

    # A plugin folder the user already chose wins; only an unset one is pointed
    # at ours, so SwiftBar's first launch doesn't ask for one.
    local dir
    dir="$(_monitoring_plugin_dir)"
    if ! defaults read "$MONITORING_SWIFTBAR_DOMAIN" PluginDirectory >/dev/null 2>&1; then
        print_step "pointing SwiftBar's plugin folder at $dir"
        run_cmd defaults write "$MONITORING_SWIFTBAR_DOMAIN" PluginDirectory "$dir" \
            || print_warning "could not set SwiftBar's plugin folder (continuing)"
    fi

    local name
    name="$(_monitoring_plugin_name)"
    print_step "installing the SwiftBar plugin -> $dir/$name"
    install_config "$dir/$name" "$MONITORING_REPO/configs/swiftbar/agents.10s.sh" --overwrite
    [[ "$DRY_RUN" == true ]] || chmod 0755 "$dir/$name"
    _monitoring_prune_plugins "$dir" "$name"

    print_info "Open SwiftBar once (open -a SwiftBar) and turn on Launch at login in its settings."
}

monitoring_install() {
    print_header "Pack: monitoring"

    pkg_install "${MONITORING_FORMULAE[@]}" || print_warning "monitoring: not everything installed (continuing)"
    _monitoring_agents
    if is_macos; then
        _monitoring_swiftbar
    fi

    print_info "bottom installs as 'btm' on your PATH."
    print_info "lazydocker requires a running Docker (or Podman) daemon."
    print_info "agents: run 'agents' (or 'agents watch'); 'agents --help' lists kill, reap and awake."

    print_success "monitoring pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitoring_install "$@"
fi
