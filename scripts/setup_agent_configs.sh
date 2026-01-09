#!/bin/bash
# ============================================================================
# Setup AI Agent Configuration Symlinks
# ============================================================================
#
# This script creates symlinks from the central AGENTS.md to locations
# where various AI coding assistants look for project instructions.
#
# Usage:
#   ./scripts/setup_agent_configs.sh [project_path]
#
# If no path provided, uses current directory.
#
# Supported AI Agents:
#   - Claude Code     → CLAUDE.md
#   - Cursor          → .cursorrules
#   - Windsurf        → .windsurfrules
#   - Aider           → .aider.md
#   - Codex           → instructions.md
#   - GitHub Copilot  → .github/copilot-instructions.md
#   - Cline           → .clinerules
#   - Roo Code        → .roo/instructions.md
#
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="${1:-.}"
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

AGENTS_FILE="$PROJECT_DIR/AGENTS.md"

print_step() {
    echo -e "${BLUE}>>>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_skip() {
    echo -e "${YELLOW}⊘${NC} $1 (already exists)"
}

# Check if AGENTS.md exists
if [[ ! -f "$AGENTS_FILE" ]]; then
    echo "Error: AGENTS.md not found in $PROJECT_DIR"
    echo ""
    echo "Either:"
    echo "  1. Copy templates/AGENTS_TEMPLATE.md to your project as AGENTS.md"
    echo "  2. Or run this script from a directory with AGENTS.md"
    exit 1
fi

echo ""
echo "Setting up AI agent config symlinks in: $PROJECT_DIR"
echo "Source: $AGENTS_FILE"
echo ""

# Claude Code - CLAUDE.md
if [[ ! -e "$PROJECT_DIR/CLAUDE.md" ]]; then
    ln -s AGENTS.md "$PROJECT_DIR/CLAUDE.md"
    print_success "Claude Code → CLAUDE.md"
else
    print_skip "CLAUDE.md"
fi

# Cursor - .cursorrules
if [[ ! -e "$PROJECT_DIR/.cursorrules" ]]; then
    ln -s AGENTS.md "$PROJECT_DIR/.cursorrules"
    print_success "Cursor → .cursorrules"
else
    print_skip ".cursorrules"
fi

# Windsurf - .windsurfrules
if [[ ! -e "$PROJECT_DIR/.windsurfrules" ]]; then
    ln -s AGENTS.md "$PROJECT_DIR/.windsurfrules"
    print_success "Windsurf → .windsurfrules"
else
    print_skip ".windsurfrules"
fi

# Aider - .aider.md
if [[ ! -e "$PROJECT_DIR/.aider.md" ]]; then
    ln -s AGENTS.md "$PROJECT_DIR/.aider.md"
    print_success "Aider → .aider.md"
else
    print_skip ".aider.md"
fi

# Codex - instructions.md
if [[ ! -e "$PROJECT_DIR/instructions.md" ]]; then
    ln -s AGENTS.md "$PROJECT_DIR/instructions.md"
    print_success "Codex → instructions.md"
else
    print_skip "instructions.md"
fi

# GitHub Copilot - .github/copilot-instructions.md
if [[ ! -d "$PROJECT_DIR/.github" ]]; then
    mkdir -p "$PROJECT_DIR/.github"
fi
if [[ ! -e "$PROJECT_DIR/.github/copilot-instructions.md" ]]; then
    ln -s ../AGENTS.md "$PROJECT_DIR/.github/copilot-instructions.md"
    print_success "GitHub Copilot → .github/copilot-instructions.md"
else
    print_skip ".github/copilot-instructions.md"
fi

# Cline - .clinerules
if [[ ! -e "$PROJECT_DIR/.clinerules" ]]; then
    ln -s AGENTS.md "$PROJECT_DIR/.clinerules"
    print_success "Cline → .clinerules"
else
    print_skip ".clinerules"
fi

# Roo Code - .roo/instructions.md
if [[ ! -d "$PROJECT_DIR/.roo" ]]; then
    mkdir -p "$PROJECT_DIR/.roo"
fi
if [[ ! -e "$PROJECT_DIR/.roo/instructions.md" ]]; then
    ln -s ../AGENTS.md "$PROJECT_DIR/.roo/instructions.md"
    print_success "Roo Code → .roo/instructions.md"
else
    print_skip ".roo/instructions.md"
fi

echo ""
echo -e "${GREEN}Done!${NC} All AI agents will now read from AGENTS.md"
echo ""
echo "To add these to git (recommended):"
echo "  git add AGENTS.md CLAUDE.md .cursorrules .windsurfrules .aider.md"
echo "  git add instructions.md .clinerules .github/ .roo/"
echo ""
