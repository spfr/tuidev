#!/bin/bash
# ============================================================================
# tuidev performance audit
# ============================================================================
# What the OS does in the background that competes with agents (Spotlight,
# Time Machine, Low Power Mode, inotify, swap, file limits), measured on this
# machine, with the fix for each. Reading changes nothing.
#
# Usage:
#   ./scripts/perf.sh              # report
#   ./scripts/perf.sh --fix        # report, then offer each fix that needs no root
#   ./scripts/perf.sh --fix --yes  # apply those without asking
#   ./scripts/perf.sh --dry-run    # with --fix: print the commands instead
#
# Exit 0 always: a finding is advice, not a failure. See docs/performance.md.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/manifest.sh disable=SC1091
. "$SCRIPT_DIR/lib/manifest.sh"
# shellcheck source=lib/gitconfig.sh disable=SC1091
. "$SCRIPT_DIR/lib/gitconfig.sh"
# shellcheck source=lib/perf.sh disable=SC1091
. "$SCRIPT_DIR/lib/perf.sh"

FIX=false
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix|-f)     FIX=true; shift ;;
        --yes|-y)     ASSUME_YES=true; shift ;;
        --dry-run|-d) export DRY_RUN=true; shift ;;
        --help|-h)    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) print_error "Unknown option: $1"; exit 2 ;;
    esac
done

confirm() {
    $ASSUME_YES && return 0
    [[ -t 0 ]] || return 1
    local reply
    read -r -p "  $1 (y/N) " -n 1 reply
    echo ""
    [[ "$reply" =~ ^[Yy]$ ]]
}

print_header "tuidev Performance"
perf_collect
perf_report

if $FIX && (( PERF_AUTO_TOTAL > 0 )); then
    echo ""
    tuidev_manifest_enable
    perf_apply confirm
elif $FIX; then
    print_info "Nothing here can be fixed without you: see the fix lines above."
fi
