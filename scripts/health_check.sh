#!/usr/bin/env bash
# ============================================================================
# Health Check — macOS TUI Development Environment
# ============================================================================
# Profile-aware health check. Probes are split into required vs. optional:
#
#   required  → failure is counted toward the pass/fail summary and the
#               script exits non-zero if any required probe fails.
#   optional  → failure prints a warning only; never affects the exit code.
#
# Categories (which categories are required depends on the active profile):
#
#   core     — shell/CLI staples (required in every profile; on Linux
#              without Homebrew, tools the distro may not package are optional)
#   remote   — tailscale, mosh (required only in the `remote` profile)
#   sandbox  — Seatbelt (macOS only; required in desktop & remote)
#   ui       — Ghostty + macOS GUI apps (required only in `desktop`, macOS)
#   extras   — optional quality-of-life tools (never required)
#   packs    — optional packs listed in the profile manifest (never required)
#
# Usage:
#   scripts/health_check.sh                      # auto-detect profile
#   scripts/health_check.sh --profile minimal    # force a profile
#   scripts/health_check.sh --profile desktop
#   scripts/health_check.sh --profile remote
#
# Profile auto-detection reads ~/.config/tuidev/profile (the manifest written
# by the installer). When absent, falls back to the platform default:
#   macOS -> desktop, Linux -> minimal.
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/packs.sh disable=SC1091
. "$SCRIPT_DIR/lib/packs.sh"
# shellcheck source=lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/lib/pkg.sh"

# Cache uname once. Probes run dozens of times across the suite.
TUIDEV_OS="$(uname -s)"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------

REQ_PASS=0
REQ_FAIL=0
OPT_WARN=0

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

PROFILE="auto"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--profile minimal|desktop|remote|auto]

  --profile P   Force a specific profile.
                Default: 'auto' (reads the tuidev profile, else
                macOS->desktop, Linux->minimal).
  -h, --help    Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || { print_error "--profile requires a value"; exit 2; }
            PROFILE="$2"
            shift 2
            ;;
        --profile=*)
            PROFILE="${1#--profile=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Profile manifest (scripts/lib/profile.sh)
# ---------------------------------------------------------------------------

platform_default_profile() {
    case "$TUIDEV_OS" in
        Darwin) echo "desktop" ;;
        *)      echo "minimal" ;;
    esac
}

resolve_profile() {
    load_tuidev_profile || true

    if [[ "$PROFILE" == "auto" ]]; then
        PROFILE="${TUIDEV_PROFILE_NAME:-$(platform_default_profile)}"
    fi

    if [[ "$PROFILE" == custom ]]; then
        # Pack-only installs record profile=custom; check the core baseline
        # (packs are covered by the extra_packs section).
        print_info "Profile is 'custom' (pack-only install): checking the minimal baseline."
        PROFILE="minimal"
    elif ! tuidev_is_valid_profile "$PROFILE"; then
        print_error "Invalid profile: $PROFILE (expected ${TUIDEV_VALID_PROFILES[*]}|auto)"
        exit 2
    fi
}

# ---------------------------------------------------------------------------
# Required/optional probe helpers
# ---------------------------------------------------------------------------

# check_required NAME PROBE_CMD
#   Runs PROBE_CMD via `eval`. On success, counts a required pass.
#   On failure, counts a required fail and contributes to the non-zero exit.
check_required() {
    local name="$1"
    local probe="$2"
    if eval "$probe" >/dev/null 2>&1; then
        print_success "$name"
        REQ_PASS=$((REQ_PASS + 1))
        return 0
    else
        print_error "$name (required)"
        REQ_FAIL=$((REQ_FAIL + 1))
        return 1
    fi
}

# check_optional NAME PROBE_CMD
#   On failure, emits a warning and never affects the exit code.
check_optional() {
    local name="$1"
    local probe="$2"
    if eval "$probe" >/dev/null 2>&1; then
        print_success "$name"
        return 0
    else
        print_warning "$name (optional)"
        OPT_WARN=$((OPT_WARN + 1))
        return 1
    fi
}

# Convenience probe: command is on PATH. Invoked indirectly via
# check_required/check_optional which pass probe commands as strings.
# shellcheck disable=SC2329
have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# App bundle probe (macOS GUI apps). Returns non-zero on non-macOS.
# Invoked indirectly, like have_cmd.
# shellcheck disable=SC2317,SC2329
have_app() {
    [[ "$TUIDEV_OS" == "Darwin" ]] || return 1
    [[ -d "/Applications/$1.app" || -d "$HOME/Applications/$1.app" ]]
}

# ---------------------------------------------------------------------------
# Category: core
# ---------------------------------------------------------------------------

# A core tool is required unless this is Linux without Homebrew and the tool
# is one a distribution may not package (pkg.sh points apt users at its
# upstream installer instead).
core_tool_check_fn() {
    if is_linux && ! command_exists brew && [[ -n "$(pkg_manual_hint "$1")" ]]; then
        echo check_optional
    else
        echo check_required
    fi
}

check_core() {
    print_header "Core (required in every profile)"

    local formula bin
    while IFS= read -r formula; do
        bin="$(tuidev_formula_binary "$formula")"
        [[ -n "$bin" ]] || continue
        "$(core_tool_check_fn "$formula")" "$bin on PATH" "have_cmd $bin"
    done < <(pack_array core formulae)

    if have_cmd zsh; then
        check_required "zsh completion directories pass compaudit" \
            "[[ -z \"\$(zsh -f -c 'autoload -Uz compaudit; compaudit' 2>/dev/null)\" ]]"
    else
        check_required "zsh on PATH" "have_cmd zsh"
    fi
}

# ---------------------------------------------------------------------------
# Category: remote
# ---------------------------------------------------------------------------

check_remote() {
    local required="$1"   # "required" or "optional"
    print_header "Remote (Tailscale + mosh)"

    local fn="check_optional"
    [[ "$required" == "required" ]] && fn="check_required"

    # Tailscale: CLI must be on PATH (mac app adds a /usr/local symlink).
    "$fn" "tailscale on PATH" "have_cmd tailscale"
    "$fn" "mosh on PATH" "have_cmd mosh"
}

# ---------------------------------------------------------------------------
# Category: sandbox
# ---------------------------------------------------------------------------

check_sandbox() {
    local required="$1"
    print_header "Sandbox (Seatbelt)"

    if [[ "$TUIDEV_OS" != "Darwin" ]]; then
        print_info "Seatbelt is macOS-only; skipping sandbox probes."
        return 0
    fi

    local fn="check_optional"
    [[ "$required" == "required" ]] && fn="check_required"

    # Is Seatbelt itself functional? Probe with an inline allow-default profile
    # — stable across macOS versions (the built-in `no-profile` name was
    # removed on recent releases).
    "$fn" "sandbox-exec works (inline smoke profile)" \
        "sandbox-exec -p '(version 1)(allow default)' /usr/bin/true"

    # Does the strict profile exist where the installer puts it?
    "$fn" "sandbox profile present ($TUIDEV_STATE_DIR/sandbox/strict.sb)" \
        "[[ -f \"$TUIDEV_STATE_DIR/sandbox/strict.sb\" ]]"

    # Is the `sbx` wrapper on PATH?
    "$fn" "sbx wrapper on PATH" "have_cmd sbx"
}

# ---------------------------------------------------------------------------
# Category: ui (desktop GUI)
# ---------------------------------------------------------------------------

check_ui() {
    local required="$1"
    print_header "UI (Ghostty + macOS GUI apps)"

    if [[ "$TUIDEV_OS" != "Darwin" ]]; then
        print_info "GUI apps are macOS-only; skipping UI probes."
        return 0
    fi

    local fn="check_optional"
    [[ "$required" == "required" ]] && fn="check_required"

    # Ghostty: either the app bundle or the ghostty binary counts.
    "$fn" "Ghostty installed" \
        "have_app Ghostty || have_cmd ghostty"
    "$fn" "Ghostty config (~/.config/ghostty/config)" \
        "[[ -f \"$HOME/.config/ghostty/config\" ]]"

    local cask app
    while IFS= read -r cask; do
        app="$(tuidev_cask_app "$cask")"
        "$fn" "$app.app" "have_app '$app'"
    done < <(pack_array ui casks)
}

# ---------------------------------------------------------------------------
# Category: extras (never required)
# ---------------------------------------------------------------------------

check_extras() {
    print_header "Extras (optional quality-of-life tools)"

    local tool
    while IFS= read -r tool; do
        check_optional "$tool on PATH" "have_cmd $tool"
    done < <(pack_binaries extras)
}

# ---------------------------------------------------------------------------
# Category: packs (optional, manifest-driven)
# ---------------------------------------------------------------------------

pack_probe() {
    # Returns the probe command for a given pack name.
    case "$1" in
        monitoring)         echo "have_cmd btm || have_cmd bottom || have_cmd htop" ;;
        sandbox-container)  echo "have_cmd container || have_cmd podman || have_cmd docker" ;;
        mosh)               echo "have_cmd mosh" ;;
        cmux)               echo "have_cmd cmux || have_app cmux" ;;
        herdr)              echo "have_cmd herdr" ;;
        fnm)                echo "have_cmd fnm" ;;
        ai-clis)            echo "have_cmd claude || have_cmd codex" ;;
        opencode)           echo "have_cmd opencode" ;;
        nvim)               echo "have_cmd nvim" ;;
        tmux)               echo "have_cmd tmux && [[ -f \"\$HOME/.config/tmux/tmux.conf\" ]]" ;;
        *)                  echo "have_cmd $1" ;;
    esac
}

check_packs() {
    print_header "Packs (manifest-declared extras)"

    # The remote profile includes --pack tmux, so checking a node as `remote`
    # checks tmux too, even when the manifest predates that.
    local packs=() p
    while IFS= read -r p; do
        packs+=("$p")
    done < <(tuidev_extra_packs "$PROFILE")

    if [[ ${#packs[@]} -eq 0 ]]; then
        print_info "No extra_packs declared in manifest (or manifest absent)."
        return 0
    fi

    local pack probe
    for pack in "${packs[@]}"; do
        probe="$(pack_probe "$pack")"
        check_optional "pack: $pack" "$probe"
    done
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

show_profile_banner() {
    print_header "Health check — profile: $PROFILE"
    print_info "Platform: $(uname -s) $(uname -r)"
    if $TUIDEV_PROFILE_FOUND; then
        print_info "Manifest: $TUIDEV_PROFILE_FILE_DEFAULT"
        [[ -n "$TUIDEV_PROFILE_INSTALLED_AT" ]] && print_info "Installed at: $TUIDEV_PROFILE_INSTALLED_AT"
        [[ -n "$TUIDEV_PROFILE_REPO" ]]         && print_info "Repo: $TUIDEV_PROFILE_REPO"
    else
        print_info "Manifest: (not found; using platform defaults)"
    fi
    if [[ -f "$TUIDEV_ENV_FILE_DEFAULT" ]]; then
        print_info "Env file: $TUIDEV_ENV_FILE_DEFAULT"
    fi
}

run_checks() {
    # Core is always required.
    check_core

    # Remote: required only in the `remote` profile, optional elsewhere.
    case "$PROFILE" in
        remote)  check_remote required ;;
        *)       check_remote optional ;;
    esac

    # Sandbox: required in desktop + remote (macOS only); optional in minimal.
    case "$PROFILE" in
        desktop|remote) check_sandbox required ;;
        *)              check_sandbox optional ;;
    esac

    # UI: required only in desktop profile (macOS only); skipped entirely on Linux.
    case "$PROFILE" in
        desktop) check_ui required ;;
        *)       check_ui optional ;;
    esac

    # Extras + packs are never required.
    check_extras
    check_packs
}

print_summary() {
    print_header "Summary"
    printf '  Required passed:   %b%d%b\n' "$GREEN"  "$REQ_PASS" "$NC"
    printf '  Required failed:   %b%d%b\n' "$RED"    "$REQ_FAIL" "$NC"
    printf '  Optional warnings: %b%d%b\n' "$YELLOW" "$OPT_WARN" "$NC"
    echo

    if [[ $REQ_FAIL -eq 0 ]]; then
        printf '%bAll required checks passed for profile: %s%b\n' "$GREEN" "$PROFILE" "$NC"
        return 0
    else
        printf '%b%d required check(s) failed for profile: %s%b\n' "$RED" "$REQ_FAIL" "$PROFILE" "$NC"
        printf '%bRun the installer for this profile or install the missing tools.%b\n' "$YELLOW" "$NC"
        return 1
    fi
}

main() {
    resolve_profile
    show_profile_banner
    run_checks
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
