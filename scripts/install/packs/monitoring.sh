#!/bin/bash
#
# Optional pack: monitoring
#
# Installs container and system monitoring TUIs (lazydocker, bottom) and
# `agents`, a command that shows and controls agentic-coding processes
# (sessions, orphaned MCP servers, CPU hogs, keep-awake, thermal pressure),
# with mcp-lazy, which `agents mcp lazy` puts in front of an MCP server so a
# session starts it on its first tool call.
# On macOS it adds SwiftBar and a menu-bar plugin built on `agents`, and
# terminal-notifier, so a click on an agent's notification jumps to its session,
# and a LaunchAgent that runs the memory guard (`agents mem guard`), which
# stops a runaway process in an agent tree before macOS runs out of memory.
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

# terminal-notifier makes notify.sh's banners clickable (a click jumps to the
# session); it is macOS-only, so pkg_install skips it on Linux (pkg.sh).
MONITORING_FORMULAE=(lazydocker bottom terminal-notifier)
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
# $TUIDEV_LIB_DIR/agents: ~/.local/bin/agents finds them there, beside it,
# with the API list prices its reports cost tokens at (prices.tsv; yours go
# in AGENTS_PRICES, never in this file). The modules go first, so an
# interrupted install never leaves a new agents without them (the old one
# needs none).
_monitoring_agents() {
    local dest="$HOME/.local/bin/agents" lib="$TUIDEV_LIB_DIR/agents" src
    print_step "installing the agents modules -> $lib"
    while IFS= read -r src; do
        install_config "$lib/${src#"$MONITORING_REPO/lib/agents/"}" "$src" --overwrite
    done < <(find "$MONITORING_REPO/lib/agents" -type f \( -name '*.sh' -o -name '*.awk' -o -name '*.tsv' \) | LC_ALL=C sort)
    print_step "installing the agents command -> $dest"
    install_config "$dest" "$MONITORING_REPO/bin/agents" --overwrite
    [[ "$DRY_RUN" == true ]] || chmod 0755 "$dest"
    # Beside agents, which writes its path into the MCP configs it makes lazy.
    print_step "installing mcp-lazy -> ${dest%/*}/mcp-lazy"
    install_config "${dest%/*}/mcp-lazy" "$MONITORING_REPO/bin/mcp-lazy" --overwrite
    [[ "$DRY_RUN" == true ]] || chmod 0755 "${dest%/*}/mcp-lazy"
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
    print_info "terminal-notifier: allow its notifications when macOS asks (or in System Settings > Notifications), so a click on an agent's banner jumps to its session; 'terminal-notifier -diagnose' says why none appear."
    print_info "The first click asks to let terminal-notifier control your terminal app: allow it, so a click lands on the session's tab (declined, it only brings the app forward)."
}

# The memory guard's LaunchAgent: the plist (configs/agents) with this
# install's paths filled in, then (re)loaded so a new agents takes over.
MONITORING_MEMGUARD_LABEL="dev.tuidev.memguard"
_monitoring_memguard() {
    local plist="$HOME/Library/LaunchAgents/$MONITORING_MEMGUARD_LABEL.plist" tmp
    local log="$HOME/Library/Logs/tuidev-memguard.log"
    local path="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    print_step "installing the memory guard (LaunchAgent) -> $plist"
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-memguard.XXXXXX")"
    sed -e "s|@AGENTS@|$HOME/.local/bin/agents|" -e "s|@PATH@|$path|" -e "s|@LOG@|$log|" \
        "$MONITORING_REPO/configs/agents/$MONITORING_MEMGUARD_LABEL.plist" > "$tmp"
    install_config "$plist" "$tmp" --overwrite
    rm -f "$tmp"
    [[ "$DRY_RUN" == true ]] && return 0
    local job
    job="gui/$(id -u)/$MONITORING_MEMGUARD_LABEL"
    if launchctl print "$job" >/dev/null 2>&1; then
        launchctl bootout "$job" 2>/dev/null || true
        # bootout returns before the job is gone, and bootstrap fails (5:
        # Input/output error) until it is: wait up to 5 s.
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            launchctl print "$job" >/dev/null 2>&1 || break
            sleep 0.25
        done
    fi
    run_cmd launchctl bootstrap "gui/$(id -u)" "$plist" \
        || print_warning "the memory guard did not start: agents mem restart (continuing)"
    print_info "memory guard: warns past 8 GB, stops a runaway in an agent tree past half the RAM; 'agents mem' shows it, AGENTS_MEM_* in $MONITORING_CONF tune it."
}

monitoring_install() {
    print_header "Pack: monitoring"

    pkg_install "${MONITORING_FORMULAE[@]}" || print_warning "monitoring: not everything installed (continuing)"
    _monitoring_agents
    if is_macos; then
        _monitoring_swiftbar
        _monitoring_memguard
    else
        print_info "memory guard: run 'agents mem guard' in a tmux pane (or a systemd user service) to stop runaway agent processes."
    fi

    print_info "bottom installs as 'btm' on your PATH."
    print_info "lazydocker requires a running Docker (or Podman) daemon."
    print_info "agents: run 'agents' (or 'agents watch'); 'agents --help' lists kill, reap and awake."
    print_info "agents mcp lists your MCP servers; 'agents mcp lazy NAME' starts one on its first tool call instead of with every session."

    print_success "monitoring pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitoring_install "$@"
fi
