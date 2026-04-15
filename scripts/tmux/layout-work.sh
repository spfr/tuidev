#!/usr/bin/env bash
# layout-work.sh — bare named session in $PWD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="$(basename "$PWD")"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME]    # bare attach-or-create in \$PWD"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"
layout_prelude "$@"

tmux_attach
