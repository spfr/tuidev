#!/usr/bin/env bash
# ============================================================================
# Configuration Validator
# Validates all configuration files before deployment
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

ERRORS=0
WARNINGS=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((ERRORS++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARNINGS++)); }
log_info() { echo -e "[INFO] $1"; }

echo "============================================"
echo "Configuration Validator"
echo "============================================"
echo ""

# ============================================================================
# 1. Validate Shell Scripts
# ============================================================================
echo "--- Shell Scripts ---"

for script in "$REPO_DIR"/*.sh "$REPO_DIR"/scripts/*.sh; do
    if [[ -f "$script" ]]; then
        name=$(basename "$script")
        if bash -n "$script" 2>/dev/null; then
            log_pass "$name - syntax OK"
        else
            log_fail "$name - syntax error"
        fi
    fi
done
echo ""

# ============================================================================
# 2. Validate Zellij KDL Configs
# ============================================================================
echo "--- Zellij KDL Configs ---"

# Check main config
if [[ -f "$REPO_DIR/configs/zellij/config.kdl" ]]; then
    # Basic KDL validation - check for balanced braces
    open_braces=$(grep -o '{' "$REPO_DIR/configs/zellij/config.kdl" | wc -l)
    close_braces=$(grep -o '}' "$REPO_DIR/configs/zellij/config.kdl" | wc -l)
    if [[ "$open_braces" -eq "$close_braces" ]]; then
        log_pass "config.kdl - braces balanced ($open_braces pairs)"
    else
        log_fail "config.kdl - unbalanced braces (open: $open_braces, close: $close_braces)"
    fi
else
    log_fail "config.kdl - file not found"
fi

# Check layouts
for layout in "$REPO_DIR"/configs/zellij/layouts/*.kdl; do
    if [[ -f "$layout" ]]; then
        name=$(basename "$layout")
        open_braces=$(grep -o '{' "$layout" | wc -l)
        close_braces=$(grep -o '}' "$layout" | wc -l)

        if [[ "$open_braces" -eq "$close_braces" ]]; then
            # Check for common KDL issues
            if grep -qE 'tab.*focus\s+true\s*\{' "$layout" 2>/dev/null; then
                log_fail "$name - invalid KDL: 'focus true' should be inside block"
            elif grep -qE '^\s*focus\s+true\s*$' "$layout" 2>/dev/null; then
                log_pass "$name - valid KDL ($open_braces blocks)"
            else
                log_pass "$name - valid KDL ($open_braces blocks)"
            fi
        else
            log_fail "$name - unbalanced braces (open: $open_braces, close: $close_braces)"
        fi
    fi
done
echo ""

# ============================================================================
# 3. Validate TOML Configs
# ============================================================================
echo "--- TOML Configs ---"

if [[ -f "$REPO_DIR/configs/starship/starship.toml" ]]; then
    # Basic TOML validation
    if grep -qE '^\[' "$REPO_DIR/configs/starship/starship.toml"; then
        log_pass "starship.toml - has sections"
    else
        log_warn "starship.toml - no sections found"
    fi
else
    log_fail "starship.toml - file not found"
fi
echo ""

# ============================================================================
# 4. Validate Lua Configs (Neovim)
# ============================================================================
echo "--- Neovim Lua Configs ---"

for lua_file in "$REPO_DIR"/configs/nvim/*.lua "$REPO_DIR"/configs/nvim/**/*.lua; do
    if [[ -f "$lua_file" ]]; then
        name=$(basename "$lua_file")
        if command -v luac &>/dev/null; then
            if luac -p "$lua_file" 2>/dev/null; then
                log_pass "$name - syntax OK"
            else
                log_fail "$name - syntax error"
            fi
        else
            # Fallback: check for balanced structures
            if grep -qE 'return\s*\{' "$lua_file" 2>/dev/null || grep -qE '^local' "$lua_file" 2>/dev/null; then
                log_pass "$name - appears valid (no luac for full check)"
            else
                log_warn "$name - could not verify (install luac)"
            fi
        fi
    fi
done
echo ""

# ============================================================================
# 5. Validate ZSH Config
# ============================================================================
echo "--- ZSH Config ---"

if [[ -f "$REPO_DIR/configs/zsh/.zshrc" ]]; then
    # Check for hardcoded paths
    if grep -qE '/Users/[a-zA-Z]+' "$REPO_DIR/configs/zsh/.zshrc" 2>/dev/null; then
        log_warn ".zshrc - contains hardcoded user paths"
    else
        log_pass ".zshrc - no hardcoded paths"
    fi

    # Check for duplicate functions
    ai_count=$(grep -c '^ai()' "$REPO_DIR/configs/zsh/.zshrc" 2>/dev/null || echo 0)
    if [[ "$ai_count" -gt 1 ]]; then
        log_fail ".zshrc - duplicate ai() function ($ai_count definitions)"
    else
        log_pass ".zshrc - no duplicate functions"
    fi

    # Check function syntax
    if bash -n "$REPO_DIR/configs/zsh/.zshrc" 2>/dev/null; then
        log_pass ".zshrc - syntax OK"
    else
        log_warn ".zshrc - bash -n check failed (may be zsh-specific)"
    fi
else
    log_fail ".zshrc - file not found"
fi
echo ""

# ============================================================================
# 6. Validate Ghostty Config
# ============================================================================
echo "--- Ghostty Config ---"

if [[ -f "$REPO_DIR/configs/ghostty/config" ]]; then
    ghostty_config="$REPO_DIR/configs/ghostty/config"

    # Check for invalid shell-integration value (must be: none, detect, bash, elvish, fish, zsh)
    if grep -qE '^shell-integration\s*=\s*(true|false)' "$ghostty_config" 2>/dev/null; then
        log_fail "ghostty/config - invalid shell-integration value (use: none, detect, bash, elvish, fish, zsh)"
    else
        log_pass "ghostty/config - shell-integration valid"
    fi

    # Check for invalid keybind actions (send_text should be text)
    if grep -qE 'keybind\s*=.*=send_text:' "$ghostty_config" 2>/dev/null; then
        log_fail "ghostty/config - invalid keybind action 'send_text' (use 'text')"
    else
        log_pass "ghostty/config - keybind actions valid"
    fi

    # Check for deprecated bell options
    if grep -qE '^(audible-bell|visual-bell)\s*=' "$ghostty_config" 2>/dev/null; then
        log_fail "ghostty/config - deprecated bell options (use 'bell-features')"
    else
        log_pass "ghostty/config - bell config valid"
    fi

    # Check for double modifiers in keybinds (e.g., ctrl+shift+shift+d)
    if grep -qE 'keybind\s*=\s*[^=]*\+([a-z]+)\+\1\+' "$ghostty_config" 2>/dev/null; then
        log_fail "ghostty/config - duplicate modifier in keybind"
    else
        log_pass "ghostty/config - no duplicate modifiers"
    fi

    # Check for invalid actions
    if grep -qE 'keybind\s*=.*=open_scrollback_editor' "$ghostty_config" 2>/dev/null; then
        log_fail "ghostty/config - invalid action 'open_scrollback_editor' (use 'write_scrollback_file:open')"
    else
        log_pass "ghostty/config - no deprecated actions"
    fi
else
    log_fail "ghostty/config - file not found"
fi
echo ""

# ============================================================================
# 7. Check Required Files
# ============================================================================
echo "--- Required Files ---"

required_files=(
    "README.md"
    "install.sh"
    "uninstall.sh"
    "Makefile"
    "configs/zsh/.zshrc"
    "configs/zellij/config.kdl"
    "configs/zellij/layouts/dual.kdl"
    "configs/zellij/layouts/single.kdl"
    "configs/zellij/layouts/triple.kdl"
    "configs/nvim/init.lua"
    "configs/starship/starship.toml"
    "configs/ghostty/config"
    "configs/hammerspoon/init.lua"
    "scripts/health_check.sh"
    "scripts/notify.sh"
    "configs/ssh/config"
    "configs/zellij/layouts/remote.kdl"
)

for file in "${required_files[@]}"; do
    if [[ -f "$REPO_DIR/$file" ]]; then
        log_pass "$file exists"
    else
        log_fail "$file missing"
    fi
done
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "============================================"
echo "Validation Summary"
echo "============================================"
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}VALIDATION FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}VALIDATION PASSED${NC}"
    exit 0
fi
