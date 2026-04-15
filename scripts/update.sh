#!/usr/bin/env bash
# ============================================================================
# macOS TUI Development Environment - Update Script (profile-aware)
# ============================================================================
# Reads the installer-written manifest at ~/.config/tuidev/profile and
# scopes updates (brew formulae, managed config blocks, repo pulls, sandbox
# image rebuild, security audit) to the packs that were actually installed.
#
# Usage:
#   ./scripts/update.sh                    # interactive menu
#   ./scripts/update.sh --check            # preview only
#   ./scripts/update.sh --packages         # upgrade brew formulae for active packs
#   ./scripts/update.sh --configs          # re-apply managed blocks + pack configs
#   ./scripts/update.sh --repo             # git pull the repo
#   ./scripts/update.sh --sandbox-image    # rebuild agent-sandbox image
#   ./scripts/update.sh --security         # security audit (tailscale/ssh/seatbelt)
#   ./scripts/update.sh --all              # packages + configs + repo
#   ./scripts/update.sh --dry-run          # preview any of the above
#
# The tui-update / tui-check shell helpers just exec this script, so every
# flag combination reachable here is reachable from zsh as well.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ----------------------------------------------------------------------------
# Shared libraries. ui.sh provides print_*, run_cmd, command_exists, etc.
# config_write.sh provides managed-block helpers. profile.sh parses the
# installer manifest.
# ----------------------------------------------------------------------------

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/lib/config_write.sh"
# shellcheck source=lib/profile.sh disable=SC1091
. "$SCRIPT_DIR/lib/profile.sh"

# print_section is a variant not defined in ui.sh; add locally.
print_section() { echo ""; echo -e "${CYAN}▶ $1${NC}"; }

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------

MODE=""              # check|packages|configs|repo|sandbox-image|security|all|menu
NON_INTERACTIVE=false

set_mode() {
    if [[ -n "$MODE" && "$MODE" != "$1" ]]; then
        print_error "Conflicting modes: --$MODE and --$1"
        exit 2
    fi
    MODE="$1"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modes (pick one; default is an interactive menu):
  --check             Preview outdated packages and config drift; mutate nothing
  --packages          brew upgrade formulae/casks belonging to active packs
  --configs           Re-apply repo managed blocks and pack-owned configs
  --repo              git pull the tuidev repo and show git-clean dry-run
  --sandbox-image     Rebuild agent-sandbox container (needs sandbox-container pack)
  --security          Audit tailscale/ssh perms/seatbelt profiles
  --all               packages + configs + repo (NOT sandbox-image, NOT security)

Options:
  --dry-run           Print commands instead of executing them (honored in every mode)
  --yes, -y           Assume yes to prompts (non-interactive)
  --help, -h          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)         set_mode check; shift ;;
        --packages|-p)      set_mode packages; shift ;;
        --configs|-C)       set_mode configs; shift ;;
        --repo|-r)          set_mode repo; shift ;;
        --sandbox-image)    set_mode sandbox-image; shift ;;
        --security)         set_mode security; shift ;;
        --all|-a)           set_mode all; NON_INTERACTIVE=true; shift ;;
        --dry-run|-d)       DRY_RUN=true; shift ;;
        --yes|-y)           NON_INTERACTIVE=true; shift ;;
        --help|-h)          usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage; exit 2 ;;
    esac
done

[[ -z "$MODE" ]] && MODE=menu

confirm() {
    if [[ "$NON_INTERACTIVE" == true ]]; then return 0; fi
    local reply
    read -r -p "  $1 (y/N) " -n 1 reply
    echo ""
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ----------------------------------------------------------------------------
# Profile manifest — delegates to scripts/lib/profile.sh for parsing.
# ----------------------------------------------------------------------------

TUIDEV_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tuidev"
PROFILE_FILE="$TUIDEV_CONFIG_DIR/profile"
ENV_FILE="$TUIDEV_CONFIG_DIR/env"

# Pack flags and names are provided by lib/profile.sh. We re-export them
# under the legacy names this file previously used, so the body of update.sh
# doesn't need a sweeping rename.
PROFILE_NAME=""
PACK_CORE=false
PACK_REMOTE=false
PACK_SANDBOX=false
PACK_UI=false
PACK_EXTRAS=false
EXTRA_PACKS=()
PROFILE_FOUND=false

load_profile() {
    if load_tuidev_profile "$PROFILE_FILE"; then
        PROFILE_NAME="$TUIDEV_PROFILE_NAME"
        PACK_CORE="$TUIDEV_PACK_CORE"
        PACK_REMOTE="$TUIDEV_PACK_REMOTE"
        PACK_SANDBOX="$TUIDEV_PACK_SANDBOX"
        PACK_UI="$TUIDEV_PACK_UI"
        PACK_EXTRAS="$TUIDEV_PACK_EXTRAS"
        EXTRA_PACKS=("${TUIDEV_EXTRA_PACKS_ARR[@]}")
        PROFILE_FOUND=true
    else
        print_warning "tuidev profile manifest not found at $PROFILE_FILE"
        print_info   "Treating as legacy install — falling back to 'update everything brew reports outdated'."
        PACK_CORE=true; PACK_REMOTE=true; PACK_SANDBOX=true
        PACK_UI=true;   PACK_EXTRAS=true
    fi

    # env file carries TUIDEV_REPO for shell-source consumers; keep sourcing it
    # here so the rest of this script sees the right repo path.
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi

    return 0
}

active_packs() {
    local packs=()
    $PACK_CORE    && packs+=("core")
    $PACK_REMOTE  && packs+=("remote")
    $PACK_SANDBOX && packs+=("sandbox")
    $PACK_UI      && packs+=("ui")
    $PACK_EXTRAS  && packs+=("extras")
    printf '%s\n' "${packs[@]}"
}

# ----------------------------------------------------------------------------
# Pack formula discovery
#
# Each pack script (scripts/install/<name>.sh) is expected to define an array
# of brew formulae. Convention (per the refactor spec) is uppercase pack name
# + `_FORMULAE`, e.g. CORE_FORMULAE, REMOTE_FORMULAE. We are defensive because
# pack scripts are being authored by sibling agents and the convention may
# slip: we sniff several plausible array names and, as a last resort, scrape
# `brew install <formula>` lines from the script.
# ----------------------------------------------------------------------------

PACK_SCRIPT_DIR="$SCRIPT_DIR/install"

# Return (on stdout) the formula names contributed by a single pack script.
# Silently emits nothing if the pack is missing.
pack_formulae() {
    local pack="$1"
    local script="$PACK_SCRIPT_DIR/${pack}.sh"
    [[ -f "$script" ]] || return 0

    # Candidate array names — keep the list generous.
    local upper
    upper="$(printf '%s' "$pack" | tr '[:lower:]' '[:upper:]')"
    local candidates=(
        "${upper}_FORMULAE"
        "${upper}_PACKAGES"
        "${upper}_BREW"
        "${upper}_BREW_FORMULAE"
        "FORMULAE"
        "PACKAGES"
    )

    # Source in a subshell so the pack script can't clobber our state.
    (
        set +u +e
        # shellcheck disable=SC1090
        source "$script" 2>/dev/null || true
        for name in "${candidates[@]}"; do
            # Bash indirect array expansion.
            local arr_ref="${name}[@]"
            if declare -p "$name" >/dev/null 2>&1; then
                printf '%s\n' "${!arr_ref}"
                exit 0
            fi
        done
        # Fallback: scrape `brew install <formula>` lines (ignore --cask taps).
        # This keeps us working even when a pack doesn't expose an array.
        grep -E 'brew install[[:space:]]+' "$script" 2>/dev/null \
            | grep -v -- '--cask' \
            | sed -E 's/.*brew install[[:space:]]+//; s/#.*$//; s/["'\'']//g' \
            | tr ' ' '\n' \
            | grep -Ev '^(--|-|$)'
    )
}

pack_casks() {
    local pack="$1"
    local script="$PACK_SCRIPT_DIR/${pack}.sh"
    [[ -f "$script" ]] || return 0

    local upper
    upper="$(printf '%s' "$pack" | tr '[:lower:]' '[:upper:]')"
    local candidates=(
        "${upper}_CASKS"
        "${upper}_BREW_CASKS"
        "CASKS"
    )
    (
        set +u +e
        # shellcheck disable=SC1090
        source "$script" 2>/dev/null || true
        for name in "${candidates[@]}"; do
            local arr_ref="${name}[@]"
            if declare -p "$name" >/dev/null 2>&1; then
                printf '%s\n' "${!arr_ref}"
                exit 0
            fi
        done
        grep -E 'brew install[[:space:]]+--cask' "$script" 2>/dev/null \
            | sed -E 's/.*--cask[[:space:]]+//; s/#.*$//; s/["'\'']//g' \
            | tr ' ' '\n' \
            | grep -Ev '^(--|-|$)'
    )
}

# Collect formulae from every enabled pack, including extras listed in the
# manifest. Deduplicated.
collect_active_formulae() {
    local all=()
    local p
    for p in $(active_packs); do
        while IFS= read -r f; do
            [[ -n "$f" ]] && all+=("$f")
        done < <(pack_formulae "$p")
    done
    # Extra packs (scripts/install/packs/<name>.sh) — best-effort.
    for p in "${EXTRA_PACKS[@]:-}"; do
        [[ -z "$p" ]] && continue
        local script="$PACK_SCRIPT_DIR/packs/${p}.sh"
        [[ -f "$script" ]] || continue
        while IFS= read -r f; do
            [[ -n "$f" ]] && all+=("$f")
        done < <(
            (
                set +u +e
                # shellcheck disable=SC1090
                source "$script" 2>/dev/null || true
                for name in FORMULAE PACKAGES; do
                    local arr_ref="${name}[@]"
                    if declare -p "$name" >/dev/null 2>&1; then
                        printf '%s\n' "${!arr_ref}"
                        exit 0
                    fi
                done
                grep -E 'brew install[[:space:]]+' "$script" 2>/dev/null \
                    | grep -v -- '--cask' \
                    | sed -E 's/.*brew install[[:space:]]+//; s/#.*$//; s/["'\'']//g' \
                    | tr ' ' '\n' \
                    | grep -Ev '^(--|-|$)'
            )
        )
    done
    printf '%s\n' "${all[@]}" | awk 'NF && !seen[$0]++'
}

collect_active_casks() {
    local all=()
    local p
    for p in $(active_packs); do
        while IFS= read -r c; do
            [[ -n "$c" ]] && all+=("$c")
        done < <(pack_casks "$p")
    done
    printf '%s\n' "${all[@]}" | awk 'NF && !seen[$0]++'
}

# ----------------------------------------------------------------------------
# Managed-block drift detection
#
# The installer writes idempotent blocks like
#     # >>> tuidev managed (ID) >>>
#     ...content...
#     # <<< tuidev managed (ID) <<<
# into user-owned dotfiles. This script compares the block in the live file
# against the source-of-truth content in the repo and reports / re-applies.
#
# The mapping below is intentionally small — cross-cutting files only. Pack
# scripts own their own files (ghostty, ssh, hammerspoon, etc.) and should
# expose an `install_config` we can re-invoke; drift for those is handled
# separately via `pack_reapply_configs`.
# ----------------------------------------------------------------------------

# Format: dest_path|source_path|block_id
# Block IDs must match exactly what install.sh writes. If this list drifts
# from install.sh's cross-cutting config section, drift detection
# misclassifies in-sync files as legacy-no-block installs.
MANAGED_BLOCKS=(
    "$HOME/.zshrc|$REPO_DIR/configs/zsh/.zshrc|tuidev-zshrc"
    "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml|$REPO_DIR/configs/starship/starship.toml|tuidev-starship"
    "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf|$REPO_DIR/configs/tmux/tmux.conf|tuidev-tmux"
)

# Best-effort "source of truth" — the entire file, modulo its own managed
# markers if any. The installer writes these source files as bare content,
# but we defer to read_managed_block when markers are present (defensive).
extract_source_block() {
    local file="$1" id="$2"
    [[ -f "$file" ]] || return 1
    if grep -qF "# >>> tuidev managed (${id})" "$file" 2>/dev/null; then
        read_managed_block "$file" "$id"
    else
        cat "$file"
    fi
}

# Prints drift report for each entry in MANAGED_BLOCKS. Populates DRIFT_ITEMS
# with entries that need re-applying and DRIFT_LEGACY with files that exist
# but have no block (→ need `make adopt`).
DRIFT_ITEMS=()
DRIFT_LEGACY=()

detect_drift() {
    DRIFT_ITEMS=()
    DRIFT_LEGACY=()

    local entry dest src id current desired diff_out
    for entry in "${MANAGED_BLOCKS[@]}"; do
        IFS='|' read -r dest src id <<<"$entry"

        if [[ ! -f "$src" ]]; then
            print_warning "Source missing, skipping drift check: $src"
            continue
        fi

        if [[ ! -f "$dest" ]]; then
            print_info "$dest (not present; pack install will create it)"
            DRIFT_ITEMS+=("$entry")
            continue
        fi

        if ! grep -q "^# >>> tuidev managed (${id})" "$dest" 2>/dev/null; then
            print_warning "$dest — no managed block found (legacy install)"
            print_info   "  run 'make adopt' to convert this file to a managed block"
            DRIFT_LEGACY+=("$entry")
            continue
        fi

        current="$(read_managed_block "$dest" "$id" 2>/dev/null || true)"
        desired="$(extract_source_block   "$src"  "$id" 2>/dev/null || true)"

        if [[ "$current" == "$desired" ]]; then
            print_success "$dest (block '$id' in sync)"
        else
            print_warning "$dest — managed block '$id' drifted:"
            diff_out="$(diff -u <(printf '%s\n' "$current") <(printf '%s\n' "$desired") || true)"
            # Indent the diff for readability.
            printf '%s\n' "$diff_out" | sed 's/^/      /'
            DRIFT_ITEMS+=("$entry")
        fi
    done
}

reapply_drift() {
    if [[ ${#DRIFT_ITEMS[@]} -eq 0 ]]; then
        print_success "Nothing to re-apply"
        return 0
    fi

    local entry dest src id content
    for entry in "${DRIFT_ITEMS[@]}"; do
        IFS='|' read -r dest src id <<<"$entry"
        content="$(extract_source_block "$src" "$id")"

        if declare -F write_managed_block >/dev/null; then
            # Use the shared helper when it's available. Signature (per brief):
            # write_managed_block <dest> <id> <content>
            run_cmd write_managed_block "$dest" "$id" "$content"
        else
            # Fallback: naive in-place rewrite that preserves surrounding text.
            reapply_drift_fallback "$dest" "$id" "$content"
        fi
        print_success "Re-applied managed block '$id' → $dest"
    done
}

reapply_drift_fallback() {
    local dest="$1" id="$2" content="$3"
    local dir; dir="$(dirname "$dest")"
    run_cmd mkdir -p "$dir"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}  [DRY RUN]${NC} would rewrite managed block '$id' in $dest"
        return 0
    fi

    local tmp; tmp="$(mktemp)"
    if [[ -f "$dest" ]] && grep -q "^# >>> tuidev managed (${id})" "$dest"; then
        awk -v id="$id" -v content="$content" '
            BEGIN {replaced=0}
            $0 ~ "^# >>> tuidev managed \\(" id "\\) >>>" {
                print
                print content
                inblk=1
                next
            }
            $0 ~ "^# <<< tuidev managed \\(" id "\\) <<<" {
                inblk=0
                print
                replaced=1
                next
            }
            !inblk {print}
        ' "$dest" >"$tmp"
    else
        {
            [[ -f "$dest" ]] && cat "$dest"
            echo ""
            echo "# >>> tuidev managed ($id) >>>"
            echo "$content"
            echo "# <<< tuidev managed ($id) <<<"
        } >"$tmp"
    fi
    mv "$tmp" "$dest"
}

# Re-run each enabled pack's main entrypoint. Packs are idempotent — brew
# installs short-circuit on "already installed" and install_config calls
# with --adopt-existing/--managed-block preserve user state — so this is
# safe to invoke on every `update --configs`.
#
# Covers both first-class packs (scripts/install/<name>.sh) and optional
# packs recorded as extra_packs in the profile manifest
# (scripts/install/packs/<name>.sh). Entrypoint convention is
# "<name_with_underscores>_install", matching install.sh's dispatcher.
pack_reapply_configs() {
    local p script fn
    for p in $(active_packs); do
        script="$PACK_SCRIPT_DIR/${p}.sh"
        [[ -f "$script" ]] || continue
        fn="${p//-/_}_install"
        (
            set +u +e
            # shellcheck disable=SC1090
            source "$script" 2>/dev/null || true
            if declare -F "$fn" >/dev/null; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "${YELLOW}  [DRY RUN]${NC} $fn (pack=$p)"
                else
                    "$fn"
                fi
            fi
        )
    done

    for p in "${EXTRA_PACKS[@]:-}"; do
        [[ -z "$p" ]] && continue
        script="$PACK_SCRIPT_DIR/packs/${p}.sh"
        [[ -f "$script" ]] || continue
        fn="${p//-/_}_install"
        (
            set +u +e
            # shellcheck disable=SC1090
            source "$script" 2>/dev/null || true
            if declare -F "$fn" >/dev/null; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "${YELLOW}  [DRY RUN]${NC} $fn (pack=$p)"
                else
                    "$fn"
                fi
            fi
        )
    done
}

# ----------------------------------------------------------------------------
# Mode: --check / --packages  (brew)
# ----------------------------------------------------------------------------

# Returns the list of outdated formulae (stdout) out of the given name list.
# Uses `brew outdated --json=v2` when jq is available for precision, falls
# back to line-match grep otherwise.
outdated_subset() {
    local -a wanted=("$@")
    (( ${#wanted[@]} == 0 )) && return 0

    if ! command -v brew >/dev/null 2>&1; then
        return 0
    fi

    local json
    if command -v jq >/dev/null 2>&1; then
        json="$(brew outdated --json=v2 2>/dev/null || true)"
        if [[ -n "$json" ]]; then
            printf '%s\n' "${wanted[@]}" \
                | jq -Rr --argjson blob "$json" '
                    . as $n
                    | $blob.formulae[]?
                    | select(.name == $n or (.full_name // "") == $n)
                    | .name
                '
            return 0
        fi
    fi

    # Fallback without jq
    local outdated_list; outdated_list="$(brew outdated --quiet 2>/dev/null || true)"
    local w
    for w in "${wanted[@]}"; do
        grep -qxF "$w" <<<"$outdated_list" && printf '%s\n' "$w"
    done
}

run_packages_mode() {
    print_section "Checking pack-scoped package updates"

    if ! command -v brew >/dev/null 2>&1; then
        print_warning "brew not found — skipping package updates"
        return 0
    fi

    run_cmd brew update --quiet || true

    local packs; packs=$(active_packs)
    if [[ -z "$packs" ]]; then
        print_warning "No active packs detected; nothing to update"
        return 0
    fi

    local total_outdated=0
    local pack name_list outdated
    for pack in $packs; do
        mapfile -t name_list < <(pack_formulae "$pack")
        if [[ ${#name_list[@]} -eq 0 ]]; then
            print_info "${pack^} updates: (no formulae discovered in scripts/install/${pack}.sh)"
            continue
        fi

        mapfile -t outdated < <(outdated_subset "${name_list[@]}")
        echo ""
        echo -e "  ${BOLD}${pack^} updates${NC} (${#name_list[@]} tracked, ${#outdated[@]} outdated):"

        if [[ ${#outdated[@]} -eq 0 ]]; then
            print_success "all up to date"
            continue
        fi

        local o
        for o in "${outdated[@]}"; do
            printf "    ${CYAN}•${NC} %s\n" "$o"
        done

        total_outdated=$((total_outdated + ${#outdated[@]}))

        if [[ "$MODE" == "check" ]]; then
            continue
        fi

        if confirm "Upgrade ${#outdated[@]} ${pack} formula(e)?"; then
            for o in "${outdated[@]}"; do
                run_cmd brew upgrade "$o" || print_warning "Failed to upgrade $o"
            done
        fi
    done

    # Extras (optional per-pack user-selected scripts).
    local extra
    for extra in "${EXTRA_PACKS[@]:-}"; do
        [[ -z "$extra" ]] && continue
        local script="$PACK_SCRIPT_DIR/packs/${extra}.sh"
        [[ -f "$script" ]] || continue
        mapfile -t name_list < <(
            (
                set +u +e
                # shellcheck disable=SC1090
                source "$script" 2>/dev/null || true
                for n in FORMULAE PACKAGES; do
                    ref="${n}[@]"
                    if declare -p "$n" >/dev/null 2>&1; then
                        printf '%s\n' "${!ref}"; exit 0
                    fi
                done
            )
        )
        (( ${#name_list[@]} == 0 )) && continue
        mapfile -t outdated < <(outdated_subset "${name_list[@]}")
        echo ""
        echo -e "  ${BOLD}Extra pack: ${extra}${NC} (${#name_list[@]} tracked, ${#outdated[@]} outdated):"
        (( ${#outdated[@]} == 0 )) && { print_success "all up to date"; continue; }
        total_outdated=$((total_outdated + ${#outdated[@]}))
        [[ "$MODE" == "check" ]] && continue
        if confirm "Upgrade ${#outdated[@]} formula(e) from extra pack '$extra'?"; then
            for o in "${outdated[@]}"; do
                run_cmd brew upgrade "$o" || print_warning "Failed to upgrade $o"
            done
        fi
    done

    echo ""
    if [[ "$MODE" == "check" ]]; then
        if [[ $total_outdated -eq 0 ]]; then
            print_success "All pack-tracked packages up to date"
        else
            print_info "${total_outdated} package(s) have updates available — run without --check to apply"
        fi
    fi
}

# ----------------------------------------------------------------------------
# Mode: --configs
# ----------------------------------------------------------------------------

run_configs_mode() {
    print_section "Checking managed-block drift"
    detect_drift

    if [[ "$MODE" == "check" ]]; then
        if [[ ${#DRIFT_LEGACY[@]} -gt 0 ]]; then
            print_warning "${#DRIFT_LEGACY[@]} file(s) need adoption (run 'make adopt')"
        fi
        if [[ ${#DRIFT_ITEMS[@]} -gt 0 ]]; then
            print_info "${#DRIFT_ITEMS[@]} managed block(s) drifted — run without --check to re-apply"
        fi
        return 0
    fi

    if [[ ${#DRIFT_ITEMS[@]} -gt 0 ]]; then
        if confirm "Re-apply ${#DRIFT_ITEMS[@]} managed block(s)?"; then
            reapply_drift
        fi
    fi

    print_section "Re-syncing pack-owned configs"
    pack_reapply_configs
    print_success "Pack configs re-applied"
}

# ----------------------------------------------------------------------------
# Mode: --repo
# ----------------------------------------------------------------------------

run_repo_mode() {
    print_section "Repository sync"

    local target="${TUIDEV_REPO:-$REPO_DIR}"
    # .git can be a directory (normal clone) or a file (worktree/submodule).
    if [[ ! -e "$target/.git" ]]; then
        print_warning "No git checkout at $target — skipping"
        return 0
    fi

    echo -e "  ${BLUE}Repo:${NC} $target"

    if [[ "$MODE" == "check" ]]; then
        run_cmd git -C "$target" fetch --quiet origin || true
        local local_sha remote_sha
        local_sha="$(git -C "$target" rev-parse HEAD 2>/dev/null || echo 0)"
        remote_sha="$(git -C "$target" rev-parse '@{u}' 2>/dev/null || echo 0)"
        if [[ "$local_sha" == "$remote_sha" ]]; then
            print_success "Repo up to date"
        else
            local behind
            behind="$(git -C "$target" rev-list --count "HEAD..@{u}" 2>/dev/null || echo '?')"
            print_warning "Repo is $behind commit(s) behind upstream"
            git -C "$target" log --oneline "HEAD..@{u}" 2>/dev/null | head -5 | sed 's/^/      /'
        fi
    else
        run_cmd git -C "$target" pull --ff-only || print_warning "Fast-forward failed — manual intervention needed"
    fi

    print_section "git clean --dry-run (untracked / ignored)"
    run_cmd git -C "$target" clean -ndx
}

# ----------------------------------------------------------------------------
# Mode: --sandbox-image
# ----------------------------------------------------------------------------

has_extra_pack() {
    local want="$1" p
    for p in "${EXTRA_PACKS[@]:-}"; do
        [[ "$p" == "$want" ]] && return 0
    done
    return 1
}

run_sandbox_image_mode() {
    print_section "Agent sandbox image"

    if ! has_extra_pack "sandbox-container"; then
        print_info "sandbox-container pack not installed — no-op"
        return 0
    fi

    if ! command -v podman >/dev/null 2>&1; then
        print_warning "podman not found — install the sandbox pack first"
        return 0
    fi

    # Image / Dockerfile path conventions — let the pack override via env.
    local image="${TUIDEV_SANDBOX_IMAGE:-agent-sandbox:latest}"
    local base="${TUIDEV_SANDBOX_BASE:-docker.io/library/ubuntu:24.04}"
    local dockerfile="${TUIDEV_SANDBOX_DOCKERFILE:-$REPO_DIR/Dockerfile}"

    if [[ "$MODE" == "check" ]]; then
        print_info "Would pull $base and rebuild $image from $dockerfile"
        return 0
    fi

    run_cmd podman pull "$base"
    if [[ -f "$dockerfile" ]]; then
        run_cmd podman build -t "$image" -f "$dockerfile" "$REPO_DIR"
    else
        print_warning "Dockerfile not found at $dockerfile — skipping rebuild"
    fi
}

# ----------------------------------------------------------------------------
# Mode: --security
# ----------------------------------------------------------------------------

check_ssh_perms() {
    local ssh_dir="$HOME/.ssh"
    [[ -d "$ssh_dir" ]] || { print_info "No $ssh_dir — skipping ssh perms check"; return 0; }

    local mode
    mode="$(stat -f '%A' "$ssh_dir" 2>/dev/null || stat -c '%a' "$ssh_dir" 2>/dev/null || echo '?')"
    if [[ "$mode" == "700" ]]; then
        print_success "$ssh_dir is 0700"
    else
        print_warning "$ssh_dir mode is $mode (expected 700)"
    fi

    local f
    while IFS= read -r -d '' f; do
        mode="$(stat -f '%A' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo '?')"
        if [[ "$mode" == "600" || "$mode" == "400" ]]; then
            print_success "$(basename "$f") is $mode"
        else
            print_warning "$f mode is $mode (expected 600)"
        fi
    done < <(find "$ssh_dir" -maxdepth 1 -type f -print0 2>/dev/null)
}

check_seatbelt_drift() {
    # Paths must match scripts/install/sandbox.sh: installed to
    # ~/.config/tuidev/sandbox/ from configs/sandbox/profiles/*.sb.
    local sb_src="$REPO_DIR/configs/sandbox/profiles"
    local sb_dest="${XDG_CONFIG_HOME:-$HOME/.config}/tuidev/sandbox"
    if [[ ! -d "$sb_src" ]]; then
        print_info "No Seatbelt profiles in repo — skipping"
        return 0
    fi
    if [[ ! -d "$sb_dest" ]]; then
        print_info "No installed Seatbelt profiles at $sb_dest — skipping"
        return 0
    fi

    local f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$sb_src"/}"
        if [[ ! -f "$sb_dest/$rel" ]]; then
            print_warning "Missing installed profile: $rel"
            continue
        fi
        if ! diff -q "$f" "$sb_dest/$rel" >/dev/null 2>&1; then
            print_warning "Seatbelt drift: $rel"
            diff -u "$sb_dest/$rel" "$f" 2>/dev/null | sed 's/^/      /'
        else
            print_success "Seatbelt $rel in sync"
        fi
    done < <(find "$sb_src" -type f -print0 2>/dev/null)
}

run_security_mode() {
    print_section "Tailscale"
    if command -v tailscale >/dev/null 2>&1; then
        run_cmd tailscale status || print_warning "tailscale status reported non-zero"
    else
        print_info "tailscale not installed — skipping"
    fi

    print_section "SSH permissions"
    check_ssh_perms

    print_section "Seatbelt profiles"
    check_seatbelt_drift
}

# ----------------------------------------------------------------------------
# Interactive menu (default when no flags given)
# ----------------------------------------------------------------------------

run_menu() {
    print_section "Select an action"
    cat <<EOF
    1) Check for updates (preview only)
    2) Update packages (active packs only)
    3) Re-apply configs (managed blocks + pack configs)
    4) Update repo (git pull)
    5) Rebuild sandbox image
    6) Security audit
    7) Update all (packages + configs + repo)
    q) Quit
EOF
    local reply
    read -r -p "  Choice: " -n 1 reply
    echo ""
    case "$reply" in
        1) MODE=check;          run_mode ;;
        2) MODE=packages;       run_mode ;;
        3) MODE=configs;        run_mode ;;
        4) MODE=repo;           run_mode ;;
        5) MODE=sandbox-image;  run_mode ;;
        6) MODE=security;       run_mode ;;
        7) MODE=all;            run_mode ;;
        q|Q|"") print_info "No action selected." ;;
        *) print_error "Unknown choice: $reply"; exit 2 ;;
    esac
}

# ----------------------------------------------------------------------------
# Dispatch
# ----------------------------------------------------------------------------

run_mode() {
    case "$MODE" in
        check)
            # In --check, we run everything in read-only mode.
            run_packages_mode
            run_configs_mode
            run_repo_mode
            ;;
        packages)      run_packages_mode ;;
        configs)       run_configs_mode ;;
        repo)          run_repo_mode ;;
        sandbox-image) run_sandbox_image_mode ;;
        security)      run_security_mode ;;
        all)
            run_packages_mode
            run_configs_mode
            run_repo_mode
            ;;
        *) print_error "Unhandled mode: $MODE"; exit 2 ;;
    esac
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

print_header "macOS TUI Environment Update"

echo -e "  ${BLUE}Repo:${NC}    $REPO_DIR"
echo -e "  ${BLUE}Date:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"
[[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}Mode:${NC}    dry-run"

load_profile || true

if $PROFILE_FOUND; then
    echo -e "  ${BLUE}Profile:${NC} ${PROFILE_NAME:-?}"
    echo -e "  ${BLUE}Packs:${NC}   $(active_packs | paste -sd, -)"
    [[ ${#EXTRA_PACKS[@]} -gt 0 ]] && echo -e "  ${BLUE}Extras:${NC}  ${EXTRA_PACKS[*]}"
fi

case "$MODE" in
    menu)
        if ! $PROFILE_FOUND; then
            print_info "No profile manifest — interactive menu treats install as legacy"
        fi
        run_menu
        ;;
    *)
        run_mode
        ;;
esac

print_header "Update Complete"
if [[ "$MODE" == "check" ]]; then
    echo -e "  Run ${CYAN}./scripts/update.sh${NC} without --check to apply updates."
else
    echo -e "  ${GREEN}Done.${NC}"
fi
echo ""
