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
#                monitoring, sandbox-container, mosh, cmux, bosun, herdr,
#                fnm, ai-clis (cc/cx/oc wrappers + AI CLI configs)
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
# shellcheck source=scripts/lib/manifest.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/manifest.sh"
# shellcheck source=scripts/lib/migrate.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/migrate.sh"

# Is this a machine tuidev has never touched? Captured HERE, before a single
# byte is written: the profile manifest is rewritten on every run, so asking
# later always answers "yes, installed". Decides whether historical migrations
# get baselined away (fresh machine) or actually applied (upgrade).
TUIDEV_FRESH_INSTALL=false
tuidev_is_fresh_install && TUIDEV_FRESH_INSTALL=true

# Bookkeeping, not chatter: from here on, every brew install and every config
# write that goes through the shared libs appends a line to
# ~/.config/tuidev/manifest. uninstall.sh reads it to remove exactly what this
# machine got. Silent by design; nothing below prints because of it.
tuidev_manifest_enable

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
# Migrations
# ----------------------------------------------------------------------------
#
# A first install has no legacy state, so historical fixups are noise: record
# them as applied without running any. Every other run is an upgrade of an
# existing machine — `./install.sh --pack herdr` on a year-old install is the
# common case — so pending migrations actually run, before the packs write
# anything a migration might be there to repair.

_apply_install_migrations() {
    if $TUIDEV_FRESH_INSTALL; then
        local baselined
        baselined="$(tuidev_migrations_baseline)"
        if [[ "${baselined:-0}" -gt 0 ]]; then
            print_info "new install: ${baselined} migration(s) marked applied, none run"
        fi
        return 0
    fi

    [[ -z "$(tuidev_migrations_pending)" ]] && return 0

    print_header "Applying pending migrations"
    if ! tuidev_run_migrations; then
        die "migration failed — resolve it and re-run; no packs were installed"
    fi
}

_apply_install_migrations

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
        tuidev_manifest_record pack "${script%.sh}"
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
    tuidev_manifest_record pack "$name"
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

print_header "Configuring shell and editor"

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

# Bootstrap TPM (tmux plugin manager) so tmux-resurrect / tmux-continuum — the
# durability layer — actually load. Idempotent and non-fatal; only runs once
# tmux.conf is in place. Skipped under --dry-run.
_bootstrap_tmux_plugins() {
    command_exists tmux || return 0
    command_exists git  || return 0
    local tpm_dir="$HOME/.config/tmux/plugins/tpm"
    if [[ -d "$tpm_dir/.git" ]]; then
        print_success "tpm (already present)"
    else
        print_step "installing TPM (tmux plugin manager)"
        run_cmd git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir" \
            || { print_warning "tpm clone failed (continuing)"; return 0; }
    fi
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would run: $tpm_dir/bin/install_plugins"
    elif [[ -x "$tpm_dir/bin/install_plugins" ]]; then
        print_step "installing tmux plugins (resurrect, continuum)"
        "$tpm_dir/bin/install_plugins" >/dev/null 2>&1 \
            || print_warning "tmux plugin install failed (open tmux and press 'prefix + I' to retry)"
    fi
}

_install_cross_cutting "$HOME/.zshrc"                  "$TUIDEV_REPO/configs/zsh/.zshrc"                   tuidev-zshrc
_install_cross_cutting "$HOME/.config/starship.toml"   "$TUIDEV_REPO/configs/starship/starship.toml"       tuidev-starship
_install_cross_cutting "$HOME/.config/tmux/tmux.conf"  "$TUIDEV_REPO/configs/tmux/tmux.conf"               tuidev-tmux

# TPM bootstrap runs after tmux.conf is in place; tmux ships with --core.
$PACKS_CORE && _bootstrap_tmux_plugins

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
            tuidev_manifest_record dir "$nvim_dest"
            print_success "nvim (LazyVim) config installed"
        fi
    fi
fi

# AI CLI wrappers + configs live in the opt-in `--pack ai-clis` (kept out of the
# core terminal-tools bundle); they are not written here.

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
[[ "$DRY_RUN" == true ]] || mkdir -p "$HOME/.local/bin"
if [[ -f "$TUIDEV_REPO/scripts/notify.sh" ]]; then
    install_config "$HOME/.local/bin/notify.sh" "$TUIDEV_REPO/scripts/notify.sh" \
        --overwrite
    [[ "$DRY_RUN" == true ]] || chmod +x "$HOME/.local/bin/notify.sh"
fi

# --- Default shell ---
# chsh authenticates through PAM. Run where it cannot succeed — no TTY, or a
# PAM stack that won't authenticate the user — it emits a bare "Password:"
# prompt and fails, and the login shell silently stays bash (so none of the
# zshrc functions load on login). Attempt it only when it has a chance, and
# otherwise hand the user the exact command.
if [[ "$SHELL" != *zsh ]] && command_exists zsh; then
    zsh_path="$(command -v zsh)"
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would set default shell to zsh"
    elif ! command_exists chsh; then
        print_warning "chsh is not installed; set your login shell manually:"
        print_info "    chsh -s $zsh_path"
    elif [[ -f /etc/shells ]] && ! grep -qxF "$zsh_path" /etc/shells; then
        # chsh refuses any shell missing from /etc/shells (common for a
        # brew-installed zsh on Linux).
        print_warning "$zsh_path is not listed in /etc/shells; leaving your login shell alone."
        print_info "To switch manually:"
        print_info "    echo '$zsh_path' | sudo tee -a /etc/shells"
        print_info "    chsh -s $zsh_path"
    elif [[ "$(id -u)" -eq 0 ]] || [[ -t 0 ]]; then
        # root is never prompted; anyone else needs a terminal to answer PAM.
        print_step "setting default shell to zsh"
        if ! chsh -s "$zsh_path"; then
            print_warning "could not change default shell (chsh failed)."
            print_info "Run this yourself when convenient:"
            print_info "    chsh -s $zsh_path"
        fi
    else
        print_info "not changing your login shell: chsh needs a terminal for its password prompt."
        print_info "Run this yourself:"
        print_info "    chsh -s $zsh_path"
    fi
fi

# ----------------------------------------------------------------------------
# Default theme
# ----------------------------------------------------------------------------
# The shipped starship config selects palette "tuidev", but the palette table
# itself is written by scripts/theme.sh. Without this step every prompt warns
# "Could not find color palette: tuidev" until a theme is applied. Respect an
# already-chosen theme; only seed the default on machines with no theme state.
if [[ "$DRY_RUN" != true && ! -f "$HOME/.config/tuidev/theme" ]]; then
    if ! "$TUIDEV_REPO/scripts/theme.sh" apply tokyo-night; then
        print_warning "could not apply the default theme; run: make theme NAME=tokyo-night"
    fi
fi

# ----------------------------------------------------------------------------
# Profile manifest
# ----------------------------------------------------------------------------

if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$HOME/.config/tuidev"
    # Installs are additive: merge with any existing profile record so a
    # pack-only run (./install.sh --pack NAME) doesn't erase what earlier
    # runs installed. Groups only ever flip to true; extra_packs is a union;
    # the profile name is kept unless --profile was passed this run.
    MERGED_PACKS="${EXTRA_PACKS[*]}"
    if [[ -f "$HOME/.config/tuidev/profile" ]]; then
        while IFS='=' read -r _k _v; do
            case "$_k" in
                profile) [[ -z "$PROFILE" && "$_v" != custom ]] && PROFILE="$_v" ;;
                core)    [[ "$_v" == true ]] && PACKS_CORE=true ;;
                remote)  [[ "$_v" == true ]] && PACKS_REMOTE=true ;;
                sandbox) [[ "$_v" == true ]] && PACKS_SANDBOX=true ;;
                ui)      [[ "$_v" == true ]] && PACKS_UI=true ;;
                extras)  [[ "$_v" == true ]] && PACKS_EXTRAS=true ;;
                extra_packs)
                    for _p in $_v; do
                        case " $MERGED_PACKS " in
                            *" $_p "*) ;;
                            *) MERGED_PACKS="${MERGED_PACKS:+$MERGED_PACKS }$_p" ;;
                        esac
                    done ;;
            esac
        done < "$HOME/.config/tuidev/profile"
    fi
    {
        echo "profile=${PROFILE:-custom}"
        echo "core=$PACKS_CORE"
        echo "remote=$PACKS_REMOTE"
        echo "sandbox=$PACKS_SANDBOX"
        echo "ui=$PACKS_UI"
        echo "extras=$PACKS_EXTRAS"
        echo "extra_packs=$MERGED_PACKS"
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

    tuidev_manifest_record profile "${PROFILE:-custom}"
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
                          ${YELLOW}ai${NC}                  (nvim | 2 work panes)
  3. AI CLIs (opt-in):    ${YELLOW}./install.sh --pack ai-clis${NC}  (cc/cx/oc + sbx routing)
  4. Verify health:       ${YELLOW}make check${NC}

${CYAN}Docs:${NC}
  docs/profiles.md         what each profile installs
  docs/sandboxing.md       Seatbelt details and escape hatches
  docs/remote.md           Tailscale + tmux + mosh workflow
  docs/agent-workflows.md  AI CLIs, Herdr, remote control, cmux, bosun

${CYAN}Your profile manifest:${NC} ~/.config/tuidev/profile
${CYAN}What was installed:${NC}    ~/.config/tuidev/manifest  (read by ./uninstall.sh)
EOF
