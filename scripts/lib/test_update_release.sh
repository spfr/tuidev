#!/bin/bash
# End-to-end test of update.sh in release mode: an install made with get.sh
# (no .git, a VERSION and a get.sh in ~/.local/share/tuidev/current) updating
# itself from a newer release served through file://. --repo and --self fetch
# it and move `current`; --self and --all hand over to the new release's
# update.sh exactly once; --check and --dry-run only report; a failed fetch
# leaves the install as it was and ends with "not updated" and exit 1 (so
# does a clone whose pull fails); a failed migration says where the install
# stands, and the next update finishes it; one update runs at a time (the
# lock in scripts/lib/lock.sh). The real update.sh and get.sh run; the new
# release's update.sh is a recording stub (and, at times, the real one).
# Run: bash scripts/lib/test_update_release.sh  -> exit 0 on pass (also /bin/bash).
#
# shellcheck disable=SC2015,SC2016  # `a && b || fail` checks; stub code in single quotes on purpose

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-updrel.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

REAL_CURL="$(command -v curl)" || fail "test needs curl"
export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/home/.config/tuidev" XDG_CACHE_HOME="$tmp/home/.cache"
export TUIDEV_HOME="$tmp/h" TUIDEV_NO_COLOR=1 CALLS="$tmp/calls" DLOG="$tmp/downloads" REL="$tmp/rel"
export TUIDEV_RELEASE_URL="file://$REL"
unset TUIDEV_REPO TUIDEV_VERSION TUIDEV_UPDATE_REEXEC XDG_CONFIG_HOME XDG_DATA_HOME TUIDEV_UPDATE_CHECK
mkdir -p "$HOME" "$tmp/bin"

# No Homebrew, no package manager: a PATH of stubs and the system basics. The
# curl stub answers the "which release is latest" question (its -w redirect)
# and passes every real download through to curl for file://.
printf '#!/bin/bash\necho Linux\n' > "$tmp/bin/uname"
cat > "$tmp/bin/curl" <<EOF2
#!/bin/bash
case "\$*" in
    *redirect_url*) echo "curl latest" >> "\$CALLS"; printf '%s' "\${STUB_LATEST_TAG:-}" ;;
    *) echo "download \$*" >> "\$DLOG"; exec "$REAL_CURL" "\$@" ;;
esac
EOF2
chmod +x "$tmp/bin/uname" "$tmp/bin/curl"
export PATH="$tmp/bin:/usr/bin:/bin"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# real_tree DIR VERSION — what a release carries that update.sh needs to run.
real_tree() {
    mkdir -p "$1"
    cp -R "$REPO_DIR/scripts" "$REPO_DIR/lib" "$REPO_DIR/configs" "$REPO_DIR/bin" "$REPO_DIR/templates" \
          "$REPO_DIR/install.sh" "$REPO_DIR/uninstall.sh" "$REPO_DIR/get.sh" "$1/"
    printf '%s\n' "$2" > "$1/VERSION"
}
# publish DIR — DIR (named tuidev-X.Y.Z) as the latest release.
publish() {
    mkdir -p "$REL/latest/download"
    COPYFILE_DISABLE=1 tar -czf "$REL/latest/download/tuidev.tar.gz" -C "$(dirname "$1")" "$(basename "$1")"
    printf '%s  tuidev.tar.gz\n' "$(sha "$REL/latest/download/tuidev.tar.gz")" > "$REL/latest/download/tuidev.tar.gz.sha256"
}
# stub_release VERSION — a release whose update.sh only records how it was run.
stub_release() {
    local d="$tmp/build/tuidev-$1"
    rm -rf "$d"; mkdir -p "$d/scripts" "$d/bin"
    printf '%s\n' "$1" > "$d/VERSION"
    printf '#!/bin/bash\n' > "$d/install.sh"; chmod +x "$d/install.sh"
    cp "$REPO_DIR/get.sh" "$d/get.sh"; cp "$REPO_DIR/bin/tuidev" "$d/bin/tuidev"
    cat > "$d/scripts/update.sh" <<'EOF2'
#!/bin/bash
echo "NEW update.sh $* reexec=${TUIDEV_UPDATE_REEXEC:-} from=$(cd "$(dirname "$0")/.." && pwd -P)" | tee -a "$CALLS"
EOF2
    chmod +x "$d/scripts/update.sh" "$d/bin/tuidev"
    publish "$d"
}

# setup — an install of 1.0.0 as get.sh leaves it, with the profile pointing at it.
OLD="$tmp/build/tuidev-1.0.0"
real_tree "$OLD" 1.0.0
setup() {
    rm -rf "$TUIDEV_HOME" "$HOME" "$CALLS" "$REL"; mkdir -p "$TUIDEV_HOME/versions" "$TUIDEV_STATE_DIR"
    cp -R "$OLD" "$TUIDEV_HOME/versions/1.0.0"
    ln -s versions/1.0.0 "$TUIDEV_HOME/current"
    printf 'profile=test\ncore=false\nremote=false\nsandbox=false\nui=false\nextras=false\nrepo=%s\n' "$TUIDEV_HOME/current" > "$TUIDEV_STATE_DIR/profile"
    : > "$CALLS"; : > "$DLOG"
    unset TUIDEV_UPDATE_REEXEC
}
update() { "$SH" "$TUIDEV_HOME/current/scripts/update.sh" "$@" < /dev/null 2>&1; }
cur() { readlink "$TUIDEV_HOME/current"; }
downloads() { wc -l < "$DLOG" | tr -d ' '; }   # archive and checksum fetches by get.sh
ran() { grep -v '^curl latest' "$CALLS" || true; }   # what the new release's update.sh recorded

# --- 1. --repo: fetch and move, no hand-over ----------------------------------------------------
setup; stub_release 2.0.0
out="$(update --repo)" || fail "--repo: $out"
[[ "$(cur)" == versions/2.0.0 && "$(cat "$TUIDEV_HOME/current/VERSION")" == 2.0.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.0.0 ]] || fail "--repo did not move current: $(cur)"
[[ "$out" == *"tuidev 1.0.0"*"2.0.0"* && "$out" == *"Update Complete"* && -z "$(ran)" ]] || fail "--repo output or a hand-over: $out"
[[ -d "$TUIDEV_HOME/versions/1.0.0" ]] || fail "the release that ran was removed"
pass "--repo: fetches the newer release, moves current, records previous, does not hand over"

# --- 2. --self: one hand-over to the new update.sh ---------------------------------------------------
setup; stub_release 2.0.0
out="$(update --self)" || fail "--self: $out"
[[ "$(cur)" == versions/2.0.0 ]] || fail "--self current: $(cur)"
[[ "$(grep -c 'NEW update.sh' "$CALLS")" == 1 && "$(ran)" == "NEW update.sh --self reexec=1 from=$(cd "$TUIDEV_HOME/versions/2.0.0" && pwd -P)" ]] || fail "the hand-over: $(cat "$CALLS")"
[[ "$out" != *"Update Complete"* ]] || fail "the old update.sh carried on after exec: $out"
pass "--self: the new release's update.sh runs once, with TUIDEV_UPDATE_REEXEC=1 and the same arguments"

setup; stub_release 2.0.0
update --all --dry-run >/dev/null; [[ "$(cur)" == versions/1.0.0 && -z "$(ran)" ]] || fail "--all --dry-run changed something: $(cur) $(ran)"
# the guard: a process already handed over neither fetches nor hands over again
TUIDEV_UPDATE_REEXEC=1 update --self >/dev/null || true
[[ "$(cur)" == versions/1.0.0 && -z "$(ran)" && "$(downloads)" == 0 ]] || fail "a process already handed over fetched or handed over again: $(cur) $(ran)"
setup; stub_release 2.0.0
update --all --yes >/dev/null || true
[[ "$(ran)" == "NEW update.sh --all --yes reexec=1 "* ]] || fail "--all hand-over: $(cat "$CALLS")"
pass "--all hands over too; a process already handed over does not again; --dry-run changes nothing"

# --- 3. --check and --dry-run only report -------------------------------------------------------------
for flags in "--check" "--repo --dry-run"; do
    setup; stub_release 2.0.0
    # shellcheck disable=SC2086  # $flags is a word list on purpose
    out="$(STUB_LATEST_TAG="https://example.invalid/releases/tag/v2.0.0" update $flags)" || fail "$flags: $out"
    [[ "$(cur)" == versions/1.0.0 && ! -e "$TUIDEV_HOME/versions/2.0.0" && ! -e "$TUIDEV_HOME/previous" && -z "$(ran)" ]] || fail "$flags changed or ran things: $(cur) $(ran)"
    [[ "$out" == *"Release:"*"1.0.0"* && "$out" == *"2.0.0 is out"* ]] || fail "$flags did not report the newer release: $out"
    [[ -z "$(find "$TUIDEV_HOME" -name '.get.*')" ]] || fail "$flags left a temp dir"
done
setup; out="$(update --check)" || fail "--check offline: $out"
[[ "$out" == *"no release checked yet"* && "$(cur)" == versions/1.0.0 ]] || fail "--check without an answer: $out"
pass "--check and --dry-run: report the latest release and change nothing"

# --- 4. nothing newer, and a fetch that fails ----------------------------------------------------------
setup; publish "$OLD"
out="$(update --repo)" || fail "--repo, latest: $out"
[[ "$out" == *"is the latest release"* && "$(cur)" == versions/1.0.0 && ! -e "$TUIDEV_HOME/previous" ]] || fail "--repo with nothing newer: $out"
for mode in --repo --self --all; do
    setup; rm -rf "$REL"; rc=0
    out="$(update "$mode")" || rc=$?
    [[ "$rc" == 1 && "$out" == *"not updated: could not reach or verify the latest release at $TUIDEV_RELEASE_URL (still on 1.0.0)"* \
       && "$out" != *"Update Complete"* && "$out" != *"migration"* && "$(cur)" == versions/1.0.0 ]] || fail "$mode, failed fetch: rc=$rc $out"
done
setup; stub_release 2.0.0; printf '0%.0s' $(seq 1 64) > "$REL/latest/download/tuidev.tar.gz.sha256"; rc=0
out="$(update --self)" || rc=$?
[[ "$rc" == 1 && "$out" == *"not updated:"*"(still on 1.0.0)"* && "$(cur)" == versions/1.0.0 && -z "$(ran)" ]] || fail "bad checksum moved or handed over: rc=$rc $out"
# Offline with a warm cache that says 1.0.0 is the latest: not "is the latest release".
setup; rm -rf "$REL"; echo 1.0.0 > "$TUIDEV_STATE_DIR/version"
mkdir -p "$XDG_CACHE_HOME/tuidev"; echo "1.0.0 99999999999 1" > "$XDG_CACHE_HOME/tuidev/latest"; rc=0
out="$(update --self)" || rc=$?
[[ "$rc" == 1 && "$out" != *"is the latest release"* && "$out" == *"not updated:"*"(still on 1.0.0)"* ]] || fail "offline with a warm cache: rc=$rc $out"
pass "latest already: no change; a failed or refused download (offline, warm cache or not) ends with 'not updated' and exit 1, and hands nothing over"

# --- 5. the whole thing with the real update.sh in both releases ------------------------------------------
setup
NEW="$tmp/build/tuidev-2.0.0"; rm -rf "$NEW"; real_tree "$NEW" 2.0.0; publish "$NEW"
out="$(update --self)" || fail "real --self: $(echo "$out" | tail -15)"
[[ "$(cur)" == versions/2.0.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.0.0 ]] || fail "real --self current: $(cur)"
[[ "$out" == *"Update Complete"* && "$(grep -c 'tuidev Update' <<<"$out")" -ge 2 ]] || fail "the new release's update.sh did not run to the end: $(echo "$out" | tail -15)"
[[ "$(cat "$TUIDEV_STATE_DIR/version" 2>/dev/null)" == 2.0.0 ]] || fail "configs did not record the new version: $(cat "$TUIDEV_STATE_DIR/version" 2>&1)"
[[ -x "$HOME/.local/bin/tuidev" ]] || fail "the CLI was not installed by --self"
# and a --self when already current: runs through migrations and configs once, no loop
out="$(update --self)" || fail "real --self, current: $(echo "$out" | tail -15)"
[[ "$out" == *"is the latest release"* && "$out" == *"Update Complete"* && "$(cur)" == versions/2.0.0 ]] || fail "real --self when current: $(echo "$out" | tail -15)"
[[ "$(downloads)" == 4 ]] || fail "downloads over the two --self runs (2 for the move, 2 for the no-op when the latest is unknown): $(cat "$DLOG")"
pass "real update.sh in both releases: --self moves to 2.0.0, finishes there, records the version, then is a no-op"

# --- 6. what is downloaded -------------------------------------------------------------------------------
# A real --self to a newer release: the archive and its checksum once; the new release's update.sh hands nothing over again.
setup
NEW="$tmp/build/tuidev-2.0.0"; publish "$NEW"
update --self >/dev/null || fail "--self download count run"
[[ "$(downloads)" == 2 && "$(grep -c 'tuidev.tar.gz ' "$DLOG")" == 1 ]] || fail "a --self update downloaded: $(cat "$DLOG")"
[[ "$(grep -c 'tuidev.tar.gz.sha256' "$DLOG")" == 1 ]] || fail "the checksum was not fetched once: $(cat "$DLOG")"

# Already current and the latest release known (the stub answers the redirect): nothing is downloaded.
setup; publish "$OLD"; echo 1.0.0 > "$TUIDEV_STATE_DIR/version"
out="$(STUB_LATEST_TAG="https://example.invalid/releases/tag/v1.0.0" update --repo)" || fail "known latest: $out"
[[ "$(downloads)" == 0 && "$out" == *"is the latest release"* && "$(cur)" == versions/1.0.0 ]] || fail "already current, known: downloads=$(downloads) $out"
# The same, when the state version is not the release's: the download decides.
setup; publish "$OLD"; echo 0.9.0 > "$TUIDEV_STATE_DIR/version"
out="$(STUB_LATEST_TAG="https://example.invalid/releases/tag/v1.0.0" update --repo)" || fail "state version differs: $out"
[[ "$(downloads)" == 2 && "$out" == *"the update to 1.0.0 is not finished (installed: 0.9.0)"* && "$out" != *"is the latest release"* ]] || fail "a state version that differs must still download, and say the update is not finished: downloads=$(downloads) $out"
setup; publish "$OLD"; rm -f "$TUIDEV_STATE_DIR/version"
out="$(STUB_LATEST_TAG="https://example.invalid/releases/tag/v1.0.0" update --repo)" || fail "no state version: $out"
[[ "$(downloads)" == 2 ]] || fail "without a recorded version the latest-known shortcut must not apply: downloads=$(downloads)"
# The latest release is not known (the redirect gives nothing): the download decides and finds nothing newer.
setup; publish "$OLD"; echo 1.0.0 > "$TUIDEV_STATE_DIR/version"
out="$(update --repo)" || fail "unknown latest: $out"
[[ "$(downloads)" == 2 && "$out" == *"is the latest release"* && "$(cur)" == versions/1.0.0 ]] || fail "latest unknown: downloads=$(downloads) $out"
# A newer release is known: it is downloaded.
setup; echo 1.0.0 > "$TUIDEV_STATE_DIR/version"; stub_release 2.0.0
out="$(STUB_LATEST_TAG="https://example.invalid/releases/tag/v2.0.0" update --repo)" || fail "newer known: $out"
[[ "$(downloads)" == 2 && "$(cur)" == versions/2.0.0 ]] || fail "a newer release known: downloads=$(downloads) $(cur)"
# A process that was handed over does not fetch again.
setup; publish "$OLD"
out="$(TUIDEV_UPDATE_REEXEC=1 update --repo)" || fail "handed over: $out"
[[ "$(downloads)" == 0 && "$out" == *"Release:"* && "$out" != *"is the latest release"* ]] || fail "TUIDEV_UPDATE_REEXEC=1 fetched or went on: downloads=$(downloads) $out"
pass "downloads: a --self update fetches archive and checksum once; already current (and known so) fetches nothing; an unknown latest or a differing state version lets the download decide; a handed-over process fetches nothing"

# --- 7. a stale TUIDEV_REPO ---------------------------------------------------------------------------------
setup; stub_release 2.0.0
out="$(TUIDEV_REPO="$tmp/gone" update --check)" || fail "stale TUIDEV_REPO: $out"
[[ "$out" == *"Release:"*"1.0.0"* && "$out" != *"No git checkout"* && "$out" == *"in $TUIDEV_HOME/current"* ]] || fail "a stale TUIDEV_REPO beside a release dir: $out"
setup; stub_release 2.0.0
out="$(TUIDEV_REPO="$tmp/gone" update --repo)" || fail "stale TUIDEV_REPO --repo: $out"
[[ "$(cur)" == versions/2.0.0 ]] || fail "a stale TUIDEV_REPO stopped the update: $(cur) $out"
pass "a TUIDEV_REPO that is gone falls back to the release this update.sh runs from"

# --- 8. TUIDEV_HOME / XDG_DATA_HOME elsewhere ----------------------------------------------------------------
setup; stub_release 2.0.0
out="$(TUIDEV_HOME="$tmp/elsewhere" XDG_DATA_HOME="$tmp/xdg" "$SH" "$tmp/h/current/scripts/update.sh" --repo < /dev/null 2>&1)" || fail "another TUIDEV_HOME: $out"
[[ "$(cur)" == versions/2.0.0 && ! -e "$tmp/elsewhere" && ! -e "$tmp/xdg" ]] || fail "an update with another TUIDEV_HOME went elsewhere: $(cur) $(ls "$tmp/elsewhere" "$tmp/xdg" 2>&1)"
pass "an update moves the install it runs from, whatever TUIDEV_HOME or XDG_DATA_HOME say"

# --- 9. a migration that fails mid-update, and the next update finishing it ------------------------------------
# get.sh has moved `current` to 2.0.0 when 2.0.0's update.sh runs its migrations: the install is split.
setup; echo 1.0.0 > "$TUIDEV_STATE_DIR/version"
NEW="$tmp/build/tuidev-2.0.0"; rm -rf "$NEW"; real_tree "$NEW" 2.0.0
# It fails while $HOME/.blocker is there: the cause, which the user then fixes.
printf '#!/bin/bash\n[[ -e "$HOME/.blocker" ]] || exit 0\necho "boom: $HOME/.blocker is in the way" >&2\nexit 3\n' > "$NEW/scripts/migrations/209912312359_test_fails.sh"
publish "$NEW"; : > "$HOME/.blocker"; rc=0
out="$(update --self)" || rc=$?
[[ "$rc" == 1 && "$(cur)" == versions/2.0.0 && "$(cat "$TUIDEV_STATE_DIR/version")" == 1.0.0 ]] || fail "a failed migration: rc=$rc $(cur) $(echo "$out" | tail -12)"
[[ "$out" == *"the update from 1.0.0 to 2.0.0 stopped partway"* && "$out" == *"run tuidev update again"* \
   && "$out" == *"tuidev update --rollback"* && "$out" != *"Update Complete"* ]] || fail "a failed migration must say where the install stands and the ways out: $(echo "$out" | tail -12)"
# The cause fixed, the next update finishes 2.0.0 (the download finds nothing newer): not "the latest release".
rm -f "$HOME/.blocker"
out="$(update --self)" || fail "finishing the update: $(echo "$out" | tail -12)"
[[ "$out" == *"finishing the update to 2.0.0 (installed: 1.0.0)"* && "$out" != *"is the latest release"* && "$out" == *"Update Complete"* ]] || fail "the next update did not say it is finishing: $(echo "$out" | tail -12)"
[[ "$(cat "$TUIDEV_STATE_DIR/version")" == 2.0.0 ]] || fail "the finished update did not record 2.0.0"
# Finishing needs no download: offline, the files on disk still finish it.
setup; echo 0.9.0 > "$TUIDEV_STATE_DIR/version"; rm -rf "$REL"
out="$(update --self)" || fail "finishing offline: $(echo "$out" | tail -12)"
[[ "$out" == *"finishing the update to 1.0.0 (installed: 0.9.0)"* && "$(cat "$TUIDEV_STATE_DIR/version")" == 1.0.0 ]] || fail "finishing offline: $(echo "$out" | tail -12)"
pass "a failed migration names the split state and the two ways out; the next update says it is finishing, online or not"

# --- 10. one update at a time ------------------------------------------------------------------------------
lockf="$TUIDEV_STATE_DIR/update.lock"
started() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { $1 = $1; print; exit }'; }
# Held by a live process (this test's shell): refused, nothing fetched or moved.
setup; stub_release 2.0.0; printf '%s %s\n' "$$" "$(started $$)" > "$lockf"; rc=0
out="$(update --self)" || rc=$?
[[ "$rc" == 1 && "$out" == *"another tuidev update is running (pid $$)"* && "$(cur)" == versions/1.0.0 && "$(downloads)" == 0 && -z "$(ran)" ]] || fail "a held lock: rc=$rc $out"
[[ "$(cat "$lockf")" == "$$ $(started $$)" ]] || fail "the holder's lock was touched: $(cat "$lockf")"
# --check and --dry-run take none, held or not.
update --check >/dev/null || fail "--check with the lock held"
update --self --dry-run >/dev/null || fail "--dry-run with the lock held"
rc=0; "$SH" "$TUIDEV_HOME/current/install.sh" --pack release-age --dry-run < /dev/null >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 ]] || fail "install.sh --dry-run with the lock held: rc=$rc"
rc=0; out="$("$SH" "$TUIDEV_HOME/current/install.sh" --pack release-age < /dev/null 2>&1)" || rc=$?
[[ "$rc" == 1 && "$out" == *"another tuidev update is running (pid $$)"* && ! -e "$TUIDEV_STATE_DIR/manifest" ]] || fail "install.sh with the lock held: rc=$rc $out"
# A holder that is gone (its pid ended, or is another process now) is taken over, and the lock released at the end.
dead="$("$SH" -c 'echo $$')"
setup; stub_release 2.0.0; printf '%s Thu Jan  1 00:00:00 1970\n' "$dead" > "$lockf"
out="$(update --repo)" || fail "a dead holder's lock: $out"
[[ "$(cur)" == versions/2.0.0 && ! -e "$lockf" ]] || fail "a dead holder's lock was not taken over and released: $(cur) $(cat "$lockf" 2>&1)"
# Twelve at once over a dead holder's lock: never two holders (a takeover by rename let several in).
setup; mkdir -p "$tmp/race/in"; : > "$tmp/race/seen"; printf '%s Thu Jan  1 00:00:00 1970\n' "$dead" > "$lockf"
cat > "$tmp/race/c.sh" <<'RACE'
. "$1/scripts/lib/lock.sh"
tuidev_update_lock >/dev/null 2>&1 || exit 0
: > "$2/in/$$"; ls "$2/in" | wc -l >> "$2/seen"; sleep 0.3; rm -f "$2/in/$$"; tuidev_update_unlock
RACE
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do "$SH" "$tmp/race/c.sh" "$REPO_DIR" "$tmp/race" & done; wait
most="$(sort -n "$tmp/race/seen" | tail -1 | tr -d ' ')"
[[ "$most" == 1 && ! -e "$lockf" && ! -e "$lockf.claim" ]] || fail "twelve takers of a dead holder's lock: ${most:-0} held it at once; left: $(cd "$TUIDEV_STATE_DIR" && echo ./*)"
# Handed over with exec (same pid): the new update.sh keeps the lock, and releases it at the end.
setup; NEW="$tmp/build/tuidev-2.0.0"; rm -rf "$NEW"; real_tree "$NEW" 2.0.0; publish "$NEW"
out="$(update --self)" || fail "a real hand-over with the lock: $(echo "$out" | tail -8)"
[[ "$out" == *"Update Complete"* && "$out" != *"another tuidev update"* && ! -e "$lockf" ]] || fail "the hand-over and the lock: $(echo "$out" | tail -8)"
pass "one update at a time: a live holder refuses update and install; dry runs take none; a dead one is taken over, by one of twelve; an exec hand-over keeps it"

# --- 11. a clone whose pull fails -------------------------------------------------------------------------------
setup
git init -q --bare "$tmp/upstream.git" 2>/dev/null
git clone -q "$tmp/upstream.git" "$tmp/clone" 2>/dev/null
real_tree "$tmp/clone" 1.0.0
git -C "$tmp/clone" add -A 2>/dev/null
git -C "$tmp/clone" -c user.name=t -c user.email=t@example.invalid commit -q -m init 2>/dev/null
git -C "$tmp/clone" push -q origin HEAD 2>/dev/null
git -C "$tmp/clone" branch -q --set-upstream-to "origin/$(git -C "$tmp/clone" rev-parse --abbrev-ref HEAD 2>/dev/null)" 2>/dev/null
printf 'profile=test\ncore=false\nremote=false\nsandbox=false\nui=false\nextras=false\nrepo=%s\n' "$tmp/clone" > "$TUIDEV_STATE_DIR/profile"
rm -rf "$tmp/upstream.git"; rc=0
out="$("$SH" "$tmp/clone/scripts/update.sh" --self < /dev/null 2>&1)" || rc=$?
[[ "$rc" == 1 && "$out" == *"not updated: could not reach or fast-forward the upstream of $tmp/clone (still on 1.0.0 at "* \
   && "$out" != *"Update Complete"* && "$out" != *"Done."* ]] || fail "a clone whose pull fails: rc=$rc $(echo "$out" | tail -8)"
rm -rf "$tmp/clone"
pass "a clone whose pull fails ends with 'not updated' and exit 1, not Done"

echo ""
echo "All update release-mode tests passed."
