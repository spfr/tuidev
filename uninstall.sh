#!/bin/bash

# ============================================================================
# macOS TUI Development Environment - Uninstaller
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}macOS TUI Development Environment - Uninstaller${NC}"
echo ""
echo "This will:"
echo "  1. Remove configuration files (with backup option)"
echo "  2. Optionally uninstall Homebrew packages"
echo ""

read -p "Do you want to continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Backup configs
BACKUP_DIR="$HOME/.config-uninstall-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo -e "${YELLOW}Backing up configurations to $BACKUP_DIR${NC}"

[[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$BACKUP_DIR/"
[[ -d "$HOME/.config/zellij" ]] && cp -r "$HOME/.config/zellij" "$BACKUP_DIR/"
[[ -d "$HOME/.config/nvim" ]] && cp -r "$HOME/.config/nvim" "$BACKUP_DIR/"
[[ -f "$HOME/.config/starship.toml" ]] && cp "$HOME/.config/starship.toml" "$BACKUP_DIR/"
[[ -f "$HOME/.config/ghostty/config" ]] && cp "$HOME/.config/ghostty/config" "$BACKUP_DIR/"
[[ -d "$HOME/.config/tmux" ]] && cp -r "$HOME/.config/tmux" "$BACKUP_DIR/"
[[ -d "$HOME/.hammerspoon" ]] && cp -r "$HOME/.hammerspoon" "$BACKUP_DIR/"
[[ -f "$HOME/.ssh/config" ]] && cp "$HOME/.ssh/config" "$BACKUP_DIR/ssh_config"
[[ -f "$HOME/.local/bin/notify.sh" ]] && cp "$HOME/.local/bin/notify.sh" "$BACKUP_DIR/"

# Remove configs
echo "Removing configuration files..."

rm -f "$HOME/.config/starship.toml"
rm -rf "$HOME/.config/zellij"
rm -rf "$HOME/.config/nvim"
rm -rf "$HOME/.config/tmux"
rm -rf "$HOME/.config/ghostty"
rm -rf "$HOME/.hammerspoon"
rm -f "$HOME/.local/bin/notify.sh"
rm -f "$HOME/.local/bin/ai-workflow.sh"
rm -rf "$HOME/.config/opencode"
# Neovim state/cache (reinstalls cleanly on next launch)
rm -rf "$HOME/.local/share/nvim"
rm -rf "$HOME/.local/state/nvim"
rm -rf "$HOME/.cache/nvim"
# Don't remove .zshrc, just offer to restore backup

echo ""
read -p "Do you want to uninstall the Homebrew packages as well? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    PACKAGES=(
        "zellij"
        "tmux"
        "starship"
        "fzf"
        "ripgrep"
        "bat"
        "eza"
        "fd"
        "lazygit"
        "lazydocker"
        "git-delta"
        "zoxide"
        "atuin"
        "gh"
        "bottom"
        "nnn"
        "yazi"
        "broot"
        "sd"
        "tealdeer"
        "glow"
        "ncdu"
        "fastfetch"
        "k9s"
        "httpie"
        "jq"
        "yq"
        "procs"
        "dust"
        "duf"
        "tokei"
        "hyperfine"
        "bandwhich"
        "cloudflared"
        "shellcheck"
        "mosh"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "zsh-completions"
    )

    for pkg in "${PACKAGES[@]}"; do
        if brew list "$pkg" &>/dev/null; then
            echo "Uninstalling $pkg..."
            brew uninstall "$pkg" || echo "Failed to uninstall $pkg"
        fi
    done

    # Uninstall cask applications
    CASK_PACKAGES=(
        "tailscale"
        "rectangle"
        "stats"
        "maccy"
        "hiddenbar"
        "hammerspoon"
    )

    for cask in "${CASK_PACKAGES[@]}"; do
        if brew list --cask "$cask" &>/dev/null; then
            echo "Uninstalling $cask..."
            brew uninstall --cask "$cask" || echo "Failed to uninstall $cask"
        fi
    done
fi

echo ""
echo -e "${GREEN}Uninstall complete!${NC}"
echo ""
echo "Your configurations have been backed up to: $BACKUP_DIR"
echo ""
echo "To restore your original .zshrc, check the backup directories:"
echo "  ls ~/.config-uninstall-backup-*"
echo ""
echo "Then copy your preferred backup:"
echo "  cp ~/.config-uninstall-backup-XXXXXX/.zshrc ~/.zshrc"
