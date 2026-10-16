#!/bin/bash
# scripts/lib/release.sh - install one asset of a GitHub release, checked
# against the sha256 digest the release itself lists.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/release.sh"
#
# Exposes:
#   release_json REPO TAG                the release's API record (TAG: latest or vX.Y.Z)
#   release_asset_field JSON ASSET KEY   one field of one asset (digest, browser_download_url)
#   release_install REPO TAG ASSET DEST  download, verify, and put ASSET at DEST
#
# The GitHub API lists a `digest` (sha256:HEX) for every release asset. An
# asset without one, or a download that doesn't match it, is refused and DEST
# is left as it was. The download lands in a temp file beside DEST and
# replaces it in one rename, so a process running the old DEST keeps its inode
# and a failed download never leaves half a binary. Nothing is piped into a
# shell. An interrupt (Ctrl-C, SIGTERM, SIGHUP) mid-download removes the temp
# file and then acts as it would have: the caller's own trap runs, or the
# shell dies of the signal. Needs curl and jq. Under DRY_RUN it only says what
# it would fetch: no network, no writes. On success RELEASE_TAG holds the tag
# it installed.

if [[ -n "${_TUIDEV_RELEASE_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_RELEASE_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

# shellcheck disable=SC2034  # read by callers
RELEASE_TAG=""

release_json() {
    local url="https://api.github.com/repos/$1/releases/latest"
    [[ "$2" == latest ]] || url="https://api.github.com/repos/$1/releases/tags/$2"
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
        -H 'Accept: application/vnd.github+json' "$url"
}

release_asset_field() {
    printf '%s' "$1" | jq -r --arg a "$2" --arg k "$3" \
        'first(.assets[]? | select(.name == $a) | .[$k] // empty) // empty' 2>/dev/null
}

# The temp file a download is writing, and the traps it displaced (bash 3.2
# also reports the shell's traps to `trap -p` in a command substitution).
_RELEASE_TMP=""
_RELEASE_TRAP_INT="" _RELEASE_TRAP_TERM="" _RELEASE_TRAP_HUP=""
_RELEASE_TRAPPED=false

_release_traps_set() {
    _RELEASE_TRAP_INT="$(trap -p INT)"
    _RELEASE_TRAP_TERM="$(trap -p TERM)"
    _RELEASE_TRAP_HUP="$(trap -p HUP)"
    _RELEASE_TRAPPED=true
    trap '_release_interrupted INT' INT
    trap '_release_interrupted TERM' TERM
    trap '_release_interrupted HUP' HUP
}

# Once only: after an interrupt, the caller's traps are already back.
_release_traps_restore() {
    local t
    [[ "$_RELEASE_TRAPPED" == true ]] || return 0
    _RELEASE_TRAPPED=false
    trap - INT TERM HUP
    for t in "$_RELEASE_TRAP_INT" "$_RELEASE_TRAP_TERM" "$_RELEASE_TRAP_HUP"; do
        [[ -z "$t" ]] || eval "$t"
    done
    _RELEASE_TRAP_INT="" _RELEASE_TRAP_TERM="" _RELEASE_TRAP_HUP="" _RELEASE_TMP=""
}

# Clean up, put the displaced traps back, then do what the signal would have
# done without us: run the caller's trap for it, or re-raise it on this very
# (sub)shell so it dies of it. (Re-raising doesn't reach a caller's trap: bash
# 3.2 drops a signal that arrives while its own trap runs.) bash 3.2 has no
# BASHPID; a child exec'd from a command substitution reports the shell that
# ran it as its parent.
_release_interrupted() {
    local sig="$1" saved
    [[ -z "$_RELEASE_TMP" ]] || rm -f "$_RELEASE_TMP"
    eval "saved=\"\${_RELEASE_TRAP_$sig}\""
    _release_traps_restore
    if [[ -n "$saved" ]]; then
        eval "set -- $saved"   # trap -- 'ACTION' SIGNAME
        eval "$3"              # in this function's scope: its locals shadow
    else
        kill -s "$sig" "${BASHPID:-$(exec sh -c 'echo "$PPID"')}"
    fi
}

# Download URL to PART, check it against WANT, and rename it onto DEST.
_release_fetch() {
    local asset="$1" url="$2" want="$3" part="$4" dest="$5" got
    if ! curl -fsSL --retry 2 --connect-timeout 10 --max-time 300 -o "$part" "$url"; then
        rm -f "$part"
        print_warning "download of $asset failed"
        return 1
    fi
    got="$(file_sha256 "$part")"
    if [[ "$got" != "$want" ]]; then
        rm -f "$part"
        print_warning "$asset checksum mismatch (expected $want, got ${got:-none}); nothing installed"
        return 1
    fi
    if ! chmod 755 "$part" || ! mv -f "$part" "$dest"; then
        rm -f "$part"
        print_warning "could not put $asset in place at $dest"
        return 1
    fi
}

release_install() {
    local repo="$1" tag="$2" asset="$3" dest="$4" json want url part rc=0
    RELEASE_TAG=""
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} download $asset ($tag) from github.com/$repo, check its sha256, install as $dest"
        return 0
    fi
    if ! command_exists curl || ! command_exists jq; then
        print_warning "downloading $asset needs curl and jq"
        return 1
    fi
    if [[ -L "$dest" && -d "$dest" ]]; then
        print_warning "$dest links to a directory; not replacing it"
        return 1
    fi
    json="$(release_json "$repo" "$tag")" || {
        print_warning "could not read release $tag of $repo from the GitHub API"
        return 1
    }
    want="$(release_asset_field "$json" "$asset" digest)"
    want="$(printf '%s' "${want#sha256:}" | tr 'A-F' 'a-f')"
    if ! [[ "$want" =~ ^[0-9a-f]{64}$ ]]; then
        print_warning "$repo $tag lists no sha256 digest for $asset; refusing to install it unverified"
        return 1
    fi
    url="$(release_asset_field "$json" "$asset" browser_download_url)"
    case "$url" in
        "https://github.com/$repo/releases/download/"*) ;;
        *) print_warning "unexpected download URL for $asset: ${url:-none}"; return 1 ;;
    esac

    mkdir -p "$(dirname "$dest")" || return 1
    _release_traps_set
    if part="$(mktemp "$(dirname "$dest")/.${asset}.XXXXXX")"; then
        _RELEASE_TMP="$part"
        _release_fetch "$asset" "$url" "$want" "$part" "$dest" || rc=$?
    else
        rc=1
    fi
    _release_traps_restore
    [[ $rc -eq 0 ]] || return "$rc"
    # shellcheck disable=SC2034  # read by callers
    RELEASE_TAG="$(printf '%s' "$json" | jq -r '.tag_name // empty' 2>/dev/null)"
    return 0
}
