#!/bin/bash

# ============================================================================
# notify.sh — one notification helper for agent hooks, on any host
# ============================================================================
# Called from Claude Code hooks (configs/claude/settings.json) and, opt-in,
# Codex's `notify` (configs/codex/config.toml). Tries each channel in order and
# stops at the first that works:
#
#   1. herdr toast          inside a herdr pane (HERDR_ENV=1)
#   2. tmux status line     inside tmux ($TMUX)
#   3. macOS banner         osascript
#   4. Linux desktop        notify-send, when installed
#   5. ntfy push            only when NTFY_URL is set (e.g. https://ntfy.sh/topic)
#   6. nothing              silent no-op
#
# It never prints and always exits 0: hook stdout is parsed by the calling CLI,
# and a failed notification must not surface as a hook error.
#
# Usage:
#   notify.sh <title> <message> [subtitle] [sound]
#
# Examples:
#   notify.sh "Claude Code" "Task completed"
#   notify.sh "Claude Code" "Needs your approval" "Permission"
#   notify.sh "Build" "Tests passed" "CI" "Glass"
#
# Sounds (macOS only): Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse,
#   Ping, Pop, Purr, Sosumi, Submarine, Tink
# ============================================================================

TITLE="${1:-}"
MESSAGE="${2:-}"
SUBTITLE="${3:-}"
SOUND="${4:-Glass}"

[[ -n "$TITLE" && -n "$MESSAGE" ]] || exit 0

# Message with the subtitle folded in, for channels that have no subtitle field.
BODY="$MESSAGE"
[[ -n "$SUBTITLE" ]] && BODY="$SUBTITLE: $MESSAGE"

have() { command -v "$1" >/dev/null 2>&1; }

notify_herdr() {
    [[ "${HERDR_ENV:-}" == 1 ]] && have herdr || return 1
    herdr notification show "$TITLE" --body "$BODY"
}

notify_tmux() {
    [[ -n "${TMUX:-}" ]] && have tmux || return 1
    local text="[$TITLE] $BODY"
    # -l prints the text literally (tmux >= 3.4). Older tmux: escape `#` so a
    # message cannot expand formats such as #(command).
    tmux display-message -l "$text" || tmux display-message "${text//#/##}"
}

notify_macos() {
    [[ "$(uname -s)" == Darwin ]] && have osascript || return 1
    # Escape backslashes and double quotes for AppleScript string safety.
    escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    local script
    script="display notification \"$(escape "$MESSAGE")\""
    script+=" with title \"$(escape "$TITLE")\""
    [[ -n "$SUBTITLE" ]] && script+=" subtitle \"$(escape "$SUBTITLE")\""
    script+=" sound name \"$(escape "$SOUND")\""
    osascript -e "$script"
}

notify_linux_desktop() {
    have notify-send || return 1
    notify-send --app-name="$TITLE" "$TITLE" "$BODY"
}

notify_ntfy() {
    [[ -n "${NTFY_URL:-}" ]] && have curl || return 1
    curl -fsS --max-time 5 -H "Title: $TITLE" -d "$BODY" "$NTFY_URL"
}

{
    notify_herdr || notify_tmux || notify_macos || notify_linux_desktop || notify_ntfy
} >/dev/null 2>&1
exit 0
