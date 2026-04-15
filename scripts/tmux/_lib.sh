#!/bin/bash
# scripts/tmux/_lib.sh - shared preamble for layout-*.sh scripts.
#
# Each layout-X.sh script sources this file and calls layout_prelude.
# Behavior:
#   - Handle --help/-h (print USAGE and exit 0).
#   - Verify tmux is on PATH (exit 127 with a helpful error otherwise).
#   - Short-circuit to attach if a session with SESSION_NAME already exists.
#   - Export SESSION_NAME and a helper tmux_send that wraps run_cmd.
#
# Callers set:
#   LAYOUT_DEFAULT_NAME   default session name if no arg given
#   LAYOUT_USAGE          one-line usage string (auto-prefixed with script)
#
# Then call:
#   layout_prelude "$@"
#
# After layout_prelude returns, the script can build its layout assuming a
# fresh detached session already exists (created by this lib) and focus is
# on pane 0.0. No further existence checks are needed.

if [[ -n "${_TUIDEV_TMUX_LIB_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_TMUX_LIB_LOADED=1

# shellcheck source=../lib/ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../lib/ui.sh"

layout_prelude() {
    : "${LAYOUT_DEFAULT_NAME:?layout_prelude: set LAYOUT_DEFAULT_NAME first}"
    : "${LAYOUT_USAGE:=[SESSION_NAME]}"

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo "Usage: $(basename "$0") $LAYOUT_USAGE"
        exit 0
    fi

    if ! command_exists tmux; then
        print_error "tmux is not installed. Install with: brew install tmux"
        exit 127
    fi

    SESSION_NAME="${1:-$LAYOUT_DEFAULT_NAME}"
    export SESSION_NAME

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        run_cmd tmux attach-session -t "$SESSION_NAME"
        exit 0
    fi

    # Create a detached session with a reasonable default geometry. Callers
    # then split, send keys, etc. and finish with `tmux_attach`.
    run_cmd tmux new-session -d -s "$SESSION_NAME" -c "$PWD" -x 220 -y 50
}

# Attach to the session created by layout_prelude. Every layout script should
# call this as its last line.
tmux_attach() {
    run_cmd tmux attach-session -t "$SESSION_NAME"
}
