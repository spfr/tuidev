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
#   remote    → core + remote + sandbox + --pack tmux   (headless/Tailscale node)
#
# Packs (compose your own):
#   --core       the shell for agent CLIs (ripgrep, fd, fzf, starship, delta, ...)
#   --remote     tailscale + mosh + SSH config
#   --sandbox    Seatbelt profiles + sbx wrapper (macOS only)
#   --ui         GUI apps: Ghostty, Rectangle, Stats, Maccy, Hidden Bar
#                (macOS only)
#   --extras     lazygit, httpie, atuin, dust, broot, hyperfine, tokei, ...
#
#   --pack NAME  optional pack (repeatable): ai-clis (Claude Code + Codex
#                configs, native sandboxes on), opencode, nvim (Neovim +
#                LazyVim), tmux (durable sessions + TPM), herdr, cmux,
#                sandbox-container, mosh, fnm, monitoring
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
# shellcheck source=scripts/lib/gitconfig.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/gitconfig.sh"
# shellcheck source=scripts/lib/migrate.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/migrate.sh"
# shellcheck source=scripts/lib/packs.sh disable=SC1091
. "$TUIDEV_REPO/scripts/lib/packs.sh"

# Is this a machine tuidev has never touched? Captured HERE, before a single
# byte is written: the profile manifest is rewritten on every run, so asking
# later always answers "yes, installed". Decides whether historical migrations
# get baselined away (fresh machine) or actually applied (upgrade).
TUIDEV_FRESH_INSTALL=false
# shellcheck disable=SC2119  # STATE_DIR arg is optional; the default is wanted
tuidev_is_fresh_install && TUIDEV_FRESH_INSTALL=true

# Bookkeeping, not chatter: from here on, every package install and every
# config write that goes through the shared libs appends a line to
# $TUIDEV_STATE_DIR/manifest. uninstall.sh reads it to remove exactly what this
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

usage() { sed -n '2,40p' "$0"; }

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
    remote)  PACKS_CORE=true; PACKS_REMOTE=true; PACKS_SANDBOX=true
             # Durable sessions are what a remote node is for (--pack tmux).
             case " ${EXTRA_PACKS[*]} " in *" tmux "*) ;; *) EXTRA_PACKS+=(tmux) ;; esac
             ;;
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

# Reject a mistyped pack name up front, not halfway through the install.
for pack in "${EXTRA_PACKS[@]}"; do
    tuidev_is_valid_pack "$pack" \
        || die "unknown --pack: $pack  (valid: ${TUIDEV_VALID_PACKS[*]})"
done

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
        print_info "Packages will be skipped with a warning; configs are still written."
    else
        print_info "no Homebrew: packages come from apt-get/dnf/pacman (root or passwordless sudo)."
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
    # shellcheck disable=SC2119  # --list arg is optional; a real run is wanted
    if ! tuidev_run_migrations; then
        die "migration failed — resolve it and re-run; no packs were installed"
    fi
}

_apply_install_migrations

# ----------------------------------------------------------------------------
# Pack dispatch
# ----------------------------------------------------------------------------

# Source the pack, run its entrypoint, record it (scripts/lib/packs.sh).
_run_pack() {
    pack_run "$1"
    tuidev_manifest_record pack "$1"
}

$PACKS_CORE    && _run_pack core
$PACKS_REMOTE  && _run_pack remote
$PACKS_SANDBOX && _run_pack sandbox
$PACKS_UI      && _run_pack ui
$PACKS_EXTRAS  && _run_pack extras

for pack in "${EXTRA_PACKS[@]}"; do
    _run_pack "$pack"
done

# ----------------------------------------------------------------------------
# Cross-cutting configuration files
# ----------------------------------------------------------------------------
#
# These are written here (not in packs) because they span multiple packs
# or are fundamental to the shell experience. Packs install *tools*; this
# section writes *settings*.

print_header "Configuring the shell"

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

# tmux.conf (and TPM) belong to `--pack tmux`, Neovim's config to `--pack nvim`,
# and the Claude Code / Codex configs to `--pack ai-clis`; none is written here.

# --- Git defaults ---

tuidev_git_defaults

# --- Local bin helpers ---
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
if [[ "$DRY_RUN" != true && ! -f "$TUIDEV_STATE_DIR/theme" ]]; then
    if ! "$TUIDEV_REPO/scripts/theme.sh" apply tokyo-night; then
        print_warning "could not apply the default theme; run: make theme NAME=tokyo-night"
    fi
fi

# ----------------------------------------------------------------------------
# Profile manifest
# ----------------------------------------------------------------------------

# Installs are additive: merge with any existing record so a pack-only run
# (./install.sh --pack NAME) doesn't erase what earlier runs installed. Groups
# only ever flip to true; extra_packs is a union; the recorded profile name is
# kept unless --profile was passed this run.
# shellcheck disable=SC2034  # profile.sh globals, read by tuidev_profile_write
_write_profile() {
    load_tuidev_profile || true   # resets the globals when there is no record
    TUIDEV_PROFILE_NAME="${PROFILE:-${TUIDEV_PROFILE_NAME:-custom}}"
    $PACKS_CORE    && TUIDEV_PACK_CORE=true
    $PACKS_REMOTE  && TUIDEV_PACK_REMOTE=true
    $PACKS_SANDBOX && TUIDEV_PACK_SANDBOX=true
    $PACKS_UI      && TUIDEV_PACK_UI=true
    $PACKS_EXTRAS  && TUIDEV_PACK_EXTRAS=true
    local p
    for p in "${EXTRA_PACKS[@]}"; do
        case " $TUIDEV_EXTRA_PACKS " in
            *" $p "*) ;;
            *) TUIDEV_EXTRA_PACKS="${TUIDEV_EXTRA_PACKS:+$TUIDEV_EXTRA_PACKS }$p" ;;
        esac
    done
    TUIDEV_PROFILE_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    TUIDEV_PROFILE_REPO="$TUIDEV_REPO"
    tuidev_profile_write
    print_success "profile manifest written: $TUIDEV_PROFILE_FILE_DEFAULT"
}

# Shell-sourceable env file: the zsh helpers (tui-update, …) read this to
# locate the repo.
_write_env() {
    {
        echo "# Auto-generated by install.sh — do not edit by hand."
        echo "export TUIDEV_REPO=\"$TUIDEV_REPO\""
        echo "export TUIDEV_PROFILE=\"$TUIDEV_PROFILE_NAME\""
    } > "$TUIDEV_ENV_FILE_DEFAULT"
    print_success "shell env written: $TUIDEV_ENV_FILE_DEFAULT"
}

if [[ "$DRY_RUN" != true ]]; then
    _write_profile
    _write_env
    tuidev_manifest_record profile "$TUIDEV_PROFILE_NAME"
fi

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------

print_header "Installation Complete"
printf '%b\n' "${GREEN}Next steps:${NC}
  1. Restart your shell:  ${YELLOW}exec zsh -l${NC}
  2. Agent CLI configs:   ${YELLOW}./install.sh --pack ai-clis${NC}  (Claude Code + Codex, native sandboxes on)
  3. Run an agent:        ${YELLOW}claude${NC}  or  ${YELLOW}codex${NC}  in a project, next to your editor
  4. Verify health:       ${YELLOW}make check${NC}

${CYAN}Docs:${NC}
  docs/profiles.md         what each profile and pack installs
  docs/sandboxing.md       native sandboxes, sbx, escape hatches
  docs/remote.md           Tailscale + tmux + mosh workflow
  docs/agent-workflows.md  AI CLIs, editors, worktrees, Herdr, cmux

${CYAN}Your profile manifest:${NC} $TUIDEV_PROFILE_FILE_DEFAULT
${CYAN}What was installed:${NC}    $TUIDEV_MANIFEST_FILE  (read by ./uninstall.sh)"
