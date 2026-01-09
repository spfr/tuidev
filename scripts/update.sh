#!/usr/bin/env bash
# ============================================================================
# macOS TUI Development Environment - Update Script
# ============================================================================
# Provides a seamless update experience for keeping the environment current.
#
# Usage:
#   ./scripts/update.sh              # Interactive update
#   ./scripts/update.sh --check      # Check for updates only (no changes)
#   ./scripts/update.sh --packages   # Update packages only
#   ./scripts/update.sh --configs    # Update configs only
#   ./scripts/update.sh --all        # Update everything (non-interactive)
#
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Global arrays for update tracking
OUTDATED=()
OUTDATED_INFO=()
CONFIG_CHANGES=()

# Parse arguments
CHECK_ONLY=false
PACKAGES_ONLY=false
CONFIGS_ONLY=false
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --check|-c)
            CHECK_ONLY=true
            shift
            ;;
        --packages|-p)
            PACKAGES_ONLY=true
            shift
            ;;
        --configs|-C)
            CONFIGS_ONLY=true
            shift
            ;;
        --all|-a)
            NON_INTERACTIVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --check, -c      Check for updates only (no changes)"
            echo "  --packages, -p   Update packages only"
            echo "  --configs, -C    Update configs only"
            echo "  --all, -a        Update everything non-interactively"
            echo "  --help, -h       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}${BOLD}$1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

print_error() {
    echo -e "${RED}  ✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}  ℹ${NC} $1"
}

confirm() {
    if [[ "$NON_INTERACTIVE" == true ]]; then
        return 0
    fi
    read -p "  $1 (y/N) " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]]
}

# ============================================================================
# Check for Package Updates
# ============================================================================

check_package_updates() {
    print_section "Checking for package updates..."

    # Update brew database
    brew update --quiet 2>/dev/null || true

    # Get outdated packages (only ones we care about)
    CORE_PACKAGES=(
        "zellij" "starship" "fzf" "ripgrep" "bat" "eza" "fd" "zoxide"
        "lazygit" "lazydocker" "git-delta" "atuin" "neovim" "gh"
        "bottom" "nnn" "glow" "ncdu" "fastfetch" "k9s" "jq" "yq"
        "httpie" "bandwhich" "procs" "dust" "duf" "tokei" "hyperfine"
        "cloudflared" "shellcheck" "tmux"
    )

    OUTDATED=()
    OUTDATED_INFO=()

    for pkg in "${CORE_PACKAGES[@]}"; do
        if brew list "$pkg" &>/dev/null; then
            info=$(brew outdated --verbose "$pkg" 2>/dev/null || true)
            if [[ -n "$info" ]]; then
                OUTDATED+=("$pkg")
                OUTDATED_INFO+=("$info")
            fi
        fi
    done

    if [[ ${#OUTDATED[@]} -eq 0 ]]; then
        print_success "All packages are up to date"
        return 1
    else
        echo ""
        echo -e "${YELLOW}  Updates available for ${#OUTDATED[@]} packages:${NC}"
        echo ""
        for info in "${OUTDATED_INFO[@]}"; do
            # Format: package (current) < new
            pkg=$(echo "$info" | cut -d' ' -f1)
            current=$(echo "$info" | grep -oE '\([^)]+\)' | tr -d '()')
            new=$(echo "$info" | grep -oE '< [0-9.]+' | cut -d' ' -f2)
            printf "    ${CYAN}%-15s${NC} %s → ${GREEN}%s${NC}\n" "$pkg" "$current" "$new"
        done
        echo ""
        return 0
    fi
}

# ============================================================================
# Check for Config Updates
# ============================================================================

check_config_updates() {
    print_section "Checking for configuration updates..."

    CONFIG_CHANGES=()

    # Check each config file using simple arrays
    local config_sources=(
        "configs/ghostty/config"
        "configs/zellij/config.kdl"
        "configs/starship/starship.toml"
        "configs/zsh/.zshrc"
        "configs/hammerspoon/init.lua"
    )
    local config_dests=(
        "$HOME/.config/ghostty/config"
        "$HOME/.config/zellij/config.kdl"
        "$HOME/.config/starship.toml"
        "$HOME/.zshrc"
        "$HOME/.hammerspoon/init.lua"
    )

    for i in "${!config_sources[@]}"; do
        local src="${config_sources[$i]}"
        local dest="${config_dests[$i]}"
        local src_path="$REPO_DIR/$src"

        if [[ -f "$src_path" ]] && [[ -f "$dest" ]]; then
            if ! diff -q "$src_path" "$dest" &>/dev/null; then
                CONFIG_CHANGES+=("$src")
            fi
        elif [[ -f "$src_path" ]] && [[ ! -f "$dest" ]]; then
            CONFIG_CHANGES+=("$src (new)")
        fi
    done

    # Check layouts
    if [[ -d "$REPO_DIR/configs/zellij/layouts" ]]; then
        for layout in "$REPO_DIR"/configs/zellij/layouts/*.kdl; do
            if [[ -f "$layout" ]]; then
                local name
                name=$(basename "$layout")
                local dest="$HOME/.config/zellij/layouts/$name"
                if [[ ! -f "$dest" ]] || ! diff -q "$layout" "$dest" &>/dev/null; then
                    CONFIG_CHANGES+=("configs/zellij/layouts/$name")
                fi
            fi
        done
    fi

    if [[ ${#CONFIG_CHANGES[@]} -eq 0 ]]; then
        print_success "All configurations are in sync"
        return 1
    else
        echo ""
        echo -e "${YELLOW}  Configuration changes detected:${NC}"
        echo ""
        for cfg in "${CONFIG_CHANGES[@]}"; do
            echo -e "    ${CYAN}•${NC} $cfg"
        done
        echo ""
        return 0
    fi
}

# ============================================================================
# Check for Repo Updates
# ============================================================================

check_repo_updates() {
    print_section "Checking for repository updates..."

    cd "$REPO_DIR"

    # Fetch latest
    git fetch origin --quiet 2>/dev/null || {
        print_warning "Could not fetch from remote"
        return 1
    }

    # Check if behind
    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)

    if [[ "$LOCAL" == "$REMOTE" ]]; then
        print_success "Repository is up to date"
        return 1
    else
        BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || git rev-list --count HEAD..origin/master 2>/dev/null || echo "?")
        echo ""
        echo -e "${YELLOW}  Repository is ${BEHIND} commit(s) behind${NC}"
        echo ""

        # Show recent commits
        echo -e "  ${CYAN}Recent changes:${NC}"
        git log --oneline HEAD..origin/main 2>/dev/null | head -5 | while read -r line; do
            echo "    • $line"
        done
        echo ""
        return 0
    fi
}

# ============================================================================
# Update Packages
# ============================================================================

update_packages() {
    print_section "Updating packages..."

    if ! check_package_updates; then
        return 0
    fi

    if [[ "$CHECK_ONLY" == true ]]; then
        return 0
    fi

    if confirm "Update ${#OUTDATED[@]} packages?"; then
        echo ""
        for pkg in "${OUTDATED[@]}"; do
            print_info "Upgrading $pkg..."
            if brew upgrade "$pkg" 2>/dev/null; then
                print_success "$pkg updated"
            else
                print_warning "Failed to update $pkg"
            fi
        done
    fi
}

# ============================================================================
# Update Configs
# ============================================================================

update_configs() {
    print_section "Updating configurations..."

    if ! check_config_updates; then
        return 0
    fi

    if [[ "$CHECK_ONLY" == true ]]; then
        return 0
    fi

    if confirm "Update configurations? (backups will be created)"; then
        # Create backup
        BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"

        # Backup existing configs
        cp -r "$HOME/.config/ghostty" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "$HOME/.config/zellij" "$BACKUP_DIR/" 2>/dev/null || true
        cp "$HOME/.config/starship.toml" "$BACKUP_DIR/" 2>/dev/null || true
        cp "$HOME/.zshrc" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "$HOME/.hammerspoon" "$BACKUP_DIR/" 2>/dev/null || true

        print_info "Backup created at $BACKUP_DIR"

        # Copy updated configs
        echo ""
        for cfg in "${CONFIG_CHANGES[@]}"; do
            cfg_clean="${cfg% (new)}"  # Remove " (new)" suffix if present
            src="$REPO_DIR/$cfg_clean"

            case "$cfg_clean" in
                configs/ghostty/config)
                    mkdir -p "$HOME/.config/ghostty"
                    cp "$src" "$HOME/.config/ghostty/config"
                    ;;
                configs/zellij/config.kdl)
                    mkdir -p "$HOME/.config/zellij"
                    cp "$src" "$HOME/.config/zellij/config.kdl"
                    ;;
                configs/starship/starship.toml)
                    cp "$src" "$HOME/.config/starship.toml"
                    ;;
                configs/zsh/.zshrc)
                    cp "$src" "$HOME/.zshrc"
                    ;;
                configs/hammerspoon/init.lua)
                    mkdir -p "$HOME/.hammerspoon"
                    cp "$src" "$HOME/.hammerspoon/init.lua"
                    ;;
                configs/zellij/layouts/*)
                    mkdir -p "$HOME/.config/zellij/layouts"
                    cp "$src" "$HOME/.config/zellij/layouts/"
                    ;;
            esac
            print_success "Updated $cfg_clean"
        done
    fi
}

# ============================================================================
# Update Repository
# ============================================================================

update_repo() {
    print_section "Updating repository..."

    if ! check_repo_updates; then
        return 0
    fi

    if [[ "$CHECK_ONLY" == true ]]; then
        return 0
    fi

    if confirm "Pull latest changes?"; then
        cd "$REPO_DIR"
        if git pull --ff-only origin main 2>/dev/null || git pull --ff-only origin master 2>/dev/null; then
            print_success "Repository updated"
        else
            print_warning "Could not fast-forward. Manual intervention may be needed."
        fi
    fi
}

# ============================================================================
# Validate After Update
# ============================================================================

validate_update() {
    print_section "Validating configurations..."

    if [[ -x "$SCRIPT_DIR/validate_configs.sh" ]]; then
        if "$SCRIPT_DIR/validate_configs.sh" &>/dev/null; then
            print_success "All configurations valid"
        else
            print_warning "Some configuration issues detected. Run: make validate-configs"
        fi
    fi
}

# ============================================================================
# Main
# ============================================================================

print_header "macOS TUI Environment Update"

echo -e "  ${BLUE}Repo:${NC}    $REPO_DIR"
echo -e "  ${BLUE}Date:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"

if [[ "$CHECK_ONLY" == true ]]; then
    echo -e "  ${YELLOW}Mode:${NC}    Check only (no changes)"
fi

# Run updates based on flags
if [[ "$PACKAGES_ONLY" == true ]]; then
    update_packages
elif [[ "$CONFIGS_ONLY" == true ]]; then
    update_repo
    update_configs
    validate_update
else
    # Full update
    update_repo
    update_packages
    update_configs
    validate_update
fi

# Summary
print_header "Update Complete"

if [[ "$CHECK_ONLY" == true ]]; then
    echo -e "  Run ${CYAN}./scripts/update.sh${NC} to apply updates"
else
    echo -e "  ${GREEN}Your environment is up to date!${NC}"
    echo ""
    echo -e "  ${BLUE}Quick tips:${NC}"
    echo "    • Restart your terminal to apply shell changes"
    echo "    • Restart Ghostty to apply terminal changes"
    echo "    • Run 'source ~/.zshrc' to reload shell config now"
fi

echo ""
