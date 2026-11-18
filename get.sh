#!/bin/bash
# get.sh - install tuidev without git: download a release, check it, run its
# installer.
#
#   curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash
#       asks what this machine should get, then asks before it installs
#   curl -fsSL .../get.sh | bash -s -- --profile full
#       the installer's flags, for a choice you already made
#   bash get.sh --fetch            # download only; print where it is
#
# What it does, in order:
#   1. downloads tuidev.tar.gz and tuidev.tar.gz.sha256 from the release;
#   2. refuses the archive unless its sha256 matches, and unless every path in
#      it sits under one tuidev-X.Y.Z/ directory;
#   3. unpacks it to $TUIDEV_HOME/versions/X.Y.Z;
#   4. asks once, then points $TUIDEV_HOME/current at it (the version before
#      stays, for a rollback) and runs that copy's ./install.sh with your
#      arguments. The installer's own --dry-run previews every change, and
#      answering "p" here runs it for you first. With no terminal to ask on
#      (CI, a container build), it installs only with --yes.
#
# Nothing else is downloaded or run by this file. `tuidev update` uses its
# --fetch for later releases, so this is the only code that fetches tuidev.
#
# Options (everything else goes to install.sh):
#   --fetch      download and unpack only; print the version's directory
#   --yes, -y    do not ask before installing (required without a terminal)
#
# Environment:
#   TUIDEV_VERSION      a release tag (v3.23.0) instead of the latest
#   TUIDEV_HOME         where releases are kept (~/.local/share/tuidev)
#   TUIDEV_RELEASE_URL  the releases base URL (a mirror, or a test's file://)
#
# The checksum guards against a truncated or mismatched download; that the
# files are tuidev's rests on HTTPS to github.com, as it does for this script.
# bash 3.2. Needs curl, tar and shasum or sha256sum. No libs: it runs before
# anything is on disk, so _get_sha256, _get_flip and the layout it writes have
# twins (scripts/lib/ui.sh, bin/tuidev, scripts/lib/version.sh) that
# test_contract.sh compares.

set -eo pipefail

_GET_TMP="" _GET_DEST=""

_get_say()  { printf '%s\n' "tuidev: $*" >&2; }
_get_die()  { _get_say "$*"; exit 1; }
_get_tty()  { { : < /dev/tty; } 2>/dev/null; }

# On the way out of _get_fetch, however it ends: a re-fetch of the version
# already there that was cut between its two moves puts the old tree back.
_get_cleanup() {
    if [[ -n "$_GET_DEST" && ! -e "$_GET_DEST" && -d "$_GET_TMP/old" ]]; then mv "$_GET_TMP/old" "$_GET_DEST"; fi
    [[ -z "$_GET_TMP" ]] || rm -rf "$_GET_TMP"
}

_get_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1" 2>/dev/null; fi | cut -d' ' -f1
}

# _get_fetch — download, verify and unpack; GET_VERSION and GET_DIR on success.
_get_fetch() {
    local base="${TUIDEV_RELEASE_URL:-https://github.com/spfr/tuidev/releases}" from tmp want got top v dest
    local home="${TUIDEV_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/tuidev}"
    command -v curl >/dev/null 2>&1 || _get_die "curl is needed"
    command -v tar >/dev/null 2>&1 || _get_die "tar is needed"
    # https stays https through every redirect, a ~/.curlrc changes nothing,
    # and the archive (about 1 MB) gets 5 minutes and 64 MB at most.
    local curl=(curl -q -fsSL --retry 2 --connect-timeout 15 --max-time 300 --max-filesize 67108864)
    case "$base" in https://*) curl+=(--proto '=https' --proto-redir '=https') ;; esac

    if [[ -n "${TUIDEV_VERSION:-}" ]]; then
        [[ "$TUIDEV_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || _get_die "TUIDEV_VERSION must look like v3.23.0"
        from="$base/download/$TUIDEV_VERSION"
    else
        from="$base/latest/download"
    fi

    [[ ! -L "$home/versions" ]] || _get_die "$home/versions is a symlink: refusing to unpack or prune through it"
    mkdir -p "$home/versions"
    tmp="$(mktemp -d "$home/.get.XXXXXX")"
    _GET_TMP="$tmp"
    trap _get_cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

    _get_say "downloading $from/tuidev.tar.gz"
    "${curl[@]}" -o "$tmp/tuidev.tar.gz" "$from/tuidev.tar.gz" \
        || _get_die "download failed: $from/tuidev.tar.gz (releases before 3.23.0 have no archive: clone the repo for those)"
    "${curl[@]}" -o "$tmp/sum" "$from/tuidev.tar.gz.sha256" \
        || _get_die "download failed: $from/tuidev.tar.gz.sha256"

    read -r want _ < "$tmp/sum" || true
    [[ "$want" =~ ^[0-9a-f]{64}$ ]] || _get_die "the release's checksum file is not a sha256"
    got="$(_get_sha256 "$tmp/tuidev.tar.gz")" || _get_die "shasum or sha256sum is needed to check the download"
    [[ "$got" == "$want" ]] || _get_die "checksum mismatch (expected $want, got $got): nothing installed"

    # One top directory, tuidev-X.Y.Z, and no path that climbs out of it.
    tar -tzf "$tmp/tuidev.tar.gz" > "$tmp/list" || _get_die "the archive does not list"
    top="$(head -1 "$tmp/list")"; top="${top%%/*}"
    [[ "$top" =~ ^tuidev-([0-9]+\.[0-9]+\.[0-9]+)$ ]] || _get_die "unexpected archive layout: $top"
    v="${BASH_REMATCH[1]}"
    if grep -qvE "^${top//./\\.}(/|\$)" "$tmp/list" || grep -qE '(^|/)\.\.(/|$)' "$tmp/list"; then
        _get_die "the archive has paths outside $top: nothing installed"
    fi

    # -o: files belong to whoever runs this, never to an owner the archive
    # names. tuidev ships no symlinks or hard links, so one in the archive is
    # refused: its target could lie outside the directory.
    mkdir "$tmp/x"
    tar -xzof "$tmp/tuidev.tar.gz" -C "$tmp/x" || _get_die "the archive does not unpack"
    [[ -z "$(find "$tmp/x" -type l 2>/dev/null | head -1)" ]] \
        || _get_die "the archive holds a symlink: nothing installed"
    [[ -z "$(find "$tmp/x" -type f -links +1 2>/dev/null | head -1)" ]] \
        || _get_die "the archive holds a hard link: nothing installed"
    [[ -f "$tmp/x/$top/install.sh" && "$(cat "$tmp/x/$top/VERSION" 2>/dev/null)" == "$v" ]] \
        || _get_die "the archive is not tuidev $v: nothing installed"

    # In place of an earlier download of the same version (_get_cleanup puts
    # it back if this stops halfway). `current` is not moved here:
    # _get_activate does that, once the install is going ahead.
    dest="$home/versions/$v"
    _GET_DEST="$dest"
    if [[ -d "$dest" ]]; then mv "$dest" "$tmp/old"; fi
    mv "$tmp/x/$top" "$dest" || _get_die "could not put the release at $dest: nothing changed"
    _GET_DEST=""
    trap - INT TERM HUP EXIT
    _get_cleanup; _GET_TMP=""
    GET_VERSION="$v" GET_HOME="$home" GET_DIR="$home/current" GET_UNPACKED="$dest"
}

# _get_flip HOME VERSION — HOME/current to versions/VERSION in one rename, so
# it never dangles (ln -sfn unlinks first): mv -T is GNU's, mv -h BSD's, and
# ln -sfn the fallback. A current that is not a link is left alone.
_get_flip() {
    local link="$1/current" tmp="$1/.current.$$"
    [[ -L "$link" || ! -e "$link" ]] || return 1
    rm -f "$tmp" && ln -s "versions/$2" "$tmp" || return 1
    mv -T "$tmp" "$link" 2>/dev/null || mv -h "$tmp" "$link" 2>/dev/null \
        || { rm -f "$tmp"; ln -sfn "versions/$2" "$link"; }
}

# _get_activate — point `current` at the version _get_fetch unpacked, remember
# the one before it, and drop older ones.
_get_activate() {
    local home="$GET_HOME" v="$GET_VERSION" prev=""
    [[ -L "$home/current" ]] && prev="$(readlink "$home/current")" && prev="${prev##*/}"
    _get_flip "$home" "$v" || _get_die "$home/current is not a symlink: nothing installed"
    if [[ -n "$prev" && "$prev" != "$v" ]]; then printf '%s\n' "$prev" > "$home/previous"; fi

    # Keep this version and the one before it (a running update still reads
    # its files from there); older ones go.
    local d keep=""
    [[ ! -r "$home/previous" ]] || read -r keep < "$home/previous" || true
    for d in "$home/versions"/*/; do
        d="${d%/}"
        # Only what this script put there: directories named as versions.
        [[ ! -L "$d" && "${d##*/}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        [[ "${d##*/}" == "$v" || "${d##*/}" == "$keep" ]] || rm -rf "$d"
    done
}

_get_main() {
    local fetch_only=false yes=false args=() a reply=""
    # The call below ends in --get-end: a script cut inside that line would
    # otherwise run with the arguments it lost.
    [[ $# -gt 0 && "${!#}" == --get-end ]] || _get_die "this script is cut short: nothing installed"
    set -- "${@:1:$(( $# - 1 ))}"
    for a in "$@"; do
        case "$a" in
            --fetch)  fetch_only=true ;;
            --yes|-y) yes=true ;;
            *)        args+=("$a") ;;
        esac
    done

    _get_fetch
    if [[ "$fetch_only" == true ]]; then
        _get_activate
        printf '%s\n' "$GET_DIR"
        return 0
    fi

    _get_say "tuidev $GET_VERSION is in $GET_UNPACKED"
    # No flags and someone to ask: the installer's own question says what
    # this machine should get (install.sh --choose prints the flags).
    if [[ ${#args[@]} -eq 0 && "$yes" == false ]] && _get_tty; then
        reply="$("$GET_UNPACKED/install.sh" --choose < /dev/tty)" \
            || { _get_say "nothing installed, and an install you already have is as it was. Later: bash get.sh"; return 0; }
        [[ "$reply" =~ ^--[a-z]+(\ [a-z-]+)*$ ]] || _get_die "unexpected answer from the installer: nothing installed"
        # shellcheck disable=SC2206  # fixed words, split on spaces
        args=($reply)
    fi
    local shown="./install.sh${args[*]:+ ${args[*]}}"
    # Piped from curl, stdin is this script: the question and the installer
    # read the terminal instead. Without one (CI, a container build, an
    # agent) there is nobody to ask, so nothing runs unless --yes says so.
    if [[ "$yes" == false ]] && ! _get_tty; then
        _get_say "no terminal to ask on, so nothing was installed. Either add --yes:"
        _get_say "  curl -fsSL ... | bash -s -- --yes${args[*]:+ ${args[*]}}"
        _get_die "or preview first: $GET_UNPACKED/install.sh${args[*]:+ ${args[*]}} --dry-run"
    fi
    if [[ "$yes" == false ]]; then
        while :; do
            printf '%s' "tuidev: run $shown now? [Y]es / [p]review first (--dry-run) / [n]o: " >&2
            read -r reply < /dev/tty || reply=n
            case "$reply" in
                p|P) "$GET_UNPACKED/install.sh" ${args[@]+"${args[@]}"} --dry-run < /dev/tty || true ;;
                n|N) _get_say "nothing installed, and an install you already have is as it was. Later: bash get.sh"; return 0 ;;
                ""|y|Y) break ;;
            esac
        done
    fi
    _get_activate
    # The installer reads the terminal when one was asked for or flags were
    # given with one there; --yes alone installs with nothing to read.
    if [[ "$yes" == false || ${#args[@]} -gt 0 ]] && _get_tty; then
        _get_install ${args[@]+"${args[@]}"} < /dev/tty
    else
        _get_install ${args[@]+"${args[@]}"} < /dev/null
    fi
}

# _get_install ARGS... — the activated release's installer; when it fails,
# say that the install is not complete, and how to go back or on.
_get_install() {
    local rc=0 prev=""
    "$GET_DIR/install.sh" "$@" || rc=$?
    [[ $rc -ne 0 ]] || return 0
    [[ ! -r "$GET_HOME/previous" ]] || read -r prev < "$GET_HOME/previous" || true
    _get_say "the installer stopped (exit $rc): tuidev $GET_VERSION is not completely installed."
    [[ -z "$prev" || ! -d "$GET_HOME/versions/$prev" ]] || _get_say "Back to $prev: tuidev update --rollback. Or:"
    _get_say "fix what it said, then run it again: $GET_DIR/install.sh${*:+ $*}"
    return "$rc"
}

# Called on the last line, so a download cut short runs nothing.
_get_main "$@" --get-end
