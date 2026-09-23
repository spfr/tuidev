#!/usr/bin/env bash
# ============================================================================
# Configuration Validator — the one config check CI and `make validate-configs`
# run. Parses every shipped config with a real parser: bash -n / zsh -n for
# shell, jq for JSON, Python's tomllib for TOML, luac -p for Lua, and
# `ghostty +validate-config` when Ghostty is installed.
#
# Usage: scripts/validate_configs.sh [--strict]
#   --strict  a missing validator (jq, python3 >= 3.11, luac) is an error, not
#             a warning; CI passes it so a skipped check can never pass.
# Honors NO_COLOR / TUIDEV_NO_COLOR via scripts/lib/ui.sh.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

STRICT=false
case "${1:-}" in
    --strict) STRICT=true ;;
    "") ;;
    *) die "usage: $0 [--strict]" 2 ;;
esac

ERRORS=0
WARNINGS=0

# Arithmetic *assignment*, not ((x++)): under `set -e`, ((x++)) returns non-zero
# when the old value is 0 and would abort on the first failure.
pass() { print_success "$1"; }
fail() { print_error "$1"; ERRORS=$((ERRORS + 1)); }
warn() { print_warning "$1"; WARNINGS=$((WARNINGS + 1)); }

# missing_tool WHAT — a validator is unavailable: an error under --strict.
missing_tool() {
    if [[ "$STRICT" == true ]]; then fail "$1"; else warn "$1"; fi
}

# rel FILE — path relative to the repo root, for readable output.
rel() { echo "${1#"$REPO_DIR"/}"; }

# first_cmd CMD... — print the first command that exists.
first_cmd() {
    local c
    for c in "$@"; do
        if command_exists "$c"; then echo "$c"; return 0; fi
    done
    return 1
}

print_header "Configuration Validator"

# ============================================================================
# Shell scripts
# ============================================================================
print_step "Shell scripts (bash -n)"

for script in "$REPO_DIR"/*.sh \
              "$REPO_DIR"/scripts/*.sh \
              "$REPO_DIR"/scripts/lib/*.sh \
              "$REPO_DIR"/scripts/install/*.sh \
              "$REPO_DIR"/scripts/install/packs/*.sh; do
    [[ -f "$script" ]] || continue
    if bash -n "$script" 2>/dev/null; then
        pass "$(rel "$script")"
    else
        fail "$(rel "$script") - syntax error"
    fi
done
echo ""

# ============================================================================
# JSON
# ============================================================================
print_step "JSON (jq)"

json_files=(
    configs/claude/settings.json
    configs/opencode/opencode.json
    configs/opencode/tui.json
)
if command_exists jq; then
    for f in "${json_files[@]}"; do
        if [[ ! -f "$REPO_DIR/$f" ]]; then
            fail "$f - file not found"
        elif jq empty "$REPO_DIR/$f" 2>/dev/null; then
            pass "$f"
        else
            fail "$f - invalid JSON"
        fi
    done
else
    missing_tool "jq not installed - JSON configs not checked"
fi
echo ""

# ============================================================================
# TOML
# ============================================================================
print_step "TOML (python3 tomllib)"

toml_files=(
    "$REPO_DIR/configs/starship/starship.toml"
    "$REPO_DIR/configs/codex/config.toml"
    "$REPO_DIR/configs/herdr/config.toml"
    "$REPO_DIR"/configs/themes/*/palette.toml
)
if command_exists python3 && python3 -c 'import tomllib' 2>/dev/null; then
    for f in "${toml_files[@]}"; do
        if [[ ! -f "$f" ]]; then
            fail "$(rel "$f") - file not found"
        elif err=$(python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$f" 2>&1); then
            pass "$(rel "$f")"
        else
            fail "$(rel "$f") - ${err##*$'\n'}"
        fi
    done
else
    missing_tool "python3 >= 3.11 (tomllib) not available - TOML configs not checked"
fi
echo ""

# ============================================================================
# Lua (Neovim)
# ============================================================================
print_step "Lua (luac -p)"

# luac -p only parses. `lua -e "loadfile(f)"` is not a check: loadfile returns
# nil plus an error message and lua still exits 0.
lua_files=()
while IFS= read -r f; do lua_files+=("$f"); done < <(
    find "$REPO_DIR/configs/nvim" -name '*.lua' -type f | sort
)
if luac=$(first_cmd luac luac5.4 luac5.3 luac5.1); then
    for f in "${lua_files[@]}"; do
        if err=$("$luac" -p "$f" 2>&1); then
            pass "$(rel "$f")"
        else
            fail "$(rel "$f") - $err"
        fi
    done
else
    missing_tool "luac not installed - Lua configs not checked"
fi
echo ""

# ============================================================================
# zsh
# ============================================================================
print_step "zsh (.zshrc)"

zshrc="$REPO_DIR/configs/zsh/.zshrc"
if [[ -f "$zshrc" ]]; then
    if grep -qE '/Users/[a-zA-Z]+' "$zshrc"; then
        warn ".zshrc - contains hardcoded user paths"
    else
        pass ".zshrc - no hardcoded paths"
    fi

    if command_exists zsh; then
        if zsh -n "$zshrc" 2>/dev/null; then
            pass ".zshrc - syntax OK (zsh -n)"
        else
            fail ".zshrc - zsh -n syntax check failed"
        fi
    else
        missing_tool "zsh not installed - .zshrc syntax not checked"
    fi
else
    fail ".zshrc - file not found"
fi
echo ""

# ============================================================================
# Ghostty
# ============================================================================
print_step "Ghostty"

ghostty_config="$REPO_DIR/configs/ghostty/config"
ghostty_bin=$(first_cmd ghostty || true)
if [[ -z "$ghostty_bin" && -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then
    ghostty_bin=/Applications/Ghostty.app/Contents/MacOS/ghostty
fi

# Static checks run everywhere: repo policy (no `term` override) plus the
# mistakes this repo has made before. Each entry: "REGEX :: message".
ghostty_checks=(
    '^term\s*= :: do not override term (breaks tmux feature detection)'
    '^shell-integration\s*=\s*(true|false) :: shell-integration must be none, detect, bash, elvish, fish or zsh'
    'keybind\s*=.*=send_text: :: keybind action send_text is invalid (use text:)'
    '^(audible-bell|visual-bell)\s*= :: audible-bell/visual-bell are gone (use bell-features)'
    'keybind\s*=\s*[^=]*\+([a-z]+)\+\1\+ :: duplicate modifier in a keybind'
    'keybind\s*=.*=open_scrollback_editor :: open_scrollback_editor is invalid (use write_scrollback_file:open)'
    '^notify-on-command-finish-after\s*=\s*[0-9]+(\s*#.*)?$ :: notify-on-command-finish-after needs a unit (e.g. 10s)'
)

if [[ ! -f "$ghostty_config" ]]; then
    fail "ghostty/config - file not found"
else
    ghostty_ok=true
    for check in "${ghostty_checks[@]}"; do
        if grep -qE "${check%% :: *}" "$ghostty_config"; then
            fail "ghostty/config - ${check#* :: }"
            ghostty_ok=false
        fi
    done
    [[ "$ghostty_ok" == true ]] && pass "ghostty/config - static checks"

    # Ghostty's own parser: unknown keys, bad values and bad keybinds all fail.
    if [[ -z "$ghostty_bin" ]]; then
        print_info "ghostty/config - Ghostty not installed, full parse skipped"
    elif err=$("$ghostty_bin" +validate-config --config-file="$ghostty_config" 2>&1); then
        pass "ghostty/config - ghostty +validate-config"
    else
        fail "ghostty/config - $err"
    fi
fi
echo ""

# ============================================================================
# tmux
# ============================================================================
print_step "tmux"

tmux_conf="$REPO_DIR/configs/tmux/tmux.conf"
if [[ -f "$tmux_conf" ]]; then
    for setting in default-terminal prefix mouse; do
        if grep -q "$setting" "$tmux_conf"; then
            pass "tmux.conf - $setting set"
        else
            fail "tmux.conf - missing $setting"
        fi
    done
else
    fail "tmux.conf - file not found (configs/tmux/tmux.conf)"
fi
echo ""

# ============================================================================
# Theme palettes: every configs/themes/*/palette.toml must carry the exact
# 26-key color contract (see docs/theming.md); key sets must match across
# themes so `theme.sh apply` renders identically for any of them.
# ============================================================================
print_step "Theme palette contract"

theme_ref=""
for palette in "$REPO_DIR"/configs/themes/*/palette.toml; do
    [[ -f "$palette" ]] || continue
    name=$(basename "$(dirname "$palette")")
    keys=$(grep -oE '^[a-z0-9_]+ = "#[0-9a-f]{6}"' "$palette" | cut -d' ' -f1 | sort)
    count=$(printf '%s\n' "$keys" | grep -c .)
    if [[ "$count" -ne 26 ]]; then
        fail "$name/palette.toml - expected 26 color keys, found $count"
    elif [[ -z "$theme_ref" ]]; then
        theme_ref="$keys"; pass "$name/palette.toml - 26 keys"
    elif [[ "$keys" != "$theme_ref" ]]; then
        fail "$name/palette.toml - key set differs from the contract"
    else
        pass "$name/palette.toml - matches the contract"
    fi
done
echo ""

# ============================================================================
# Required files
# ============================================================================
print_step "Required files"

required_files=(
    README.md
    install.sh
    uninstall.sh
    Makefile
    configs/zsh/.zshrc
    configs/nvim/init.lua
    configs/starship/starship.toml
    configs/herdr/config.toml
    configs/themes/tokyo-night/palette.toml
    configs/themes/catppuccin-mocha/palette.toml
    configs/ghostty/config
    scripts/health_check.sh
    scripts/notify.sh
    configs/ssh/config
    configs/tmux/tmux.conf
)
for f in "${required_files[@]}"; do
    if [[ -f "$REPO_DIR/$f" ]]; then
        pass "$f"
    else
        fail "$f missing"
    fi
done

# ============================================================================
# Summary
# ============================================================================
print_header "Validation Summary"
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    print_error "VALIDATION FAILED"
    exit 1
fi
print_success "VALIDATION PASSED"
