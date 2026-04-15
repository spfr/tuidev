#!/usr/bin/env bash
# layout-fullstack.sh — five windows: code / web / api / db / logs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="fullstack"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # five windows: code / web / api / db / logs"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

run_cmd tmux rename-window -t "${SESSION_NAME}:0" code
run_cmd tmux send-keys -t "${SESSION_NAME}:code.0" "nvim" C-m
for w in web api db logs; do
    run_cmd tmux new-window -t "$SESSION_NAME" -n "$w" -c "$PWD"
done
run_cmd tmux select-window -t "${SESSION_NAME}:code"

tmux_attach
