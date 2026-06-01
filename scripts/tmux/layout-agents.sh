#!/usr/bin/env bash
# layout-agents.sh — two columns: claude | codex.
# Each pane launches the AI CLI if present; otherwise leaves the pane as a
# shell with an install hint. (Wrappers/configs come from `--pack ai-clis`.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="agents"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # 2 columns: claude | codex"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

_install_hint() {
    case "$1" in
        claude) echo "install: npm install -g @anthropic-ai/claude-code" ;;
        codex)  echo "install: npm install -g @openai/codex" ;;
        *)      echo "install $1 via your package manager" ;;
    esac
}

_launch_or_hint() {
    local target="$1" cli="$2"
    if command_exists "$cli"; then
        run_cmd tmux send-keys -t "$target" "$cli" C-m
    else
        run_cmd tmux send-keys -t "$target" "echo '[${cli} not installed — $(_install_hint "$cli")]'" C-m
    fi
}

# Two equal columns.
run_cmd tmux split-window -t "${SESSION_NAME}:0.0" -h -p 50 -c "$PWD"

_launch_or_hint "${SESSION_NAME}:0.0" claude
_launch_or_hint "${SESSION_NAME}:0.1" codex

run_cmd tmux select-pane -t "${SESSION_NAME}:0.0"

tmux_attach
