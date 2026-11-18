#!/bin/bash
# scripts/lib/version.sh - tuidev's own version numbers, and the releases
# get.sh unpacks into a home: HOME/versions/X.Y.Z, HOME/current (a symlink
# to one of them) and HOME/previous (the version before).
#
# Source it; it needs no other lib. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/version.sh"
#
# Exposes:
#   version_valid V          is V a version, X.Y.Z (numbers only, no "v")?
#   version_newer A B        is version A newer than B? Part by part, as
#                            numbers: 3.10.0 is newer than 3.9.0
#   tuidev_is_release DIR    is DIR a release get.sh unpacked: no .git, a
#                            VERSION, and the get.sh that fetches the next one?
#   tuidev_release_home DIR  REPLY: the home DIR lives in, when DIR is its
#                            current or one of its versions/X.Y.Z; else false
#
# Copies that cannot source this, because they run without the repo's libs:
# bin/tuidev (_tuidev_is_version, _tuidev_newer, _tuidev_managed,
# _tuidev_release_home, and newer() in its whatsnew awk), lib/agents/release.sh
# (_agents_release_newer) and get.sh (the layout it writes). test_contract.sh
# runs each copy against these functions.

if [[ -n "${_TUIDEV_VERSION_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_VERSION_LOADED=1

version_valid() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# 10#: a leading zero is decimal, not octal.
version_newer() {
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

tuidev_is_release() { [[ ! -e "$1/.git" && -f "$1/VERSION" && -f "$1/get.sh" ]]; }

tuidev_release_home() {
    case "$1" in
        */current) REPLY="${1%/current}" ;;
        */versions/*) version_valid "${1##*/versions/}" || return 1
                      REPLY="${1%/versions/*}" ;;
        *) return 1 ;;
    esac
}
