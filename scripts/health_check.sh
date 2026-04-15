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
#   core     — shell/editor/CLI staples (required in every profile)
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
                Default: 'auto' (reads ~/.config/tuidev/profile, else
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
# Profile manifest
# ---------------------------------------------------------------------------

MANIFEST_DIR="$HOME/.config/tuidev"
MANIFEST_FILE="$MANIFEST_DIR/profile"
ENV_FILE="$MANIFEST_DIR/env"

# shellcheck source=lib/profile.sh disable=SC1091
. "$SCRIPT_DIR/lib/profile.sh"

# Legacy-named aliases over the lib's globals, so the rest of this file
# doesn't need renames.
MANIFEST_PROFILE=""
MANIFEST_EXTRA_PACKS=""
MANIFEST_INSTALLED_AT=""
MANIFEST_REPO=""

parse_manifest() {
    load_tuidev_profile "$MANIFEST_FILE" || true
    MANIFEST_PROFILE="$TUIDEV_PROFILE_NAME"
    MANIFEST_EXTRA_PACKS="$TUIDEV_EXTRA_PACKS"
    MANIFEST_INSTALLED_AT="$TUIDEV_PROFILE_INSTALLED_AT"
    MANIFEST_REPO="$TUIDEV_PROFILE_REPO"
}

platform_default_profile() {
    case "$TUIDEV_OS" in
        Darwin) echo "desktop" ;;
        *)      echo "minimal" ;;
    esac
}

resolve_profile() {
    parse_manifest

    if [[ "$PROFILE" == "auto" ]]; then
        if [[ -n "$MANIFEST_PROFILE" ]]; then
            PROFILE="$MANIFEST_PROFILE"
        else
            PROFILE="$(platform_default_profile)"
        fi
    fi

    case "$PROFILE" in
        minimal|desktop|remote) ;;
        *)
            print_error "Invalid profile: $PROFILE (expected minimal|desktop|remote|auto)"
            exit 2
            ;;
    esac
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
# shellcheck disable=SC2329
have_app() {
    [[ "$TUIDEV_OS" == "Darwin" ]] || return 1
    [[ -d "/Applications/$1.app" || -d "$HOME/Applications/$1.app" ]]
}

# ---------------------------------------------------------------------------
# Category: core
# ---------------------------------------------------------------------------

check_core() {
    print_header "Core (required in every profile)"

    local tools=(
        tmux
        nvim
        rg
        fd
        bat
        fzf
        zoxide
        starship
        delta
        lazygit
        jq
        yq
        eza
        gh
        shellcheck
    )

    local tool
    for tool in "${tools[@]}"; do
        check_required "$tool on PATH" "have_cmd $tool"
    done

    # Git is implicit but worth checking as it underpins delta/lazygit/gh.
    check_required "git on PATH" "have_cmd git"
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
    "$fn" "sandbox profile present (~/.config/tuidev/sandbox/strict.sb)" \
        "[[ -f \"$HOME/.config/tuidev/sandbox/strict.sb\" ]]"

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

    "$fn" "Rectangle.app"  "have_app Rectangle"
    "$fn" "Stats.app"      "have_app Stats"
    "$fn" "Maccy.app"      "have_app Maccy"
    "$fn" "Hidden Bar.app" "have_app 'Hidden Bar'"
    "$fn" "Hammerspoon.app" "have_app Hammerspoon"
}

# ---------------------------------------------------------------------------
# Category: extras (never required)
# ---------------------------------------------------------------------------

check_extras() {
    print_header "Extras (optional quality-of-life tools)"

    local tools=(atuin dust broot bandwhich duf hyperfine tokei)
    local tool
    for tool in "${tools[@]}"; do
        check_optional "$tool on PATH" "have_cmd $tool"
    done
}

# ---------------------------------------------------------------------------
# Category: packs (optional, manifest-driven)
# ---------------------------------------------------------------------------

pack_probe() {
    # Returns the probe command for a given pack name.
    case "$1" in
        zellij)             echo "have_cmd zellij" ;;
        yazi)               echo "have_cmd yazi" ;;
        nnn)                echo "have_cmd nnn" ;;
        monitoring)         echo "have_cmd btm || have_cmd bottom || have_cmd htop" ;;
        sandbox-container)  echo "have_cmd podman" ;;
        *)                  echo "have_cmd $1" ;;
    esac
}

check_packs() {
    print_header "Packs (manifest-declared extras)"

    if [[ -z "$MANIFEST_EXTRA_PACKS" ]]; then
        print_info "No extra_packs declared in manifest (or manifest absent)."
        return 0
    fi

    # extra_packs is expected to be space- or comma-separated.
    local packs_str="${MANIFEST_EXTRA_PACKS//,/ }"
    # shellcheck disable=SC2206
    local packs=($packs_str)

    if [[ ${#packs[@]} -eq 0 ]]; then
        print_info "No extra_packs declared in manifest."
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
    if [[ -f "$MANIFEST_FILE" ]]; then
        print_info "Manifest: $MANIFEST_FILE"
        [[ -n "$MANIFEST_INSTALLED_AT" ]] && print_info "Installed at: $MANIFEST_INSTALLED_AT"
        [[ -n "$MANIFEST_REPO" ]]         && print_info "Repo: $MANIFEST_REPO"
    else
        print_info "Manifest: (not found; using platform defaults)"
    fi
    if [[ -f "$ENV_FILE" ]]; then
        print_info "Env file: $ENV_FILE"
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
