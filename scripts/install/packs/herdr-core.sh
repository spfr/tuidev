#!/bin/bash
#
# Optional pack: herdr-core
#
# Your agents on your phone. Herdr's phone app (iPhone, iPad, Android) lists
# the agents that run in herdr-core (`hc`), the runtime under Herdr's desktop
# app, and talks to it over SSH: no account, no server in between. It does not
# see a program a Herdr TUI pane owns. `agents hc run claude` (lib/agents/hc.sh,
# the monitoring pack) starts the agent in herdr-core and puts the pane on it,
# so the same agent is in the pane, in the Herdr sidebar and in the phone's
# inbox.
#
# What this pack adds to that command: a job that runs `agents hc up -q` at
# login and every 5 minutes, so a core that stopped is started again (`up`
# never stops one).
#   - macOS: a LaunchAgent (dev.tuidev.hc). A core the phone starts over SSH
#     runs outside the desktop login, where its agents cannot reach the
#     Keychain (Claude Code says "Not logged in"); one that is already up in
#     the desktop login is the one the phone finds.
#   - Linux: a systemd user timer and service (tuidev-hc.timer/.service), for
#     an always-on box (a Raspberry Pi, a VM) the phone reaches with the
#     laptop shut. Without lingering they run only while you are logged in:
#     the pack checks and prints the one sudo command. No systemd (a
#     container): a warning, and what to run by hand.
#
# On every platform, a shell fragment (shell.d/hc-auto.zsh) for the opt-in
# AGENTS_HC_AUTO=1: a `claude` or `codex` typed in a Herdr pane is then
# hosted in herdr-core by itself (`agents hc auto`), and starts the plain way
# whenever that cannot work. With the setting off it defines nothing.
#
# Install policy: herdr-core itself is not installed here. Its releases are
# checked against a sha256 from the same server and, on macOS, installed as a
# signed app bundle by its own installer; the pack prints where that is.
#
# Entrypoint: herdr_core_install
# Invoked via: tuidev install --pack monitoring --pack herdr-core   (monitoring first:
#   it brings the `agents` the LaunchAgent runs)
#
# Upstream: https://herdr.dev/core/  (Apache-2.0)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"
# _monitoring_launchagent: agents' LaunchAgents are installed one way;
# MONITORING_REPO: where configs/agents/ is.
# shellcheck source=./monitoring.sh disable=SC1091
. "$SCRIPT_DIR/monitoring.sh"

HERDR_CORE_LABEL="dev.tuidev.hc"
HERDR_CORE_UNIT="tuidev-hc"
HERDR_CORE_URL="https://herdr.dev/core/"
HERDR_CORE_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"

_herdr_core_bin() {
    command -v herdr-core 2>/dev/null || { [[ -x "$HOME/.local/bin/herdr-core" ]] && echo "$HOME/.local/bin/herdr-core"; }
}

# _herdr_core_systemd — Linux: the user timer and service that keep the core
# running, enabled, and whether they run without a login (lingering).
_herdr_core_systemd() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" u user linger
    for u in "$HERDR_CORE_UNIT.service" "$HERDR_CORE_UNIT.timer"; do
        print_step "installing herdr-core kept running (systemd user unit) -> $dir/$u"
        install_config "$dir/$u" "$MONITORING_REPO/configs/agents/$u" --overwrite
    done
    if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
        print_warning "no systemd user manager here (a container?): nothing starts herdr-core (continuing)."
        print_info "  Where systemd runs: systemctl --user enable --now $HERDR_CORE_UNIT.timer. Else run agents hc up after each boot."
        return 0
    fi
    { run_cmd systemctl --user daemon-reload && run_cmd systemctl --user enable --now "$HERDR_CORE_UNIT.timer"; } \
        || { print_warning "$HERDR_CORE_UNIT.timer did not start: systemctl --user enable --now $HERDR_CORE_UNIT.timer (continuing)"; return 0; }
    print_info "herdr-core starts with your user manager from now on, and again within 5 minutes if it stops."
    print_info "  Off: AGENTS_HC_UP=0 in $MONITORING_CONF (a core you stop stays down), or systemctl --user disable --now $HERDR_CORE_UNIT.timer until the next tuidev update"
    user="${USER:-$(id -un)}"
    linger="$(loginctl show-user "$user" -p Linger 2>/dev/null)" || linger=""
    if [[ "$linger" != "Linger=yes" ]]; then
        print_warning "lingering is off: your user manager, and this timer, run only while you are logged in."
        print_info "  So it runs from boot, with no login (needs root, once): sudo loginctl enable-linger $user"
    fi
}

# The claude and codex functions for AGENTS_HC_AUTO, in our own shell.d dir.
_herdr_core_fragment() {
    local src="$HERDR_CORE_REPO/configs/zsh/hc-auto.zsh"
    [[ -f "$src" ]] || { print_warning "hc-auto fragment missing: $src"; return 0; }
    install_config "$TUIDEV_STATE_DIR/shell.d/hc-auto.zsh" "$src" --overwrite
}

herdr_core_install() {
    print_header "Pack: herdr-core"

    if [[ -z "$(_herdr_core_bin)" ]]; then
        print_warning "herdr-core is not installed (continuing)."
        print_info "Its installer, and what it does, are at $HERDR_CORE_URL; Herdr's desktop app brings it too."
        print_info "  Then: agents hc   (is it running, and in your desktop login?)"
    else
        print_success "herdr-core: $("$(_herdr_core_bin)" --version 2>/dev/null || echo present)"
    fi
    if [[ ! -x "$HOME/.local/bin/agents" && "$DRY_RUN" != true ]]; then
        print_warning "agents is not installed: tuidev install --pack monitoring brings it. Until then the job fails, at login and every 5 minutes (continuing)."
    fi

    if is_macos; then
        _monitoring_launchagent "$HERDR_CORE_LABEL" tuidev-hc "herdr-core at login" "agents hc up"
        print_info "herdr-core starts in your desktop login from now on, so the phone finds one whose agents can use the Keychain, and again within 5 minutes if it stops."
        print_info "  Off: AGENTS_HC_UP=0 in $MONITORING_CONF (a core you stop stays down)"
    else
        _herdr_core_systemd
        print_info "No Keychain here: log Claude Code in once with claude and /login (kept in ~/.claude); a token exported in your shell does not reach a hosted agent."
    fi
    _herdr_core_fragment
    print_info "Start an agent the phone can see: agents hc run claude   (ctrl+\\ detaches; it keeps running)"
    print_info "Or have each claude and codex typed in a Herdr pane hosted there: AGENTS_HC_AUTO=1 in agents.conf (opt-in; a new shell picks it up)."
    print_info "Phone: Herdr's app, add this machine over SSH (Tailscale SSH needs no key). See docs/remote.md."
    print_success "herdr-core pack complete"
}

# The health check's probe (pack_check): herdr-core is here, and so is the
# job that keeps it up (the LaunchAgent, or the systemd timer's unit file).
# File tests only: no core is asked anything (a client command starts one).
herdr_core_check() {
    [[ -n "$(_herdr_core_bin)" ]] || return 1
    if is_macos; then
        [[ -f "$HOME/Library/LaunchAgents/$HERDR_CORE_LABEL.plist" ]]
    else
        [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$HERDR_CORE_UNIT.timer" ]]
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    herdr_core_install "$@"
fi
