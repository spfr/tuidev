#!/bin/bash
# scripts/install/core.sh - install pack: essential CLI tools.
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: core_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'core':
#   the shell an agent CLI runs in: search, nav, git UX, shell prompt,
#   JSON/YAML, shell plugins, shellcheck. No editor and no multiplexer (those
#   are --pack nvim and --pack tmux), no GUI apps, no remote stack, no sandbox
#   tooling. Ghostty is added on macOS only. Also `secret` (bin/secret) in
#   ~/.local/bin: tokens in the OS secret store, not in dotfiles. It lives
#   here, not in the macOS-only sandbox pack, because every profile and
#   platform should have it (docs/secrets.md).
#
# Package managers: scripts/lib/pkg.sh — Homebrew on macOS (and on Linux when
#   present), else apt-get / dnf / pacman. Homebrew has no aarch64 Linux build,
#   so the native fallback is what makes --profile minimal/remote work on a
#   Raspberry Pi. Tools a distribution lacks are skipped with a pointer to
#   their official install page — we never pipe a remote installer into a shell.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../lib/pkg.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../lib/config_write.sh"

# Formula list (Homebrew). Kept alphabetized for drift-diff friendliness.
CORE_FORMULAE=(
    bat
    eza
    fd
    fzf
    gh
    git
    git-delta
    jq
    ripgrep
    shellcheck
    starship
    yq
    zoxide
    zsh-autosuggestions
    zsh-completions
    zsh-syntax-highlighting
)

# Casks (macOS only).
CORE_CASKS=(
    ghostty
)

# Debian renames some binaries to avoid collisions (fd-find → fdfind,
# bat → batcat). Put a correctly-named symlink on PATH so the shell config,
# aliases, and docs work unchanged.
_core_link_debian_binary() {
    local want="$1" have="$2" src bindir
    command_exists "$want" && return 0
    src="$(command -v "$have" 2>/dev/null || true)"
    [[ -n "$src" ]] || return 0
    bindir="$HOME/.local/bin"
    run_cmd mkdir -p "$bindir"
    run_cmd ln -sf "$src" "$bindir/$want"
    tuidev_manifest_record file "$bindir/$want"
    print_info "linked $want -> $have in $bindir (Debian renames this binary)"
}

# ~/.local/bin/secret from the repo's bin/secret. tuidev owns the file; it runs
# alone, without the repo or the libs.
_core_install_secret() {
    local src dest="$HOME/.local/bin/secret"
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/secret"
    [[ -f "$src" ]] || { print_warning "bin/secret is missing from the repo; secret not installed"; return 0; }
    install_config "$dest" "$src" --overwrite
    [[ "${DRY_RUN:-false}" == true ]] || chmod 0755 "$dest"
}

core_install() {
    print_header "Pack: core"

    pkg_install "${CORE_FORMULAE[@]}" \
        || print_info "The setup works without the tools listed above; nothing else depends on them."
    if is_macos && command_exists brew; then
        brew_install_casks "${CORE_CASKS[@]}"
    fi
    if [[ "$(pkg_manager 2>/dev/null)" == apt ]]; then
        _core_link_debian_binary fd  fdfind
        _core_link_debian_binary bat batcat
    fi
    _core_install_secret

    print_success "core pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    core_install "$@"
fi
