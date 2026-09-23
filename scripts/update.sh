#!/usr/bin/env bash
# ============================================================================
# macOS TUI Development Environment - Update Script (profile-aware)
# ============================================================================
# Reads the installer-written profile ($TUIDEV_STATE_DIR/profile, normally
# ~/.config/tuidev/profile) and scopes updates (brew formulae, managed config
# blocks, repo pulls, security audit) to the packs that were actually installed.
# bash 3.2-clean: runs under the /bin/bash macOS ships.
#
# Usage:
#   ./scripts/update.sh                    # interactive menu
#   ./scripts/update.sh --check            # preview only
#   ./scripts/update.sh --packages         # upgrade brew formulae for active packs
#   ./scripts/update.sh --configs          # re-apply managed blocks + pack configs
#   ./scripts/update.sh --migrations       # run pending one-shot migrations
#   ./scripts/update.sh --repo             # git pull the repo
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
# Shared libraries. ui.sh: print_*, run_cmd, TUIDEV_STATE_DIR. config_write.sh:
# managed blocks. packs.sh (+ profile.sh): the profile and pack discovery.
# ----------------------------------------------------------------------------

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/lib/config_write.sh"
# shellcheck source=lib/packs.sh disable=SC1091
. "$SCRIPT_DIR/lib/packs.sh"
# shellcheck source=lib/migrate.sh disable=SC1091
. "$SCRIPT_DIR/lib/migrate.sh"
# shellcheck source=lib/manifest.sh disable=SC1091
. "$SCRIPT_DIR/lib/manifest.sh"
# shellcheck source=lib/gitconfig.sh disable=SC1091
. "$SCRIPT_DIR/lib/gitconfig.sh"

# print_section is a variant not defined in ui.sh; add locally.
print_section() { echo ""; echo -e "${CYAN}▶ $1${NC}"; }

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------

MODE=""              # check|packages|configs|migrations|repo|security|all|menu
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
                      (runs pending migrations first)
  --migrations        Run pending one-shot migrations only
  --repo              git pull the tuidev repo and show git-clean dry-run
  --security          Audit tailscale/ssh perms/seatbelt profiles
  --all               packages + configs + repo (NOT security)

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
        --migrations|-m)    set_mode migrations; shift ;;
        --repo|-r)          set_mode repo; shift ;;
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
# Profile manifest — scripts/lib/profile.sh owns the parsing and the
# TUIDEV_PACK_* / TUIDEV_EXTRA_PACKS globals; tuidev_active_packs lists them.
# ----------------------------------------------------------------------------

# (Re)read the profile. Called again after migrations, which may edit it.
# shellcheck disable=SC2034  # profile.sh globals, read by tuidev_active_packs
load_profile() {
    if ! load_tuidev_profile; then
        print_warning "tuidev profile manifest not found at $TUIDEV_PROFILE_FILE_DEFAULT"
        print_info   "Treating as legacy install — every built-in pack counts as active."
        TUIDEV_PACK_CORE=true; TUIDEV_PACK_REMOTE=true; TUIDEV_PACK_SANDBOX=true
        TUIDEV_PACK_UI=true;   TUIDEV_PACK_EXTRAS=true
    fi

    # The env file carries TUIDEV_REPO for the repo-sync step.
    if [[ -f "$TUIDEV_ENV_FILE_DEFAULT" ]]; then
        # shellcheck disable=SC1090
        source "$TUIDEV_ENV_FILE_DEFAULT"
    fi
    return 0
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
# scripts own their own files (ghostty, ssh, etc.) and should
# expose an `install_config` we can re-invoke; drift for those is handled
# separately via `pack_reapply_configs`.
# ----------------------------------------------------------------------------

# Format: dest_path|source_path|block_id
# Block IDs must match exactly what install.sh (and --pack tmux) writes. If
# this list drifts from install.sh's cross-cutting config section, drift detection
# misclassifies in-sync files as legacy-no-block installs.
MANAGED_BLOCKS=(
    "$HOME/.zshrc|$REPO_DIR/configs/zsh/.zshrc|tuidev-zshrc"
    "$HOME/.config/starship.toml|$REPO_DIR/configs/starship/starship.toml|tuidev-starship"
    "$HOME/.config/tmux/tmux.conf|$REPO_DIR/configs/tmux/tmux.conf|tuidev-tmux"
)

# tmux.conf belongs to --pack tmux: check (and re-apply) its block only where
# that pack is active or the block is already in the file, so an update never
# creates a tmux.conf on a machine without the pack.
managed_block_applies() {
    local dest="$1" id="$2"
    [[ "$id" == tuidev-tmux ]] || return 0
    tuidev_active_packs | grep -qx tmux && return 0
    [[ -f "$dest" ]] && grep -qxF "$(tuidev_block_begin "$id")" "$dest" 2>/dev/null
}

# Best-effort "source of truth" — the entire file, modulo its own managed
# markers if any. The installer writes these source files as bare content,
# but we defer to read_managed_block when markers are present (defensive).
extract_source_block() {
    local file="$1" id="$2"
    [[ -f "$file" ]] || return 1
    if grep -qxF "$(tuidev_block_begin "$id")" "$file" 2>/dev/null; then
        read_managed_block "$file" "$id"
    else
        cat "$file"
    fi
}

# Detect source-content duplication in the region of FILE that lies OUTSIDE
# the managed block ID. This catches the "upgrade from pre-managed-block era"
# foot-gun where an older installer wrote the whole source into the file
# directly, and a newer installer then appended the same content again inside
# markers — producing TOML duplicate-key errors (starship), stale tmux
# directives, alias/function collisions in zshrc, etc.
#
# Prints:
#   "exact-pre"    — source content appears verbatim before the block
#   "exact-post"   — source content appears verbatim after the block
#   "partial-pre"  — 5+ consecutive non-blank source lines appear before the block
#   "partial-post" — same, after the block
# (Empty output means no duplication detected.) Checks pre-block first, then
# post-block — reports whichever it sees first.
detect_outside_duplication() {
    local dest="$1" id="$2" src="$3" begin end
    begin="$(tuidev_block_begin "$id")"
    end="$(tuidev_block_end "$id")"

    [[ -f "$dest" && -f "$src" ]] || return 0
    grep -qF "$begin" "$dest" 2>/dev/null || return 0

    local source_content signature pre post
    source_content="$(cat "$src")"
    [[ -z "$source_content" ]] && return 0

    pre="$(awk -v begin="$begin" '$0 == begin {exit} {print}' "$dest")"
    post="$(awk -v end="$end" 'p; $0 == end {p=1}' "$dest")"

    # First 5 consecutive non-blank lines of source — a fingerprint that's
    # extremely unlikely to appear in genuine user content by coincidence.
    signature="$(printf '%s\n' "$source_content" | awk 'NF {print; if (++n == 5) exit}')"

    if [[ -n "$pre" && "$pre" == *"$source_content"* ]]; then
        echo "exact-pre"; return 0
    fi
    if [[ -n "$post" && "$post" == *"$source_content"* ]]; then
        echo "exact-post"; return 0
    fi
    if [[ -n "$signature" ]]; then
        if [[ -n "$pre" && "$pre" == *"$signature"* ]]; then
            echo "partial-pre"; return 0
        fi
        if [[ -n "$post" && "$post" == *"$signature"* ]]; then
            echo "partial-post"; return 0
        fi
    fi
}

# Rewrites DEST in place so everything before the managed block is discarded
# (for "exact-pre") or everything after the end marker is discarded (for
# "exact-post"). Creates a timestamped backup via tuidev_backup. Only called
# after detect_outside_duplication returns an "exact-*" verdict.
clean_outside_duplication() {
    local dest="$1" id="$2" where="$3" begin end
    begin="$(tuidev_block_begin "$id")"
    end="$(tuidev_block_end "$id")"

    tuidev_backup "$dest" "$(basename "$dest")" >/dev/null || true
    local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-cleanup.XXXXXX")"

    case "$where" in
        exact-pre)
            awk -v begin="$begin" '
                !seen && $0 == begin { seen=1 }
                seen { print }
            ' "$dest" > "$tmp"
            ;;
        exact-post)
            awk -v end="$end" '
                { print }
                $0 == end { exit }
            ' "$dest" > "$tmp"
            ;;
        *)
            print_error "clean_outside_duplication: unsupported mode: $where"
            rm -f "$tmp"; return 2
            ;;
    esac
    mv "$tmp" "$dest"
    print_success "cleaned $where duplicate from $dest"
}

# Prints drift report for each entry in MANAGED_BLOCKS. Populates DRIFT_ITEMS
# with entries that need re-applying and DRIFT_LEGACY with files that exist
# but have no block (→ need `make adopt`). DRIFT_DUPLICATE catches the
# harder case: block is present but source content is also duplicated outside
# it (from a pre-managed-block install that was later upgraded).
DRIFT_ITEMS=()
DRIFT_LEGACY=()
DRIFT_DUPLICATE=()

detect_drift() {
    DRIFT_ITEMS=()
    DRIFT_LEGACY=()
    DRIFT_DUPLICATE=()

    local entry dest src id current desired diff_out
    for entry in "${MANAGED_BLOCKS[@]}"; do
        IFS='|' read -r dest src id <<<"$entry"
        managed_block_applies "$dest" "$id" || continue

        if [[ ! -f "$src" ]]; then
            print_warning "Source missing, skipping drift check: $src"
            continue
        fi

        if [[ ! -f "$dest" ]]; then
            print_info "$dest (not present; pack install will create it)"
            DRIFT_ITEMS+=("$entry")
            continue
        fi

        if ! grep -qxF "$(tuidev_block_begin "$id")" "$dest" 2>/dev/null; then
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

        # Orthogonal to in-block drift: pre-/post-block content may duplicate
        # the source (legacy-install artifact). An in-sync block that still
        # has this duplication will pass the previous check but break TOML
        # parsing or trigger alias/function collisions, so report separately.
        local dup_kind
        dup_kind="$(detect_outside_duplication "$dest" "$id" "$src")"
        case "$dup_kind" in
            exact-*)
                print_warning "$dest — source content duplicated OUTSIDE managed block ($dup_kind)"
                print_info   "  this breaks parsers that reject duplicate keys (TOML) and"
                print_info   "  causes alias/function collisions in zsh. Safe to auto-clean."
                DRIFT_DUPLICATE+=("${entry}|${dup_kind}")
                ;;
            partial-*)
                print_warning "$dest — partial source duplication OUTSIDE block ($dup_kind)"
                print_info   "  5+ contiguous source lines appear outside the managed block."
                print_info   "  Review $dest manually — auto-clean skipped (may contain user edits)."
                DRIFT_DUPLICATE+=("${entry}|${dup_kind}")
                ;;
        esac
    done
}

reapply_drift() {
    if [[ ${#DRIFT_ITEMS[@]} -eq 0 ]]; then
        print_success "Nothing to re-apply"
        return 0
    fi

    local entry dest src id
    for entry in "${DRIFT_ITEMS[@]}"; do
        IFS='|' read -r dest src id <<<"$entry"
        write_managed_block "$dest" "$id" "$(extract_source_block "$src" "$id")"
    done
}

# Re-run each enabled pack's entrypoint (built-in and extra packs alike, via
# scripts/lib/packs.sh). Packs are idempotent — installs short-circuit on
# "already present" and install_config preserves user state — so this is safe
# on every `update --configs`. Each runs in a subshell so it cannot clobber
# this script's state.
pack_reapply_configs() {
    local p
    for p in $(tuidev_active_packs); do
        if ! pack_script "$p" >/dev/null; then
            print_warning "pack '$p' is recorded but no longer exists — skipping"
        elif [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}  [DRY RUN]${NC} $(pack_entrypoint "$p") (pack=$p)"
        else
            ( set +u; pack_run "$p" ) || print_warning "pack $p reported an error (continuing)"
        fi
    done
}

# ----------------------------------------------------------------------------
# Mode: --check / --packages  (brew)
# ----------------------------------------------------------------------------

# outdated_subset formula|cask NAME... — print the NAMEs brew reports outdated.
# Uses `brew outdated --json=v2` when jq is available for precision, falls
# back to a line match otherwise. Returns 2 when brew itself fails.
outdated_subset() {
    local kind="$1"; shift
    (( $# == 0 )) && return 0
    command_exists brew || return 0

    local flag="--formula" json status=0
    [[ "$kind" == cask ]] && flag="--cask"

    if command_exists jq; then
        json="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated "$flag" --json=v2 2>/dev/null)" || status=$?
        if [[ $status -eq 0 && -n "$json" ]]; then
            printf '%s\n' "$@" \
                | jq -Rr --argjson blob "$json" '
                    . as $n
                    | (($blob.formulae // []) + ($blob.casks // []))[]
                    | select((.name // "") == $n or (.token // "") == $n or (.full_name // "") == $n)
                    | (.name // .token)
                '
            return 0
        fi
    fi

    local outdated_list w
    outdated_list="$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated "$flag" --quiet 2>/dev/null)" || return 2
    for w in "$@"; do
        grep -qxF "$w" <<<"$outdated_list" && printf '%s\n' "$w"
    done
    return 0
}

# ----------------------------------------------------------------------------
# Per-pack update reporting — shared by profile packs and extra packs
# ----------------------------------------------------------------------------

# Accumulators summed across packs by _report_brew_group; read by the
# run_packages_mode summary. Reset at the top of run_packages_mode.
PKG_OUTDATED_TOTAL=0
PKG_UNKNOWN=0

# Report (and, outside --check, optionally upgrade) one brew group for a pack.
#   $1 header  section label, e.g. "core updates" / "core cask updates"
#   $2 noun    confirm-prompt noun, e.g. "core formula(e)" / "core cask(s)"
#   $3 kind    "formula" | "cask"
#   $4.. items tracked names (no-op when empty)
_report_brew_group() {
    local header="$1" noun="$2" kind="$3"; shift 3
    (( $# == 0 )) && return 0
    local tracked=$#

    local raw status=0 o
    raw="$(outdated_subset "$kind" "$@")" || status=$?
    local outdated=()
    while IFS= read -r o; do
        [[ -n "$o" ]] && outdated+=("$o")
    done <<<"$raw"

    echo ""
    if [[ $status -ne 0 ]]; then
        echo -e "  ${BOLD}${header}${NC} (${tracked} tracked, status unknown):"
        print_warning "brew outdated probe failed; status unknown"
        PKG_UNKNOWN=$((PKG_UNKNOWN + 1))
        return 0
    fi

    echo -e "  ${BOLD}${header}${NC} (${tracked} tracked, ${#outdated[@]} outdated):"
    if (( ${#outdated[@]} == 0 )); then
        print_success "all up to date"
        return 0
    fi
    for o in "${outdated[@]}"; do
        printf "    ${CYAN}•${NC} %s\n" "$o"
    done
    PKG_OUTDATED_TOTAL=$((PKG_OUTDATED_TOTAL + ${#outdated[@]}))

    [[ "$MODE" == "check" ]] && return 0
    confirm "Upgrade ${#outdated[@]} ${noun}?" || return 0
    for o in "${outdated[@]}"; do
        if [[ "$kind" == cask ]]; then
            run_cmd brew upgrade --cask "$o" || print_warning "Failed to upgrade cask $o"
        else
            run_cmd brew upgrade "$o" || print_warning "Failed to upgrade $o"
        fi
    done
}

# Report every brew item a pack declares (scripts/lib/packs.sh pack_array):
# formulae always, casks on macOS.
report_pack_updates() {
    local pack="$1" item
    local formulae=() casks=()
    while IFS= read -r item; do formulae+=("$item"); done < <(pack_array "$pack" formulae)
    if is_macos; then
        while IFS= read -r item; do casks+=("$item"); done < <(pack_array "$pack" casks)
    fi

    if (( ${#formulae[@]} + ${#casks[@]} == 0 )); then
        print_info "${pack} updates: (no Homebrew packages declared)"
        return 0
    fi
    if (( ${#formulae[@]} > 0 )); then
        _report_brew_group "${pack} updates" "${pack} formula(e)" formula "${formulae[@]}"
    fi
    if (( ${#casks[@]} > 0 )); then
        _report_brew_group "${pack} cask updates" "${pack} cask(s)" cask "${casks[@]}"
    fi
}

run_packages_mode() {
    print_section "Checking pack-scoped package updates"

    if ! command -v brew >/dev/null 2>&1; then
        print_warning "brew not found — skipping package updates"
        return 0
    fi

    if [[ "$MODE" == "check" ]]; then
        print_info "Using local Homebrew metadata; run --packages to refresh and upgrade."
    else
        run_cmd brew update --quiet || true
    fi

    PKG_OUTDATED_TOTAL=0
    PKG_UNKNOWN=0

    # Built-in and extra packs are reported the same way, so fnm's
    # FNM_FORMULAE and cmux's CMUX_CASKS are tracked just like core's.
    local pack any_pack=false
    for pack in $(tuidev_active_packs); do
        any_pack=true
        report_pack_updates "$pack"
    done

    if [[ "$any_pack" != true ]]; then
        print_warning "No active packs detected; nothing to update"
        return 0
    fi

    echo ""
    if [[ "$MODE" == "check" ]]; then
        if [[ $PKG_UNKNOWN -gt 0 ]]; then
            print_warning "${PKG_UNKNOWN} package group(s) could not be checked"
        elif [[ $PKG_OUTDATED_TOTAL -eq 0 ]]; then
            print_success "All pack-tracked packages up to date"
        else
            print_info "${PKG_OUTDATED_TOTAL} package(s) have updates available — run without --check to apply"
        fi
    fi
}

# ----------------------------------------------------------------------------
# Mode: --migrations
#
# One-shot fixups for machines installed by an older tuidev — the things
# idempotent pack re-runs can never repair, because the artifact's source is
# gone from the repo. See scripts/migrations/README.md for the contract.
#
# Runs before --configs re-applies anything, so a migration that repairs the
# shape of a file is done before drift detection reads it. A failure stops the
# whole run: the machine is in a known-bad state and re-applying configs on top
# would only obscure it.
# ----------------------------------------------------------------------------

run_migrations_mode() {
    print_section "One-shot migrations"

    if [[ "$MODE" == "check" ]]; then
        tuidev_run_migrations --list
        return 0
    fi

    if ! tuidev_run_migrations; then
        print_error "Migration failed — stopping before any further changes."
        exit 1
    fi
    # A migration may have edited the profile (e.g. added a pack); later
    # steps in this same run must see that, not the pre-migration copy.
    load_profile >/dev/null
}

# ----------------------------------------------------------------------------
# Mode: --configs
# ----------------------------------------------------------------------------

run_configs_mode() {
    print_section "Checking managed-block drift"
    detect_drift

    # Summary of exact vs partial duplicates — used both for --check preview
    # and to gate the auto-clean prompt below.
    local exact_dupes=0 partial_dupes=0 item dest src id
    for item in ${DRIFT_DUPLICATE[@]+"${DRIFT_DUPLICATE[@]}"}; do
        case "${item##*|}" in
            exact-*)   exact_dupes=$((exact_dupes+1));;
            partial-*) partial_dupes=$((partial_dupes+1));;
        esac
    done

    if [[ "$MODE" == "check" ]]; then
        if [[ ${#DRIFT_LEGACY[@]} -gt 0 ]]; then
            print_warning "${#DRIFT_LEGACY[@]} file(s) need adoption (run 'make adopt')"
        fi
        if [[ ${#DRIFT_ITEMS[@]} -gt 0 ]]; then
            print_info "${#DRIFT_ITEMS[@]} managed block(s) drifted — run without --check to re-apply"
        fi
        if [[ $exact_dupes -gt 0 ]]; then
            print_warning "${exact_dupes} file(s) have source content duplicated outside the managed block — run without --check to clean"
        fi
        if [[ $partial_dupes -gt 0 ]]; then
            print_warning "${partial_dupes} file(s) have partial source duplication — manual review required"
        fi
        return 0
    fi

    if [[ $exact_dupes -gt 0 ]]; then
        if confirm "Clean ${exact_dupes} file(s) with exact duplicate content outside managed block? (backups saved)"; then
            for item in ${DRIFT_DUPLICATE[@]+"${DRIFT_DUPLICATE[@]}"}; do
                local entry_part="${item%|*}" dup_kind="${item##*|}"
                case "$dup_kind" in
                    exact-*)
                        IFS='|' read -r dest src id <<<"$entry_part"
                        clean_outside_duplication "$dest" "$id" "$dup_kind"
                        ;;
                esac
            done
        fi
    fi

    if [[ ${#DRIFT_ITEMS[@]} -gt 0 ]]; then
        if confirm "Re-apply ${#DRIFT_ITEMS[@]} managed block(s)?"; then
            reapply_drift
        fi
    fi

    print_section "Re-syncing pack-owned configs"
    # Anything the re-sync installs (a formula a pack gained since the last
    # release, a config file that was missing) belongs in the manifest too.
    tuidev_manifest_enable
    pack_reapply_configs
    # New git defaults reach existing machines too (unset keys only).
    tuidev_git_defaults
    tuidev_manifest_disable
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
# Mode: --security
# ----------------------------------------------------------------------------

check_ssh_perms() {
    local ssh_dir="$HOME/.ssh"
    [[ -d "$ssh_dir" ]] || { print_info "No $ssh_dir — skipping ssh perms check"; return 0; }

    local mode
    mode="$(file_mode "$ssh_dir" || echo '?')"
    if [[ "$mode" == "700" ]]; then
        print_success "$ssh_dir is 0700"
    else
        print_warning "$ssh_dir mode is $mode (expected 700)"
    fi

    local f
    while IFS= read -r -d '' f; do
        mode="$(file_mode "$f" || echo '?')"
        if [[ "$mode" == "600" || "$mode" == "400" ]]; then
            print_success "$(basename "$f") is $mode"
        else
            print_warning "$f mode is $mode (expected 600)"
        fi
    done < <(find "$ssh_dir" -maxdepth 1 -type f -print0 2>/dev/null)
}

check_seatbelt_drift() {
    # Paths must match scripts/install/sandbox.sh: installed to
    # $TUIDEV_STATE_DIR/sandbox/ from configs/sandbox/profiles/*.sb.
    local sb_src="$REPO_DIR/configs/sandbox/profiles"
    local sb_dest="$TUIDEV_STATE_DIR/sandbox"
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
    5) Security audit
    6) Update all (packages + configs + repo)
    7) Run pending migrations
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
        5) MODE=security;       run_mode ;;
        6) MODE=all;            run_mode ;;
        7) MODE=migrations;     run_mode ;;
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
            run_migrations_mode
            run_configs_mode
            run_repo_mode
            ;;
        packages)      run_packages_mode ;;
        migrations)    run_migrations_mode ;;
        configs)       run_migrations_mode; run_configs_mode ;;
        repo)          run_repo_mode ;;
        security)      run_security_mode ;;
        all)
            run_packages_mode
            run_migrations_mode
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

load_profile

if $TUIDEV_PROFILE_FOUND; then
    echo -e "  ${BLUE}Profile:${NC} ${TUIDEV_PROFILE_NAME:-?}"
    echo -e "  ${BLUE}Packs:${NC}   $(tuidev_active_packs | paste -sd, -)"
fi

case "$MODE" in
    menu)
        if ! $TUIDEV_PROFILE_FOUND; then
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
