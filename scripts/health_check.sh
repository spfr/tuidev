#!/bin/bash

# ============================================================================
# Health Check Script for macOS TUI Development Environment
# ============================================================================
# This script verifies that all tools are installed and working correctly.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Track results
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
    echo ""
}

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ ${NC}$1"
    ((PASSED++)) || true
}

print_error() {
    echo -e "${RED}✗ ${NC}$1"
    ((FAILED++)) || true
}

print_warning() {
    echo -e "${YELLOW}⚠ ${NC}$1"
    ((WARNINGS++)) || true
}

# Check if command exists
check_command() {
    if command -v "$1" > /dev/null 2>&1; then
        print_success "$1 is installed (version: $($1 --version 2> /dev/null | head -1 || echo "unknown"))"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Check if app exists in Applications
check_app() {
    if [[ -d "/Applications/$1.app" ]] || [[ -d "$HOME/Applications/$1.app" ]]; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Check if config file exists
check_config() {
    if [[ -f "$1" ]]; then
        print_success "$1 exists"
        return 0
    else
        print_error "$1 does not exist"
        return 1
    fi
}

# ============================================================================
# System Checks
# ============================================================================

print_header "System Checks"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "Not running on macOS (current: $(uname))"
else
    print_success "Running on macOS $(sw_vers -productVersion)"
fi

# Check if zsh is the default shell
if [[ "$SHELL" == *"zsh"* ]]; then
    print_success "Default shell is zsh"
else
    print_warning "Default shell is not zsh (current: $SHELL)"
fi

# ============================================================================
# Homebrew Check
# ============================================================================

print_header "Package Manager Check"

if command -v brew > /dev/null 2>&1; then
    print_success "Homebrew is installed (version: $(brew --version | head -1))"
    brew_output=$(brew doctor 2>&1 || true)
    if echo "$brew_output" | grep -q "Your system is ready to brew"; then
        print_success "Homebrew is healthy"
    else
        print_warning "Homebrew doctor found issues"
        echo "$brew_output" | grep -A 5 "Warning\|Error" | head -10
    fi
else
    print_error "Homebrew is not installed"
fi

# ============================================================================
# Terminal & CLI Tools
# ============================================================================

print_header "Terminal & CLI Tools"

CORE_TOOLS=(
    "zellij"
    "starship"
    "fzf"
    "rg"
    "bat"
    "eza"
    "fd"
    "zoxide"
    "lazygit"
    "delta"
    "atuin"
)

for tool in "${CORE_TOOLS[@]}"; do
    check_command "$tool" || true
done

# Additional tools
if command -v gh > /dev/null 2>&1; then
    print_success "GitHub CLI is installed (version: $(gh --version 2> /dev/null | head -1))"
else
    print_warning "GitHub CLI is not installed (optional)"
fi

if command -v nvim > /dev/null 2>&1; then
    print_success "Neovim is installed (version: $(nvim --version | head -1))"
else
    print_warning "Neovim is not installed (optional)"
fi

if command -v btm > /dev/null 2>&1; then
    print_success "bottom is installed (version: $(btm --version 2> /dev/null))"
else
    print_warning "bottom is not installed (optional)"
fi

if command -v jq > /dev/null 2>&1; then
    print_success "jq is installed (version: $(jq --version))"
else
    print_warning "jq is not installed (optional)"
fi

# ============================================================================
# AI CLI Tools
# ============================================================================

print_header "AI CLI Tools"

# Check OpenCode
if command -v opencode > /dev/null 2>&1; then
    print_success "OpenCode is installed (version: $(opencode --version 2> /dev/null | head -1 || echo "unknown"))"
else
    print_warning "OpenCode is not installed (optional - install from https://opencode.ai)"
fi

# Check Claude Code
if command -v claude > /dev/null 2>&1; then
    print_success "Claude Code is installed (version: $(claude --version 2> /dev/null | head -1 || echo "unknown"))"
else
    print_warning "Claude Code is not installed (optional - npm install -g @anthropic-ai/claude-code)"
fi

# Check Gemini CLI
if command -v gemini > /dev/null 2>&1; then
    print_success "Gemini CLI is installed (version: $(gemini --version 2> /dev/null | head -1 || echo "unknown"))"
else
    print_warning "Gemini CLI is not installed (optional - npm install -g @anthropic-ai/gemini-cli)"
fi

# ============================================================================
# AI CLI Configurations
# ============================================================================

print_header "AI CLI Configurations"

# Check OpenCode config
if [[ -f "$HOME/.config/opencode/opencode.json" ]]; then
    print_success "OpenCode config exists"
else
    print_warning "OpenCode config not found (~/.config/opencode/opencode.json)"
fi

# Check Claude Code config
if [[ -f "$HOME/.claude.json" ]]; then
    print_success "Claude Code config exists"
else
    print_warning "Claude Code config not found (~/.claude.json)"
fi

# Check Gemini CLI config
if [[ -f "$HOME/.gemini/settings.json" ]]; then
    print_success "Gemini CLI config exists"
else
    print_warning "Gemini CLI config not found (~/.gemini/settings.json)"
fi

# Check MCP data directories
if [[ -d "$HOME/.local/share/mcp" ]]; then
    print_success "MCP data directory exists"
else
    print_warning "MCP data directory missing (~/.local/share/mcp)"
fi

# Check MCP environment template
if [[ -f "$HOME/.config/mcp-env.template" ]]; then
    print_success "MCP environment template exists"
    if [[ -f "$HOME/.config/mcp-env" ]]; then
        print_success "MCP environment configured"
    else
        print_warning "MCP environment not configured (copy mcp-env.template to mcp-env)"
    fi
fi

# ============================================================================
# GUI Applications
# ============================================================================

print_header "GUI Applications"

GUI_APPS=(
    "Rectangle"
    "Stats"
    "Maccy"
    "Hidden Bar"
)

for app in "${GUI_APPS[@]}"; do
    check_app "$app" || true
done

# Ghostty is optional
if [[ -d "/Applications/Ghostty.app" ]] || command -v ghostty &> /dev/null; then
    print_success "Ghostty is installed"
else
    print_warning "Ghostty is not installed (optional)"
fi

# ============================================================================
# Configuration Files
# ============================================================================

print_header "Configuration Files"

check_config "$HOME/.zshrc"
check_config "$HOME/.config/starship.toml"
check_config "$HOME/.config/zellij/config.kdl"

# Check layouts
if [[ -d "$HOME/.config/zellij/layouts" ]]; then
    print_success "Zellij layouts directory exists"
    for layout in dev.kdl multi-agent.kdl fullstack.kdl; do
        if [[ -f "$HOME/.config/zellij/layouts/$layout" ]]; then
            print_success "Zellij layout: $layout"
        else
            print_warning "Zellij layout missing: $layout"
        fi
    done
else
    print_error "Zellij layouts directory does not exist"
fi

# Check Ghostty config (optional)
if [[ -f "$HOME/.config/ghostty/config" ]]; then
    print_success "Ghostty config exists"
else
    print_warning "Ghostty config does not exist (optional)"
fi

# ============================================================================
# Git Configuration
# ============================================================================

print_header "Git Configuration"

if command -v git > /dev/null 2>&1; then
    print_success "Git is installed (version: $(git --version | head -1))"

    # Check if delta is configured
    if git config --global core.pager 2> /dev/null | grep -q "delta"; then
        print_success "Git configured with delta pager"
    else
        print_warning "Git not configured with delta pager"
    fi

    # Check git user
    if git config --global user.name > /dev/null 2>&1; then
        print_success "Git user configured: $(git config --global user.name)"
    else
        print_warning "Git user.name not configured"
    fi
else
    print_error "Git is not installed"
fi

# ============================================================================
# Shell Integration Tests
# ============================================================================

print_header "Shell Integration Tests"

# Check if fzf is properly integrated
if [[ -f ~/.fzf.zsh ]] || grep -q "fzf" ~/.zshrc 2>/dev/null || command -v fzf > /dev/null 2>&1; then
    print_success "fzf is available"
else
    print_warning "fzf integration may not be working"
fi

# Check if starship is integrated
if grep -q "starship init zsh" ~/.zshrc; then
    print_success "Starship prompt is configured in .zshrc"
else
    print_error "Starship prompt is not configured in .zshrc"
fi

# Check if zoxide is integrated
if grep -q "zoxide init zsh" ~/.zshrc; then
    print_success "zoxide is configured in .zshrc"
else
    print_error "zoxide is not configured in .zshrc"
fi

# Check if atuin is integrated
if grep -q "atuin init zsh" ~/.zshrc; then
    print_success "atuin is configured in .zshrc"
else
    print_warning "atuin is not configured in .zshrc"
fi

# ============================================================================
# Functionality Tests
# ============================================================================

print_header "Functionality Tests"

# Test ripgrep
if command -v rg > /dev/null 2>&1; then
    if echo "test" | rg -q "test" 2> /dev/null; then
        print_success "ripgrep is working"
    else
        print_error "ripgrep not working properly"
    fi
fi

# Test fd
if command -v fd > /dev/null 2>&1; then
    if fd -H -t f -d 1 "health_check.sh" . > /dev/null 2>&1; then
        print_success "fd is working"
    else
        print_error "fd not working properly"
    fi
fi

# Test eza
if command -v eza > /dev/null 2>&1; then
    if eza > /dev/null 2>&1; then
        print_success "eza is working"
    else
        print_error "eza not working properly"
    fi
fi

# Test bat
if command -v bat > /dev/null 2>&1; then
    if echo "test" | bat --style=plain > /dev/null 2>&1; then
        print_success "bat is working"
    else
        print_error "bat not working properly"
    fi
fi

# ============================================================================
# Summary
# ============================================================================

print_header "Health Check Summary"

echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}All critical checks passed! Your environment is healthy. 🚀${NC}"
    exit 0
elif [[ $FAILED -le 5 ]]; then
    echo ""
    echo -e "${YELLOW}Some checks failed. Review the output above and install missing tools.${NC}"
    echo "Run: ./install.sh"
    exit 1
else
    echo ""
    echo -e "${RED}Many checks failed. Consider running a fresh installation.${NC}"
    echo "Run: ./install.sh"
    exit 2
fi
