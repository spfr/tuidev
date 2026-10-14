#!/bin/bash
# ============================================================================
# tuidev uninstaller
# ============================================================================
#
# Reverses a tuidev install using the manifest install.sh wrote
# ($TUIDEV_STATE_DIR/manifest, normally ~/.config/tuidev/manifest). Only what
# that manifest records is removed:
#   - managed blocks (content outside the markers is preserved), plus any
#     tuidev-theme blocks written later by scripts/theme.sh;
#   - helpers under ~/.local/bin (with the agents modules in
#     ~/.local/lib/tuidev), and global git keys tuidev set (only while
#     they still hold tuidev's value);
#   - optionally, config files tuidev created — never one it adopted, never a
#     whole CLI home, so auth and session state (~/.codex/auth.json,
#     ~/.claude/…) always survive. Each removal is backed up first;
#   - optionally, Homebrew formulae and casks tuidev installed (never one you
#     already had). apt/dnf/pacman packages are listed, not removed;
#   - tuidev's own state dir, except its backups/;
#   - the agents history (${XDG_STATE_HOME:-~/.local/state}/tuidev/agents)
#     only when you say so: a prompt that defaults to keep (never asked when
#     stdin is not a terminal), or --purge-history.
#
# Installs predating the manifest get only the safe subset: managed blocks,
# and helpers still byte-identical to the repo copy. Everything else is listed
# for you to review instead of deleted.
#
# Usage:
#   ./uninstall.sh              # interactive
#   ./uninstall.sh --all        # non-interactive: yes to every step
#   ./uninstall.sh --dry-run    # preview mutations
#   ./uninstall.sh --purge-history  # also delete the agents history, unasked

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/ui.sh"
# shellcheck source=scripts/lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/config_write.sh"
# shellcheck source=scripts/lib/manifest.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/manifest.sh"
# shellcheck source=scripts/lib/packs.sh disable=SC1091
. "$SCRIPT_DIR/scripts/lib/packs.sh"

ALL=false
PURGE_HISTORY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)     ALL=true; shift ;;
        --dry-run) export DRY_RUN=true; shift ;;
        --purge-history) PURGE_HISTORY=true; shift ;;
        -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
        *)         die "unknown flag: $1" ;;
    esac
done

# ask "question" -> sets ANSWER=y|n. --all answers yes.
ask() {
    if $ALL; then ANSWER=y; return; fi
    local reply
    read -r -p "$1 (y/N) " -n 1 reply
    echo ""
    [[ $reply =~ ^[Yy]$ ]] && ANSWER=y || ANSWER=n
}

# done_msg MSG — report a completed mutation; run_cmd already echoed it in a
# dry run.
done_msg() { [[ "$DRY_RUN" == true ]] || print_success "$1"; }

# each_line TEXT FN — call FN once per non-empty line of TEXT.
each_line() {
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && "$2" "$line"
    done <<EOF
$1
EOF
    return 0
}

print_header "tuidev uninstaller"

if tuidev_manifest_present; then
    MANIFEST_MODE=true
    print_info "using install manifest: $TUIDEV_MANIFEST_FILE"
    print_info "  only what this machine recorded installing will be removed"
else
    MANIFEST_MODE=false
    print_warning "no install manifest at $TUIDEV_MANIFEST_FILE"
    print_info "  (install predates the manifest, or was never completed)"
    print_info "  only managed blocks and unmodified tuidev helpers will be removed;"
    print_info "  everything else is listed for you to review"
fi
echo ""

# Read every record up front: the last step removes the manifest itself.
# Newline-delimited strings keep this bash 3.2-clean.
M_BLOCKS="$(tuidev_manifest_values block)"
M_FILES="$(tuidev_manifest_values file)"
M_DIRS="$(tuidev_manifest_values dir)"
M_GIT="$(tuidev_manifest_values gitconfig)"
M_FORMULAE="$(tuidev_manifest_values formula)"
M_CASKS="$(tuidev_manifest_values cask)"

ask "continue?"
[[ "$ANSWER" == "y" ]] || { echo "cancelled."; exit 0; }

# ---------------------------------------------------------------------------
# 1. Managed blocks and git keys — surgical, so never optional.
# ---------------------------------------------------------------------------

print_header "removing tuidev managed blocks and settings"

# Records are `<block_id> <path>`; the id has no spaces, the path may.
_remove_block_record() { remove_managed_block "${1#* }" "${1%% *}"; }

if $MANIFEST_MODE; then
    each_line "$M_BLOCKS" _remove_block_record
else
    remove_managed_block "$HOME/.zshrc"                 tuidev-zshrc
    remove_managed_block "$HOME/.zshrc"                 tuidev-sandbox-path
    remove_managed_block "$HOME/.config/starship.toml"  tuidev-starship
    remove_managed_block "$HOME/.config/tmux/tmux.conf" tuidev-tmux
fi

# Theme blocks are stripped in both modes: scripts/theme.sh writes them after
# install without manifest recording. A no-op where they are absent.
remove_managed_block "$HOME/.config/tmux/tmux.conf" tuidev-theme
remove_managed_block "$HOME/.config/tmux/theme.conf" tuidev-theme
remove_managed_block "$HOME/.config/ghostty/config" tuidev-theme
remove_managed_block "$HOME/.config/starship.toml"  tuidev-theme

# Records are `<key> <value>`. A key the user has since changed is theirs now.
# Install checked with --includes (is the key set anywhere the user's global
# config reaches?); this check deliberately reads without includes, because
# `--unset` edits only the global file itself: remove our line when that file
# still holds exactly what we wrote, whatever an included file says.
_unset_git_record() {
    local key="${1%% *}" value="${1#* }"
    command_exists git || return 0
    [[ "$(git config --global --no-includes --get "$key" 2>/dev/null)" == "$value" ]] || return 0
    run_cmd git config --global --unset "$key"
    done_msg "unset git $key"
}
each_line "$M_GIT" _unset_git_record

# ---------------------------------------------------------------------------
# 2. Helpers in ~/.local/bin, and the modules agents loads.
# ---------------------------------------------------------------------------

print_header "removing tuidev helpers"

# Release a keep-awake hold `agents` started before the helper goes away.
if [[ -x "$HOME/.local/bin/agents" ]]; then
    run_cmd "$HOME/.local/bin/agents" awake off || true
fi

_remove_helper() {
    case "$1" in "$HOME/.local/bin/"*|"$TUIDEV_LIB_DIR/"*) ;; *) return 0 ;; esac
    [[ -e "$1" || -L "$1" ]] || return 0
    run_cmd rm -f "$1"
    done_msg "removed $1"
}

# The module directories, once their files are gone (only empty ones).
_remove_lib_dirs() {
    local d
    [[ "$DRY_RUN" != true ]] || return 0
    for d in "$TUIDEV_LIB_DIR/agents/awk" "$TUIDEV_LIB_DIR/agents" "$TUIDEV_LIB_DIR"; do
        [[ -d "$d" ]] && rmdir "$d" 2>/dev/null && done_msg "removed $d"
    done
    return 0
}

# _remove_if_ours FILE REPO_COPY — without a record, remove FILE only while it
# is still exactly the repo's copy.
_remove_if_ours() {
    if [[ -f "$1" ]] && cmp -s "$1" "$2"; then
        _remove_helper "$1"
    elif [[ -e "$1" ]]; then
        print_info "kept $1 (differs from the repo copy — review it yourself)"
    fi
}

if $MANIFEST_MODE; then
    each_line "$M_FILES" _remove_helper
else
    # Without a record, remove a helper only if it is still exactly ours.
    for pair in "sbx:bin/sbx" "notify.sh:scripts/notify.sh" "agents:bin/agents"; do
        _remove_if_ours "$HOME/.local/bin/${pair%%:*}" "$SCRIPT_DIR/${pair#*:}"
    done
    while IFS= read -r src; do
        _remove_if_ours "$TUIDEV_LIB_DIR/agents/${src#"$SCRIPT_DIR/lib/agents/"}" "$src"
    done < <(find "$SCRIPT_DIR/lib/agents" -type f | LC_ALL=C sort)
fi
_remove_lib_dirs

# The SwiftBar plugin only calls `agents`, so it goes with it: left behind, it
# would show "not on PATH" on every refresh.
_remove_swiftbar_plugin() {
    case "${1##*/}" in agents.*.sh) ;; *) return 0 ;; esac
    [[ -f "$1" ]] && grep -q 'agents' "$1" 2>/dev/null || return 0
    run_cmd rm -f "$1"
    done_msg "removed $1"
}
swiftbar_dir="${XDG_CONFIG_HOME:-$HOME/.config}/swiftbar/plugins"
if $MANIFEST_MODE; then
    each_line "$M_FILES" _remove_swiftbar_plugin
else
    for f in "$swiftbar_dir"/agents.*.sh; do
        [[ -f "$f" ]] && cmp -s "$f" "$SCRIPT_DIR/configs/swiftbar/agents.10s.sh" && _remove_swiftbar_plugin "$f"
    done
fi
# Unset SwiftBar's plugin folder only if it is still ours and now empty.
if is_macos && [[ "$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null)" == "$swiftbar_dir" ]] \
   && [[ -z "$(ls -A "$swiftbar_dir" 2>/dev/null)" ]]; then
    run_cmd defaults delete com.ameba.SwiftBar PluginDirectory
    done_msg "reset SwiftBar's plugin folder"
fi

# ---------------------------------------------------------------------------
# 3. Optional: config files tuidev created (backed up first).
# ---------------------------------------------------------------------------

# Backups go to TUIDEV_BACKUP_DIR, which step 5 keeps. The prefix encodes the
# full path so two same-named files (~/.codex/config.toml,
# ~/.config/herdr/config.toml) never share a backup slot.
_remove_config_path() {
    local path="$1"
    case "$path" in
        "$HOME/.local/bin/"*|"$TUIDEV_LIB_DIR/"*|"$TUIDEV_STATE_DIR"/*) return 0 ;;   # steps 2 and 5
    esac
    [[ -e "$path" ]] || return 0
    local rel="${path#"$HOME"/}"
    tuidev_backup "$path" "uninstall-$(printf '%s' "$rel" | tr '/' '_')" >/dev/null
    run_cmd rm -rf "$path"
    done_msg "removed $path"
}

ask "also remove config files tuidev created (nvim, ghostty, AI CLI settings, …)?"
if [[ "$ANSWER" == "y" ]]; then
    if $MANIFEST_MODE; then
        each_line "$M_FILES" _remove_config_path
        each_line "$M_DIRS"  _remove_config_path
        # LazyVim's plugin/state cache exists only because tuidev placed the
        # config; nvim rebuilds it on next launch.
        if tuidev_manifest_has dir "$HOME/.config/nvim" \
           || tuidev_manifest_has file "$HOME/.config/nvim/init.lua"; then
            run_cmd rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
            done_msg "cleared nvim state/cache"
        fi
    else
        print_info "no manifest, so nothing is deleted. Paths tuidev may have written:"
        for path in "$HOME/.config/nvim" "$HOME/.config/ghostty/config" \
                    "$HOME/.hammerspoon/init.lua" "$HOME/.claude/settings.json" \
                    "$HOME/.codex/config.toml" "$HOME/.config/opencode" \
                    "$HOME/.config/herdr/config.toml" "$HOME/.config/agents.conf"; do
            [[ -e "$path" ]] && print_info "    $path"
        done
    fi
fi

# ---------------------------------------------------------------------------
# 4. Optional: packages.
# ---------------------------------------------------------------------------

_purge_formula() {
    brew list --formula "$1" >/dev/null 2>&1 || return 0
    run_cmd brew uninstall "$1" || print_warning "failed: $1"
}
_purge_cask() {
    brew list --cask "$1" >/dev/null 2>&1 || return 0
    run_cmd brew uninstall --cask "$1" || print_warning "failed: $1"
}

# System packages need root; list them rather than escalate on our own.
_print_system_packages() {
    local mgr pkgs cmd
    for mgr in apt dnf pacman; do
        pkgs="$(tuidev_manifest_values "$mgr" | tr '\n' ' ')"
        [[ -n "${pkgs// /}" ]] || continue
        case "$mgr" in
            apt)    cmd="sudo apt-get remove" ;;
            dnf)    cmd="sudo dnf remove" ;;
            pacman) cmd="sudo pacman -R" ;;
        esac
        print_info "installed via $mgr — remove them yourself if you like:"
        print_info "    $cmd ${pkgs% }"
    done
}

# No manifest: offer (never run) a brew command for the pack packages that
# happen to be installed — they may well predate tuidev.
_print_legacy_brew_candidates() {
    local pack item formulae="" casks=""
    for pack in "${TUIDEV_BUILTIN_PACKS[@]}" "${TUIDEV_VALID_PACKS[@]}"; do
        while IFS= read -r item; do
            case "$formulae " in *" $item "*) continue ;; esac   # mosh is in two packs
            brew list --formula "$item" >/dev/null 2>&1 && formulae="$formulae $item"
        done < <(pack_array "$pack" formulae)
        while IFS= read -r item; do
            brew list --cask "$item" >/dev/null 2>&1 && casks="$casks $item"
        done < <(pack_array "$pack" casks)
    done
    print_info "no manifest, so no package is removed. Installed packages tuidev packs use"
    print_info "(some may predate tuidev — keep what you use):"
    [[ -n "$formulae" ]] && print_info "    brew uninstall$formulae"
    [[ -n "$casks" ]]    && print_info "    brew uninstall --cask$casks"
    return 0
}

ask "also uninstall the Homebrew formulae and casks tuidev installed?"
if [[ "$ANSWER" == "y" ]]; then
    if ! command_exists brew; then
        print_info "Homebrew not found — nothing to purge"
    elif $MANIFEST_MODE; then
        print_info "purging only the packages recorded in the manifest"
        each_line "$M_FORMULAE" _purge_formula
        each_line "$M_CASKS"    _purge_cask
    else
        _print_legacy_brew_candidates
    fi
    _print_system_packages
fi

# ---------------------------------------------------------------------------
# 5. tuidev's own state — everything but backups/.
# ---------------------------------------------------------------------------

if [[ -d "$TUIDEV_STATE_DIR" ]]; then
    print_info "removing $TUIDEV_STATE_DIR (profile, manifest, env, theme, …) — keeping backups/"
    for entry in "$TUIDEV_STATE_DIR"/* "$TUIDEV_STATE_DIR"/.[!.]*; do
        [[ -e "$entry" && "$entry" != "$TUIDEV_BACKUP_DIR" ]] || continue
        run_cmd rm -rf "$entry"
    done
    [[ "$DRY_RUN" == true ]] || rmdir "$TUIDEV_STATE_DIR" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 6. Optional: the agents history (data, so kept unless you say otherwise).
# ---------------------------------------------------------------------------

# Only this one directory, only inside $HOME, and never through a symlink.
# --all does not imply it: the history is yours, not tuidev's config.
_purge_agents_history() {
    local dir="${XDG_STATE_HOME:-$HOME/.local/state}/tuidev/agents" real home purge=$PURGE_HISTORY reply
    [[ -d "$dir" || -L "$dir" ]] || return 0
    if [[ -L "$dir" ]]; then
        print_warning "kept $dir (a symlink: remove it yourself if you like)"; return 0
    fi
    real="$(cd -P "$dir" 2>/dev/null && pwd -P)" || return 0
    home="$(cd -P "$HOME" 2>/dev/null && pwd -P)" || return 0
    case "$real" in
        "$home"/?*/tuidev/agents) ;;
        *) print_warning "kept $dir (resolves outside $HOME)"; return 0 ;;
    esac
    if ! $purge && [[ -t 0 ]]; then
        read -r -p "also delete the agents history in $dir? (y/N) " -n 1 reply
        echo ""
        [[ $reply =~ ^[Yy]$ ]] && purge=true
    fi
    if ! $purge; then
        print_info "kept the agents history: $dir (--purge-history deletes it)"
        return 0
    fi
    run_cmd rm -rf "$real"
    [[ "$DRY_RUN" == true ]] || rmdir "${real%/*}" 2>/dev/null || true
    done_msg "removed the agents history: $dir"
}
_purge_agents_history

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

print_header "Uninstall complete"
printf '%b\n' "${GREEN}What was removed:${NC}
  - tuidev managed blocks and the global git keys tuidev set (if unchanged)
  - tuidev helpers under ~/.local/bin, and the agents modules in ~/.local/lib/tuidev
  - $TUIDEV_STATE_DIR (profile, manifest, env, theme state)
  - (optional) config files tuidev created, and the brew packages it installed

${CYAN}What was preserved:${NC}
  - Backups of everything removed or overwritten: $TUIDEV_BACKUP_DIR
  - Your own edits outside the managed blocks, and any config tuidev adopted
  - CLI auth and session state, your git config, ssh keys, shell history
  - The agents history, unless you chose to delete it"
