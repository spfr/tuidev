#!/usr/bin/env bash
# ============================================================================
# Force Clean All Zellij Sessions
# Use this to completely reset zellij state
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Cleaning up all Zellij sessions...${NC}"

# 1. Kill any running zellij processes
echo "Killing zellij processes..."
pkill -f zellij 2>/dev/null || true
sleep 1

# 2. Remove session files
echo "Removing session files..."
find ~/.config/zellij -name "*session*" -delete 2>/dev/null || true
find ~/Library/Application\ Support -name "*session*" -delete 2>/dev/null || true

# 3. Remove Zellij data directory (this is where sessions are stored)
if [ -d ~/Library/Application\ Support/Zellij ]; then
    echo "Removing Zellij data directory..."
    rm -rf ~/Library/Application\ Support/Zellij
fi

# 4. Clear any defaults
echo "Clearing zellij defaults..."
defaults delete com.github.zellij-zellij 2>/dev/null || true

# 5. Verify
echo -e "${GREEN}✓ All Zellij sessions cleaned!${NC}"
echo ""
echo "You can now start fresh with:"
echo "  ai           # Start AI session"
echo "  remote       # Start remote session"
echo "  dev          # Start dev session"
