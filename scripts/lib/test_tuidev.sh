#!/bin/bash
# Tests for bin/tuidev: how it finds tuidev's files, the version comparison,
# the once-a-day update check (against a stub curl), the one notification per
# release, whatsnew, the palette rows, and `update` in its modes including
# --ask and --rollback. Nothing is fetched: curl, update.sh and notify.sh are
# stubs, and HOME is a throwaway directory.
# Run: bash scripts/lib/test_tuidev.sh  -> exit 0 on pass (also under /bin/bash).
#
# shellcheck disable=SC2015,SC2016  # `a && b || fail` checks; stub code in single quotes on purpose

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUIDEV="$REPO_DIR/bin/tuidev"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-cli.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home"
export TUIDEV_STATE_DIR="$HOME/.config/tuidev" XDG_CACHE_HOME="$HOME/.cache" TUIDEV_HOME="$HOME/.local/share/tuidev"
export TUIDEV_RELEASE_URL="https://example.invalid/releases"
export TUIDEV_NOW=1000000
unset TUIDEV_REPO TUIDEV_UPDATE_CHECK XDG_CONFIG_HOME XDG_DATA_HOME HERDR_ENV
CACHE="$XDG_CACHE_HOME/tuidev"
BIN="$tmp/bin"
mkdir -p "$HOME/.local/bin" "$BIN"
CALLS="$tmp/calls"        # one line per curl / notify / update.sh call

# A curl that prints $CURL_OUT (the redirect URL -w would print) or fails.
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$CALLS"
[[ -z "${CURL_SLEEP:-}" ]] || sleep "$CURL_SLEEP"
[[ "${CURL_RC:-0}" == 0 ]] || exit "$CURL_RC"
printf '%s' "${CURL_OUT:-}"
EOF
chmod +x "$BIN/curl"
export CALLS
# Only the stubs and the system basics: no real agents, herdr, secret or fzf.
export PATH="$BIN:/usr/bin:/bin"
tuidev() { "$SH" "$TUIDEV" "$@"; }

# fixture DIR VERSION — a tuidev tree: an installer, a VERSION, a CHANGELOG, a
# themes dir and an update.sh that records its arguments.
fixture() {
    mkdir -p "$1/scripts" "$1/configs/themes/night"
    printf '%s\n' "$2" > "$1/VERSION"
    printf '#!/bin/bash\necho "install.sh $*" >> "$CALLS"\n' > "$1/install.sh"
    printf '#!/bin/bash\necho "update.sh $*" >> "$CALLS"\n' > "$1/scripts/update.sh"
    chmod +x "$1/install.sh" "$1/scripts/update.sh"
}
calls() { cat "$CALLS" 2>/dev/null || true; }
reset() {
    rm -rf "$HOME/.config" "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/bin/notify.sh"
    mkdir -p "$HOME/.local/bin" "$TUIDEV_STATE_DIR"; : > "$CALLS"
    unset TUIDEV_REPO TUIDEV_UPDATE_CHECK CURL_RC CURL_OUT
    export TUIDEV_NOW=1000000
}
cache() { cat "$CACHE/latest" 2>/dev/null || echo none; }
setcache() { mkdir -p "$CACHE"; printf '%s\n' "$1" > "$CACHE/latest"; }
TAG="https://example.invalid/releases/tag"

# --- 1. where tuidev's files are ---------------------------------------------------
reset
fixture "$tmp/clone" 3.0.0; fixture "$tmp/profrepo" 3.1.0; fixture "$tmp/rel/versions/3.2.0" 3.2.0
mkdir -p "$TUIDEV_HOME"; ln -s "$tmp/rel/versions/3.2.0" "$TUIDEV_HOME/current"

out="$(tuidev home 2>&1)" && [[ "$out" == "$tmp/rel/versions/3.2.0" || "$out" == "$TUIDEV_HOME/current" ]] || fail "current: $out"
printf 'profile=x\nrepo=%s\n' "$tmp/profrepo" > "$TUIDEV_STATE_DIR/profile"
[[ "$(tuidev home)" == "$tmp/profrepo" ]] || fail "repo= in the profile: $(tuidev home)"
[[ "$(TUIDEV_REPO="$tmp/clone" tuidev home)" == "$tmp/clone" ]] || fail "TUIDEV_REPO beats the profile"
# A recorded path that is not (any more) a tuidev tree falls to the unpacked release.
printf 'repo=%s\n' "$tmp/gone" > "$TUIDEV_STATE_DIR/profile"
[[ "$(tuidev home)" == "$TUIDEV_HOME/current" ]] || fail "stale repo=: $(tuidev home)"
[[ "$(TUIDEV_REPO="$tmp/gone" tuidev home)" == "$TUIDEV_HOME/current" ]] || fail "stale TUIDEV_REPO"
rm "$TUIDEV_HOME/current"
rc=0; err="$(tuidev home 2>&1)" || rc=$?
[[ "$rc" == 1 && "$err" == *"not on this machine any more"* && "$err" == *"get.sh"* ]] || fail "no repo at all: rc=$rc $err"
rc=0; tuidev update >/dev/null 2>&1 || rc=$?; [[ "$rc" == 1 ]] || fail "update with no repo: rc=$rc"
pass "repo discovery: TUIDEV_REPO, repo= in the profile, TUIDEV_HOME/current, then a clear error"

# --- 2. version ----------------------------------------------------------------------
reset; fixture "$tmp/clone" 3.0.0
[[ "$(TUIDEV_REPO="$tmp/clone" tuidev version)" == "tuidev 3.0.0" ]] || fail "version from TUIDEV_REPO"
[[ "$(tuidev version)" == "tuidev unknown" ]] || fail "version with nothing: $(tuidev version)"
echo 2.5.1 > "$TUIDEV_STATE_DIR/version"
[[ "$(tuidev version)" == "tuidev 2.5.1" && "$(tuidev --version)" == "tuidev 2.5.1" && "$(tuidev -V)" == "tuidev 2.5.1" ]] || fail "version from the state file"
echo garbage > "$TUIDEV_STATE_DIR/version"; printf 'repo=%s\n' "$tmp/clone" > "$TUIDEV_STATE_DIR/profile"
[[ "$(tuidev version)" == "tuidev 3.0.0" ]] || fail "a bad state version falls to the repo's VERSION: $(tuidev version)"
# What was last applied (the state file) beats the files' own VERSION; TUIDEV_REPO unset reads no VERSION of its own.
echo 2.5.1 > "$TUIDEV_STATE_DIR/version"
[[ "$(TUIDEV_REPO="$tmp/clone" tuidev version)" == "tuidev 2.5.1" ]] || fail "the state version beats TUIDEV_REPO's VERSION: $(TUIDEV_REPO="$tmp/clone" tuidev version)"
[[ "$(tuidev version)" == "tuidev 2.5.1" ]] || fail "TUIDEV_REPO unset: the state version: $(tuidev version)"
echo garbage > "$TUIDEV_STATE_DIR/version"
[[ "$(TUIDEV_REPO="$tmp/clone" tuidev version)" == "tuidev 3.0.0" ]] || fail "a bad state version falls to TUIDEV_REPO's VERSION"
pass "version: the state file, then TUIDEV_REPO's VERSION, then the recorded repo; garbage ignored"

# --- 3. which is newer: numbers, not text ------------------------------------------------
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
check() {  # check INSTALLED CACHED WANT-substring
    echo "$1" > "$tmp/clone/VERSION"; setcache "$2 99999999 $TUIDEV_NOW"
    out="$(tuidev latest)"; [[ "$out" == *"$3"* ]] || fail "installed $1, latest $2: wanted '$3', got '$out'"
}
check 3.9.0 3.10.0 "3.10.0 is out; you have 3.9.0"
check 3.10.0 3.9.0 "is up to date"
check 3.9.0 3.9.0 "is up to date"
check 3.9.1 3.9.0 "is up to date"
check 3.9.0 3.9.1 "3.9.1 is out"
check 3.9.0 4.0.0 "4.0.0 is out"
check 3.23.0 3.100.0 "3.100.0 is out"
check 3.9.0 3.08.0 "is up to date"
setcache "- 0 0"; out="$(tuidev latest)"; [[ "$out" == *"no release checked yet"* ]] || fail "no cache: $out"
[[ -z "$(calls)" ]] || fail "plain latest made a request: $(calls)"
setcache "3.9.0 99999999 $(( TUIDEV_NOW - 7200 ))"; out="$(tuidev latest)"; [[ "$out" == *"checked 2h ago"* ]] || fail "age: $out"
pass "latest compares numbers: 3.10.0 > 3.9.0, equal and older are up to date, and plain latest asks nothing"

# --- 4. the check itself ---------------------------------------------------------------------
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
CURL_OUT="$TAG/v3.25.0" tuidev latest --refresh >/dev/null
[[ "$(cache)" == "3.25.0 1086400 1000000" ]] || fail "success books a day: $(cache)"
[[ "$(calls)" == "curl -q -fsS -o /dev/null -w %{redirect_url} --connect-timeout 10 --max-time 20 $TUIDEV_RELEASE_URL/latest" ]] || fail "the request: $(calls)"
for bad in "$TAG/nightly" "" "$TAG/v3.25" "https://example.invalid/releases/" "$TAG/v3.25.0-rc1"; do
    reset; setcache "3.20.0 5 4"; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
    err="$(CURL_OUT="$bad" tuidev latest --refresh 2>&1 >/dev/null)" || true
    [[ "$err" == *"could not reach"* ]] || fail "garbage redirect '$bad' not reported: $err"
    [[ "$(cache)" == "3.20.0 1003600 4" ]] || fail "garbage redirect '$bad': a retry in an hour, the old answer kept: $(cache)"
done
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
err="$(CURL_RC=6 tuidev latest --refresh 2>&1 >/dev/null)" || true
[[ "$err" == *"could not reach"* && "$(cache)" == "- 1003600 0" ]] || fail "curl failure: $err / $(cache)"
pass "refresh: a good tag books a day, garbage or a failed request books an hour and keeps the old answer"

# --if-due: silent, and no request before NEXT.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
setcache "3.20.0 1000500 900000"
out="$(CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due)"
[[ -z "$out" && -z "$(calls)" && "$(cache)" == "3.20.0 1000500 900000" ]] || fail "--if-due before NEXT: out='$out' calls='$(calls)' cache=$(cache)"
TUIDEV_NOW=1000500 CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due > "$tmp/o"
[[ ! -s "$tmp/o" && "$(cache)" == "3.30.0 1086900 1000500" && "$(calls | wc -l | tr -d ' ')" == 1 ]] || fail "--if-due at NEXT: $(cache) $(calls)"
# A failed due check is silent too, and books the retry.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
out="$(CURL_RC=7 tuidev latest --if-due 2>&1)"; [[ -z "$out" && "$(cache)" == "- 1003600 0" ]] || fail "--if-due failing: '$out' $(cache)"
# Two refreshes in a row: the second finds the next check booked (the cache is written before the request).
out="$(tuidev latest --if-due 2>&1)"; [[ "$(calls | wc -l | tr -d ' ')" == 1 ]] || fail "a booked retry still asked again: $(calls)"
pass "--if-due: silent, no request before NEXT, one request after, a failure is booked"

# A cache dir that cannot be written: --if-due asks nothing, --refresh still asks.
if [[ "$(id -u)" == 0 ]]; then
    echo "SKIP: running as root, a chmod 500 cache dir stays writable"
else
    reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
    mkdir -p "$CACHE"; chmod 500 "$CACHE"
    out="$(CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due 2>&1)"
    [[ -z "$out" && -z "$(calls)" ]] || fail "--if-due with an unwritable cache asked: '$out' $(calls)"
    out="$(CURL_OUT="$TAG/v3.30.0" tuidev latest --refresh 2>&1)" || true
    [[ "$(calls | wc -l | tr -d ' ')" == 1 ]] || fail "--refresh with an unwritable cache must still ask: $(calls)"
    chmod 700 "$CACHE"
    pass "an unwritable cache dir: --if-due makes no request, a forced --refresh does"
fi

# One check at a time: a lock dir, stale after 120 s.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
for _ in 1 2 3; do CURL_SLEEP=1 CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1 & done; wait
[[ "$(calls | wc -l | tr -d ' ')" == 1 && "$(cache)" == "3.30.0 1086400 1000000" && ! -e "$CACHE/lock" ]] \
    || fail "three concurrent --if-due: $(calls) / $(cache) / lock: $(ls "$CACHE")"
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
mkdir -p "$CACHE/lock"; echo "$TUIDEV_NOW" > "$CACHE/lock/at"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ -z "$(calls)" && -d "$CACHE/lock" ]] || fail "a fresh lock held by someone else: asked ($(calls)) or removed it"
echo "$(( TUIDEV_NOW - 100 ))" > "$CACHE/lock/at"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ -z "$(calls)" ]] || fail "a lock 100 s old is not stale: $(calls)"
echo "$(( TUIDEV_NOW - 121 ))" > "$CACHE/lock/at"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ "$(calls | wc -l | tr -d ' ')" == 1 && ! -e "$CACHE/lock" && "$(cache)" == "3.30.0 1086400 1000000" ]] || fail "a stale lock was not taken over: $(calls) / $(cache)"
pass "the check lock: three concurrent --if-due make one request; a fresh lock means none; a stale one is taken over"

# Taking over a stale lock: claimed in place (a `claim` directory inside it),
# never moved, so it is free for nobody else meanwhile. A claim another check
# holds means this one takes nothing and leaves the lock as it is.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
mkdir -p "$CACHE/lock/claim"; echo "$(( TUIDEV_NOW - 500 ))" > "$CACHE/lock/at"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ -z "$(calls)" && -d "$CACHE/lock/claim" && "$(cat "$CACHE/lock/at")" == "$(( TUIDEV_NOW - 500 ))" ]] \
    || fail "a stale lock another check is claiming was taken or changed: $(calls) / $(ls -A "$CACHE/lock" 2>&1)"
# A claim whose owner died as well: cleared with its lock once ten times as
# old, and the check after that asks.
echo "$(( TUIDEV_NOW - 1300 ))" > "$CACHE/lock/at"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ -z "$(calls)" && ! -e "$CACHE/lock" ]] || fail "a dead claim's lock was not cleared: $(calls) / $(ls -A "$CACHE")"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ "$(calls | wc -l | tr -d ' ')" == 1 && ! -e "$CACHE/lock" ]] || fail "the check after a cleared lock did not ask once: $(calls)"
# Eight checks that find the same stale lock: one request.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
mkdir -p "$CACHE/lock"; echo "$(( TUIDEV_NOW - 500 ))" > "$CACHE/lock/at"
for _ in 1 2 3 4 5 6 7 8; do CURL_SLEEP=1 CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1 & done; wait
[[ "$(calls | wc -l | tr -d ' ')" == 1 && ! -e "$CACHE/lock" && -z "$(find "$CACHE" -name 'lock.*')" ]] \
    || fail "eight checks taking over one stale lock: $(calls) / $(ls -A "$CACHE")"
# A lock with no time in it belongs to a check between its mkdir and its
# echo: never taken over, however long that takes. One left like that for
# two minutes (the directory's own time) is removed, and the next check asks.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
mkdir -p "$CACHE/lock"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ -z "$(calls)" && -d "$CACHE/lock" ]] || fail "a fresh lock with no time was taken or removed: $(calls) / $(ls -A "$CACHE")"
touch -t 202001010000 "$CACHE/lock"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ -z "$(calls)" && ! -e "$CACHE/lock" ]] || fail "an old lock with no time was not removed: $(calls) / $(ls -A "$CACHE")"
CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null 2>&1
[[ "$(calls | wc -l | tr -d ' ')" == 1 && ! -e "$CACHE/lock" ]] || fail "the check after it did not ask once: $(calls)"
pass "a stale lock: one of several takes it over, in place; another's claim is left alone and a dead one cleared; one with no time is left to its holder, and removed once it is old"

# --newer: silent, 0 newer known, 1 the latest is installed, 2 unknown.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
setcache "3.10.0 99999999 1"; rc=0; out="$(tuidev latest --newer 2>&1)" || rc=$?
[[ "$rc" == 0 && -z "$out" ]] || fail "--newer with a newer release: rc=$rc '$out'"
setcache "3.9.0 99999999 1"; rc=0; out="$(tuidev latest --newer 2>&1)" || rc=$?
[[ "$rc" == 1 && -z "$out" ]] || fail "--newer with the latest installed: rc=$rc '$out'"
setcache "3.8.0 99999999 1"; rc=0; tuidev latest --newer >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "--newer with an older latest: rc=$rc"
setcache "- 0 0"; rc=0; out="$(tuidev latest --newer 2>&1)" || rc=$?
[[ "$rc" == 2 && -z "$out" && -z "$(calls)" ]] || fail "--newer with no release known: rc=$rc '$out' $(calls)"
setcache "3.9.0 99999999 1"; echo 'garbage' > "$tmp/clone/VERSION"; rc=0; tuidev latest --newer >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "--newer with no installed version known: rc=$rc"
echo 3.9.0 > "$tmp/clone/VERSION"
rc=0; out="$(CURL_OUT="$TAG/v3.30.0" tuidev latest --refresh --newer 2>&1)" || rc=$?
[[ "$rc" == 0 && -z "$out" && "$(cache)" == "3.30.0 1086400 1000000" ]] || fail "--refresh --newer: rc=$rc '$out' $(cache)"
pass "latest --newer: silent; exit 0 newer known, 1 the latest is installed, 2 unknown"

# off / on / TUIDEV_UPDATE_CHECK=0
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
out="$(tuidev latest off)"; [[ "$out" == *"update check is off"* && "$(cat "$TUIDEV_STATE_DIR/update-check")" == off ]] || fail "latest off: $out"
CURL_OUT="$TAG/v3.30.0" tuidev latest --refresh >/dev/null; CURL_OUT="$TAG/v3.30.0" tuidev latest --if-due >/dev/null
[[ -z "$(calls)" && "$(cache)" == "- 1086400 0" ]] || fail "off still asked: $(calls) / $(cache)"
out="$(tuidev latest)"; [[ "$out" == *"check is off"* ]] || fail "off is not mentioned: $out"
out="$(tuidev latest on)"; [[ "$out" == *"is on"* && ! -e "$TUIDEV_STATE_DIR/update-check" ]] || fail "latest on: $out"
CURL_OUT="$TAG/v3.30.0" tuidev latest --refresh >/dev/null; [[ "$(cache)" == "3.30.0 1086400 1000000" ]] || fail "on: $(cache)"
: > "$CALLS"; rm -rf "$CACHE"
TUIDEV_UPDATE_CHECK=0 CURL_OUT="$TAG/v3.30.0" tuidev latest --refresh >/dev/null
[[ -z "$(calls)" ]] || fail "TUIDEV_UPDATE_CHECK=0 asked: $(calls)"
pass "off, on and TUIDEV_UPDATE_CHECK=0: no request while off"

rc=0; tuidev latest --bogus >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] || fail "latest --bogus: rc=$rc"

# --- 5. one notification per release ---------------------------------------------------------
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
printf '#!/bin/bash\necho "notify.sh $*" >> "$CALLS"\n' > "$HOME/.local/bin/notify.sh"; chmod +x "$HOME/.local/bin/notify.sh"
setcache "3.9.0 99999999 1"; tuidev latest --notify
[[ -z "$(calls)" ]] || fail "notified with nothing new: $(calls)"
setcache "3.10.0 99999999 1"; tuidev latest --notify; tuidev latest --notify; tuidev latest --notify
[[ "$(calls | wc -l | tr -d ' ')" == 1 && "$(calls)" == *"notify.sh tuidev 3.10.0 is out (you have 3.9.0)"* ]] || fail "one notify for 3.10.0: $(calls)"
[[ -d "$CACHE/notified.3.10.0" ]] || fail "notified marker"
setcache "3.11.0 99999999 1"; tuidev latest --notify
[[ "$(calls | wc -l | tr -d ' ')" == 2 ]] || fail "a newer release notifies again: $(calls)"
[[ -d "$CACHE/notified.3.11.0" && ! -e "$CACHE/notified.3.10.0" ]] || fail "the older record stays, or the new one is missing: $(ls "$CACHE")"
# A check that still held the older answer does not undo the newer record.
setcache "3.10.0 99999999 1"; tuidev latest --notify; setcache "3.11.0 99999999 1"; tuidev latest --notify
[[ "$(calls | wc -l | tr -d ' ')" == 3 && -d "$CACHE/notified.3.11.0" ]] || fail "an older answer removed the newer record: $(calls) / $(ls "$CACHE")"
# 3.23.0 recorded it in a file: what it told you is not told again, and the file goes.
rm -rf "$CACHE"/notified.*; : > "$CALLS"; echo 3.11.0 > "$CACHE/notified"; tuidev latest --notify
[[ -z "$(calls)" && -d "$CACHE/notified.3.11.0" && ! -e "$CACHE/notified" ]] || fail "3.23.0's record: $(calls) / $(ls "$CACHE")"
rm "$HOME/.local/bin/notify.sh"; setcache "3.12.0 99999999 1"; tuidev latest --notify
[[ -d "$CACHE/notified.3.12.0" ]] || fail "no notify.sh: still marked"
pass "--notify: once per release version, never for what is installed, quiet without notify.sh"

# Concurrent notifies call notify.sh once; a cache that cannot record it shows nothing.
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
printf '#!/bin/bash\nsleep 1\necho "notify.sh $*" >> "$CALLS"\n' > "$HOME/.local/bin/notify.sh"; chmod +x "$HOME/.local/bin/notify.sh"
setcache "3.10.0 99999999 1"
for _ in 1 2 3 4 5 6; do tuidev latest --notify >/dev/null 2>&1 & done; wait
[[ "$(calls | wc -l | tr -d ' ')" == 1 && -d "$CACHE/notified.3.10.0" && "$(find "$CACHE" -name 'notified*' | wc -l | tr -d ' ')" == 1 ]] \
    || fail "three concurrent --notify: $(calls) / $(ls "$CACHE")"
if [[ "$(id -u)" != 0 ]]; then
    : > "$CALLS"; rmdir "$CACHE/notified.3.10.0"; chmod 500 "$CACHE"
    tuidev latest --notify >/dev/null 2>&1
    chmod 700 "$CACHE"
    [[ -z "$(calls)" ]] || fail "--notify with a cache that cannot record it showed something: $(calls)"
fi
rm -f "$HOME/.local/bin/notify.sh"
pass "--notify: concurrent runs notify once; with an unwritable cache nothing is shown"

# --- 6. whatsnew ------------------------------------------------------------------------------
reset; fixture "$tmp/clone" 3.10.0; export TUIDEV_REPO="$tmp/clone"
cat > "$tmp/clone/CHANGELOG.md" <<'EOF'
# Changelog

Preamble that is no section.

## [Unreleased]

- an unreleased thing

## [3.10.0] - 2026-11-01

- ten

## [3.9.0] - 2026-10-01

- nine

## [3.1.0] - 2026-09-01

- one

## [3.0.0] - 2026-08-01

- zero
EOF
out="$(tuidev whatsnew)"
[[ "$out" == *"- ten"* && "$out" != *"nine"* && "$out" != *"unreleased"* && "$out" != *"Preamble"* ]] || fail "whatsnew: $out"
out="$(tuidev whatsnew 3.1.0)"
[[ "$out" == *"- ten"* && "$out" == *"- nine"* && "$out" != *"- one"* && "$out" != *"unreleased"* ]] || fail "whatsnew 3.1.0: $out"
out="$(tuidev whatsnew v3.9.0)"
[[ "$out" == *"- ten"* && "$out" != *"nine"* ]] || fail "whatsnew v3.9.0 (10 > 9): $out"
out="$(tuidev whatsnew 0.1.0)"; [[ "$out" == *"- zero"* && "$out" != *unreleased* ]] || fail "whatsnew from the start: $out"
out="$(tuidev whatsnew 3.10.0)"; [[ -z "$out" ]] || fail "whatsnew from the latest should be empty: $out"
rc=0; tuidev whatsnew nine >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] || fail "whatsnew with a bad FROM: rc=$rc"
rm "$tmp/clone/CHANGELOG.md"; rc=0; err="$(tuidev whatsnew 2>&1)" || rc=$?
[[ "$rc" == 1 && "$err" == *"no CHANGELOG.md"* ]] || fail "no changelog: $rc $err"
pass "whatsnew: the newest section, or all after FROM, numeric order, [Unreleased] skipped"

# --- 7. the palette ----------------------------------------------------------------------------
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
setcache "3.9.0 99999999 1"
rows="$(tuidev palette --list)"
bad="$(printf '%s\n' "$rows" | awk -F'\t' 'NF != 4 || $3 !~ /^[01]$/ || $4 == "" { print }')"
[[ -n "$rows" && -z "$bad" ]] || fail "palette rows that are not TITLE<TAB>WHAT<TAB>0|1<TAB>COMMAND: $bad"
[[ "$rows" != *"Update tuidev to"* ]] || fail "an update row with nothing newer"
[[ "$rows" == *"Theme: night"* && "$rows" == *"Health check"* ]] || fail "repo rows missing: $rows"
setcache "3.10.0 99999999 1"
rows="$(tuidev palette --list)"
bad="$(printf '%s\n' "$rows" | awk -F'\t' 'NF != 4 { print }')"; [[ -z "$bad" ]] || fail "rows with an update: $bad"
[[ "$(printf '%s\n' "$rows" | head -1)" == "Update tuidev to 3.10.0"$'\t'*$'\t'1$'\t'"tuidev update --ask" ]] || fail "the update row is first: $(printf '%s\n' "$rows" | head -1)"
printf '#!/bin/bash\n' > "$BIN/agents"; chmod +x "$BIN/agents"
rows="$(tuidev palette --list)"; bad="$(printf '%s\n' "$rows" | awk -F'\t' 'NF != 4 { print }')"
[[ -z "$bad" && "$rows" == *"Who needs me"* ]] || fail "rows with agents: $bad"
rm "$BIN/agents"
# Theme rows only for names like a theme's: a stray directory adds none.
for odd in "Bad Name" "-x" ".hidden" 'a;b' 'Caps' "it's"; do mkdir -p "$tmp/clone/configs/themes/$odd"; done
mkdir -p "$tmp/clone/configs/themes/dark-2_x"
rows="$(tuidev palette --list)"
[[ "$(printf '%s\n' "$rows" | grep -c '^Theme: ')" == 2 && "$rows" == *"Theme: night"* && "$rows" == *"Theme: dark-2_x"* ]] || fail "theme rows: $(printf '%s\n' "$rows" | grep '^Theme: ')"
# The Cheatsheet command survives a repo path with a space and a quote.
weird="$tmp/it's a repo"; fixture "$weird" 3.9.0; mkdir -p "$weird/docs"; : > "$weird/docs/CHEATSHEET.md"
printf '#!/bin/bash\nprintf "%%s" "$1" > "%s/pager.arg"\n' "$tmp" > "$BIN/rec"; chmod +x "$BIN/rec"
rows="$(PAGER=rec TUIDEV_REPO="$weird" tuidev palette --list)"
row="$(printf '%s\n' "$rows" | grep '^Cheatsheet')"; cmd="${row##*$'\t'}"
PAGER=rec bash -c "$cmd" || fail "the Cheatsheet command does not run: $cmd"
[[ "$(cat "$tmp/pager.arg")" == "$weird/docs/CHEATSHEET.md" ]] || fail "the pager got '$(cat "$tmp/pager.arg")'"
rm -rf "$weird" "$BIN/rec"
# ~/.local/bin is searched even when PATH lacks it (a Herdr server started by launchd).
printf '#!/bin/bash\n' > "$HOME/.local/bin/agents"; chmod +x "$HOME/.local/bin/agents"
rows="$(tuidev palette --list)"; [[ "$rows" == *"Who needs me"* ]] || fail "palette did not look in ~/.local/bin"
rm -f "$HOME/.local/bin/agents"
pass "palette: theme rows only for safe names, a quoted Cheatsheet command, ~/.local/bin on PATH"
# No repo and nothing else on PATH: nothing to show.
reset; rc=0; err="$(tuidev palette --list 2>&1)" || rc=$?
[[ "$rc" == 1 && "$err" == *"nothing to show"* ]] || fail "empty palette: $rc $err"
pass "palette --list: four tab-separated fields per row, the update row only when one is out"

# --- 8. update ----------------------------------------------------------------------------------
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
tuidev update; [[ "$(calls)" == "update.sh --self" ]] || fail "update: $(calls)"
: > "$CALLS"; tuidev update --check; [[ "$(calls)" == "update.sh --check" ]] || fail "update --check: $(calls)"
: > "$CALLS"; tuidev update --packages --yes; [[ "$(calls)" == "update.sh --packages --yes" ]] || fail "update --packages --yes: $(calls)"
# --yes and --dry-run alone still mean tuidev itself, never update.sh's menu.
: > "$CALLS"; tuidev update --yes; [[ "$(calls)" == "update.sh --self --yes" ]] || fail "update --yes: $(calls)"
: > "$CALLS"; tuidev update --dry-run -y; [[ "$(calls)" == "update.sh --self --dry-run -y" ]] || fail "update --dry-run -y: $(calls)"
: > "$CALLS"; tuidev install --profile minimal --dry-run; [[ "$(calls)" == "install.sh --profile minimal --dry-run" ]] || fail "install: $(calls)"

# --ask
: > "$CALLS"; setcache "3.9.0 99999999 1"
out="$(CURL_OUT="$TAG/v3.9.0" tuidev update --ask </dev/null)"
[[ "$out" == *"is the latest release"* && "$(calls)" == curl* && "$(calls)" != *update.sh* ]] || fail "--ask with nothing newer: $out / $(calls)"
: > "$CALLS"
out="$(CURL_OUT="$TAG/v3.10.0" tuidev update --ask <<< n)"
[[ "$out" == *"tuidev 3.10.0 is out; you have 3.9.0."* && "$out" == *"Update now? [y/N]"* && "$out" == *"Not updated"* ]] || fail "--ask n: $out"
[[ "$(calls)" != *update.sh* ]] || fail "--ask n ran update.sh: $(calls)"
: > "$CALLS"; out="$(CURL_OUT="$TAG/v3.10.0" tuidev update --ask </dev/null)"
[[ "$out" == *"Not updated"* && "$(calls)" != *update.sh* ]] || fail "--ask with no answer must not update: $out"
: > "$CALLS"; CURL_OUT="$TAG/v3.10.0" tuidev update --ask <<< y >/dev/null
[[ "$(calls)" == *"update.sh --self" ]] || fail "--ask y: $(calls)"
: > "$CALLS"; out="$(CURL_OUT="$TAG/v3.10.0" tuidev update --ask <<< yes)"
[[ "$(calls)" != *update.sh* ]] || fail "--ask 'yes' is not y/Y: $(calls)"
# the check failing: the known answer is used
: > "$CALLS"; setcache "3.10.0 99999999 1"
out="$(CURL_RC=7 tuidev update --ask <<< n 2>&1)"
[[ "$out" == *"could not reach"* && "$out" == *"3.10.0 is out"* ]] || fail "--ask offline: $out"
pass "update: no args is --self, flags pass through, --ask asks and only y updates"

# --rollback
reset
mk_rel() { fixture "$TUIDEV_HOME/versions/$1" "$1"; printf '#!/bin/bash\n' > "$TUIDEV_HOME/versions/$1/get.sh"; }
mk_rel 1.0.0; mk_rel 1.1.0
ln -s versions/1.1.0 "$TUIDEV_HOME/current"; echo 1.0.0 > "$TUIDEV_HOME/previous"
printf 'repo=%s\n' "$TUIDEV_HOME/current" > "$TUIDEV_STATE_DIR/profile"
REAL_LN="$(command -v ln)"
printf '#!/bin/bash\necho "ln $*" >> "$CALLS"\nexec "%s" "$@"\n' "$REAL_LN" > "$BIN/ln"; chmod +x "$BIN/ln"
out="$(tuidev update --rollback)"
rm -f "$BIN/ln"
[[ "$out" == *"back on 1.0.0"* && "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.1.0 ]] || fail "rollback: $out / $(readlink "$TUIDEV_HOME/current") / $(cat "$TUIDEV_HOME/previous")"
# current moves with one rename onto it (get.sh's way), never ln -sfn.
[[ "$(calls)" == "ln -s versions/1.0.0 $TUIDEV_HOME/.current."*$'\n'"update.sh --configs --yes" ]] || fail "rollback: ln -s beside current, then configs: $(calls)"
[[ -z "$(find "$TUIDEV_HOME" -name '.current.*')" ]] || fail "rollback left its temp link"
: > "$CALLS"; out="$(tuidev update --rollback)"
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "rolling back twice goes forward again"
# no earlier release kept
rm "$TUIDEV_HOME/previous"; rc=0; err="$(tuidev update --rollback 2>&1)" || rc=$?
[[ "$rc" == 1 && "$err" == *"no earlier release"* && "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "no previous: $rc $err"
echo 0.9.0 > "$TUIDEV_HOME/previous"; rc=0; err="$(tuidev update --rollback 2>&1)" || rc=$?
[[ "$rc" == 1 && "$err" == *"no earlier release"* ]] || fail "previous not on disk: $rc $err"
echo '../../x' > "$TUIDEV_HOME/previous"; rc=0; err="$(tuidev update --rollback 2>&1)" || rc=$?
[[ "$rc" == 1 && "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "a hostile previous was followed: $rc $err"
# The home it lives in comes from the recorded path, not from TUIDEV_HOME in the environment.
reset
A="$tmp/homeA"; rm -rf "$A" "$tmp/other"
for v in 1.0.0 1.1.0; do fixture "$A/versions/$v" "$v"; printf '#!/bin/bash\n' > "$A/versions/$v/get.sh"; done
ln -s versions/1.1.0 "$A/current"; echo 1.0.0 > "$A/previous"; echo 9.9.9 > "$TUIDEV_STATE_DIR/version"
printf 'repo=%s\n' "$A/current" > "$TUIDEV_STATE_DIR/profile"
out="$(TUIDEV_HOME="$tmp/other" tuidev update --rollback)"
[[ "$(readlink "$A/current")" == versions/1.0.0 && "$(cat "$A/previous")" == 1.1.0 && ! -e "$tmp/other" ]] \
    || fail "rollback with another TUIDEV_HOME: $(readlink "$A/current") prev=$(cat "$A/previous") other=$(ls "$tmp/other" 2>&1)"
[[ "$(calls)" == "update.sh --configs --yes" ]] || fail "rollback re-applies configs: $(calls)"
rm -rf "$A"
# a git clone refuses
reset; fixture "$tmp/clone" 3.9.0; mkdir "$tmp/clone/.git"; : > "$tmp/clone/get.sh"; export TUIDEV_REPO="$tmp/clone"
rc=0; err="$(tuidev update --rollback 2>&1)" || rc=$?
[[ "$rc" == 1 && "$err" == *"--rollback is for an install made with get.sh"* ]] || fail "rollback in a clone: $rc $err"
pass "update --rollback: moves current back and re-applies configs; refused in a clone, without a previous, or with a bad one"

# --- 9. the rest of the commands ------------------------------------------------------------------
reset; fixture "$tmp/clone" 3.9.0; export TUIDEV_REPO="$tmp/clone"
printf '#!/bin/bash\necho "uninstall.sh $*" >> "$CALLS"\n' > "$tmp/clone/uninstall.sh"; chmod +x "$tmp/clone/uninstall.sh"
tuidev uninstall --all; [[ "$(calls)" == "uninstall.sh --all" ]] || fail "uninstall: $(calls)"
rc=0; err="$(tuidev frobnicate 2>&1)" || rc=$?
[[ "$rc" == 2 && "$err" == *"unknown command 'frobnicate'"* && "$err" == *"tuidev version | home"* ]] || fail "unknown command: rc=$rc $err"
out="$(tuidev help)"; last="$(printf '%s\n' "$out" | tail -1)"
[[ "$out" == "tuidev: one command"* && "$last" == *"tuidev version | home"* ]] || fail "usage should end at the command list, not mid-sentence; last line: '$last'"
[[ "$(tuidev </dev/null)" == "$out" ]] || fail "no args and no terminal prints the usage"
pass "uninstall passes through, unknown commands exit 2, usage is the command list"

echo ""
echo "All tuidev CLI tests passed."
