#!/bin/bash

# ============================================================================
# macOS Notification Wrapper
# ============================================================================
# Sends native macOS notifications via osascript.
# Falls back to echo on non-macOS systems.
#
# Usage:
#   notify.sh <title> <message> [subtitle] [sound]
#
# Examples:
#   notify.sh "Claude Code" "Task completed"
#   notify.sh "Claude Code" "Needs your input" "Approval Required"
#   notify.sh "Build" "Tests passed" "CI" "Glass"
#
# Sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping,
#          Pop, Purr, Sosumi, Submarine, Tink
# ============================================================================

set -e

TITLE="${1:?Usage: notify.sh <title> <message> [subtitle] [sound]}"
MESSAGE="${2:?Usage: notify.sh <title> <message> [subtitle] [sound]}"
SUBTITLE="${3:-}"
SOUND="${4:-Glass}"

if [[ "$(uname)" == "Darwin" ]]; then
    # Escape backslashes and double quotes for AppleScript string safety
    escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    script="display notification \"$(escape "$MESSAGE")\""
    script+=" with title \"$(escape "$TITLE")\""
    [[ -n "$SUBTITLE" ]] && script+=" subtitle \"$(escape "$SUBTITLE")\""
    script+=" sound name \"$(escape "$SOUND")\""
    osascript -e "$script"
else
    # Fallback for non-macOS
    echo "[${TITLE}] ${MESSAGE}"
    [[ -n "$SUBTITLE" ]] && echo "  ${SUBTITLE}"
fi
