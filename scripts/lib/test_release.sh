#!/bin/bash
# Tests for scripts/release.sh, the steps of .github/workflows/release.yml:
# `check` refuses a tag that is not vX.Y.Z, a run not on the tag, a checkout
# that is not the tagged commit, a VERSION or CHANGELOG.md that disagrees, a
# commit off the release branch and an empty section; `notes` prints the
# section `tuidev whatsnew` shows, less its heading; `publish` creates a
# release with the three assets, keeps releases/latest on the newest version,
# never changes a release that exists, and with --attach-missing uploads only
# what it lacks once what it has matches this build (and publishes a draft
# that a create cut short). gh is a stub that records its calls.
# Everything runs on a small git repo built here.
# Run: bash scripts/lib/test_release.sh  -> exit 0 on pass (also under /bin/bash).
#
# shellcheck disable=SC2015,SC2016  # `a && b || fail` checks

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-release.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME"
unset TUIDEV_VERSION TUIDEV_RELEASE_URL TUIDEV_HOME XDG_DATA_HOME TUIDEV_REPO GH_TOKEN GH_REPO
export TUIDEV_STATE_DIR="$HOME/.config/tuidev"

# --- the fixture repo ------------------------------------------------------------------------------
fx="$tmp/fx"
mkdir -p "$fx/scripts/lib" "$fx/bin"
cp "$REPO_DIR/scripts/release.sh" "$fx/scripts/release.sh"
cp "$REPO_DIR/scripts/lib/version.sh" "$fx/scripts/lib/version.sh"
cp "$REPO_DIR/bin/tuidev" "$fx/bin/tuidev"
printf '#!/bin/bash\n' > "$fx/install.sh"
chmod +x "$fx/install.sh" "$fx/bin/tuidev" "$fx/scripts/release.sh"
echo 7.8.9 > "$fx/VERSION"
cat > "$fx/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- not released yet

## [7.8.9] - 2026-01-02


### Added

- **A thing.** It works.

## [7.8.8] - 2026-01-01

- an older one
EOF
git -C "$fx" init -q -b main
git -C "$fx" config user.name tester
git -C "$fx" config user.email tester@example.invalid
git -C "$fx" config commit.gpgsign false
git -C "$fx" config tag.gpgsign false
git -C "$fx" add -A
git -C "$fx" commit -q -m init
git -C "$fx" tag v7.8.9

rel() { "$SH" "$fx/scripts/release.sh" "$@"; }
refused() {  # refused WHAT EXPECTED -- ARGS: release.sh must fail and say EXPECTED
    local what="$1" want="$2" out; shift 3
    if out="$(rel "$@" 2>&1)"; then fail "$what: accepted ($out)"; fi
    [[ "$out" == *"$want"* ]] || fail "$what: expected '$want', got: $out"
}

# --- 1. check ---------------------------------------------------------------------------------------
out="$(rel check v7.8.9 --ref refs/tags/v7.8.9 --on main 2>&1)" || fail "check of a good tag: $out"
[[ "$out" == *"v7.8.9: tag, VERSION and CHANGELOG.md agree, and it is on main"* ]] || fail "check's report: $out"
rel check v7.8.9 >/dev/null 2>&1 || fail "check without --ref and --on"
refused "a tag that is not vX.Y.Z" "must look like v3.23.0" -- check 7.8.9
refused "a tag with a suffix" "must look like v3.23.0" -- check v7.8.9-rc1
refused "a run on a branch" "Run it from the tag: gh workflow run release.yml --ref v7.8.9 -f tag=v7.8.9" \
    -- check v7.8.9 --ref refs/heads/main
refused "a run on another tag" "not on the tag v7.8.9" -- check v7.8.9 --ref refs/tags/v7.8.8
refused "a tag that does not exist" "there is no tag v7.9.0" -- check v7.9.0
git -C "$fx" tag v7.8.8
refused "a tag VERSION disagrees with" "the tag says 7.8.8, the committed VERSION says '7.8.9'" -- check v7.8.8
refused "an unknown --on" "there is no nope" -- check v7.8.9 --on nope
refused "an unknown argument" "unknown argument" -- check v7.8.9 --force

# The checkout is not the commit the tag names.
echo more >> "$fx/install.sh"; git -C "$fx" commit -q -am more
refused "a checkout past the tag" "is not the commit v7.8.9 names" -- check v7.8.9

# VERSION bumped, but the changelog's newest section is still the old one.
echo 7.9.0 > "$fx/VERSION"; git -C "$fx" commit -q -am bump; git -C "$fx" tag v7.9.0
refused "a changelog without the version's section" "newest section is '## [7.8.9] - 2026-01-02', not 7.9.0" -- check v7.9.0

# A section with nothing in it.
awk '/^## \[7.8.9\]/ { print "## [7.9.0] - 2026-01-03\n" } { print }' "$fx/CHANGELOG.md" > "$tmp/cl" && mv "$tmp/cl" "$fx/CHANGELOG.md"
git -C "$fx" commit -q -am empty; git -C "$fx" tag -f v7.9.0 >/dev/null 2>&1
refused "an empty section" "section for 7.9.0 is empty" -- check v7.9.0

# A tagged commit that is not on main.
git -C "$fx" checkout -q -b side
awk '/^## \[7.9.0\]/ { print; print "\n- side work"; next } { print }' "$fx/CHANGELOG.md" > "$tmp/cl" && mv "$tmp/cl" "$fx/CHANGELOG.md"
git -C "$fx" commit -q -am side; git -C "$fx" tag -f v7.9.0 >/dev/null 2>&1
rel check v7.9.0 >/dev/null 2>&1 || fail "the side commit should pass without --on"
refused "a commit off main" "v7.9.0 is not on main" -- check v7.9.0 --on main
git -C "$fx" checkout -q main
git -C "$fx" merge -q --ff-only side
rel check v7.9.0 --on main >/dev/null 2>&1 || fail "the same commit once main has it"
pass "check: a vX.Y.Z tag on the commit checked out, the run on that tag, VERSION, the changelog's newest section with notes, and on main"

# --- 2. notes ---------------------------------------------------------------------------------------
git -C "$fx" checkout -q v7.8.9 2>/dev/null
notes="$(rel notes v7.8.9 2>&1)" || fail "notes: $notes"
want='### Added

- **A thing.** It works.'
[[ "$notes" == "$want" ]] || fail "notes: got [$notes], want [$want]"
[[ "$(rel notes v7.8.9 | tail -c 1 | od -An -c | tr -d ' ')" == '\n' ]] || fail "notes do not end with a newline"
refused "notes for a version that is not the newest section" "not 7.8.8" -- notes v7.8.8
git -C "$fx" checkout -q main
pass "notes: the section tuidev whatsnew prints, without its heading and the blank lines around it"

# --- 3. publish, with a stub gh ---------------------------------------------------------------------
git -C "$fx" checkout -q v7.8.9 2>/dev/null
dist="$tmp/dist"; mkdir -p "$dist"
printf 'archive' > "$dist/tuidev.tar.gz"
printf 'sum  tuidev.tar.gz\n' > "$dist/tuidev.tar.gz.sha256"
printf '#!/bin/bash\n' > "$dist/get.sh"
rel notes v7.8.9 > "$tmp/notes.md"

gs="$tmp/gh"; mkdir -p "$gs/bin" "$gs/assets"
cat > "$gs/bin/gh" <<'EOF'
#!/bin/bash
# A stub gh: logs each call; answers from files in $GH_STUB.
printf '%s\n' "$*" >> "$GH_STUB/log"
[[ "$1" == release ]] || { echo "stub gh: $*" >&2; exit 2; }
case "$2" in
    view)
        if [[ "${3:-}" == --json ]]; then              # the latest release
            [[ -f "$GH_STUB/latest" ]] && { cat "$GH_STUB/latest"; exit 0; }
            echo "release not found" >&2; exit 1
        fi
        [[ -f "$GH_STUB/view.err" ]] && { cat "$GH_STUB/view.err" >&2; exit 1; }
        [[ -f "$GH_STUB/view" ]] && { cat "$GH_STUB/view"; exit 0; }
        echo "release not found" >&2; exit 1 ;;
    download)
        shift 3; p="" d="."
        while [[ $# -gt 0 ]]; do
            case "$1" in --pattern) p="$2"; shift 2 ;; --dir) d="$2"; shift 2 ;; *) shift ;; esac
        done
        mkdir -p "$d" && cp "$GH_STUB/assets/$p" "$d/$p" ;;
    create)
        while [[ $# -gt 0 ]]; do
            [[ "$1" == --notes-file ]] && cp "$2" "$GH_STUB/notes"
            shift
        done ;;
    upload|edit) ;;
    *) echo "stub gh: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$gs/bin/gh"
export GH_STUB="$gs"
reset_gh() { rm -rf "${gs:?}/log" "$gs/latest" "$gs/view" "$gs/view.err" "$gs/notes" "$gs/assets"; mkdir -p "$gs/assets"; : > "$gs/log"; }
pub() { PATH="$gs/bin:$PATH" "$SH" "$fx/scripts/release.sh" publish v7.8.9 "$dist" "$tmp/notes.md" "$@"; }
pub_refused() {  # pub_refused WHAT EXPECTED [ARGS]
    local what="$1" want="$2" out; shift 2
    if out="$(pub "$@" 2>&1)"; then fail "$what: accepted ($out)"; fi
    [[ "$out" == *"$want"* ]] || fail "$what: expected '$want', got: $out"
}
calls() { grep -E "^release $1 " "$gs/log" || true; }

# A first release, none before it.
reset_gh
out="$(pub 2>&1)" || fail "publish: $out"
c="$(calls create)"
[[ "$c" == "release create v7.8.9 $dist/tuidev.tar.gz $dist/tuidev.tar.gz.sha256 $dist/get.sh --verify-tag --title v7.8.9 --notes-file $tmp/notes.md --latest" ]] \
    || fail "the create call: $c"
cmp -s "$gs/notes" "$tmp/notes.md" || fail "the notes handed to gh"
[[ -z "$(calls upload)$(calls edit)" ]] || fail "a new release also uploaded or edited: $(cat "$gs/log")"

# An older release is the latest: this one takes over. A newer one: it does not.
reset_gh; echo v7.8.8 > "$gs/latest"
pub >/dev/null 2>&1 || fail "publish after v7.8.8"
[[ "$(calls create)" == *" --latest" ]] || fail "after an older latest: $(calls create)"
reset_gh; echo v7.10.0 > "$gs/latest"
out="$(pub 2>&1)" || fail "publish with v7.10.0 out: $out"
[[ "$(calls create)" == *" --latest=false" && "$out" == *"v7.10.0 is newer than v7.8.9"* ]] || fail "with a newer latest: $(calls create) / $out"

# GitHub cannot be asked: nothing is created.
reset_gh; echo "HTTP 401: Bad credentials" > "$gs/view.err"
pub_refused "an error that is not 'not found'" "could not ask GitHub about v7.8.9: HTTP 401"
[[ -z "$(calls create)" ]] || fail "created after an API error"

# Assets or notes missing here: refused before gh is asked anything.
reset_gh; mv "$dist/get.sh" "$tmp/get.sh.away"
pub_refused "a missing asset" "$dist/get.sh is missing"
mv "$tmp/get.sh.away" "$dist/get.sh"
pub_refused "an unknown argument" "unknown argument '--clobber'" --clobber
PATH="$gs/bin:$PATH" "$SH" "$fx/scripts/release.sh" publish v7.8.9 "$dist" "$tmp/none.md" >/dev/null 2>&1 && fail "publish without notes"
[[ ! -s "$gs/log" ]] || fail "gh was called for a refused publish: $(cat "$gs/log")"
pass "publish: a new release gets the three assets, the notes and --verify-tag; it becomes the latest unless a newer one is out; errors create nothing"

# The release exists: refused, whatever it holds.
reset_gh; printf 'published\ntuidev.tar.gz\n' > "$gs/view"
pub_refused "an existing release" "the release v7.8.9 exists already: nothing was uploaded or replaced"
[[ -z "$(calls create)$(calls upload)$(calls edit)$(calls download)" ]] || fail "an existing release was touched: $(cat "$gs/log")"

# --attach-missing: the asset it has is this build's, the two it lacks go up.
cp "$dist/tuidev.tar.gz" "$gs/assets/"
out="$(pub --attach-missing 2>&1)" || fail "attach-missing: $out"
[[ "$(calls upload)" == "release upload v7.8.9 $dist/tuidev.tar.gz.sha256 $dist/get.sh" ]] || fail "the upload: $(calls upload)"
[[ -z "$(calls create)$(calls edit)" ]] || fail "attach-missing created or edited: $(cat "$gs/log")"
[[ "$out" == *"attached tuidev.tar.gz.sha256 get.sh"* ]] || fail "attach-missing's report: $out"

# One it has differs from this build: nothing is uploaded.
reset_gh; printf 'published\ntuidev.tar.gz\n' > "$gs/view"; printf 'other' > "$gs/assets/tuidev.tar.gz"
pub_refused "an asset that differs" "v7.8.9 has a tuidev.tar.gz that is not this build's: nothing was uploaded" --attach-missing
[[ -z "$(calls upload)" ]] || fail "uploaded next to a different asset"

# It has all three: nothing to do.
reset_gh; printf 'published\ntuidev.tar.gz\ntuidev.tar.gz.sha256\nget.sh\nsomething-else.txt\n' > "$gs/view"
cp "$dist/tuidev.tar.gz" "$dist/tuidev.tar.gz.sha256" "$dist/get.sh" "$gs/assets/"
out="$(pub --attach-missing 2>&1)" || fail "attach-missing with all three: $out"
[[ -z "$(calls upload)$(calls edit)" && "$out" == *"has all three assets"* ]] || fail "all three present: $(cat "$gs/log") / $out"

# A draft left by a create cut short: what it lacks goes up, then it is published.
reset_gh; printf 'draft\ntuidev.tar.gz\n' > "$gs/view"; cp "$dist/tuidev.tar.gz" "$gs/assets/"
pub_refused "a draft without --attach-missing" "exists already"
pub --attach-missing >/dev/null 2>&1 || fail "attach-missing on a draft"
[[ "$(calls upload)" == "release upload v7.8.9 $dist/tuidev.tar.gz.sha256 $dist/get.sh" ]] || fail "the draft's upload: $(calls upload)"
[[ "$(calls edit)" == "release edit v7.8.9 --draft=false --latest" ]] || fail "the draft was not published: $(calls edit)"
git -C "$fx" checkout -q main
pass "publish: an existing release is refused; --attach-missing uploads only what it lacks, refuses one whose assets differ, and publishes a draft"

echo ""
echo "All release tests passed."
