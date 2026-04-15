#!/usr/bin/env bash
# layout-remote.sh — nvim (70%) + shell (30%), keystroke-friendly for
# mosh/SSH over high-latency or narrow-terminal connections.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="remote"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # minimal nvim(70%) + shell(30%) for remote/narrow"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

run_cmd tmux send-keys -t "${SESSION_NAME}:0.0" "nvim" C-m
run_cmd tmux split-window -t "${SESSION_NAME}:0.0" -h -p 30 -c "$PWD"
run_cmd tmux select-pane -t "${SESSION_NAME}:0.0"

tmux_attach
