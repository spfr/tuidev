# shellcheck shell=bash
# Source this (bash, from the repo root) to get the screenshot demo shell:
# a throwaway HOME (DEMO_HOME, made here unless set) with three made-up
# projects, a generic two-line prompt, the repo's sbx, and the demo `agents`
# that reads fixtures/ instead of this machine. See README.md next to it.
_demo_tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_demo_repo="$(cd "$_demo_tapes/../../.." && pwd)"

# A time zone where it is mid-afternoon now, so the made-up history
# (demo-history.sh) has a full working day behind its "Today" whenever the
# shots are rendered, and the report's busiest hours stay the same.
_demo_off=$(( (15 - 10#$(date -u +%H) + 36) % 24 - 12 ))
if [[ $_demo_off -ge 0 ]]; then TZ="Etc/GMT-$_demo_off"; else TZ="Etc/GMT+${_demo_off#-}"; fi
export TZ
unset _demo_off

if [[ -z "${DEMO_HOME:-}" ]]; then
    DEMO_HOME="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-demo.XXXXXX")/NAME"
fi
bash "$_demo_tapes/demo-setup.sh" "$DEMO_HOME"
# Seatbelt matches real paths, so resolve symlinks (/tmp, /var/folders).
DEMO_HOME="$(cd "$DEMO_HOME" && pwd -P)"
export DEMO_HOME HOME="$DEMO_HOME"
export PATH="$_demo_tapes/bin:$_demo_repo/bin:$PATH"
export HISTFILE=/dev/null
unset PROMPT_COMMAND _demo_repo _demo_tapes

# The shape of the shipped Starship prompt, without reading this machine
# (user, host, git state) the way Starship would.
PS1='\[\e[1;32m\]╭─\[\e[1;36m\]\w\[\e[0m\]\n\[\e[1;32m\]╰─❯\[\e[0m\] '
cd "$HOME/myapp" || return
