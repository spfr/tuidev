#!/usr/bin/env bash
# ============================================================================
# AI Agentic Development Workflow Launcher
# Starts Zellij with optimized layout for AI-assisted development
# Usage: ./scripts/ai-workflow.sh [layout]
# Layouts: single, dual, triple, remote
# ============================================================================

set -e

LAYOUT="${1:-dual}"
SESSION_NAME="ai-dev-$(date +%s)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Starting AI Agentic Development Workflow...${NC}"
echo -e "${GREEN}Layout: $LAYOUT${NC}"

# Check if zellij is installed
if ! command -v zellij &> /dev/null; then
    echo "Error: zellij not found. Install it first:"
    echo "  brew install zellij"
    exit 1
fi

# Start zellij with appropriate layout
case "$LAYOUT" in
    single)
        # Single workspace: nvim (left) + terminal (right)
        zellij --layout single --session "$SESSION_NAME"
        ;;
    dual)
        # Dual workspace: nvim (top) + 2 agents (bottom)
        zellij --layout dual --session "$SESSION_NAME"
        ;;
    triple)
        # Triple workspace: nvim + 3 AI agents
        zellij --layout triple --session "$SESSION_NAME"
        ;;
    remote)
        # Remote session setup: nvim + remote access info
        zellij --layout remote --session "$SESSION_NAME"
        ;;
    *)
        echo "Unknown layout: $LAYOUT"
        echo "Available layouts: single, dual, triple, remote"
        exit 1
        ;;
esac
