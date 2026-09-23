#!/bin/bash
# scripts/lib/ui.sh - the base lib every tuidev script sources: printing,
# dry-run guarding, platform probes, and the one tuidev state-dir path.
#
# Source this file; it defines color constants and print_* helpers. Safe to
# source multiple times (idempotent).
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/ui.sh"
#
# All helpers respect TUIDEV_NO_COLOR=1 / NO_COLOR for non-TTY / CI output.

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

# Where tuidev keeps its own state: profile, manifest, env, migrations, theme,
# backups, sandbox profiles, shell.d fragments. The ONE definition — every
# script derives its state paths from this, so XDG_CONFIG_HOME is honored
# everywhere or nowhere. Deliberately not exported: a child process with a
# different HOME recomputes it.
: "${TUIDEV_STATE_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}"

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

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_macos() { [[ "$(uname)" == "Darwin" ]]; }
is_linux() { [[ "$(uname)" == "Linux" ]]; }

# _stat_fmt GNU_FORMAT BSD_FORMAT PATH — one stat field, portably. GNU first:
# BSD stat rejects -c outright, whereas GNU `stat -f` means "filesystem
# status" and would succeed with the wrong answer.
_stat_fmt() {
    stat -c "$1" "$3" 2>/dev/null || stat -f "$2" "$3" 2>/dev/null
}

# file_mode PATH — octal permission bits, e.g. "700". Empty + non-zero if absent.
file_mode()  { _stat_fmt '%a' '%Lp' "$1"; }

# file_owner PATH — owning user name.
file_owner() { _stat_fmt '%U' '%Su' "$1"; }

# file_sha256 PATH — hex SHA-256 of a file (shasum on macOS, sha256sum on Linux).
file_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        sha256sum "$1" | cut -d' ' -f1
    fi
}

die() {
    print_error "$1"
    exit "${2:-1}"
}
