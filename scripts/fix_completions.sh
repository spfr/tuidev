#!/bin/bash

# ============================================================================
# Fix Insecure Zsh Completion Directories
# ============================================================================
# This script fixes permissions and removes insecure completion directories.
# zsh's compaudit checks both completion directories and their parents, so a
# group-writable Homebrew prefix parent such as /opt/homebrew/share can trigger
# prompts even when share/zsh/site-functions itself is already locked down.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

fix_path_permissions() {
    local path="$1"

    [[ -e "$path" ]] || return 0

    echo "Fixing: $path"

    local owner
    owner="$(stat -f '%Su' "$path" 2>/dev/null || stat -c '%U' "$path" 2>/dev/null || echo '')"

    if [[ "$owner" != "$(whoami)" && "$owner" != "root" ]]; then
        sudo chown "$(whoami)":admin "$path" 2>/dev/null \
            || sudo chown "$(whoami)":staff "$path" 2>/dev/null \
            || true
    fi
    chmod go-w "$path" 2>/dev/null || sudo chmod go-w "$path" 2>/dev/null || true

    echo -e "${GREEN}✓ Fixed permissions for $path${NC}"
}

collect_compaudit_paths() {
    zsh -f -c 'autoload -Uz compaudit; compaudit' 2>/dev/null \
        | sed -n '/^There are insecure /d; /^$/d; p' \
        || true
}

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Fixing Zsh Completion Directories${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Fix Homebrew completion directories
if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix)

    echo -e "${YELLOW}Fixing Homebrew completion directories...${NC}"

    for path in \
        "$BREW_PREFIX/share" \
        "$BREW_PREFIX/share/zsh" \
        "$BREW_PREFIX/share/zsh-completions" \
        "$BREW_PREFIX/share/zsh/site-functions"; do
        fix_path_permissions "$path"
    done
fi

# Fix anything compaudit still reports. This catches non-Homebrew completion
# paths without relying on a hard-coded fpath list.
INSECURE_PATHS=()
while IFS= read -r path; do
    INSECURE_PATHS+=("$path")
done < <(collect_compaudit_paths)
if [[ ${#INSECURE_PATHS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Fixing compaudit-reported paths...${NC}"
    for path in "${INSECURE_PATHS[@]}"; do
        fix_path_permissions "$path"
    done
fi

# Fix Docker completions
if [[ -d "$HOME/.docker/completions" ]]; then
    echo ""
    echo -e "${YELLOW}Fixing Docker completion directory...${NC}"
    chmod -R go-w "$HOME/.docker/completions"
    chown -R "$(whoami)":staff "$HOME/.docker/completions" 2>/dev/null || true
    echo -e "${GREEN}✓ Fixed permissions for $HOME/.docker/completions${NC}"
fi

# Fix zcompdump file
if [[ -f "$HOME/.zcompdump" ]]; then
    echo ""
    echo -e "${YELLOW}Fixing zcompdump file...${NC}"
    chmod 644 "$HOME/.zcompdump"
    chown "$(whoami)":staff "$HOME/.zcompdump" 2>/dev/null || true
    echo -e "${GREEN}✓ Fixed permissions for .zcompdump${NC}"
fi

# Remove old completion cache
echo ""
echo -e "${YELLOW}Cleaning completion cache...${NC}"
if rm -f "$HOME"/.zcompdump* "${XDG_CACHE_HOME:-$HOME/.cache}"/zsh/zcompdump* 2>/dev/null; then
    echo -e "${GREEN}✓ Removed old completion cache${NC}"
else
    echo -e "${YELLOW}Could not remove every completion cache file; continuing.${NC}"
fi

# Verify compaudit is clean, then regenerate completions without suppressing
# security checks.
echo ""
echo -e "${YELLOW}Checking compaudit...${NC}"
REMAINING_PATHS=()
while IFS= read -r path; do
    REMAINING_PATHS+=("$path")
done < <(collect_compaudit_paths)
if [[ ${#REMAINING_PATHS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Some completion paths are still insecure:${NC}"
    printf '  %s\n' "${REMAINING_PATHS[@]}"
    echo ""
    echo "Fix these manually, then rerun: make fix-completions"
else
    echo -e "${GREEN}✓ compaudit clean${NC}"
    echo ""
    echo -e "${YELLOW}Regenerating completions...${NC}"
    zsh -f -c '
        _dump_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
        mkdir -p "$_dump_dir" 2>/dev/null || true
        autoload -Uz compinit
        compinit -d "$_dump_dir/zcompdump-${ZSH_VERSION}"
    ' 2>/dev/null || true
    echo -e "${GREEN}✓ Completions regenerated${NC}"
fi

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Done! Restart your shell to apply changes.${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Run: exec zsh"
