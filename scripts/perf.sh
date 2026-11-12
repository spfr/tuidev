#!/bin/bash
# ============================================================================
# tuidev performance audit
# ============================================================================
# What the OS does in the background that competes with agents (Spotlight,
# Time Machine, Low Power Mode, inotify, swap, file limits, daemon CPU, memory,
# free disk), measured on this machine, each with how it was measured and the
# fix. Reading changes nothing.
#
# Usage:
#   ./scripts/perf.sh              # report
#   ./scripts/perf.sh --fix        # report, the plan, then ask for each fix that needs no root
#   ./scripts/perf.sh --fix --yes  # apply those without asking (required without a terminal)
#   ./scripts/perf.sh --dry-run    # with --fix: print the commands and log lines instead
#
# Each change is logged with its undo in ~/.config/tuidev/disk.log.
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
        --help|-h)    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) print_error "Unknown option: $1"; exit 2 ;;
    esac
done

# Yes only for y or yes typed, then Enter; anything else is no. What was
# typed while the audit ran is thrown away first, so a stray key never answers.
confirm() {
    $ASSUME_YES && return 0
    [[ -t 0 ]] || return 1
    local reply=""
    perl -MPOSIX=tcflush,TCIFLUSH -e 'tcflush(0, TCIFLUSH)' 2>/dev/null \
        || while IFS= read -r -t 1 -n 1 _; do :; done
    read -r -p "  $1 [y/N] " reply || true
    case "$reply" in y|Y|yes|Yes|YES) return 0 ;; esac
    return 1
}

print_header "tuidev Performance"
perf_collect
perf_report

if $FIX && (( PERF_AUTO_TOTAL > 0 )) && ! $ASSUME_YES && [[ ! -t 0 ]] && [[ "$DRY_RUN" != true ]]; then
    # Nothing to ask with: a fix without a terminal needs an explicit --yes.
    echo ""
    perf_plan || true
    print_info "Not a terminal and no --yes: nothing changed. Run it in a terminal, or add --yes to apply the plan above."
elif $FIX && (( PERF_AUTO_TOTAL > 0 )); then
    echo ""
    tuidev_manifest_enable
    if [[ "$DRY_RUN" == true ]]; then perf_apply; else perf_apply confirm; fi
elif $FIX; then
    print_info "Nothing here can be fixed without you: see the fix lines above."
fi
