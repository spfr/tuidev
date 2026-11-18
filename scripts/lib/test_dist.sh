#!/bin/bash
# Tests for scripts/dist.sh, the release builder: it archives the last commit
# (`git archive HEAD`), so what the archive holds is what was committed and
# nothing else; that it is deterministic and owned by root; that get.sh takes
# it (checksum, layout, executable bits); and that --release refuses a dirty
# tree (an untracked file too) or a version without a CHANGELOG section.
# Everything runs on a small git repo built here: the real repo's HEAD is not
# touched or read. Archives go to a throwaway TUIDEV_DIST_DIR.
# Run: bash scripts/lib/test_dist.sh  -> exit 0 on pass (also under /bin/bash).
#
# shellcheck disable=SC2015,SC2016  # `a && b || fail` checks

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-dist.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME"
unset TUIDEV_VERSION TUIDEV_RELEASE_URL TUIDEV_HOME XDG_DATA_HOME TUIDEV_REPO TUIDEV_DIST_DIR
export TUIDEV_STATE_DIR="$HOME/.config/tuidev"

# --- the fixture repo ------------------------------------------------------------------------------
version=7.8.9
fx="$tmp/fx"
mkdir -p "$fx/scripts/lib" "$fx/bin" "$fx/docs/assets" "$fx/.github/workflows" "$fx/configs"
cp "$REPO_DIR/scripts/dist.sh" "$fx/scripts/dist.sh"
cp "$REPO_DIR/scripts/lib/ui.sh" "$REPO_DIR/scripts/lib/version.sh" "$fx/scripts/lib/"
cp "$REPO_DIR/get.sh" "$fx/get.sh"
cp "$REPO_DIR/bin/tuidev" "$fx/bin/tuidev"
printf '#!/bin/bash\n' > "$fx/install.sh"; printf '#!/bin/bash\n' > "$fx/scripts/update.sh"
chmod +x "$fx/install.sh" "$fx/bin/tuidev" "$fx/scripts/dist.sh" "$fx/scripts/update.sh" "$fx/get.sh"
echo "$version" > "$fx/VERSION"
printf '# Changelog\n\n## [Unreleased]\n\n## [%s] - 2026-01-01\n\n- x\n' "$version" > "$fx/CHANGELOG.md"
echo png > "$fx/docs/assets/a.png"; echo ci > "$fx/.github/workflows/ci.yml"; echo cfg > "$fx/configs/a.conf"
printf 'ignored.txt\n' > "$fx/.gitignore"
git -C "$fx" init -q
git -C "$fx" config user.name tester
git -C "$fx" config user.email tester@example.invalid
git -C "$fx" config commit.gpgsign false
git -C "$fx" add -A
git -C "$fx" commit -q -m init
# What is in the working tree but not in the commit.
echo i > "$fx/ignored.txt"
build() {  # build OUTDIR [ARGS]
    local o="$1"; shift
    TUIDEV_DIST_DIR="$o" "$SH" "$fx/scripts/dist.sh" "$@"
}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# --- 1. a clean tree: what the archive holds ------------------------------------------------------
out="$tmp/out"
log="$(build "$out" 2>"$tmp/stderr")" || fail "dist.sh: $log $(cat "$tmp/stderr")"
[[ ! -s "$tmp/stderr" ]] || fail "a clean tree printed a note: $(cat "$tmp/stderr")"
[[ -s "$out/tuidev.tar.gz" && -s "$out/tuidev.tar.gz.sha256" && -s "$out/get.sh" ]] || fail "the three files: $(ls "$out")"
[[ "$log" == *"$out/tuidev.tar.gz ($version,"* ]] || fail "dist.sh's report: $log"
cmp -s "$out/get.sh" "$REPO_DIR/get.sh" || fail "dist/get.sh is not the committed get.sh"
[[ "$(wc -l < "$out/tuidev.tar.gz.sha256" | tr -d ' ')" == 1 && "$(cut -d' ' -f3 "$out/tuidev.tar.gz.sha256")" == tuidev.tar.gz \
    && "$(cut -d' ' -f1 "$out/tuidev.tar.gz.sha256")" == "$(sha "$out/tuidev.tar.gz")" ]] || fail "checksum file: $(cat "$out/tuidev.tar.gz.sha256")"

tar -tzvf "$out/tuidev.tar.gz" > "$tmp/verbose"
tar -tzf "$out/tuidev.tar.gz" > "$tmp/list"
top="tuidev-$version"
[[ "$(head -1 "$tmp/list")" == "$top/" || "$(head -1 "$tmp/list")" == "$top" ]] || fail "top directory: $(head -1 "$tmp/list")"
if grep -qvE "^$top(/|\$)" "$tmp/list"; then fail "paths outside $top: $(grep -vE "^$top(/|\$)" "$tmp/list" | head -3)"; fi
for banned in docs/assets .github dist; do
    ! grep -qE "^$top/$banned(/|\$)" "$tmp/list" || fail "the archive has $banned/"
done
! grep -q 'ignored.txt' "$tmp/list" || fail "the archive has an ignored file"
! grep -qE '(^|/)\._' "$tmp/list" || fail "macOS ._ files in the archive"
for f in VERSION get.sh install.sh bin/tuidev scripts/dist.sh CHANGELOG.md configs/a.conf; do
    grep -qxE "$top/$f" "$tmp/list" || fail "the archive lacks $f"
done
for f in get.sh install.sh bin/tuidev scripts/update.sh; do
    grep -E " $top/$f\$" "$tmp/verbose" | grep -q '^-..x' || fail "$f is not executable in the archive: $(grep " $top/$f\$" "$tmp/verbose")"
done
# Owned by root (or numeric 0), never by whoever built it.
me="$(id -un)"
if [[ "$me" != root ]]; then
    ! grep -qw -- "$me" "$tmp/verbose" || fail "an entry is owned by $me: $(grep -w -- "$me" "$tmp/verbose" | head -2)"
fi
if grep -vE '(^|[ /])(root|0)[ /]+(root|wheel|0)( |$)' "$tmp/verbose" | grep -q .; then
    fail "entries not owned by root/0: $(grep -vE '(^|[ /])(root|0)[ /]+(root|wheel|0)( |$)' "$tmp/verbose" | head -3)"
fi
pass "the archive: one tuidev-$version/ top, only committed files, executable bits, owned by root; no docs/assets, .github, ignored files"

# --- 2. deterministic ---------------------------------------------------------------------------------
build "$tmp/out2" >/dev/null 2>&1 || fail "second build"
sleep 1
build "$tmp/out3" >/dev/null 2>&1 || fail "third build"
[[ "$(sha "$out/tuidev.tar.gz")" == "$(sha "$tmp/out2/tuidev.tar.gz")" && "$(sha "$out/tuidev.tar.gz")" == "$(sha "$tmp/out3/tuidev.tar.gz")" ]] \
    || fail "builds of one commit differ: $(sha "$out/tuidev.tar.gz") $(sha "$tmp/out2/tuidev.tar.gz") $(sha "$tmp/out3/tuidev.tar.gz")"
pass "two builds of the same commit, a second apart, give the same sha256"

# --- 3. round trip through get.sh ---------------------------------------------------------------------
rel="$tmp/rel"; mkdir -p "$rel/latest/download"
cp "$out/tuidev.tar.gz" "$out/tuidev.tar.gz.sha256" "$rel/latest/download/"
dest="$(TUIDEV_RELEASE_URL="file://$rel" TUIDEV_HOME="$tmp/h" "$SH" "$out/get.sh" --fetch 2>/dev/null)" || fail "get.sh --fetch of the built release"
[[ "$dest" == "$tmp/h/current" && "$(cat "$dest/VERSION")" == "$version" && -x "$dest/install.sh" && -x "$dest/bin/tuidev" && -f "$dest/get.sh" ]] || fail "the unpacked release"
cmp -s "$dest/get.sh" "$REPO_DIR/get.sh" || fail "the release's get.sh differs"
[[ ! -e "$dest/docs/assets" && ! -e "$dest/.github" ]] || fail "excluded paths unpacked"
# And the unpacked tuidev runs: it finds itself as its own repo.
[[ "$(TUIDEV_HOME="$tmp/h" HOME="$tmp/home" "$SH" "$dest/bin/tuidev" home)" == "$tmp/h/current" ]] || fail "bin/tuidev home from the release"
[[ "$(TUIDEV_HOME="$tmp/h" HOME="$tmp/home" "$SH" "$dest/bin/tuidev" version)" == "tuidev $version" ]] || fail "bin/tuidev version from the release"
# A flipped byte is refused.
printf 'x' >> "$rel/latest/download/tuidev.tar.gz"
if TUIDEV_RELEASE_URL="file://$rel" TUIDEV_HOME="$tmp/h2" "$SH" "$out/get.sh" --fetch >/dev/null 2>&1; then fail "a corrupted archive was taken"; fi
pass "the built release round-trips through get.sh --fetch, and a corrupted one is refused"

# --- 4. a dirty tree, without --release: builds the commit and says so ---------------------------------
echo changed >> "$fx/configs/a.conf"
echo untracked > "$fx/untracked.txt"
ln -s /etc "$fx/untracked-link"
rc=0; build "$tmp/o4" >/dev/null 2>"$tmp/stderr" || rc=$?
[[ "$rc" == 0 ]] || fail "a dev build of a dirty tree failed: $(cat "$tmp/stderr")"
grep -qF "building the last commit; uncommitted changes are not in it" "$tmp/stderr" || fail "no note about the dirty tree: $(cat "$tmp/stderr")"
tar -tzf "$tmp/o4/tuidev.tar.gz" > "$tmp/list4"
! grep -qE 'untracked' "$tmp/list4" || fail "an untracked file or symlink is in the archive: $(grep untracked "$tmp/list4")"
mkdir "$tmp/x4"; tar -xzof "$tmp/o4/tuidev.tar.gz" -C "$tmp/x4"
[[ "$(cat "$tmp/x4/$top/configs/a.conf")" == cfg ]] || fail "an uncommitted edit is in the archive: $(cat "$tmp/x4/$top/configs/a.conf")"
[[ "$(sha "$tmp/o4/tuidev.tar.gz")" == "$(sha "$out/tuidev.tar.gz")" ]] || fail "the dirty tree changed the archive"
[[ -z "$(find "$tmp/x4" -type l)" ]] || fail "a symlink was shipped"
pass "without --release a dirty tree builds the last commit, with a note; uncommitted and untracked files (a symlink too) are not in it"

# --- 5. --release ---------------------------------------------------------------------------------------
git -C "$fx" checkout -q configs/a.conf
err="$(build "$tmp/o5" --release 2>&1)" && fail "--release took a tree with an untracked file"
[[ "$err" == *"not clean"* && ! -e "$tmp/o5" ]] || fail "dirty (untracked): $err"
# status.showUntrackedFiles=no must not hide it.
git -C "$fx" config status.showUntrackedFiles no
[[ -z "$(git -C "$fx" status --porcelain)" ]] || fail "fixture: the config should hide the untracked files from plain status"
err="$(build "$tmp/o5" --release 2>&1)" && fail "--release took an untracked file with status.showUntrackedFiles=no"
[[ "$err" == *"not clean"* && ! -e "$tmp/o5" ]] || fail "dirty (untracked, hidden by config): $err"
git -C "$fx" config --unset status.showUntrackedFiles
rm "$fx/untracked.txt" "$fx/untracked-link" "$fx/ignored.txt"
echo edit >> "$fx/get.sh"
err="$(build "$tmp/o5" --release 2>&1)" && fail "--release took a tree with a modified file"
[[ "$err" == *"not clean"* ]] || fail "dirty (modified): $err"
git -C "$fx" checkout -q get.sh
build "$tmp/o6" --release >/dev/null 2>&1 || fail "--release on a clean tree with a CHANGELOG section"
[[ "$(sha "$tmp/o6/tuidev.tar.gz")" == "$(sha "$out/tuidev.tar.gz")" ]] || fail "--release built something else"
# The CHANGELOG section is read from the commit.
echo 7.8.10 > "$fx/VERSION"; git -C "$fx" commit -q -am bump
err="$(build "$tmp/o5" --release 2>&1)" && fail "--release without a CHANGELOG section for 7.8.10"
[[ "$err" == *"no section for 7.8.10"* && ! -e "$tmp/o5" ]] || fail "no section: $err"
echo 7.8 > "$fx/VERSION"; git -C "$fx" commit -q -am badversion
err="$(build "$tmp/o5" 2>&1)" && fail "a VERSION that is not X.Y.Z built"
[[ "$err" == *"VERSION must be X.Y.Z"* ]] || fail "bad VERSION: $err"
pass "--release refuses a dirty tree (an untracked file too, whatever status.showUntrackedFiles says), a missing CHANGELOG section and a bad VERSION"

# A changelog far bigger than a pipe's buffer, its section at the top: the
# check reads all of it, or git show dies of SIGPIPE and pipefail says "no section".
echo 7.8.11 > "$fx/VERSION"
{ printf '# Changelog\n\n## [7.8.11] - 2026-01-02\n\n- x\n\n'; for i in $(seq 1 4000); do printf '## [0.0.%s] - 2020-01-01\n\n- old entry, long enough to fill a pipe buffer\n\n' "$i"; done; } > "$fx/CHANGELOG.md"
git -C "$fx" commit -q -am bigchangelog
for i in 1 2 3; do
    err="$(build "$tmp/o7" --release 2>&1)" || fail "--release with a large changelog (run $i): $err"
done
pass "--release finds the section at the top of a changelog larger than a pipe buffer"

# make dist builds with --release.
grep -A2 '^dist:' "$REPO_DIR/Makefile" | grep -q 'dist.sh --release' || fail "make dist does not run dist.sh --release"
pass "make dist runs dist.sh --release"

echo ""
echo "All dist tests passed."
