#!/usr/bin/env bash
# layout-ai.sh — nvim (60%) + 2 stacked agent panes (40% right column).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="ai"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # nvim(60%) + 2 stacked agent panes (40%)"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

run_cmd tmux send-keys -t "${SESSION_NAME}:0.0" "nvim" C-m
run_cmd tmux split-window -t "${SESSION_NAME}:0.0" -h -p 40 -c "$PWD"
run_cmd tmux split-window -t "${SESSION_NAME}:0.1" -v -p 50 -c "$PWD"
run_cmd tmux select-pane -t "${SESSION_NAME}:0.0"

tmux_attach
