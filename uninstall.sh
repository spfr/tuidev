#!/bin/bash
# ============================================================================
# tuidev uninstaller
# ============================================================================
#
# Cleanly removes tuidev from the host:
#   - Strips tuidev managed blocks from shell/prompt/tmux configs
#     (user content outside the blocks is preserved).
#   - Removes tuidev-installed helpers under ~/.local/bin.
#   - Removes ~/.config/tuidev/ manifest + env.
#
# When ~/.config/tuidev/manifest exists (written by install.sh), this script
# removes what that machine actually got: the managed blocks, helper files and
# brew packages recorded at install time. Installs predating the manifest fall
# back to the hardcoded lists below, which are a superset covering every pack.
#   - Optionally removes tuidev-owned configs (Ghostty, nvim, starship,
#     tmux, hammerspoon, opencode, codex, herdr) with a backup first.
#   - Optionally uninstalls the Homebrew formulae and casks installed
#     by the packs the user had enabled.
#
# Usage:
#   ./uninstall.sh              # interactive
#   ./uninstall.sh --all        # non-interactive: strip managed blocks,
#                                 remove configs, purge brew packages.
#   ./uninstall.sh --dry-run    # preview mutations

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/ui.sh"
# shellcheck source=scripts/lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/config_write.sh"
# shellcheck source=scripts/lib/manifest.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/manifest.sh"

ALL=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)     ALL=true; shift ;;
        --dry-run) export DRY_RUN=true; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *)         die "unknown flag: $1" ;;
    esac
done

ask() {
    # Usage: ask "question text" -> exports ANSWER=y|n. Respects --all.
    if $ALL; then ANSWER=y; return; fi
    local prompt="$1"
    read -r -p "$prompt (y/N) " -n 1 reply
    echo ""
    [[ $reply =~ ^[Yy]$ ]] && ANSWER=y || ANSWER=n
}

print_header "tuidev uninstaller"

# Manifest mode: remove what this machine recorded. Legacy mode: fall back to
# the hardcoded superset, which is all a pre-manifest install can tell us.
if tuidev_manifest_present; then
    MANIFEST_MODE=true
    print_info "using install manifest: $TUIDEV_MANIFEST_FILE"
    print_info "  only what this machine recorded installing will be removed"
else
    MANIFEST_MODE=false
    print_warning "no install manifest at $TUIDEV_MANIFEST_FILE"
    print_info "  (install predates the manifest, or was never completed)"
    print_info "  falling back to the built-in list of everything tuidev can install"
fi
echo ""

# Read every manifest record up front: step 3 deletes ~/.config/tuidev, and
# steps 4 and 5 still need this data afterwards. Newline-delimited strings
# rather than arrays keep this readable under the bash 3.2 macOS ships.
MANIFEST_BLOCKS=""
MANIFEST_FILES=""
MANIFEST_DIRS=""
MANIFEST_FORMULAE=""
MANIFEST_CASKS=""
if $MANIFEST_MODE; then
    MANIFEST_BLOCKS="$(tuidev_manifest_values block)"
    MANIFEST_FILES="$(tuidev_manifest_values file)"
    MANIFEST_DIRS="$(tuidev_manifest_values dir)"
    MANIFEST_FORMULAE="$(tuidev_manifest_values formula)"
    MANIFEST_CASKS="$(tuidev_manifest_values cask)"
fi

print_info "this will reverse a tuidev install:"
print_info "  - strip managed blocks from shell configs (user edits preserved)"
print_info "  - remove tuidev helpers under \$HOME/.local/bin"
print_info "  - optionally remove tuidev-owned config files (with backup)"
print_info "  - optionally purge brew formulae and casks"
echo ""

ask "continue?"
[[ "$ANSWER" == "y" ]] || { echo "cancelled."; exit 0; }

# ---------------------------------------------------------------------------
# 1. Strip managed blocks. User content outside each block is preserved.
# ---------------------------------------------------------------------------

print_header "removing tuidev managed blocks"

if [[ -n "$MANIFEST_BLOCKS" ]]; then
    # Records are `<block_id> <path>`; the id never contains a space, so the
    # path is everything after the first one — and may contain spaces itself.
    while IFS= read -r record; do
        [[ -n "$record" ]] || continue
        remove_managed_block "${record#* }" "${record%% *}"
    done <<EOF
$MANIFEST_BLOCKS
EOF
else
    remove_managed_block "$HOME/.zshrc"                 tuidev-zshrc
    remove_managed_block "$HOME/.zshrc"                 tuidev-sandbox-path
    remove_managed_block "$HOME/.config/starship.toml"  tuidev-starship
    remove_managed_block "$HOME/.config/tmux/tmux.conf" tuidev-tmux
fi

# Theme blocks (id: tuidev-theme) are stripped in BOTH modes. `scripts/theme.sh
# apply` writes them long after install, and it does not enable manifest
# recording, so they never appear in the manifest — trusting it here would leave
# them behind. remove_managed_block is a no-op when the block is absent, so a
# machine that never ran `theme.sh apply` sees nothing. The theme state file
# ~/.config/tuidev/theme goes with the rest of ~/.config/tuidev in step 3.
remove_managed_block "$HOME/.config/tmux/tmux.conf" tuidev-theme
remove_managed_block "$HOME/.config/ghostty/config" tuidev-theme
remove_managed_block "$HOME/.config/starship.toml"  tuidev-theme

# ---------------------------------------------------------------------------
# 2. Remove tuidev-placed scripts in ~/.local/bin.
# ---------------------------------------------------------------------------

print_header "removing tuidev helpers"

# Manifest `file` records cover both ~/.local/bin helpers and any config file
# installed whole (rather than as a managed block). Config files are handled in
# the opt-in section below, so only executables land here.
remove_helper() {
    local f="$1"
    if [[ -e "$f" ]]; then
        run_cmd rm -f "$f"
        [[ "$DRY_RUN" == true ]] || print_success "removed $f"
    fi
}

if $MANIFEST_MODE; then
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        case "$f" in
            "$HOME/.local/bin/"*) remove_helper "$f" ;;
        esac
    done <<EOF
$MANIFEST_FILES
EOF
else
    for f in "$HOME/.local/bin/sbx" \
             "$HOME/.local/bin/sbx-container" \
             "$HOME/.local/bin/notify.sh"; do
        remove_helper "$f"
    done
fi

# ---------------------------------------------------------------------------
# 3. Remove the tuidev manifest + env file.
# ---------------------------------------------------------------------------

if [[ -d "$HOME/.config/tuidev" ]]; then
    print_info "removing ~/.config/tuidev (manifest + env + deprecations + theme state)"
    run_cmd rm -rf "$HOME/.config/tuidev"
fi

# ---------------------------------------------------------------------------
# 4. Optional: remove tuidev-owned configs (with a timestamped backup first).
# ---------------------------------------------------------------------------

ask "also remove tuidev-owned configs (nvim, ghostty, tmux, hammerspoon, sandbox profiles, AI CLI settings)?"
if [[ "$ANSWER" == "y" ]]; then
    BACKUP="$HOME/.config-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
    run_cmd mkdir -p "$BACKUP"

    remove_config_path() {
        local path="$1"
        if [[ -e "$path" ]]; then
            run_cmd cp -R "$path" "$BACKUP/" 2>/dev/null || true
            run_cmd rm -rf "$path"
            [[ "$DRY_RUN" == true ]] || print_success "removed $path (backup in $BACKUP)"
        fi
    }

    # This step is opt-in, consented to, and backs everything up first, so it
    # uses the union of the manifest's file/dir records and the well-known
    # tuidev-owned paths. Some packs still place configs with a bare `cp` and
    # so record nothing; dropping the hardcoded list here would silently start
    # leaving those behind.
    for path in \
        "$HOME/.config/nvim" \
        "$HOME/.config/ghostty" \
        "$HOME/.config/tmux" \
        "$HOME/.config/zellij" \
        "$HOME/.config/opencode" \
        "$HOME/.config/herdr" \
        "$HOME/.config/starship.toml" \
        "$HOME/.codex" \
        "$HOME/.claude.json" \
        "$HOME/.hammerspoon"; do
        remove_config_path "$path"
    done

    if $MANIFEST_MODE; then
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            # ~/.local/bin entries were already handled as helpers above.
            case "$path" in
                "$HOME/.local/bin/"*) continue ;;
            esac
            remove_config_path "$path"
        done <<EOF
$MANIFEST_FILES
$MANIFEST_DIRS
EOF
    fi

    # Neovim state/cache — nvim reinstalls these cleanly on next launch.
    run_cmd rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
    print_success "cleared nvim state/cache"
fi

# ---------------------------------------------------------------------------
# 5. Optional: purge Homebrew formulae and casks installed by the packs.
# ---------------------------------------------------------------------------

ask "also uninstall Homebrew formulae and casks that tuidev packs installed?"
if [[ "$ANSWER" == "y" ]] && command_exists brew; then

    purge_formula() {
        if brew list --formula "$1" &>/dev/null; then
            run_cmd brew uninstall "$1" 2>/dev/null || print_warning "failed: $1"
        fi
    }
    purge_cask() {
        if brew list --cask "$1" &>/dev/null; then
            run_cmd brew uninstall --cask "$1" 2>/dev/null || print_warning "failed: $1"
        fi
    }

    if $MANIFEST_MODE; then
        # The manifest records only packages tuidev actually installed, so one
        # the user already had before tuidev is left alone.
        print_info "purging only the packages recorded in the manifest"
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            purge_formula "$f"
        done <<EOF
$MANIFEST_FORMULAE
EOF
        while IFS= read -r c; do
            [[ -n "$c" ]] || continue
            purge_cask "$c"
        done <<EOF
$MANIFEST_CASKS
EOF
    else

    # Aligned with scripts/install/*.sh. Not every user has every pack; we
    # `brew list` first so missing packages are silently skipped.
    FORMULAE=(
        # core
        bat eza fd fzf gh git git-delta jq lazygit neovim ripgrep
        shellcheck starship tmux yq zoxide
        zsh-autosuggestions zsh-completions zsh-syntax-highlighting
        # remote
        mosh
        # extras
        atuin bandwhich bottom broot dust duf fastfetch glow hyperfine
        ncdu procs sd tealdeer tokei
        # packs
        zellij yazi nnn lazydocker k9s podman fnm herdr
        # (bosun is cargo-installed, not brew; remove with: cargo uninstall bosun)
        # (herdr may instead come from https://herdr.dev/install.sh, which drops
        #  the binary in $HOME/.local/bin; then: rm -f "$HOME/.local/bin/herdr")
    )

    CASKS=(
        ghostty tailscale rectangle stats maccy hiddenbar hammerspoon cmux
    )

    for f in "${FORMULAE[@]}"; do
        purge_formula "$f"
    done

    for c in "${CASKS[@]}"; do
        purge_cask "$c"
    done
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

print_header "Uninstall complete"
cat <<EOF
${GREEN}What was removed:${NC}
  - tuidev managed blocks (from the install manifest when present, else
    ~/.zshrc, starship.toml, tmux.conf), plus any tuidev-theme blocks in
    tmux.conf, ghostty/config and starship.toml
  - tuidev helpers under ~/.local/bin (sbx, notify.sh, sbx-container)
  - ~/.config/tuidev/ (manifest, env, deprecations)
  - (optional) tuidev-owned config files, backed up to
    ~/.config-uninstall-backup-YYYYMMDD-HHMMSS/
  - (optional) brew formulae and casks

${CYAN}What was preserved:${NC}
  - Your own edits to ~/.zshrc outside the managed blocks
  - Any config file outside the paths tuidev writes to
  - Your git config, ssh keys, shell history
EOF
