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

# Where tuidev installs code that its commands load at run time (the agents
# modules, in agents/): ~/.local/lib/tuidev, beside ~/.local/bin, which is
# where ~/.local/bin/agents looks for it. Not a setting: the two stay paired.
# shellcheck disable=SC2034  # read by the monitoring pack and uninstall.sh
TUIDEV_LIB_DIR="$HOME/.local/lib/tuidev"

print_header() {
    echo ""
    echo -e "${PURPLE}============================================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}============================================================================${NC}"
    echo ""
}

print_step()    { echo -e "${CYAN}>>> ${NC}$1"; }
print_success() { echo -e "${GREEN}✓ ${NC}$1"; }
# Warnings are counted (TUIDEV_WARNINGS) so install.sh can say how many scrolled
# by. Counted in the calling shell: a call from a $(...) or a pipeline is lost.
TUIDEV_WARNINGS=0
print_warning() { TUIDEV_WARNINGS=$((TUIDEV_WARNINGS + 1)); echo -e "${YELLOW}⚠ ${NC}$1"; }
print_error()   { echo -e "${RED}✗ ${NC}$1"; }
print_info()    { echo -e "${CYAN}ℹ ${NC}$1"; }

# print_todo "text" — record one follow-up step for the human (an imperative
# line naming the command), to be listed again at the end of the run by
# print_todos. Identical lines are kept once. Newline-separated in a shell
# variable, so it lives in the calling shell: call it from pack functions, not
# from a $(...) or a pipeline.
TUIDEV_TODOS=""
print_todo() {
    local line="$1" nl=$'\n'
    [[ -n "$line" ]] || return 0
    case "$nl$TUIDEV_TODOS$nl" in
        *"$nl$line$nl"*) return 0 ;;
    esac
    TUIDEV_TODOS="${TUIDEV_TODOS:+$TUIDEV_TODOS$nl}$line"
}

# print_todos — the collected follow-ups, numbered, under a heading; nothing
# when there are none. Under --dry-run they are what would be needed.
print_todos() {
    [[ -n "$TUIDEV_TODOS" ]] || return 0
    local n=0 line heading="To do by hand:"
    [[ "$DRY_RUN" == true ]] && heading="Would need doing by hand (dry run):"
    echo -e "${GREEN}${heading}${NC}"
    while IFS= read -r line; do
        n=$((n + 1))
        echo -e "  $n. $line"
    done <<EOF
$TUIDEV_TODOS
EOF
}

# print_usage SCRIPT COMMAND —SCRIPT's header comment (line 2 to the first
# line that is not a comment) as its --help: without the `# ` markers or the
# `# ====` rules, and with `./NAME.sh` shown as COMMAND (`tuidev install`),
# which works for every install. Run directly from a clone, and not through
# the tuidev command (TUIDEV_VIA_CLI), it keeps `./NAME.sh`.
print_usage() {
    local self="./${1##*/}" cmd="$2"
    if [[ -z "${TUIDEV_VIA_CLI:-}" && -e "$(dirname "$1")/.git" ]]; then cmd="$self"; fi
    awk -v self="$self" -v cmd="$cmd" '
        NR == 1 { next }
        !/^#/ { exit }
        /^# *=+$/ { next }
        {
            sub(/^# ?/, "")
            out = ""
            while ((i = index($0, self)) > 0) { out = out substr($0, 1, i - 1) cmd; $0 = substr($0, i + length(self)) }
            print out $0
        }' "$1"
}

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
# get.sh has its own copy, _get_sha256 (it runs without libs; test_contract.sh).
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
