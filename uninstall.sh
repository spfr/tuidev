#!/bin/bash
# ============================================================================
# tuidev uninstaller
# ============================================================================
#
# Cleanly removes tuidev from the host:
#   - Strips tuidev managed blocks from shell/prompt/tmux configs
#     (user content outside the blocks is preserved).
#   - Removes tuidev-installed helpers under ~/.local/bin.
#   - Removes ~/.config/tuidev/ manifest + env.
#   - Optionally removes tuidev-owned configs (Ghostty, nvim, starship,
#     tmux, hammerspoon, opencode, codex) with a backup first.
#   - Optionally uninstalls the Homebrew formulae and casks installed
#     by the packs the user had enabled.
#
# Usage:
#   ./uninstall.sh              # interactive
#   ./uninstall.sh --all        # non-interactive: strip managed blocks,
#                                 remove configs, purge brew packages.
#   ./uninstall.sh --dry-run    # preview mutations

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/ui.sh"
# shellcheck source=scripts/lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/config_write.sh"

ALL=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)     ALL=true; shift ;;
        --dry-run) export DRY_RUN=true; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *)         die "unknown flag: $1" ;;
    esac
done

ask() {
    # Usage: ask "question text" -> exports ANSWER=y|n. Respects --all.
    if $ALL; then ANSWER=y; return; fi
    local prompt="$1"
    read -r -p "$prompt (y/N) " -n 1 reply
    echo ""
    [[ $reply =~ ^[Yy]$ ]] && ANSWER=y || ANSWER=n
}

print_header "tuidev uninstaller"

print_info "this will reverse a tuidev install:"
print_info "  - strip managed blocks from shell configs (user edits preserved)"
print_info "  - remove tuidev helpers under \$HOME/.local/bin"
print_info "  - optionally remove tuidev-owned config files (with backup)"
print_info "  - optionally purge brew formulae and casks"
echo ""

ask "continue?"
[[ "$ANSWER" == "y" ]] || { echo "cancelled."; exit 0; }

# ---------------------------------------------------------------------------
# 1. Strip managed blocks. User content outside each block is preserved.
# ---------------------------------------------------------------------------

print_header "removing tuidev managed blocks"

remove_managed_block "$HOME/.zshrc"                 tuidev-zshrc
remove_managed_block "$HOME/.zshrc"                 tuidev-sandbox-path
remove_managed_block "$HOME/.config/starship.toml"  tuidev-starship
remove_managed_block "$HOME/.config/tmux/tmux.conf" tuidev-tmux

# ---------------------------------------------------------------------------
# 2. Remove tuidev-placed scripts in ~/.local/bin.
# ---------------------------------------------------------------------------

print_header "removing tuidev helpers"

for f in "$HOME/.local/bin/sbx" \
         "$HOME/.local/bin/sbx-container" \
         "$HOME/.local/bin/notify.sh"; do
    if [[ -e "$f" ]]; then
        run_cmd rm -f "$f"
        print_success "removed $f"
    fi
done

# ---------------------------------------------------------------------------
# 3. Remove the tuidev manifest + env file.
# ---------------------------------------------------------------------------

if [[ -d "$HOME/.config/tuidev" ]]; then
    print_info "removing ~/.config/tuidev (manifest + env + deprecations)"
    run_cmd rm -rf "$HOME/.config/tuidev"
fi

# ---------------------------------------------------------------------------
# 4. Optional: remove tuidev-owned configs (with a timestamped backup first).
# ---------------------------------------------------------------------------

ask "also remove tuidev-owned configs (nvim, ghostty, tmux, hammerspoon, sandbox profiles, AI CLI settings)?"
if [[ "$ANSWER" == "y" ]]; then
    BACKUP="$HOME/.config-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
    run_cmd mkdir -p "$BACKUP"

    for path in \
        "$HOME/.config/nvim" \
        "$HOME/.config/ghostty" \
        "$HOME/.config/tmux" \
        "$HOME/.config/zellij" \
        "$HOME/.config/opencode" \
        "$HOME/.config/starship.toml" \
        "$HOME/.codex" \
        "$HOME/.claude.json" \
        "$HOME/.hammerspoon"; do
        if [[ -e "$path" ]]; then
            run_cmd cp -R "$path" "$BACKUP/" 2>/dev/null || true
            run_cmd rm -rf "$path"
            print_success "removed $path (backup in $BACKUP)"
        fi
    done

    # Neovim state/cache — nvim reinstalls these cleanly on next launch.
    run_cmd rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
    print_success "cleared nvim state/cache"
fi

# ---------------------------------------------------------------------------
# 5. Optional: purge Homebrew formulae and casks installed by the packs.
# ---------------------------------------------------------------------------

ask "also uninstall Homebrew formulae and casks that tuidev packs installed?"
if [[ "$ANSWER" == "y" ]] && command_exists brew; then

    # Aligned with scripts/install/*.sh. Not every user has every pack; we
    # `brew list` first so missing packages are silently skipped.
    FORMULAE=(
        # core
        bat eza fd fzf gh git git-delta jq lazygit neovim ripgrep
        shellcheck starship tmux yq zoxide
        zsh-autosuggestions zsh-completions zsh-syntax-highlighting
        # remote
        mosh
        # extras
        atuin bandwhich bottom broot dust duf fastfetch glow hyperfine
        ncdu procs sd tealdeer tokei
        # packs
        zellij yazi nnn lazydocker k9s podman
    )

    CASKS=(
        ghostty tailscale rectangle stats maccy hiddenbar hammerspoon
    )

    for f in "${FORMULAE[@]}"; do
        if brew list --formula "$f" &>/dev/null; then
            run_cmd brew uninstall "$f" 2>/dev/null || print_warning "failed: $f"
        fi
    done

    for c in "${CASKS[@]}"; do
        if brew list --cask "$c" &>/dev/null; then
            run_cmd brew uninstall --cask "$c" 2>/dev/null || print_warning "failed: $c"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

print_header "Uninstall complete"
cat <<EOF
${GREEN}What was removed:${NC}
  - tuidev managed blocks in ~/.zshrc, starship.toml, tmux.conf
  - tuidev helpers under ~/.local/bin (sbx, notify.sh, sbx-container)
  - ~/.config/tuidev/ (manifest, env, deprecations)
  - (optional) tuidev-owned config files, backed up to
    ~/.config-uninstall-backup-YYYYMMDD-HHMMSS/
  - (optional) brew formulae and casks

${CYAN}What was preserved:${NC}
  - Your own edits to ~/.zshrc outside the managed blocks
  - Any config file outside the paths tuidev writes to
  - Your git config, ssh keys, shell history
EOF
