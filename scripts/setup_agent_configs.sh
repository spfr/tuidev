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
# Default (no flag): nothing to create — the actively used CLIs read AGENTS.md
# natively:
#   - Claude Code v2.1.277+ → reads AGENTS.md when the project has no CLAUDE.md
#                             or CLAUDE.local.md (code.claude.com/docs/en/memory)
#   - Codex CLI, OpenCode   → read AGENTS.md natively
#
# --all creates compatibility files, for teams that still need them:
#   - Claude Code           → CLAUDE.md (older than v2.1.277, or sessions that
#                             cannot read AGENTS.md, e.g. Amazon Bedrock)
# and the legacy per-vendor files (the vendors' older single-file forms;
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

PROJECT_DIR="."
ALL=false
for arg in "$@"; do
    case "$arg" in
        --all) ALL=true ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) PROJECT_DIR="$arg" ;;
    esac
done
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
AGENTS_FILE="$PROJECT_DIR/AGENTS.md"

# link <relative target> <path under project> <label>
link() {
    local target="$1" rel="$2" label="$3"
    local dest="$PROJECT_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    if [[ ! -e "$dest" ]]; then
        ln -s "$target" "$dest"
        print_success "$label → $rel"
    else
        print_info "$rel (already exists)"
    fi
}

if [[ ! -f "$AGENTS_FILE" ]]; then
    print_error "AGENTS.md not found in $PROJECT_DIR"
    print_info "Copy templates/AGENTS_TEMPLATE.md to your project as AGENTS.md,"
    print_info "or run this script from a directory that has one."
    exit 1
fi

print_header "AI agent configs for $PROJECT_DIR"
print_info "Claude Code (v2.1.277+), Codex CLI and OpenCode read AGENTS.md natively."

if ! $ALL; then
    print_success "nothing to create (use --all for CLAUDE.md and legacy vendor files)"
    exit 0
fi

link AGENTS.md    CLAUDE.md                        "Claude Code (< v2.1.277 / Bedrock)"
link AGENTS.md    .cursorrules                     "Cursor (legacy)"
link AGENTS.md    .windsurfrules                   "Windsurf (legacy)"
link AGENTS.md    .aider.md                        "Aider"
link ../AGENTS.md .github/copilot-instructions.md  "GitHub Copilot"
link AGENTS.md    .clinerules                      "Cline"
link ../AGENTS.md .roo/instructions.md             "Roo Code"

print_info "To add these to git (recommended):"
print_info "    git add CLAUDE.md .cursorrules .windsurfrules .aider.md .clinerules .github/ .roo/"
