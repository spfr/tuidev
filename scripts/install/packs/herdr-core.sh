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
# What this pack adds to that command: on macOS, a LaunchAgent that runs
# `agents hc up` at login. A core the phone starts over SSH runs outside the
# desktop login, where its agents cannot reach the Keychain (Claude Code says
# "Not logged in"); one that is already up in the desktop login is the one the
# phone finds. On Linux there is nothing to add: the pack only checks.
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
# _monitoring_launchagent: agents' LaunchAgents are installed one way.
# shellcheck source=./monitoring.sh disable=SC1091
. "$SCRIPT_DIR/monitoring.sh"

HERDR_CORE_LABEL="dev.tuidev.hc"
HERDR_CORE_URL="https://herdr.dev/core/"

_herdr_core_bin() {
    command -v herdr-core 2>/dev/null || { [[ -x "$HOME/.local/bin/herdr-core" ]] && echo "$HOME/.local/bin/herdr-core"; }
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
        print_warning "agents is not installed: tuidev install --pack monitoring brings it. Until then the login job fails once (no retry); it works from the next login after (continuing)."
    fi

    if is_macos; then
        _monitoring_launchagent "$HERDR_CORE_LABEL" tuidev-hc "herdr-core at login" "agents hc up"
        print_info "herdr-core starts in your desktop login from now on, so the phone finds one whose agents can use the Keychain."
    else
        print_info "Linux: nothing to start at login. On a machine with no desktop, log Claude Code in with a token (claude setup-token)."
    fi
    print_info "Start an agent the phone can see: agents hc run claude   (ctrl+\\ detaches; it keeps running)"
    print_info "Phone: Herdr's app, add this machine over SSH (Tailscale SSH needs no key). See docs/remote.md."
    print_success "herdr-core pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    herdr_core_install "$@"
fi
