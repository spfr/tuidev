#!/usr/bin/env bash
# layout-multi.sh — three windows: dev (3-col) / monitor / git.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="multi"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # 3 windows: dev / monitor / git"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

# Window 1: dev (mirror of layout-dev).
run_cmd tmux rename-window -t "${SESSION_NAME}:0" dev
run_cmd tmux send-keys -t "${SESSION_NAME}:dev.0" "nvim" C-m
run_cmd tmux split-window -t "${SESSION_NAME}:dev.0" -h -p 45 -c "$PWD"
run_cmd tmux split-window -t "${SESSION_NAME}:dev.1" -h -p 44 -c "$PWD"
run_cmd tmux select-pane -t "${SESSION_NAME}:dev.0"

# Window 2: monitor (btop → top fallback).
run_cmd tmux new-window -t "$SESSION_NAME" -n monitor -c "$PWD"
if command_exists btop; then
    run_cmd tmux send-keys -t "${SESSION_NAME}:monitor" "btop" C-m
else
    run_cmd tmux send-keys -t "${SESSION_NAME}:monitor" "top" C-m
fi

# Window 3: git (lazygit → git status fallback).
run_cmd tmux new-window -t "$SESSION_NAME" -n git -c "$PWD"
if command_exists lazygit; then
    run_cmd tmux send-keys -t "${SESSION_NAME}:git" "lazygit" C-m
else
    run_cmd tmux send-keys -t "${SESSION_NAME}:git" "git status" C-m
fi

run_cmd tmux select-window -t "${SESSION_NAME}:dev"

tmux_attach
