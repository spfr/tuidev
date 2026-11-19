#!/bin/bash
#
# Optional pack: monitoring
#
# Installs container and system monitoring TUIs (bottom) and
# `agents`, a command that shows and controls agentic-coding processes
# (sessions, orphaned MCP servers, CPU hogs, keep-awake, thermal pressure),
# with mcp-lazy, which `agents mcp lazy` puts in front of an MCP server so a
# session starts it on its first tool call.
# On every platform it adds the sampler (`agents sample --scheduled`, once a
# minute: the history, tokens, runs, waits and usage limits, whether or not a
# menu runs) and the memory guard (`agents mem guard`), which stops a runaway
# process in an agent tree before the machine runs out of memory: on macOS
# as LaunchAgents (dev.tuidev.sample, dev.tuidev.memguard), on Linux as
# systemd user units (tuidev-sample.timer and .service,
# tuidev-memguard.service; no systemd, as in a container: a warning and what
# to run by hand). On macOS it adds SwiftBar and a menu-bar plugin built on
# `agents`, terminal-notifier, so a click on an agent's notification jumps to
# its session, and a LaunchAgent that runs the link watcher (`agents link
# watch`), which opens here what you click in a Herdr pane of another machine.
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
MONITORING_FORMULAE=(bottom terminal-notifier)
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
# in AGENTS_PRICES, never in this file) and the theme palettes its colors come
# from (lib/agents/palette.sh; without one it uses the terminal's own). The
# modules go first, so an interrupted install never leaves a new agents without
# them (the old one needs none).
_monitoring_agents() {
    local dest="$HOME/.local/bin/agents" lib="$TUIDEV_LIB_DIR/agents" src
    print_step "installing the agents modules -> $lib"
    while IFS= read -r src; do
        install_config "$lib/${src#"$MONITORING_REPO/lib/agents/"}" "$src" --overwrite
    done < <(find "$MONITORING_REPO/lib/agents" -type f \( -name '*.sh' -o -name '*.awk' -o -name '*.tsv' \) | LC_ALL=C sort)
    for src in "$MONITORING_REPO"/configs/themes/*/palette.toml; do
        install_config "$lib/themes/${src#"$MONITORING_REPO/configs/themes/"}" "$src" --overwrite
    done
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
# (AGENTS_BAR_REFRESH in agents.conf, read by agents' own parser; 1m, a
# backstop: the plugin refreshes on events). The source keeps its name,
# agents.10s.sh, which tests, docs and the menu goldens use; only the
# installed copy carries the interval.
_monitoring_plugin_name() {
    local refresh
    refresh="$(AGENTS_CONF="$MONITORING_CONF" bash "$MONITORING_REPO/bin/agents" config 2>/dev/null \
        | sed -n 's/^AGENTS_BAR_REFRESH=//p')"
    printf 'agents.%s.sh\n' "${refresh:-1m}"
}

# Drop a plugin this pack placed under another interval's name, so SwiftBar
# doesn't run two copies after AGENTS_BAR_REFRESH changes (or its default
# does: the 10s one an older tuidev installed, on the next update --configs).
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
        print_todo "Install Homebrew (https://brew.sh), then SwiftBar: tuidev install --pack monitoring"
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
    print_todo "Open SwiftBar once (open -a SwiftBar) and turn on Launch at login in its settings"
    print_todo "Allow terminal-notifier's notifications when macOS asks (System Settings > Notifications), and let it control your terminal app on the first click"
    print_info "terminal-notifier: allow its notifications when macOS asks (or in System Settings > Notifications), so a click on an agent's banner jumps to its session; 'terminal-notifier -diagnose' says why none appear."
    print_info "The first click asks to let terminal-notifier control your terminal app: allow it, so a click lands on the session's tab (declined, it only brings the app forward)."
}

# _monitoring_launchagent LABEL LOGNAME WHAT RESTART — one of agents' own
# LaunchAgents: the plist (configs/agents/LABEL.plist) with this install's
# paths filled in, then (re)loaded so a new agents takes over.
_monitoring_launchagent() {
    local label="$1" plist="$HOME/Library/LaunchAgents/$1.plist" tmp
    local log="$HOME/Library/Logs/$2.log"
    local path="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    print_step "installing $3 (LaunchAgent) -> $plist"
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-launchagent.XXXXXX")"
    sed -e "s|@AGENTS@|$HOME/.local/bin/agents|" -e "s|@PATH@|$path|" -e "s|@LOG@|$log|" \
        "$MONITORING_REPO/configs/agents/$label.plist" > "$tmp"
    install_config "$plist" "$tmp" --overwrite
    rm -f "$tmp"
    [[ "$DRY_RUN" == true ]] && return 0
    local job
    job="gui/$(id -u)/$label"
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
        || print_warning "$3 did not start: $4 (continuing)"
}

MONITORING_MEMGUARD_LABEL="dev.tuidev.memguard"
_monitoring_memguard() {
    _monitoring_launchagent "$MONITORING_MEMGUARD_LABEL" tuidev-memguard "the memory guard" "agents mem restart"
    print_info "memory guard: warns past 8 GB, stops a runaway in an agent tree past half the RAM; 'agents mem' shows it, AGENTS_MEM_* in $MONITORING_CONF tune it."
}

# The sampler: `agents sample --scheduled` once a minute, so the history,
# tokens, runs, waits and limits stay current without the menu (and the
# hooks' waits outside Herdr are recorded). A sample the menu or `agents
# watch` took within 55 s stands: the run then does nothing.
MONITORING_SAMPLE_LABEL="dev.tuidev.sample"
_monitoring_sampler() {
    _monitoring_launchagent "$MONITORING_SAMPLE_LABEL" tuidev-sample "the sampler" \
        "launchctl bootstrap gui/$(id -u) $HOME/Library/LaunchAgents/$MONITORING_SAMPLE_LABEL.plist"
    print_info "sampler: agents sample once a minute, with or without the menu; AGENTS_SAMPLER=0 in $MONITORING_CONF turns it off."
}

# --- Linux: systemd user units ------------------------------------------------
# The sampler's timer and service, and the memory guard's service, beside
# herdr-core's (scripts/install/packs/herdr-core.sh), all in
# configs/agents/ and written as shipped into ~/.config/systemd/user.
MONITORING_SAMPLE_UNIT="tuidev-sample"
MONITORING_MEMGUARD_UNIT="tuidev-memguard"

# _monitoring_systemd_ready — a systemd user manager runs here (not in a
# container, not as root without a user bus).
_monitoring_systemd_ready() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

# _monitoring_systemd_units WHAT UNIT... — write each UNIT
# (configs/agents/UNIT) into the user unit directory, recorded, then reload
# systemd's view of them. False when no systemd user manager runs here: the
# files are in place for one, and the caller says what to run instead.
_monitoring_systemd_units() {
    local what="$1" dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" u
    shift
    for u in "$@"; do
        print_step "installing $what (systemd user unit) -> $dir/$u"
        install_config "$dir/$u" "$MONITORING_REPO/configs/agents/$u" --overwrite
    done
    _monitoring_systemd_ready || return 1
    run_cmd systemctl --user daemon-reload || print_warning "systemctl --user daemon-reload failed (continuing)"
    return 0
}

# _monitoring_linger_hint WHAT — without lingering, a user manager (and WHAT)
# runs only while you are logged in: the one root command that changes that.
_monitoring_linger_hint() {
    local user linger
    user="${USER:-$(id -un)}"
    linger="$(loginctl show-user "$user" -p Linger 2>/dev/null)" || linger=""
    [[ "$linger" != "Linger=yes" ]] || return 0
    print_warning "lingering is off: your user manager, and $1, run only while you are logged in."
    print_info "  So it runs from boot, with no login (needs root, once): sudo loginctl enable-linger $user"
    print_todo "Keep your user services running without a login: sudo loginctl enable-linger $user"
}

# _monitoring_linux_units — the sampler (enabled timer) and the memory guard
# (enabled service, restarted so a new agents takes over, as launchd's
# bootstrap does on macOS).
_monitoring_linux_units() {
    local s="$MONITORING_SAMPLE_UNIT" m="$MONITORING_MEMGUARD_UNIT.service"
    if ! _monitoring_systemd_units "the sampler and the memory guard" "$s.service" "$s.timer" "$m"; then
        print_warning "no systemd user manager here (a container?): nothing samples or guards memory on its own (continuing)."
        print_info "  Where systemd runs: systemctl --user enable --now $s.timer $m"
        print_info "  Else, in a tmux pane: agents watch (it samples while it runs) and agents mem guard"
        print_todo "Start the sampler and memory guard where systemd runs: systemctl --user enable --now $s.timer $m (else, in a tmux pane: agents watch and agents mem guard)"
        return 0
    fi
    { run_cmd systemctl --user enable --now "$s.timer"; } \
        || { print_warning "$s.timer did not start: systemctl --user enable --now $s.timer (continuing)"
             print_todo "Start the sampler: systemctl --user enable --now $s.timer"; }
    { run_cmd systemctl --user enable "$m" && run_cmd systemctl --user restart "$m"; } \
        || { print_warning "the memory guard did not start: systemctl --user enable --now $m (continuing)"
             print_todo "Start the memory guard: systemctl --user enable --now $m"; }
    print_info "sampler: agents sample once a minute ($s.timer); AGENTS_SAMPLER=0 in $MONITORING_CONF turns it off."
    print_info "memory guard: warns past 8 GB, stops a runaway in an agent tree past half the RAM ($m); 'agents mem' shows it, AGENTS_MEM_* in $MONITORING_CONF tune it."
    _monitoring_linger_hint "the sampler and the memory guard"
}

# The link watcher: one ssh to each of your other machines, so a click in one
# of their Herdr panes opens here (lib/agents/link.sh).
MONITORING_LINK_LABEL="dev.tuidev.link"
_monitoring_link() {
    _monitoring_launchagent "$MONITORING_LINK_LABEL" tuidev-link "the link watcher" "agents link restart"
    print_info "link watcher: a Ctrl-click on a localhost link in a Herdr pane of another machine opens here ('agents link' shows it; AGENTS_LINK=0 in $MONITORING_CONF turns it off)."
}

monitoring_install() {
    print_header "Pack: monitoring"

    pkg_install "${MONITORING_FORMULAE[@]}" || print_warning "monitoring: not everything installed (continuing)"
    _monitoring_agents
    if is_macos; then
        _monitoring_swiftbar
        _monitoring_sampler
        _monitoring_memguard
        _monitoring_link
    else
        _monitoring_linux_units
        print_info "link watcher: on the machine you sit at, run 'agents link watch' in a tmux pane (or a systemd user service)."
    fi

    print_info "bottom installs as 'btm' on your PATH."
    print_info "agents: run 'agents' (or 'agents watch'); 'agents --help' lists kill, reap and awake."
    print_info "agents ports lists what listens here and on your other machines; 'agents forward open MACHINE PORT' brings one here."
    print_info "agents mcp lists your MCP servers; 'agents mcp lazy NAME' starts one on its first tool call instead of with every session."

    print_success "monitoring pack complete"
}

# The health check's probe (pack_check): agents, a process monitor, and the
# sampler's job (the LaunchAgent, or the systemd timer's unit file). File
# tests only: nothing asks launchd or systemd. terminal-notifier and the
# SwiftBar plugin have checks of their own there.
monitoring_check() {
    command -v agents >/dev/null 2>&1 || return 1
    command -v btm >/dev/null 2>&1 || command -v htop >/dev/null 2>&1 || return 1
    if is_macos; then
        [[ -f "$HOME/Library/LaunchAgents/$MONITORING_SAMPLE_LABEL.plist" ]]
    else
        [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$MONITORING_SAMPLE_UNIT.timer" ]]
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitoring_install "$@"
fi
