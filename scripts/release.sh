#!/bin/bash
# scripts/release.sh - the steps of .github/workflows/release.yml, kept here so
# they are shellchecked and tested (scripts/lib/test_release.sh) like the rest.
#
#   scripts/release.sh check TAG [--ref GITHUB_REF] [--on BRANCH]
#       refuse to release unless TAG is vX.Y.Z, names the commit checked out,
#       matches the committed VERSION, and CHANGELOG.md's newest section is
#       that version with notes in it. --ref: the ref the workflow runs on
#       must be that tag (so the provenance names the commit it built).
#       --on: the commit must be on BRANCH (origin/main in the workflow).
#   scripts/release.sh notes TAG
#       the release notes: that CHANGELOG section without its heading, as
#       `tuidev whatsnew` prints it
#   scripts/release.sh publish TAG DIR NOTES_FILE [--attach-missing]
#       create the GitHub release TAG with the three assets in DIR. A release
#       that exists is never changed: it is refused, or with --attach-missing
#       only the assets it lacks are uploaded, once the ones it has are the
#       same bytes as DIR's. Needs gh, with GH_TOKEN and GH_REPO set.
#
# The assets are what scripts/dist.sh builds and get.sh downloads;
# test_contract.sh keeps the names the same in all four places.

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
# shellcheck source=lib/version.sh disable=SC1091
. "$REPO_DIR/scripts/lib/version.sh"

ASSETS=(tuidev.tar.gz tuidev.tar.gz.sha256 get.sh)

die() { echo "release: $*" >&2; exit 1; }
say() { echo "release: $*" >&2; }

# _version TAG — REPLY: X.Y.Z out of vX.Y.Z, or die.
_version() {
    REPLY="${1#v}"
    [[ "${1:-}" == "v$REPLY" ]] && version_valid "$REPLY" && return 0
    die "the tag must look like v3.23.0 (got '${1:-}')"
}

# The section, from bin/tuidev's own reader, so the notes are what
# `tuidev whatsnew` shows, less the heading (the release has its own title).
cmd_notes() {
    local v out heading body
    _version "${1:-}"; v="$REPLY"
    out="$(TUIDEV_REPO="$REPO_DIR" "$REPO_DIR/bin/tuidev" whatsnew)" || die "tuidev whatsnew failed"
    heading="${out%%$'\n'*}"
    [[ "$heading" == "## [$v]"* ]] || die "CHANGELOG.md's newest section is '${heading:-none}', not $v"
    body=""
    if [[ "$out" == *$'\n'* ]]; then body="${out#*$'\n'}"; fi
    # From the first line with text; $( ) drops the blank lines at the end.
    body="$(printf '%s\n' "$body" | awk 'NF { on = 1 } on')"
    [[ -n "$body" ]] || die "CHANGELOG.md's section for $v is empty"
    printf '%s\n' "$body"
}

cmd_check() {
    local tag="${1:-}" v ref="" on="" head tagged committed newest
    _version "$tag"; v="$REPLY"
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ref) ref="${2:-}"; shift 2 ;;
            --on)  on="${2:-}"; shift 2 ;;
            *) die "check: unknown argument '$1'" ;;
        esac
    done
    if [[ -n "$ref" && "$ref" != "refs/tags/$tag" ]]; then
        die "this run is on $ref, not on the tag $tag. Run it from the tag: gh workflow run release.yml --ref $tag -f tag=$tag"
    fi
    head="$(git rev-parse --verify -q HEAD)" || die "no commit checked out"
    tagged="$(git rev-parse --verify -q "refs/tags/$tag^{commit}")" || die "there is no tag $tag here"
    [[ "$head" == "$tagged" ]] || die "the checkout ($head) is not the commit $tag names ($tagged)"
    committed="$(git show HEAD:VERSION 2>/dev/null)" || committed=""
    [[ "$committed" == "$v" ]] || die "the tag says $v, the committed VERSION says '${committed}'"
    # awk reads it all: a reader that stops at the first match would leave
    # git show a closed pipe, and pipefail would take that for a failure.
    newest="$(git show HEAD:CHANGELOG.md 2>/dev/null | awk '!h && /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { h = $0 } END { print h }')" || newest=""
    [[ "$newest" == "## [$v]"* ]] || die "CHANGELOG.md's newest section is '${newest:-none}', not $v"
    if [[ -n "$on" ]]; then
        git rev-parse --verify -q "$on^{commit}" >/dev/null || die "there is no $on to check $tag against"
        git merge-base --is-ancestor HEAD "$on" || die "$tag is not on $on: release from a commit that is"
    fi
    cmd_notes "$tag" >/dev/null
    say "$tag: tag, VERSION and CHANGELOG.md agree${on:+, and it is on $on}"
}

# _latest_flag V TMP — REPLY: gh's --latest, or --latest=false when a newer
# release than V is out. releases/latest is what get.sh and `tuidev update`
# download: an older version released late must not take it over.
_latest_flag() {
    local latest
    REPLY=--latest
    if latest="$(gh release view --json tagName --jq .tagName 2>"$2/err")"; then
        if [[ "$latest" == v* ]] && version_valid "${latest#v}" && ! version_newer "$1" "${latest#v}"; then
            REPLY=--latest=false
            say "$latest is newer than v$1: v$1 does not become the latest release"
        fi
    elif ! grep -q "not found" "$2/err"; then
        die "could not ask GitHub for the latest release: $(cat "$2/err")"
    fi
}

cmd_publish() {
    local tag="${1:-}" dir="${2:-}" notes="${3:-}" attach=false v a info state names tmp
    local files=() missing=()
    _version "$tag"; v="$REPLY"
    case "${4:-}" in
        "") ;;
        --attach-missing) attach=true ;;
        *) die "publish: unknown argument '$4'" ;;
    esac
    [[ -s "$notes" ]] || die "no release notes at '$notes'"
    for a in "${ASSETS[@]}"; do
        [[ -s "$dir/$a" ]] || die "$dir/$a is missing: build it with scripts/dist.sh --release"
        files+=("$dir/$a")
    done
    command -v gh >/dev/null 2>&1 || die "gh is needed"

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-release.XXXXXX")"
    # shellcheck disable=SC2064  # expand now: the trap outlives this function
    trap "rm -rf '$tmp'" EXIT

    if ! info="$(gh release view "$tag" --json isDraft,assets \
            --jq '(if .isDraft then "draft" else "published" end), .assets[].name' 2>"$tmp/err")"; then
        grep -q "not found" "$tmp/err" || die "could not ask GitHub about $tag: $(cat "$tmp/err")"
        _latest_flag "$v" "$tmp"
        # gh creates the release as a draft, uploads the assets, then
        # publishes it: releases/latest never points at one without them.
        gh release create "$tag" "${files[@]}" --verify-tag --title "$tag" --notes-file "$notes" "$REPLY"
        say "$tag released with ${ASSETS[*]}"
        return 0
    fi

    # It exists. Nothing in it is replaced, and nothing is added unless asked.
    [[ "$attach" == true ]] || die "the release $tag exists already: nothing was uploaded or replaced. To upload only the assets it lacks: gh workflow run release.yml --ref $tag -f tag=$tag -f attach_missing=true"
    state="${info%%$'\n'*}"
    names=""
    if [[ "$info" == *$'\n'* ]]; then names="${info#*$'\n'}"; fi
    for a in "${ASSETS[@]}"; do
        if grep -qxF "$a" <<<"$names"; then
            gh release download "$tag" --pattern "$a" --dir "$tmp/have" >/dev/null 2>"$tmp/err" \
                || die "could not download $a from $tag to compare it: $(cat "$tmp/err")"
            cmp -s "$tmp/have/$a" "$dir/$a" \
                || die "$tag has a $a that is not this build's: nothing was uploaded. Assets are never replaced; release a new version."
        else
            missing+=("$dir/$a")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        gh release upload "$tag" "${missing[@]}"
        say "$tag: attached ${missing[*]##*/}"
    else
        say "$tag has all three assets, the same bytes as this build"
    fi
    # A draft is what a create cut short leaves: publish it now it is whole.
    if [[ "$state" == draft ]]; then
        _latest_flag "$v" "$tmp"
        gh release edit "$tag" --draft=false "$REPLY"
        say "$tag published"
    fi
}

case "${1:-}" in
    check)   shift; cmd_check "$@" ;;
    notes)   shift; cmd_notes "$@" ;;
    publish) shift; cmd_publish "$@" ;;
    *) echo "usage: scripts/release.sh check TAG [--ref REF] [--on BRANCH] | notes TAG | publish TAG DIR NOTES [--attach-missing]" >&2; exit 2 ;;
esac
