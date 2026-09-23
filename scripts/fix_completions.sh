#!/bin/bash

# ============================================================================
# Fix Insecure Zsh Completion Directories
# ============================================================================
# This script fixes permissions and removes insecure completion directories.
# zsh's compaudit checks both completion directories and their parents, so a
# group-writable Homebrew prefix parent such as /opt/homebrew/share can trigger
# prompts even when share/zsh/site-functions itself is already locked down.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

fix_path_permissions() {
    local path="$1"

    [[ -e "$path" ]] || return 0

    print_step "fixing: $path"

    local owner
    owner="$(file_owner "$path" || true)"

    if [[ "$owner" != "$(whoami)" && "$owner" != "root" ]]; then
        sudo chown "$(whoami)":admin "$path" 2>/dev/null \
            || sudo chown "$(whoami)":staff "$path" 2>/dev/null \
            || true
    fi
    chmod go-w "$path" 2>/dev/null || sudo chmod go-w "$path" 2>/dev/null || true

    print_success "fixed permissions for $path"
}

collect_compaudit_paths() {
    zsh -f -c 'autoload -Uz compaudit; compaudit' 2>/dev/null \
        | sed -n '/^There are insecure /d; /^$/d; p' \
        || true
}

print_header "Fixing Zsh Completion Directories"

# Fix Homebrew completion directories
if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix)

    print_info "Homebrew completion directories"

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
    print_info "compaudit-reported paths"
    for path in "${INSECURE_PATHS[@]}"; do
        fix_path_permissions "$path"
    done
fi

# Fix Docker completions
if [[ -d "$HOME/.docker/completions" ]]; then
    chmod -R go-w "$HOME/.docker/completions"
    chown -R "$(whoami)":staff "$HOME/.docker/completions" 2>/dev/null || true
    print_success "fixed permissions for $HOME/.docker/completions"
fi

# Fix zcompdump file
if [[ -f "$HOME/.zcompdump" ]]; then
    chmod 644 "$HOME/.zcompdump"
    chown "$(whoami)":staff "$HOME/.zcompdump" 2>/dev/null || true
    print_success "fixed permissions for .zcompdump"
fi

# Remove old completion cache
if rm -f "$HOME"/.zcompdump* "${XDG_CACHE_HOME:-$HOME/.cache}"/zsh/zcompdump* 2>/dev/null; then
    print_success "removed old completion cache"
else
    print_warning "could not remove every completion cache file; continuing"
fi

# Verify compaudit is clean, then regenerate completions without suppressing
# security checks.
print_step "checking compaudit"
REMAINING_PATHS=()
while IFS= read -r path; do
    REMAINING_PATHS+=("$path")
done < <(collect_compaudit_paths)
if [[ ${#REMAINING_PATHS[@]} -gt 0 ]]; then
    print_warning "some completion paths are still insecure:"
    printf '  %s\n' "${REMAINING_PATHS[@]}"
    print_info "fix these manually, then rerun: make fix-completions"
else
    print_success "compaudit clean"
    print_step "regenerating completions"
    zsh -f -c '
        _dump_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
        mkdir -p "$_dump_dir" 2>/dev/null || true
        autoload -Uz compinit
        compinit -d "$_dump_dir/zcompdump-${ZSH_VERSION}"
    ' 2>/dev/null || true
    print_success "completions regenerated"
fi

print_header "Done — restart your shell to apply: exec zsh"
