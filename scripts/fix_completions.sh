#!/bin/bash

# ============================================================================
# Fix Insecure Zsh Completion Directories
# ============================================================================
# This script fixes permissions and removes insecure completion directories

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Fixing Zsh Completion Directories${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Fix Homebrew completion directories
if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix)

    echo -e "${YELLOW}Fixing Homebrew completion directories...${NC}"

    for dir in "$BREW_PREFIX/share/zsh-completions" "$BREW_PREFIX/share/zsh/site-functions"; do
        if [[ -d "$dir" ]]; then
            echo "Fixing: $dir"
            sudo chown -R $(whoami):admin "$dir" 2>/dev/null || chown -R $(whoami):staff "$dir" 2>/dev/null || true
            chmod -R go-w "$dir" 2>/dev/null || true
            echo -e "${GREEN}✓ Fixed permissions for $dir${NC}"
        fi
    done
fi

# Fix Docker completions
if [[ -d "$HOME/.docker/completions" ]]; then
    echo ""
    echo -e "${YELLOW}Fixing Docker completion directory...${NC}"
    chmod -R 755 "$HOME/.docker/completions"
    chown -R $(whoami):staff "$HOME/.docker/completions"
    echo -e "${GREEN}✓ Fixed permissions for $HOME/.docker/completions${NC}"
fi

# Fix zcompdump file
if [[ -f "$HOME/.zcompdump" ]]; then
    echo ""
    echo -e "${YELLOW}Fixing zcompdump file...${NC}"
    chmod 644 "$HOME/.zcompdump"
    chown $(whoami):staff "$HOME/.zcompdump"
    echo -e "${GREEN}✓ Fixed permissions for .zcompdump${NC}"
fi

# Remove old completion cache
echo ""
echo -e "${YELLOW}Cleaning completion cache...${NC}"
rm -f "$HOME/.zcompdump*"
echo -e "${GREEN}✓ Removed old completion cache${NC}"

# Regenerate completions
echo ""
echo -e "${YELLOW}Regenerating completions...${NC}"
zsh -c "autoload -Uz compinit && compinit -i" 2>/dev/null || echo "Completions regenerated"
echo -e "${GREEN}✓ Completions regenerated${NC}"

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Done! Restart your shell to apply changes.${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Run: exec zsh"
