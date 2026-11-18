# shellcheck shell=bash
# lib/agents/release.sh — is a newer tuidev out?
#
# Owns: reading what the `tuidev` command keeps about releases (the installed
#   version, the latest release heard of, when the next check is due), and
#   starting that check when it is due.
# Uses: util.sh (_agents_now, _agents_detach), config.sh (AGENTS_RUN_DIR).
# Public: _agents_release, _agents_release_row, _agents_release_line,
#   _agents_release_newer.
#
# The check itself is `tuidev latest` (bin/tuidev): one request a day to
# github.com for the latest release's tag, off with `tuidev latest off`.
# Nothing here asks the network or forks unless that check is due, and then it
# is started detached and never waited on: this run shows what was known, the
# next one what was found. Two files, read with builtins:
#   $TUIDEV_STATE_DIR/version         X.Y.Z, written by install and update
#   ~/.cache/tuidev/latest            "X.Y.Z NEXT CHECKED" ("-" for none yet)
# Their paths and the comparison are copies of bin/tuidev's (this module runs
# without it and without the repo); test_contract.sh keeps them in step.

# _agents_release — true when a release newer than the installed one is
# known: REPLY its version, REPLY_HAVE the installed one. Starts the check
# when it is due (and `tuidev` is installed beside agents).
_agents_release() {
    local have="" latest="-" next=0 now cli="${AGENTS_PATH%/*}/tuidev"
    REPLY="" REPLY_HAVE=""
    { IFS=$' \t\n' read -r have < "${TUIDEV_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}/version"; } 2>/dev/null || true
    { IFS=$' \t\n' read -r latest next _ < "${XDG_CACHE_HOME:-$HOME/.cache}/tuidev/latest"; } 2>/dev/null || true
    [[ "$next" =~ ^[0-9]+$ ]] || next=0
    _agents_now now
    if (( now >= next )) && [[ -x "$cli" && -z "${AGENTS_TESTING:-}" ]]; then
        # At most one start an hour from here, whatever becomes of it: with a
        # cache `tuidev` cannot write, the check would stay due on every run.
        local kicked=0
        { read -r kicked < "$AGENTS_RUN_DIR/release.kick"; } 2>/dev/null || true
        [[ "$kicked" =~ ^[0-9]+$ ]] || kicked=0
        if (( now - kicked >= 3600 )) && { printf '%s\n' "$now" > "$AGENTS_RUN_DIR/release.kick"; } 2>/dev/null; then
            _agents_detach "$cli" latest --if-due --notify
        fi
    fi
    [[ "$have" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    _agents_release_newer "$latest" "$have" || return 1
    REPLY="$latest" REPLY_HAVE="$have"
}

# _agents_release_newer A B — is version A newer than B? Both X.Y.Z; part by
# part as numbers, so 3.10.0 is newer than 3.9.0.
_agents_release_newer() {
    local a b i re='^([0-9]+)\.([0-9]+)\.([0-9]+)$'
    # Split with the match itself: no IFS to set, and none of the caller's to trust.
    [[ "$1" =~ $re ]] || return 1
    a=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
    [[ "$2" =~ $re ]] || return 1
    b=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
    for i in 0 1 2; do
        (( 10#${a[i]} > 10#${b[i]} )) && return 0
        (( 10#${a[i]} < 10#${b[i]} )) && return 1
    done
    return 1
}

# _agents_release_row — `agents tsv`: "release INSTALLED LATEST" while a newer
# release is known, else nothing.
_agents_release_row() {
    _agents_release || return 0
    printf 'release\t%s\t%s\n' "$REPLY_HAVE" "$REPLY"
}

# _agents_release_line — the same for people, one line, else nothing.
_agents_release_line() {
    _agents_release || return 0
    printf 'tuidev %s is out (you have %s): tuidev update\n' "$REPLY" "$REPLY_HAVE"
}
