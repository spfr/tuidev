#!/bin/bash
# ============================================================================
# tuidev disk audit
# ============================================================================
# What developer and agent work has left on disk: tool caches, package stores,
# superseded runtimes, container storage, agent transcripts, build output of
# repos no one touches, leftover worktrees. Each with its size, a verdict
# (regenerable, stale, managed, yours), what it is, why, what reclaiming it
# costs, and the command. It says on stderr what it is doing (--verbose: every
# place and how).
# Reading changes nothing; nothing is deleted without a yes.
#
# Usage:
#   ./scripts/disk.sh               # summary: one line per item, grouped by what to do, then the next step
#   ./scripts/disk.sh --details     # every item in full: what, why, cost, command
#   ./scripts/disk.sh --explain ID  # one item in full (ID: the summary's third column)
#   ./scripts/disk.sh --agent       # ask Claude Code or Codex for a cleanup plan (read-only; sends them the audit)
#   ./scripts/disk.sh --json        # one JSON object, for an agent planning a cleanup
#   ./scripts/disk.sh --quick       # skip the repos in your code folders
#   ./scripts/disk.sh --min 1G      # hide items below a size (default 100M)
#   ./scripts/disk.sh --verbose     # say every place looked at and how, and which are not there
#   ./scripts/disk.sh --fix         # the plan, then ask before each tool's own cleanup command
#   ./scripts/disk.sh --fix --yes   # run the plan without asking (required without a terminal)
#   ./scripts/disk.sh --dry-run     # with --fix: print the plan, commands and log lines only
#
# --fix runs only a tool's own cleanup command, never rm, never on what is
# yours or managed, and not while something uses the item. Each command run
# is logged in ~/.config/tuidev/disk.log. Exit 0, or 2 on a bad option or ID.
# See docs/performance.md#disk.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/disk.sh disable=SC1091
. "$SCRIPT_DIR/lib/disk.sh"

FIX=false
JSON=false
DETAILS=false
AGENT=false
QUICK=""
EXPLAIN=""

# shellcheck disable=SC2034  # the DISK_* settings are read by the lib
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix|-f)     FIX=true; shift ;;
        --yes|-y)     DISK_ASSUME_YES=true; shift ;;
        --dry-run|-d) export DRY_RUN=true; shift ;;
        --json)       JSON=true; shift ;;
        --details)    DETAILS=true; shift ;;
        --agent)      AGENT=true; shift ;;
        --quick|-q)   QUICK=--quick; shift ;;
        --verbose|-v) DISK_VERBOSE=true; shift ;;
        --explain)
            [[ -n "${2:-}" ]] || { print_error "--explain takes an item ID (see --json)"; exit 2; }
            EXPLAIN="$2"; shift 2 ;;
        --min)
            kb="$(disk_parse_size "${2:-}")" || { print_error "--min takes a size: 0, 500M, 1G"; exit 2; }
            DISK_MIN_KB="$kb"; DISK_YOURS_MIN_KB="$kb"; shift 2 ;;
        --help|-h)    sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) print_error "Unknown option: $1"; exit 2 ;;
    esac
done

if $FIX && { $JSON || $AGENT || [[ -n "$EXPLAIN" ]]; }; then
    print_error "--fix goes alone: --json, --agent and --explain are for reading"
    exit 2
fi

# One line per stage; --verbose adds every place looked at and how.
# shellcheck disable=SC2034
if [[ "$DISK_VERBOSE" == true ]]; then DISK_PROGRESS=true; else DISK_PROGRESS=brief; fi
# shellcheck disable=SC2034
if [[ -t 0 ]]; then DISK_INTERACTIVE=true; fi

disk_collect ${QUICK:+"$QUICK"}

if $JSON; then
    disk_json
    exit 0
fi
if [[ -n "$EXPLAIN" ]]; then
    disk_explain "$EXPLAIN" || exit 2
    exit 0
fi

if $AGENT; then
    disk_agent || exit 1
    exit 0
fi

print_header "tuidev Disk"
if $DETAILS; then disk_report; else disk_summary; fi

if $FIX; then
    echo ""
    disk_apply
fi
