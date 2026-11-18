#!/bin/bash
# scripts/dist.sh - build what a release carries besides its notes, in dist/
# (or $TUIDEV_DIST_DIR):
#
#   tuidev.tar.gz          the last commit's files under tuidev-X.Y.Z/ (X.Y.Z
#                          from VERSION), without docs/assets (the README's
#                          images) and .github
#   tuidev.tar.gz.sha256   its sha256, which get.sh checks the download against
#   get.sh                 the bootstrap, so releases/latest/download/get.sh
#                          is always the released one
#
# The names carry no version, so the latest release's are always at
# https://github.com/spfr/tuidev/releases/latest/download/NAME.
#
# The archive is `git archive HEAD`: committed files only, owned by root in
# the archive, no extended attributes. Nothing in the working tree that is
# not committed can end up in a public release, whatever .gitignore misses.
#
#   scripts/dist.sh             build HEAD; a note says so when the tree has
#                               changes that are therefore not in it
#   scripts/dist.sh --release   the same, refused unless the tree is clean
#                               (untracked files count) and CHANGELOG.md has a
#                               section for VERSION. `make dist` runs this.
#
# A pushed tag runs this in .github/workflows/release.yml, which attests and
# publishes the three; by hand: gh release create vX.Y.Z dist/tuidev.tar.gz
# dist/tuidev.tar.gz.sha256 dist/get.sh (docs/engineering.md, "Releasing").

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
# file_sha256 (ui.sh), version_valid (version.sh).
# shellcheck source=lib/ui.sh disable=SC1091
. "$REPO_DIR/scripts/lib/ui.sh"
# shellcheck source=lib/version.sh disable=SC1091
. "$REPO_DIR/scripts/lib/version.sh"

die() { echo "dist: $*" >&2; exit 1; }

git rev-parse --verify -q HEAD >/dev/null || die "no commit to build from"
v="$(git show HEAD:VERSION 2>/dev/null)" || v=""
version_valid "$v" || die "the committed VERSION must be X.Y.Z (got '${v}')"

# Untracked files count, whatever status.showUntrackedFiles says.
dirty="$(git status --porcelain --untracked-files=all)"
if [[ "${1:-}" == --release ]]; then
    [[ -z "$dirty" ]] || die "the working tree is not clean"
    # grep without -q reads it all: one that stops at the first match closes
    # the pipe on git show, and pipefail takes that for a missing section.
    git show HEAD:CHANGELOG.md | grep -F "## [$v]" >/dev/null || die "CHANGELOG.md has no section for $v"
elif [[ -n "$dirty" ]]; then
    echo "dist: building the last commit; uncommitted changes are not in it" >&2
fi

out="${TUIDEV_DIST_DIR:-dist}"
mkdir -p "$out"

# gzip -n: no name or time in the header, so one commit always gives one sha256.
# tar.umask: files unpack 0755/0644, never group-writable.
git -c tar.umask=0022 archive --format=tar --prefix="tuidev-$v/" HEAD -- . ':(exclude)docs/assets' ':(exclude).github' \
    | gzip -n > "$out/tuidev.tar.gz"
sum="$(file_sha256 "$out/tuidev.tar.gz")"
printf '%s  tuidev.tar.gz\n' "$sum" > "$out/tuidev.tar.gz.sha256"
git show HEAD:get.sh > "$out/get.sh"

echo "$out/tuidev.tar.gz ($v, $(du -h "$out/tuidev.tar.gz" | cut -f1 | tr -d ' '), sha256 $sum)"
echo "$out/tuidev.tar.gz.sha256"
echo "$out/get.sh"
