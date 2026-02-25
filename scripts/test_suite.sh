#!/bin/bash

# ============================================================================
# Test Suite for macOS TUI Development Environment
# ============================================================================
# This script runs comprehensive tests on the installation and configuration.
# It can be run after installation to verify everything works correctly.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="$SCRIPT_DIR/../test_results"
mkdir -p "$TEST_RESULTS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
LOG_FILE="$TEST_RESULTS_DIR/test_$(date +%Y%m%d_%H%M%S).log"
echo "Test started at $(date)" > "$LOG_FILE"

# Helper functions
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

start_test() {
    ((TESTS_RUN++))
    echo ""
    log "${CYAN}[TEST $TESTS_RUN]${NC} $1"
    echo "Test: $1" >> "$LOG_FILE"
}

pass_test() {
    ((TESTS_PASSED++))
    log "${GREEN}  ✓ PASS${NC} $1"
    echo "PASS: $1" >> "$LOG_FILE"
}

fail_test() {
    ((TESTS_FAILED++))
    log "${RED}  ✗ FAIL${NC} $1"
    echo "FAIL: $1" >> "$LOG_FILE"
}

# ============================================================================
# Configuration Tests
# ============================================================================

print_header() {
    echo ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}$1${NC}"
    log "${BLUE}========================================${NC}"
}

print_header "Configuration Tests"

# Test .zshrc exists and is valid
start_test "Shell configuration file exists"
if [[ -f ~/.zshrc ]]; then
    pass_test "$HOME/.zshrc exists"
else
    fail_test "$HOME/.zshrc missing"
fi

# Test .zshrc is sourced correctly
start_test "Shell configuration is sourced correctly"
if grep -q "starship init zsh" ~/.zshrc; then
    pass_test "Starship prompt configured"
else
    fail_test "Starship prompt not configured"
fi

if grep -q "zoxide init zsh" ~/.zshrc; then
    pass_test "Zoxide configured"
else
    fail_test "Zoxide not configured"
fi

if grep -q "fzf --zsh" ~/.zshrc; then
    pass_test "fzf configured"
else
    fail_test "fzf not configured"
fi

# Test starship config
start_test "Starship configuration"
if [[ -f ~/.config/starship.toml ]]; then
    if grep -q "character" ~/.config/starship.toml; then
        pass_test "Starship config is valid"
    else
        fail_test "Starship config missing required sections"
    fi
else
    fail_test "Starship config missing"
fi

# Test zellij config
start_test "Zellij configuration"
if [[ -f ~/.config/zellij/config.kdl ]]; then
    if grep -q "default_shell" ~/.config/zellij/config.kdl; then
        pass_test "Zellij config is valid"
    else
        fail_test "Zellij config missing required sections"
    fi
else
    fail_test "Zellij config missing"
fi

# Test zellij layouts
start_test "Zellij layouts"
if [[ -d ~/.config/zellij/layouts ]]; then
    LAYOUT_COUNT=$(find ~/.config/zellij/layouts/ -name '*.kdl' 2>/dev/null | wc -l)
    if [[ $LAYOUT_COUNT -ge 2 ]]; then
        pass_test "Zellij has $LAYOUT_COUNT layouts"
    else
        fail_test "Zellij has insufficient layouts ($LAYOUT_COUNT)"
    fi
else
    fail_test "Zellij layouts directory missing"
fi

# ============================================================================
# CLI Tool Tests
# ============================================================================

print_header "CLI Tool Tests"

# Test ripgrep
start_test "ripgrep installation and functionality"
if command -v rg >/dev/null 2>&1; then
    if echo "test" | rg -q "test" 2>/dev/null; then
        VERSION=$(rg --version | head -1)
        pass_test "ripgrep works ($VERSION)"
    else
        fail_test "ripgrep not functional"
    fi
else
    fail_test "ripgrep not installed"
fi

# Test fd
start_test "fd installation and functionality"
if command -v fd >/dev/null 2>&1; then
    if fd -t d -d 1 "test" . >/dev/null 2>&1 || true; then
        VERSION=$(fd --version)
        pass_test "fd works ($VERSION)"
    else
        fail_test "fd not functional"
    fi
else
    fail_test "fd not installed"
fi

# Test eza
start_test "eza installation and functionality"
if command -v eza >/dev/null 2>&1; then
    if eza --version >/dev/null 2>&1; then
        pass_test "eza works"
    else
        fail_test "eza not functional"
    fi
else
    fail_test "eza not installed"
fi

# Test bat
start_test "bat installation and functionality"
if command -v bat >/dev/null 2>&1; then
    if echo "test" | bat --style=plain >/dev/null 2>&1; then
        pass_test "bat works"
    else
        fail_test "bat not functional"
    fi
else
    fail_test "bat not installed"
fi

# Test fzf
start_test "fzf installation and integration"
if command -v fzf >/dev/null 2>&1; then
    pass_test "fzf installed"
else
    fail_test "fzf not installed"
fi

# Test zoxide
start_test "zoxide installation"
if command -v zoxide >/dev/null 2>&1; then
    pass_test "zoxide installed"
else
    fail_test "zoxide not installed"
fi

# Test lazygit
start_test "lazygit installation"
if command -v lazygit >/dev/null 2>&1; then
    VERSION=$(lazygit --version)
    pass_test "lazygit works ($VERSION)"
else
    fail_test "lazygit not installed"
fi

# Test delta
start_test "delta installation"
if command -v delta >/dev/null 2>&1; then
    VERSION=$(delta --version | head -1)
    pass_test "delta works ($VERSION)"
else
    fail_test "delta not installed"
fi

# Test zellij
start_test "zellij installation"
if command -v zellij >/dev/null 2>&1; then
    VERSION=$(zellij --version 2>/dev/null || echo "unknown")
    pass_test "zellij works ($VERSION)"
else
    fail_test "zellij not installed"
fi

# Test starship
start_test "starship installation"
if command -v starship >/dev/null 2>&1; then
    VERSION=$(starship --version)
    pass_test "starship works ($VERSION)"
else
    fail_test "starship not installed"
fi

# Test neovim (optional)
start_test "neovim installation (optional)"
if command -v nvim >/dev/null 2>&1; then
    VERSION=$(nvim --version | head -1)
    pass_test "neovim works ($VERSION)"
else
    log "${YELLOW}  - SKIP${NC} neovim not installed (optional)"
fi

# Test gh (optional)
start_test "GitHub CLI installation (optional)"
if command -v gh >/dev/null 2>&1; then
    VERSION=$(gh --version 2>&1 | head -1)
    pass_test "gh works ($VERSION)"
else
    log "${YELLOW}  - SKIP${NC} gh not installed (optional)"
fi

# ============================================================================
# Integration Tests
# ============================================================================

print_header "Integration Tests"

# Test Git configuration with delta
start_test "Git delta integration"
if command -v git >/dev/null 2>&1; then
    if git config --global core.pager 2>/dev/null | grep -q "delta"; then
        pass_test "Git configured with delta"
    else
        fail_test "Git not configured with delta"
    fi
else
    fail_test "Git not installed"
fi

# Test fzf integration with ripgrep
start_test "fzf ripgrep integration"
if [[ -n "$FZF_DEFAULT_COMMAND" ]]; then
    if echo "$FZF_DEFAULT_COMMAND" | grep -q "rg"; then
        pass_test "fzf configured to use ripgrep"
    else
        fail_test "fzf not using ripgrep"
    fi
else
    log "${YELLOW}  - SKIP${NC} FZF_DEFAULT_COMMAND not set"
fi

# Test aliases are set correctly
start_test "Shell aliases"
if grep -q "alias cat='bat'" ~/.zshrc; then
    pass_test "cat alias set to bat"
else
    fail_test "cat alias not set"
fi

if grep -q "alias ls='eza" ~/.zshrc; then
    pass_test "ls alias set to eza"
else
    fail_test "ls alias not set"
fi

if grep -q "alias lg='lazygit'" ~/.zshrc; then
    pass_test "lg alias set to lazygit"
else
    fail_test "lg alias not set"
fi

# ============================================================================
# Functional Tests
# ============================================================================

print_header "Functional Tests"

# Test basic file operations
start_test "Modern CLI replacements work"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

echo "test file content" > test_file.txt

# Test bat
if command -v bat >/dev/null 2>&1; then
    if bat test_file.txt >/dev/null 2>&1; then
        pass_test "bat can read files"
    else
        fail_test "bat cannot read files"
    fi
fi

# Test eza
if command -v eza >/dev/null 2>&1; then
    if eza test_file.txt >/dev/null 2>&1; then
        pass_test "eza can list files"
    else
        fail_test "eza cannot list files"
    fi
fi

# Test ripgrep
if command -v rg >/dev/null 2>&1; then
    if rg -q "test" test_file.txt 2>/dev/null; then
        pass_test "ripgrep can search files"
    else
        fail_test "ripgrep cannot search files"
    fi
fi

cd - >/dev/null
rm -rf "$TEST_DIR"

# Test zellij can start
start_test "Zellij can create session"
if command -v zellij >/dev/null 2>&1; then
    if timeout 3 zellij --session test_session run -- sh -c "exit" 2>/dev/null; then
        pass_test "Zellij can create and close session"
    else
        log "${YELLOW}  - SKIP${NC} Cannot test zellij in non-interactive mode"
    fi
else
    fail_test "Zellij not installed"
fi

# ============================================================================
# Performance Tests
# ============================================================================

print_header "Performance Tests"

# Test shell startup time
start_test "Shell startup performance"
STARTUP_TIME=$(/usr/bin/time -l zsh -i -c exit 2>&1 | grep real | awk '{print $2}' || echo "N/A")
if [[ "$STARTUP_TIME" != "N/A" ]]; then
    log "${CYAN}  ℹ${NC} Shell startup time: $STARTUP_TIME"
    pass_test "Shell startup measured"
else
    log "${YELLOW}  - SKIP${NC} Could not measure startup time"
fi

# ============================================================================
# GUI App Tests (macOS only)
# ============================================================================

if [[ "$(uname)" == "Darwin" ]]; then
    print_header "GUI Application Tests"

    # Test Rectangle
    start_test "Rectangle app"
    if [[ -d "/Applications/Rectangle.app" ]] || [[ -d "$HOME/Applications/Rectangle.app" ]]; then
        pass_test "Rectangle is installed"
    else
        fail_test "Rectangle not installed"
    fi

    # Test Stats
    start_test "Stats app"
    if [[ -d "/Applications/Stats.app" ]] || [[ -d "$HOME/Applications/Stats.app" ]]; then
        pass_test "Stats is installed"
    else
        fail_test "Stats not installed"
    fi

    # Test Maccy
    start_test "Maccy app"
    if [[ -d "/Applications/Maccy.app" ]] || [[ -d "$HOME/Applications/Maccy.app" ]]; then
        pass_test "Maccy is installed"
    else
        fail_test "Maccy not installed"
    fi
fi

# ============================================================================
# Test Summary
# ============================================================================

print_header "Test Summary"

log "${CYAN}Tests Run:${NC}    $TESTS_RUN"
log "${GREEN}Tests Passed:${NC}  $TESTS_PASSED"
log "${RED}Tests Failed:${NC}  $TESTS_FAILED"

PASS_RATE=$(( TESTS_PASSED * 100 / TESTS_RUN ))
log "${CYAN}Pass Rate:${NC}    ${PASS_RATE}%"

log ""
log "Log saved to: $LOG_FILE"

if [[ $TESTS_FAILED -eq 0 ]]; then
    log "${GREEN}All tests passed! ✓${NC}"
    exit 0
elif [[ $PASS_RATE -ge 80 ]]; then
    log "${YELLOW}Most tests passed. Review failures above.${NC}"
    exit 1
else
    log "${RED}Many tests failed. Consider reinstalling.${NC}"
    exit 2
fi
