#!/bin/bash
# scripts/lib/ui.sh - shared UI helpers for install/update/health scripts.
#
# Source this file; it defines color constants and print_* helpers. Safe to
# source multiple times (idempotent).
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/ui.sh"
#
# All helpers respect TUIDEV_NO_COLOR=1 for non-TTY / CI output.

if [[ -n "${_TUIDEV_UI_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_UI_LOADED=1

# Globals below (RED/GREEN/... and BLUE/BOLD) are the lib's public interface.
# shellcheck disable=SC2034

if [[ -n "${TUIDEV_NO_COLOR:-}" || -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    NC=''
    BOLD=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    BOLD='\033[1m'
fi

# Global dry-run toggle; callers set DRY_RUN=true|false.
: "${DRY_RUN:=false}"

print_header() {
    echo ""
    echo -e "${PURPLE}============================================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}============================================================================${NC}"
    echo ""
}

print_step()    { echo -e "${CYAN}>>> ${NC}$1"; }
print_success() { echo -e "${GREEN}✓ ${NC}$1"; }
print_warning() { echo -e "${YELLOW}⚠ ${NC}$1"; }
print_error()   { echo -e "${RED}✗ ${NC}$1"; }
print_info()    { echo -e "${CYAN}ℹ ${NC}$1"; }

# run_cmd — echo-under-dry-run wrapper. Quotes preserved via "$@".
run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $*"
    else
        "$@"
    fi
}

# Shell-form variant for pipelines: `run_sh 'brew list | grep foo'`.
run_sh() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} sh -c: $*"
    else
        bash -c "$*"
    fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

app_installed() {
    [[ -d "/Applications/$1.app" ]] || [[ -d "$HOME/Applications/$1.app" ]]
}

is_macos() { [[ "$(uname)" == "Darwin" ]]; }
is_linux() { [[ "$(uname)" == "Linux" ]]; }

die() {
    print_error "$1"
    exit "${2:-1}"
}
