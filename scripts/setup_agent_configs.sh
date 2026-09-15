#!/bin/bash
# ============================================================================
# Setup AI Agent Configuration Symlinks
# ============================================================================
#
# Points every AI coding agent at one canonical AGENTS.md.
#
# Usage:
#   ./scripts/setup_agent_configs.sh [project_path] [--all]
#
# Default (no flag) creates only what the actively used CLIs need:
#   - Claude Code     → CLAUDE.md   (Claude reads CLAUDE.md, not AGENTS.md;
#                                    a symlink or an `@AGENTS.md` import works)
#   - Codex CLI       → nothing; reads AGENTS.md natively
#   - OpenCode        → nothing; reads AGENTS.md natively
#
# --all additionally creates the legacy per-vendor files, for teams that
# still run one of these (formats are the vendors' older single-file forms;
# Cursor and Windsurf have since moved to .cursor/rules/ and .windsurf/rules/):
#   - Cursor          → .cursorrules
#   - Windsurf        → .windsurfrules
#   - Aider           → .aider.md
#   - GitHub Copilot  → .github/copilot-instructions.md
#   - Cline           → .clinerules
#   - Roo Code        → .roo/instructions.md
#
# Existing files are never overwritten.
# ============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="."
ALL=false
for arg in "$@"; do
    case "$arg" in
        --all) ALL=true ;;
        -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) PROJECT_DIR="$arg" ;;
    esac
done
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
AGENTS_FILE="$PROJECT_DIR/AGENTS.md"

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_skip()    { echo -e "${YELLOW}⊘${NC} $1 (already exists)"; }

# link <relative target> <path under project> <label>
link() {
    local target="$1" rel="$2" label="$3"
    local dest="$PROJECT_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    if [[ ! -e "$dest" ]]; then
        ln -s "$target" "$dest"
        print_success "$label → $rel"
    else
        print_skip "$rel"
    fi
}

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

link AGENTS.md CLAUDE.md "Claude Code"
echo "  Codex CLI and OpenCode read AGENTS.md natively — nothing to create."

created="AGENTS.md CLAUDE.md"
if $ALL; then
    link AGENTS.md    .cursorrules                     "Cursor (legacy)"
    link AGENTS.md    .windsurfrules                   "Windsurf (legacy)"
    link AGENTS.md    .aider.md                        "Aider"
    link ../AGENTS.md .github/copilot-instructions.md  "GitHub Copilot"
    link AGENTS.md    .clinerules                      "Cline"
    link ../AGENTS.md .roo/instructions.md             "Roo Code"
    created="$created .cursorrules .windsurfrules .aider.md .clinerules .github/ .roo/"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo "To add these to git (recommended):"
echo "  git add $created"
echo ""
