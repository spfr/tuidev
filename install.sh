#!/bin/bash
# ============================================================================
# tuidev installer — layered, non-destructive, profile-aware.
# ============================================================================
#
# Usage:
#   ./install.sh [--profile minimal|desktop|remote]
#                [--core] [--remote] [--sandbox] [--ui] [--extras]
#                [--pack NAME ...]
#                [--no-overwrite] [--adopt-existing]
#                [--dry-run]
#
# Profiles (select a pack set):
#   minimal   → core
#   desktop   → core + ui + sandbox          (macOS laptop/desktop default)
#   remote    → core + remote + sandbox      (headless/Tailscale node)
#
# Packs (compose your own):
#   --core       essential CLI tools (tmux, nvim, ripgrep, fd, starship, ...)
#   --remote     tailscale + mosh + SSH config
#   --sandbox    Seatbelt profiles + sbx wrapper (macOS only)
#   --ui         GUI apps: Ghostty, Rectangle, Stats, Maccy, Hidden Bar,
#                Hammerspoon (macOS only)
#   --extras     atuin, dust, broot, bandwhich, duf, hyperfine, tokei, ...
#
#   --pack NAME  optional pack (repeatable): zellij, yazi, nnn,
#                monitoring, sandbox-container, mosh
#
# Config write policy:
#   By default, tuidev writes managed blocks into your shell config files
#   wrapped in '# >>> tuidev managed (ID) >>>' markers; content outside
#   the block is preserved. Use --no-overwrite to leave existing files
#   untouched entirely.
#
# Dry run:
#   --dry-run prints every mutating command without executing. Safe to
#   run on any machine to preview the changes.
# ============================================================================

set -eo pipefail

# TUIDEV_REPO: canonical repo-root path. Use this (not SCRIPT_DIR) in the
# dispatcher — sourced pack scripts overwrite SCRIPT_DIR with their own
# directory.
TUIDEV_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ui.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/ui.sh"
# shellcheck source=scripts/lib/config_write.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/config_write.sh"

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------

PROFILE=""
PACKS_CORE=false
PACKS_REMOTE=false
PACKS_SANDBOX=false
PACKS_UI=false
PACKS_EXTRAS=false
EXTRA_PACKS=()
WRITE_MODE="managed-block"   # or "adopt-existing"

usage() { sed -n '2,38p' "$0"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)         PROFILE="$2"; shift 2 ;;
        --core)            PACKS_CORE=true; shift ;;
        --remote)          PACKS_REMOTE=true; shift ;;
        --sandbox)         PACKS_SANDBOX=true; shift ;;
        --ui)              PACKS_UI=true; shift ;;
        --extras)          PACKS_EXTRAS=true; shift ;;
        --pack)            EXTRA_PACKS+=("$2"); shift 2 ;;
        --no-overwrite|--adopt-existing)
                           WRITE_MODE="adopt-existing"; shift ;;
        --dry-run|-d)      DRY_RUN=true; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 die "unknown flag: $1  (try --help)" ;;
    esac
done

# Profile → pack-flag resolution. Profile is a convenience, not a wall.
case "$PROFILE" in
    minimal) PACKS_CORE=true ;;
    desktop) PACKS_CORE=true; PACKS_UI=true; PACKS_SANDBOX=true ;;
    remote)  PACKS_CORE=true; PACKS_REMOTE=true; PACKS_SANDBOX=true ;;
    "")      # no profile — require at least one explicit pack flag
             if ! $PACKS_CORE && ! $PACKS_REMOTE && ! $PACKS_SANDBOX \
                && ! $PACKS_UI && ! $PACKS_EXTRAS && [[ ${#EXTRA_PACKS[@]} -eq 0 ]]; then
                 if is_macos; then
                     print_info "no flags given — defaulting to --profile desktop"
                     PROFILE="desktop"
                     PACKS_CORE=true; PACKS_UI=true; PACKS_SANDBOX=true
                 else
                     print_info "no flags given — defaulting to --profile minimal"
                     PROFILE="minimal"
                     PACKS_CORE=true
                 fi
             fi
             ;;
    *) die "unknown profile: $PROFILE  (use minimal|desktop|remote)" ;;
esac

# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------

print_header "tuidev installer"

if $PACKS_UI && ! is_macos; then
    print_warning "--ui is macOS-only; skipping on $(uname)"
    PACKS_UI=false
fi

if ! command_exists brew; then
    if is_macos; then
        print_warning "Homebrew not found. Install from https://brew.sh first."
        print_info "Some packs will fail without brew. Continuing in preview mode."
    else
        print_warning "Homebrew recommended on Linux for parity; skipping-unfriendly tools will warn."
    fi
fi

print_info "profile:  ${PROFILE:-custom}"
print_info "packs:    core=$PACKS_CORE remote=$PACKS_REMOTE sandbox=$PACKS_SANDBOX ui=$PACKS_UI extras=$PACKS_EXTRAS"
[[ ${#EXTRA_PACKS[@]} -gt 0 ]] && print_info "--pack:   ${EXTRA_PACKS[*]}"
print_info "write:    $WRITE_MODE"
print_info "dry-run:  $DRY_RUN"

# ----------------------------------------------------------------------------
# Pack dispatch
# ----------------------------------------------------------------------------

run_pack() {
    local script="$1"
    local fn="$2"
    if [[ -f "$TUIDEV_REPO/scripts/install/$script" ]]; then
        # shellcheck disable=SC1090
        . "$TUIDEV_REPO/scripts/install/$script"
        "$fn"
    else
        print_warning "pack missing: scripts/install/$script"
    fi
}

run_optional_pack() {
    local name="$1"
    local script="packs/$name.sh"
    local fn="${name//-/_}_install"
    [[ -f "$TUIDEV_REPO/scripts/install/$script" ]] \
        || die "unknown --pack: $name  (no scripts/install/$script)"
    # shellcheck disable=SC1090
    . "$TUIDEV_REPO/scripts/install/$script"
    "$fn"
}

$PACKS_CORE    && run_pack core.sh    core_install
$PACKS_REMOTE  && run_pack remote.sh  remote_install
$PACKS_SANDBOX && run_pack sandbox.sh sandbox_install
$PACKS_UI      && run_pack ui.sh      ui_install
$PACKS_EXTRAS  && run_pack extras.sh  extras_install

for pack in "${EXTRA_PACKS[@]}"; do
    run_optional_pack "$pack"
done

# ----------------------------------------------------------------------------
# Cross-cutting configuration files
# ----------------------------------------------------------------------------
#
# These are written here (not in packs) because they span multiple packs
# or are fundamental to the shell experience. Packs install *tools*; this
# section writes *settings*.

print_header "Configuring shell, editor, and AI CLI settings"

# Helper: write a cross-cutting config according to WRITE_MODE.
#   managed-block  (default) wrap repo content in tuidev managed markers.
#   adopt-existing  leave user file untouched if it exists; drop in the
#                   repo copy only when the destination is absent.
_install_cross_cutting() {
    local dest="$1" src="$2" block_id="$3"
    [[ -f "$src" ]] || return 0
    case "$WRITE_MODE" in
        adopt-existing)
            install_config "$dest" "$src" --adopt-existing
            ;;
        *)
            install_config "$dest" "$src" --managed-block "$block_id"
            ;;
    esac
}

_install_cross_cutting "$HOME/.zshrc"                  "$TUIDEV_REPO/configs/zsh/.zshrc"                   tuidev-zshrc
_install_cross_cutting "$HOME/.config/starship.toml"   "$TUIDEV_REPO/configs/starship/starship.toml"       tuidev-starship
_install_cross_cutting "$HOME/.config/tmux/tmux.conf"  "$TUIDEV_REPO/configs/tmux/tmux.conf"               tuidev-tmux

# --- Neovim (LazyVim). Non-destructive: backup-then-copy, never rm -rf.
#     Honors WRITE_MODE=adopt-existing by leaving any existing nvim config
#     completely untouched. Otherwise: skip if unchanged, else backup+copy.
if [[ -d "$TUIDEV_REPO/configs/nvim" ]] && command_exists nvim; then
    nvim_dest="$HOME/.config/nvim"
    if [[ "$WRITE_MODE" == "adopt-existing" && -d "$nvim_dest" ]]; then
        print_info "adopt-existing: leaving $nvim_dest untouched"
    elif [[ -d "$nvim_dest" ]] && diff -qr "$TUIDEV_REPO/configs/nvim" "$nvim_dest" >/dev/null 2>&1; then
        print_success "nvim config up to date (no changes)"
    else
        [[ -d "$nvim_dest" ]] && tuidev_backup "$nvim_dest" nvim >/dev/null
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY RUN] would copy configs/nvim -> $nvim_dest"
        else
            mkdir -p "$nvim_dest"
            cp -R "$TUIDEV_REPO/configs/nvim/." "$nvim_dest/"
            print_success "nvim (LazyVim) config installed"
        fi
    fi
fi

# --- AI CLI configs: adopt-existing (never clobber user customization) ---
if [[ -f "$TUIDEV_REPO/configs/claude/settings.json" ]]; then
    install_config "$HOME/.claude.json" \
        "$TUIDEV_REPO/configs/claude/settings.json" \
        --adopt-existing
fi

if [[ -f "$TUIDEV_REPO/configs/opencode/opencode.json" ]]; then
    mkdir -p "$HOME/.config/opencode"
    install_config "$HOME/.config/opencode/opencode.json" \
        "$TUIDEV_REPO/configs/opencode/opencode.json" \
        --adopt-existing
fi

if [[ -f "$TUIDEV_REPO/configs/codex/config.toml" ]]; then
    mkdir -p "$HOME/.codex"
    install_config "$HOME/.codex/config.toml" \
        "$TUIDEV_REPO/configs/codex/config.toml" \
        --adopt-existing
fi

# --- Git: delta pager (only if delta installed) ---
if command_exists delta && $PACKS_CORE; then
    print_step "configuring git with delta"
    run_cmd git config --global core.pager "delta"
    run_cmd git config --global interactive.diffFilter "delta --color-only"
    run_cmd git config --global delta.navigate "true"
    run_cmd git config --global delta.line-numbers "true"
    run_cmd git config --global delta.side-by-side "true"
    run_cmd git config --global merge.conflictstyle "diff3"
    print_success "git configured with delta"
fi

# --- Local bin for installed helpers (sbx, notify, etc.) ---
mkdir -p "$HOME/.local/bin"
if [[ -f "$TUIDEV_REPO/scripts/notify.sh" ]]; then
    install_config "$HOME/.local/bin/notify.sh" "$TUIDEV_REPO/scripts/notify.sh" \
        --overwrite
    [[ "$DRY_RUN" == true ]] || chmod +x "$HOME/.local/bin/notify.sh"
fi

# --- Default shell ---
if [[ "$SHELL" != *zsh ]] && command_exists zsh; then
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would set default shell to zsh"
    else
        print_step "setting default shell to zsh"
        chsh -s "$(command -v zsh)" || print_warning "could not change default shell"
    fi
fi

# ----------------------------------------------------------------------------
# Profile manifest
# ----------------------------------------------------------------------------

if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$HOME/.config/tuidev"
    {
        echo "profile=${PROFILE:-custom}"
        echo "core=$PACKS_CORE"
        echo "remote=$PACKS_REMOTE"
        echo "sandbox=$PACKS_SANDBOX"
        echo "ui=$PACKS_UI"
        echo "extras=$PACKS_EXTRAS"
        echo "extra_packs=${EXTRA_PACKS[*]}"
        echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "repo=$TUIDEV_REPO"
    } > "$HOME/.config/tuidev/profile"
    print_success "profile manifest written: $HOME/.config/tuidev/profile"

    # Shell-sourceable env file: the zsh wrappers read this to locate the
    # repo for tmux layout scripts, sandbox profiles, etc.
    {
        echo "# Auto-generated by install.sh — do not edit by hand."
        echo "export TUIDEV_REPO=\"$TUIDEV_REPO\""
        echo "export TUIDEV_PROFILE=\"${PROFILE:-custom}\""
    } > "$HOME/.config/tuidev/env"
    print_success "shell env written: $HOME/.config/tuidev/env"
fi

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------

print_header "Installation Complete"
cat <<EOF
${GREEN}Next steps:${NC}
  1. Restart your shell:  ${YELLOW}exec zsh -l${NC}
  2. Try a session:       ${YELLOW}work myproject${NC}     (bare tmux session)
                          ${YELLOW}dev${NC}                 (nvim | agent | runner)
                          ${YELLOW}ai${NC}                  (nvim | 2 AI agents)
  3. Sandboxed agents:    ${YELLOW}sbx -- cc${NC}           (Claude in Seatbelt)
  4. Verify health:       ${YELLOW}make check${NC}

${CYAN}Docs:${NC}
  docs/profiles.md       what each profile installs
  docs/sandboxing.md     Seatbelt details and escape hatches
  docs/remote.md         Tailscale + tmux + mosh workflow
  docs/migration.md      upgrading from the old zellij-first setup

${CYAN}Your profile manifest:${NC} ~/.config/tuidev/profile
EOF
