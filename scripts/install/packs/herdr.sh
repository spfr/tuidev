#!/bin/bash
#
# Optional pack: herdr
#
# Installs herdr — an agent-aware terminal runtime (Rust). A background
# server owns panes so agents keep running after detach; a sidebar marks
# each detected agent working / blocked / done. The CLI and socket API are
# the same surface agents drive. Unlike cmux (a GUI app) and bosun (a tmux
# session picker), herdr is its own multiplexer. tmux stays the default for
# `work` / `dev` / `ai`; this pack does not change those wrappers.
#
# Prefix is ctrl+b (tmux in this setup is ctrl+a). See docs/agent-workflows.md.
#
# Install policy: Homebrew only. If there is no formula the pack prints the
# official installer command for the user to run themselves — it never pipes a
# remote script into a shell on their behalf.
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
# shellcheck source=../../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/brew.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

HERDR_INSTALL_URL="https://herdr.dev/install.sh"

# Declared so `update.sh --packages` can discover a Homebrew install.
HERDR_FORMULAE=(herdr)

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

herdr_install() {
    print_header "Pack: herdr"

    if command_exists herdr; then
        _herdr_install_config
        print_info "Run 'herdr' to attach. tmux wrappers (work/dev/ai) are unchanged."
        print_success "herdr (already present)"
        return 0
    fi

    # Homebrew when it actually has the formula (`--formula` so a same-named
    # cask can't produce a false positive). We deliberately do NOT pipe a
    # remote script into a shell on the user's behalf; if brew can't do it we
    # print the official command and let the user run it. Mirrors the
    # graceful-degradation pattern in packs/bosun.sh.
    if command_exists brew && brew info --formula herdr >/dev/null 2>&1; then
        brew_update_once
        brew_install_formulae "${HERDR_FORMULAE[@]}"
    fi

    # brew_install_formula warns rather than returning non-zero, so judge the
    # install by its outcome, not its exit status.
    if command_exists herdr || [[ "$DRY_RUN" == true ]]; then
        _herdr_install_config
        print_info "tmux stays the default for work/dev/ai. Herdr is opt-in: run 'herdr'."
        print_info "Prefix is ctrl+b (tmux is ctrl+a). See docs/agent-workflows.md."
        print_success "herdr pack complete"
        return 0
    fi

    print_warning "herdr was not installed via Homebrew on this machine."
    print_info "Install it yourself with the official installer:"
    print_info "    curl -fsSL $HERDR_INSTALL_URL | sh"
    print_info "It places the binary in \$HOME/.local/bin (override: HERDR_INSTALL_DIR)."
    print_info "Docs: https://herdr.dev/docs/install/ — then re-run this pack for the config."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    herdr_install "$@"
fi
