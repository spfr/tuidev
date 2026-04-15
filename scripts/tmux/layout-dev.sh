#!/usr/bin/env bash
# layout-dev.sh — 3 columns: nvim (55%) | agent (25%) | runner (20%).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="dev"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # nvim(55%) | agent(25%) | runner(20%)"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

run_cmd tmux send-keys -t "${SESSION_NAME}:0.0" "nvim" C-m
run_cmd tmux split-window -t "${SESSION_NAME}:0.0" -h -p 45 -c "$PWD"
run_cmd tmux split-window -t "${SESSION_NAME}:0.1" -h -p 44 -c "$PWD"
run_cmd tmux select-pane -t "${SESSION_NAME}:0.0"

tmux_attach
