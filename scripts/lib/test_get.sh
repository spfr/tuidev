#!/bin/bash
# Tests for get.sh, the no-git bootstrap: what it downloads, what it refuses,
# where it unpacks, how it keeps the release before, and what it hands to
# install.sh. Releases are small fixtures built here with tar and served
# through file://, so nothing touches the network or the real HOME.
# Run: bash scripts/lib/test_get.sh  -> exit 0 on pass (also under /bin/bash).
#
# shellcheck disable=SC2015,SC2016,SC2012  # `a && b || fail` checks; stub code in single quotes on purpose

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GET="$REPO_DIR/get.sh"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-get.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home"
mkdir -p "$HOME"
unset TUIDEV_VERSION TUIDEV_HOME XDG_DATA_HOME TUIDEV_RELEASE_URL
REL="$tmp/rel"                         # TUIDEV_RELEASE_URL=file://$REL
export TUIDEV_RELEASE_URL="file://$REL"
mkdir -p "$REL/latest/download"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# tree VER — a fake release tree under $tmp/build/tuidev-VER. Its install.sh
# records its arguments, and how much it could read from stdin, in $INSTALL_LOG.
tree() {
    local d="$tmp/build/tuidev-$1"
    rm -rf "$d"; mkdir -p "$d/bin"
    printf '%s\n' "$1" > "$d/VERSION"
    cat > "$d/install.sh" <<'EOF'
#!/bin/bash
# --choose: the question alone. Logs that it was asked (and whether stdin was a
# terminal), reads 1-4 or q from stdin like the real one, or prints $CHOOSE_SAYS.
if [[ "${1:-}" == --choose ]]; then
    { [[ -t 0 ]] && echo asked-on-tty || echo asked-not-on-tty; } >> "$CHOOSE_LOG"
    if [[ -n "${CHOOSE_SAYS+x}" ]]; then printf '%s\n' "$CHOOSE_SAYS"; exit 0; fi
    read -r a || exit 1
    case "$a" in
        1) echo "--profile full" ;; 2) echo "--profile desktop --pack ai-clis" ;;
        3) echo "--profile remote --pack ai-clis" ;; 4) echo "--profile minimal" ;;
        *) exit 1 ;;
    esac
    exit 0
fi
{ printf 'argc=%s\n' "$#"; for a in "$@"; do printf '[%s]\n' "$a"; done
  if [[ -t 0 ]]; then printf 'stdin=tty\n'; else printf 'stdin=%s\n' "$(cat | wc -c | tr -d ' ')"; fi
  printf 'from=%s\n' "$(cd "$(dirname "$0")" && pwd -P)"; } > "$INSTALL_LOG"
exit "${STUB_RC:-0}"
EOF
    chmod +x "$d/install.sh"
    cp "$GET" "$d/get.sh"
    printf '#!/bin/bash\n' > "$d/bin/tuidev"; chmod +x "$d/bin/tuidev"
}

# publish SRC_DIR TOPS... — pack the named entries of SRC_DIR as the archive of
# every place a download can come from, with a matching checksum.
pack() {  # pack DEST SRC_DIR ENTRY...   (extra tar flags via TAR_FLAGS)
    local dest="$1" src="$2"; shift 2
    mkdir -p "$dest"
    # shellcheck disable=SC2086  # TAR_FLAGS is a word list on purpose
    COPYFILE_DISABLE=1 tar -czf "$dest/tuidev.tar.gz" ${TAR_FLAGS:-} -C "$src" "$@"
    printf '%s  tuidev.tar.gz\n' "$(sha "$dest/tuidev.tar.gz")" > "$dest/tuidev.tar.gz.sha256"
}
# release VER — the normal case, as the latest release and as a pinned one.
release() {
    tree "$1"
    pack "$REL/latest/download" "$tmp/build" "tuidev-$1"
    pack "$REL/download/v$1" "$tmp/build" "tuidev-$1"
}

new_home() { rm -rf "$tmp/h"; export TUIDEV_HOME="$tmp/h"; INSTALL_LOG="$tmp/install.log" CHOOSE_LOG="$tmp/choose.log"; export INSTALL_LOG CHOOSE_LOG; rm -f "$INSTALL_LOG" "$CHOOSE_LOG"; }
# detach CMD... — run CMD in a new session, so /dev/tty is not there even when
# the tests are run from a terminal (get.sh asks, or refuses, depending on it).
HAVE_PERL=""; command -v perl >/dev/null 2>&1 && HAVE_PERL=1
detach() {
    if [[ -n "$HAVE_PERL" ]]; then perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' "$@"
    else "$@"; fi
}
# with_tty CMD... — run CMD with a pseudo-terminal as its controlling
# terminal; $TTY_INPUT is typed into it (then ^D when TTY_EOF is set), and what
# it printed comes back on stdout.
with_tty() {
    python3 -I -c '
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
os.write(fd, os.environ.get("TTY_INPUT", "").encode())
if os.environ.get("TTY_EOF"): os.write(fd, b"\x04")   # ^D at the start of a line: end of input
buf = b""
while True:
    try:
        d = os.read(fd, 4096)
        if not d: break
        buf += d
    except OSError: break
_, st = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(st))
' "$@"
}
get() { detach "$SH" "$GET" "$@"; }
# refused ARGS... — get.sh must exit non-zero; its stderr is kept in $ERR.
refused() { if ERR="$(get "$@" 2>&1 >/dev/null)"; then fail "get.sh $* succeeded, should have refused"; fi; }
no_leftovers() { local l; l="$(find "$TUIDEV_HOME" -maxdepth 1 -name '.get.*' 2>/dev/null)"; [[ -z "$l" ]] || fail "temp dirs left: $l"; }
versions() { ls "$TUIDEV_HOME/versions" 2>/dev/null | tr '\n' ' '; }

# --- 1. happy path -------------------------------------------------------------
new_home; release 1.0.0
out="$(get --fetch 2>/dev/null)" || fail "--fetch failed"
[[ "$out" == "$TUIDEV_HOME/current" ]] || fail "--fetch printed '$out', not the current dir"
[[ -L "$TUIDEV_HOME/current" && "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 ]] || fail "current is $(readlink "$TUIDEV_HOME/current" 2>&1)"
[[ "$(cat "$TUIDEV_HOME/current/VERSION")" == 1.0.0 && -x "$TUIDEV_HOME/current/install.sh" && -x "$TUIDEV_HOME/current/bin/tuidev" ]] || fail "unpacked layout"
[[ ! -e "$TUIDEV_HOME/previous" ]] || fail "a first install has no previous"
[[ ! -e "$INSTALL_LOG" ]] || fail "--fetch ran install.sh"
no_leftovers
pass "fetch: unpacks to versions/1.0.0, points current at it, prints the path, runs nothing"

# TUIDEV_HOME unset falls back to XDG_DATA_HOME, then ~/.local/share.
unset TUIDEV_HOME
out="$(XDG_DATA_HOME="$tmp/xdg" get --fetch 2>/dev/null)" || fail "XDG fetch"
[[ "$out" == "$tmp/xdg/tuidev/current" ]] || fail "XDG_DATA_HOME ignored: $out"
out="$(get --fetch 2>/dev/null)" || fail "default-home fetch"
[[ "$out" == "$HOME/.local/share/tuidev/current" ]] || fail "default home: $out"
rm -rf "$tmp/xdg" "$HOME/.local"
pass "home: TUIDEV_HOME, then XDG_DATA_HOME, then ~/.local/share"

# --- 2. a download that is not the one published -----------------------------
new_home; release 1.0.0; get --fetch >/dev/null 2>&1
release 1.1.0
printf '%s  tuidev.tar.gz\n' "$(printf 'something else' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)" > "$REL/latest/download/tuidev.tar.gz.sha256"
refused --fetch
[[ "$ERR" == *"checksum mismatch"* ]] || fail "mismatch message: $ERR"
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 && "$(versions)" == "1.0.0 " && ! -e "$TUIDEV_HOME/previous" ]] || fail "a refused download touched the install: $(versions)"
no_leftovers
pass "checksum mismatch: refused, the existing install is untouched, no temp dir"

for bad in "nothex" "" "$(printf 'a%.0s' $(seq 1 63))" "$(printf 'A%.0s' $(seq 1 64))" "$(printf 'g%.0s' $(seq 1 64))"; do
    new_home; release 1.0.0
    printf '%s  tuidev.tar.gz\n' "$bad" > "$REL/latest/download/tuidev.tar.gz.sha256"
    [[ -n "$bad" ]] || : > "$REL/latest/download/tuidev.tar.gz.sha256"
    refused --fetch
    [[ "$ERR" == *"not a sha256"* ]] || fail "malformed checksum '$bad': $ERR"
    [[ ! -e "$TUIDEV_HOME/current" ]] || fail "malformed checksum '$bad' still installed"
    no_leftovers
done
pass "malformed checksum files (text, empty, 63 chars, upper case, non-hex) are refused"

new_home; release 1.0.0; rm "$REL/latest/download/tuidev.tar.gz.sha256"
refused --fetch; [[ "$ERR" == *"download failed"* && ! -e "$TUIDEV_HOME/current" ]] || fail "missing checksum: $ERR"
no_leftovers
new_home; release 1.0.0; rm "$REL/latest/download/tuidev.tar.gz"
refused --fetch; [[ "$ERR" == *"download failed"* && ! -e "$TUIDEV_HOME/current" ]] || fail "missing archive: $ERR"
no_leftovers
new_home; rm -rf "$REL/latest"; mkdir -p "$REL/latest/download"
refused --fetch; [[ "$ERR" == *"download failed"* ]] || fail "empty release: $ERR"
pass "a missing archive or checksum is a clear failure"

# --- 3. archives that are not tuidev's ----------------------------------------
new_home; release 1.0.0; tree 1.0.0; mkdir -p "$tmp/build/extra"; echo x > "$tmp/build/extra/file"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0 extra
refused --fetch; [[ "$ERR" == *"outside tuidev-1.0.0"* && ! -e "$TUIDEV_HOME/current" ]] || fail "second top dir: $ERR"
no_leftovers
rm -rf "$tmp/build/extra"

new_home; tree 1.0.0; mkdir -p "$tmp/build/dd"; echo x > "$tmp/build/dd/file"
TAR_FLAGS=-P pack "$REL/latest/download" "$tmp/build/dd" ../dd/file 2>/dev/null || true
# The member must really be named with ..; tar variants differ, so build it by hand when -P did not keep it.
if ! tar -tzf "$REL/latest/download/tuidev.tar.gz" | grep -q '\.\.'; then
    echo "SKIP: this tar will not write a .. member (checked by the layout test only)"
else
    refused --fetch; [[ ! -e "$TUIDEV_HOME/current" ]] || fail ".. member installed: $ERR"
    no_leftovers
fi
new_home; tree 1.0.0
# a .. below the top dir: tuidev-1.0.0/../../escape, written with -P and a transform-free path
mkdir -p "$tmp/build/tuidev-1.0.0/sub"; echo x > "$tmp/build/tuidev-1.0.0/sub/f"
if TAR_FLAGS=-P pack "$REL/latest/download" "$tmp/build" "tuidev-1.0.0" "tuidev-1.0.0/sub/../sub/f" 2>/dev/null \
   && tar -tzf "$REL/latest/download/tuidev.tar.gz" | grep -q '/\.\./'; then
    refused --fetch; [[ "$ERR" == *"outside"* && ! -e "$TUIDEV_HOME/current" ]] || fail "inner .. member: $ERR"
    no_leftovers
fi
rm -rf "$tmp/build/tuidev-1.0.0/sub"
pass "paths outside the top directory or with .. are refused, nothing unpacked"

new_home; tree 1.0.0; printf '1.0.1\n' > "$tmp/build/tuidev-1.0.0/VERSION"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0
refused --fetch; [[ "$ERR" == *"not tuidev 1.0.0"* && ! -e "$TUIDEV_HOME/current" ]] || fail "VERSION disagrees: $ERR"
no_leftovers
new_home; tree 1.0.0; rm "$tmp/build/tuidev-1.0.0/VERSION"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0
refused --fetch; [[ "$ERR" == *"not tuidev"* ]] || fail "no VERSION: $ERR"
new_home; tree 1.0.0; rm "$tmp/build/tuidev-1.0.0/install.sh"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0
refused --fetch; [[ "$ERR" == *"not tuidev 1.0.0"* && ! -e "$TUIDEV_HOME/current" ]] || fail "no install.sh: $ERR"
no_leftovers
new_home; tree 1.0.0; mv "$tmp/build/tuidev-1.0.0" "$tmp/build/tuidev-latest"
pack "$REL/latest/download" "$tmp/build" tuidev-latest
refused --fetch; [[ "$ERR" == *"unexpected archive layout"* ]] || fail "bad top name: $ERR"
rm -rf "$tmp/build/tuidev-latest"
new_home; printf 'not a tar' > "$tmp/junk"; mkdir -p "$REL/latest/download"
cp "$tmp/junk" "$REL/latest/download/tuidev.tar.gz"; printf '%s  tuidev.tar.gz\n' "$(sha "$tmp/junk")" > "$REL/latest/download/tuidev.tar.gz.sha256"
refused --fetch; [[ ! -e "$TUIDEV_HOME/current" ]] || fail "junk archive installed"
no_leftovers
pass "an archive whose VERSION or install.sh or top name is off, or that is not a tar, is refused"

# --- 4. TUIDEV_VERSION -----------------------------------------------------------
new_home; release 1.0.0; release 1.1.0
out="$(TUIDEV_VERSION=v1.0.0 get --fetch 2>/dev/null)" || fail "pinned fetch"
[[ "$(cat "$out/VERSION")" == 1.0.0 ]] || fail "the pin was not used: $(cat "$out/VERSION")"
out="$(TUIDEV_VERSION='' get --fetch 2>/dev/null)"; [[ "$(cat "$out/VERSION")" == 1.1.0 ]] || fail "empty pin means latest"
for bad in 3.23.0 v3.23 v3.23.0.1 latest 'v3.23.0;x' 'v3.23.0/../x' ' v3.23.0' 'V3.23.0'; do
    new_home
    ERR="$(TUIDEV_VERSION="$bad" get --fetch 2>&1 >/dev/null || true)"
    [[ "$ERR" == *"must look like v3.23.0"* && ! -e "$TUIDEV_HOME" ]] || fail "TUIDEV_VERSION='$bad': $ERR"
done
new_home; ERR="$(TUIDEV_VERSION=v9.9.9 get --fetch 2>&1 >/dev/null || true)"
[[ "$ERR" == *"download failed"* ]] || fail "an unpublished pin: $ERR"
pass "TUIDEV_VERSION: v1.0.0 picks that release, empty means latest, other forms are refused"

# --- 5. keeping the release before, pruning older ones --------------------------
new_home; release 1.0.0; get --fetch >/dev/null 2>&1
release 1.1.0; get --fetch >/dev/null 2>&1
[[ "$(cat "$TUIDEV_HOME/previous")" == 1.0.0 && "$(versions)" == "1.0.0 1.1.0 " ]] || fail "after the second: previous=$(cat "$TUIDEV_HOME/previous") versions=$(versions)"
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "current after the second"
release 1.2.0; get --fetch >/dev/null 2>&1
[[ "$(cat "$TUIDEV_HOME/previous")" == 1.1.0 && "$(versions)" == "1.1.0 1.2.0 " ]] || fail "after the third: previous=$(cat "$TUIDEV_HOME/previous") versions=$(versions)"
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.2.0 ]] || fail "current after the third"
no_leftovers
pass "a newer fetch records previous; the third prunes the oldest and keeps current + previous"

echo marker > "$TUIDEV_HOME/versions/1.2.0/marker"
get --fetch >/dev/null 2>&1
[[ ! -e "$TUIDEV_HOME/versions/1.2.0/marker" && "$(cat "$TUIDEV_HOME/previous")" == 1.1.0 && "$(versions)" == "1.1.0 1.2.0 " ]] \
    || fail "re-fetching the same version: previous=$(cat "$TUIDEV_HOME/previous") versions=$(versions)"
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.2.0 ]] || fail "current after a re-fetch"
no_leftovers
pass "re-fetching the current version replaces it and leaves previous alone"

# An older release published as latest (a rollback of the release) moves current back and records the newer as previous.
release 1.1.0; get --fetch >/dev/null 2>&1
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.2.0 ]] || fail "downgrade: $(readlink "$TUIDEV_HOME/current") prev=$(cat "$TUIDEV_HOME/previous")"
pass "fetching an older release moves current there and keeps the newer as previous"

# --- 6. what install.sh is given ---------------------------------------------------
new_home; release 1.0.0
out="$(printf 'typed into the pipe' | get --yes --profile 'full x' --pack 'a b' '' --dry-run -- '$HOME;*' 2>&1)" || fail "install run: $out"
want='argc=8
[--profile]
[full x]
[--pack]
[a b]
[]
[--dry-run]
[--]
[$HOME;*]
stdin=0'
got="$(grep -v '^from=' "$INSTALL_LOG")"
[[ "$got" == "$want" ]] || fail "install.sh got:
$got
want:
$want"
[[ "$(grep '^from=' "$INSTALL_LOG")" == "from=$(cd "$TUIDEV_HOME/versions/1.0.0" && pwd -P)" ]] || fail "install.sh ran from $(grep '^from=' "$INSTALL_LOG")"
[[ "$out" == *"tuidev 1.0.0 is in"* ]] || fail "no notice before the installer: $out"
pass "install.sh gets every argument verbatim (spaces, empty, --), not --yes, and stdin from /dev/null"

new_home; release 1.0.0
get -y --fetch --yes >/dev/null 2>&1 && [[ ! -e "$INSTALL_LOG" ]] || fail "--fetch with --yes ran install.sh"
get -y >/dev/null 2>&1
[[ "$(grep -c '^\[' "$INSTALL_LOG" || true)" == 0 && "$(sed -n 1p "$INSTALL_LOG")" == argc=0 ]] || fail "-y or --fetch reached install.sh: $(cat "$INSTALL_LOG")"
rc=0; ERR="$(STUB_RC=3 get --yes --profile x 2>&1 >/dev/null)" || rc=$?
[[ "$rc" == 3 ]] || fail "install.sh exit 3 became $rc"
[[ "$ERR" == *"installer stopped (exit 3)"*"not completely installed"* && "$ERR" == *"run it again: $TUIDEV_HOME/current/install.sh --profile x"* ]] \
    || fail "a failed install does not say so, or how to go on: $ERR"
[[ "$ERR" != *"--rollback"* ]] || fail "a first install has nothing to roll back to: $ERR"
# With a release before it, the way back is named too.
release 1.1.0; rc=0; ERR="$(STUB_RC=4 get --yes 2>&1 >/dev/null)" || rc=$?
[[ "$rc" == 4 && "$ERR" == *"Back to 1.0.0: tuidev update --rollback"* && "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] \
    || fail "a failed install over 1.0.0 does not name the rollback: rc=$rc $ERR"
pass "-y/--yes/--fetch are get.sh's own; install.sh's exit status is get.sh's, and a failure says the install is not complete and how to go back or on"

# --- 7. a truncated script runs nothing ---------------------------------------------
new_home; release 1.0.0
lines="$(wc -l < "$GET" | tr -d ' ')"
for (( n = 1; n < lines; n++ )); do
    rm -rf "$TUIDEV_HOME"; rm -f "$INSTALL_LOG"
    head -n "$n" "$GET" | detach "$SH" -s -- --yes >/dev/null 2>&1 || true
    [[ ! -e "$TUIDEV_HOME/current" && ! -e "$INSTALL_LOG" ]] || fail "get.sh cut after line $n of $lines still installed"
done
# Cut mid-line, in the middle of the final call (the only line that starts anything).
for bytes in 5 20 40; do
    rm -rf "$TUIDEV_HOME"; rm -f "$INSTALL_LOG"
    total="$(wc -c < "$GET" | tr -d ' ')"
    head -c "$(( total - bytes ))" "$GET" | detach "$SH" -s -- --yes >/dev/null 2>&1 || true
    [[ ! -e "$TUIDEV_HOME/current" && ! -e "$INSTALL_LOG" ]] || fail "get.sh cut $bytes bytes short still installed"
done
# and the whole script, piped the way curl pipes it, does work
rm -rf "$TUIDEV_HOME"
detach "$SH" -s -- --yes < "$GET" >/dev/null 2>&1 || fail "the whole script, piped, failed"
[[ -L "$TUIDEV_HOME/current" && -e "$INSTALL_LOG" ]] || fail "the piped whole script did not install"
pass "a get.sh cut at any line (or a few bytes short) runs nothing; piped whole, it installs"

# --- 8. no terminal, and the terminal when there is one ------------------------------
have_pty=""
if [[ -n "$HAVE_PERL" ]] && command -v python3 >/dev/null 2>&1 && with_tty "$SH" -c '{ : < /dev/tty; } 2>/dev/null' >/dev/null 2>&1; then have_pty=1; fi

if [[ -z "$HAVE_PERL" ]]; then
    echo "SKIP: no perl to drop the controlling terminal (the no-tty checks)"
else
    new_home; release 1.0.0
    rc=0; ERR="$(get --profile full 2>&1 >/dev/null </dev/null)" || rc=$?
    [[ "$rc" != 0 ]] || fail "without a terminal or --yes, get.sh installed"
    [[ "$ERR" == *"no terminal to ask on"* && "$ERR" == *"bash -s -- --yes --profile full"* \
        && "$ERR" == *"$TUIDEV_HOME/versions/1.0.0/install.sh --profile full --dry-run"* ]] || fail "the refusal does not say how to go on: $ERR"
    [[ ! -e "$INSTALL_LOG" ]] || fail "install.sh ran without a terminal and without --yes"
    [[ -d "$TUIDEV_HOME/versions/1.0.0" && ! -e "$TUIDEV_HOME/current" ]] || fail "the release is unpacked, but current must not be set by a refusal"
    no_leftovers
    pass "no terminal and no --yes: refuses, says --yes and --dry-run with the versions/ path; the release is unpacked, current is not set"

    # An install that exists is left exactly as it was.
    new_home; release 1.0.0; get --fetch >/dev/null 2>&1; release 1.1.0; get --fetch >/dev/null 2>&1; release 1.2.0
    # now current=1.1.0, previous=1.0.0
    refused
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.0.0 ]] || fail "a refused install moved current/previous: $(readlink "$TUIDEV_HOME/current") $(cat "$TUIDEV_HOME/previous")"
    [[ -d "$TUIDEV_HOME/versions/1.0.0" && -d "$TUIDEV_HOME/versions/1.1.0" && -d "$TUIDEV_HOME/versions/1.2.0" ]] || fail "versions after a refusal: $(versions)"
    pass "a refusal for lack of a terminal leaves an existing current and previous (and every version) as they were"
fi
if [[ -z "$have_pty" ]]; then
    echo "SKIP: no python3 pty to give get.sh a terminal (the --yes, n, p checks)"
else
    new_home; release 1.0.0
    with_tty "$SH" "$GET" --yes --profile x >/dev/null 2>&1 || fail "--yes with a terminal failed"
    [[ "$(grep '^stdin=' "$INSTALL_LOG")" == stdin=tty && "$(sed -n 2p "$INSTALL_LOG")" == "[--profile]" ]] || fail "with --yes and a terminal, install.sh did not get /dev/tty: $(cat "$INSTALL_LOG")"
    pass "--yes with a terminal: install.sh reads /dev/tty"

    # Answering n: nothing runs, current and previous stay.
    new_home; release 1.0.0; get --fetch >/dev/null 2>&1; release 1.1.0
    rc=0; TTY_INPUT=$'n\n' with_tty "$SH" "$GET" --profile x >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 0 && ! -e "$INSTALL_LOG" ]] || fail "answering n: rc=$rc, install ran: $(cat "$INSTALL_LOG" 2>&1)"
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 && ! -e "$TUIDEV_HOME/previous" && -d "$TUIDEV_HOME/versions/1.1.0" ]] || fail "answering n moved current: $(readlink "$TUIDEV_HOME/current")"
    no_leftovers
    # p previews from versions/X.Y.Z with --dry-run and still leaves current alone; then n.
    TTY_INPUT=$'p\nn\n' with_tty "$SH" "$GET" --profile x >/dev/null 2>&1 || fail "preview then n failed"
    [[ "$(sed -n '2,3p' "$INSTALL_LOG" | tr '\n' ' ')" == "[--profile] [x] " && "$(grep -c '^\[--dry-run\]' "$INSTALL_LOG")" == 1 ]] || fail "the preview did not run --dry-run: $(cat "$INSTALL_LOG")"
    [[ "$(grep '^from=' "$INSTALL_LOG")" == "from=$(cd "$TUIDEV_HOME/versions/1.1.0" && pwd -P)" ]] || fail "the preview ran from $(grep '^from=' "$INSTALL_LOG")"
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 ]] || fail "a preview moved current"
    # y: current moves, previous is recorded, the installer runs from it.
    rm -f "$INSTALL_LOG"
    TTY_INPUT=$'y\n' with_tty "$SH" "$GET" --profile x >/dev/null 2>&1 || fail "answering y failed"
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.0.0 ]] || fail "answering y: $(readlink "$TUIDEV_HOME/current")"
    [[ "$(grep -c '^\[--dry-run\]' "$INSTALL_LOG")" == 0 && "$(grep '^stdin=' "$INSTALL_LOG")" == stdin=tty ]] || fail "the install after y: $(cat "$INSTALL_LOG")"
    pass "with a terminal: n and p leave current and previous alone; y moves them and installs"
fi

# --- 9. archives with a symlink, and what unpacking is allowed to do --------------------
new_home; release 1.0.0; tree 1.0.0; ln -s /etc "$tmp/build/tuidev-1.0.0/link"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0
refused --fetch; [[ "$ERR" == *"holds a symlink"* && ! -e "$TUIDEV_HOME/current" ]] || fail "symlink inside: $ERR"
no_leftovers
rm -f "$tmp/build/tuidev-1.0.0/link"
new_home; tree 1.0.0; mkdir -p "$tmp/sl"; rm -rf "$tmp/sl/real"; mv "$tmp/build/tuidev-1.0.0" "$tmp/sl/real"
ln -s real "$tmp/sl/tuidev-1.0.0"
pack "$REL/latest/download" "$tmp/sl" tuidev-1.0.0
refused --fetch; [[ "$ERR" == *"holds a symlink"* && ! -e "$TUIDEV_HOME/current" && -z "$(versions)" ]] || fail "the top directory as a symlink: $ERR"
no_leftovers
rm -rf "$tmp/sl"
new_home; tree 1.0.0; echo x > "$tmp/build/tuidev-1.0.0/orig"; ln "$tmp/build/tuidev-1.0.0/orig" "$tmp/build/tuidev-1.0.0/twin"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0
refused --fetch; [[ "$ERR" == *"hard link"* && ! -e "$TUIDEV_HOME/current" && -z "$(versions)" ]] || fail "a hard link inside: $ERR"
no_leftovers
rm -f "$tmp/build/tuidev-1.0.0/orig" "$tmp/build/tuidev-1.0.0/twin"
pass "an archive with any symlink, the top directory included, or a hard link is refused"

# -xzof: the archive does not name the owner of what it unpacks.
mkdir -p "$tmp/stubs"; REAL_TAR="$(command -v tar)"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/tar.calls"\nexec "%s" "$@"\n' "$tmp" "$REAL_TAR" > "$tmp/stubs/tar"; chmod +x "$tmp/stubs/tar"
new_home; release 1.0.0; rm -f "$tmp/tar.calls"
PATH="$tmp/stubs:$PATH" get --fetch >/dev/null 2>&1 || fail "fetch with a tar stub"
grep -q -- '^-xzof ' "$tmp/tar.calls" || fail "tar was not run with -xzof: $(cat "$tmp/tar.calls")"
pass "extraction runs tar -xzof (no owner from the archive)"

# TUIDEV_HOME/versions as a symlink: nothing is written through it.
new_home; release 1.0.0; mkdir -p "$TUIDEV_HOME" "$tmp/elsewhere"; ln -s "$tmp/elsewhere" "$TUIDEV_HOME/versions"
refused --fetch; [[ "$ERR" == *"versions is a symlink"* ]] || fail "versions symlink: $ERR"
[[ -z "$(ls -A "$tmp/elsewhere")" && ! -e "$TUIDEV_HOME/current" ]] || fail "something was written through the versions symlink: $(ls -A "$tmp/elsewhere")"
no_leftovers
rm -rf "$tmp/elsewhere"
pass "a versions/ that is a symlink is refused before anything is written"

# Pruning removes only versions-named directories.
new_home; release 1.0.0; get --fetch >/dev/null 2>&1
mkdir -p "$TUIDEV_HOME/versions/my-notes" "$TUIDEV_HOME/versions/1.0" "$TUIDEV_HOME/versions/v1.0.0" "$tmp/linked"
echo keep > "$TUIDEV_HOME/versions/my-notes/n"; echo keep > "$tmp/linked/n"; ln -s "$tmp/linked" "$TUIDEV_HOME/versions/0.9.0"
release 1.1.0; get --fetch >/dev/null 2>&1; release 1.2.0; get --fetch >/dev/null 2>&1
[[ ! -e "$TUIDEV_HOME/versions/1.0.0" ]] || fail "an old version was not pruned"
[[ -f "$TUIDEV_HOME/versions/my-notes/n" && -d "$TUIDEV_HOME/versions/1.0" && -d "$TUIDEV_HOME/versions/v1.0.0" ]] || fail "pruning removed a directory that is not a version: $(versions)"
[[ -L "$TUIDEV_HOME/versions/0.9.0" && -f "$tmp/linked/n" ]] || fail "pruning removed or followed a symlink named like a version"
[[ -d "$TUIDEV_HOME/versions/1.1.0" && -d "$TUIDEV_HOME/versions/1.2.0" ]] || fail "current and previous were pruned: $(versions)"
rm -rf "$tmp/linked"
pass "pruning removes only X.Y.Z directories: my-notes/, 1.0/, v1.0.0/ and a symlink named 0.9.0 survive"

# An empty or newline-less previous does not end the run after current moved.
new_home; release 1.0.0; get --fetch >/dev/null 2>&1; release 1.1.0; get --fetch >/dev/null 2>&1
: > "$TUIDEV_HOME/previous"
get --fetch >/dev/null 2>&1 || fail "an empty previous file made get.sh fail"
[[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "current after an empty previous"
printf '1.0.0' > "$TUIDEV_HOME/previous"
mkdir -p "$TUIDEV_HOME/versions/1.0.0"
get --fetch >/dev/null 2>&1 || fail "a previous file without a newline made get.sh fail"
[[ -d "$TUIDEV_HOME/versions/1.0.0" && "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "a newline-less previous was not honoured: $(versions)"
no_leftovers
pass "an empty or newline-less previous file is not an error"

# A failed move puts the old tree of that version back.
new_home; release 1.1.0; get --fetch >/dev/null 2>&1; echo old > "$TUIDEV_HOME/versions/1.1.0/marker"
REAL_MV="$(command -v mv)"
cat > "$tmp/stubs/mv" <<EOF
#!/bin/bash
for last; do :; done
if [[ "\$last" == */versions/1.1.0 && "\$1" == */x/tuidev-1.1.0 ]]; then exit 1; fi
exec "$REAL_MV" "\$@"
EOF
chmod +x "$tmp/stubs/mv"
rc=0; ERR="$(PATH="$tmp/stubs:$PATH" get --fetch 2>&1 >/dev/null)" || rc=$?
[[ "$rc" != 0 && "$ERR" == *"could not put the release"* ]] || fail "a failed move: rc=$rc $ERR"
[[ "$(cat "$TUIDEV_HOME/versions/1.1.0/marker" 2>/dev/null)" == old && "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 ]] || fail "the old tree was not put back"
no_leftovers
rm -f "$tmp/stubs/mv"
pass "when the new tree cannot be moved in, the old tree of that version is put back"

# A re-fetch of the same version stopped between its two moves (a SIGTERM
# here): the old tree goes back, so current never points at nothing.
new_home; release 1.1.0; get --fetch >/dev/null 2>&1; echo old > "$TUIDEV_HOME/versions/1.1.0/marker"
cat > "$tmp/stubs/mv" <<EOF
#!/bin/bash
for last; do :; done
if [[ "\$last" == */versions/1.1.0 && "\$1" == */x/tuidev-1.1.0 ]]; then kill -TERM "\$PPID"; sleep 1; exit 1; fi
exec "$REAL_MV" "\$@"
EOF
chmod +x "$tmp/stubs/mv"
rc=0; PATH="$tmp/stubs:$PATH" get --fetch >/dev/null 2>&1 || rc=$?
[[ "$rc" == 143 ]] || fail "an interrupted re-fetch exited $rc, not 143"
[[ "$(cat "$TUIDEV_HOME/versions/1.1.0/marker" 2>/dev/null)" == old && -f "$TUIDEV_HOME/current/VERSION" ]] || fail "an interrupted re-fetch left current dangling: $(versions)"
no_leftovers
rm -f "$tmp/stubs/mv"
pass "a re-fetch interrupted between moving the old tree out and the new one in puts the old one back"

# current moves in one rename (ln -s to a temp name, then mv onto the link),
# never ln -sfn, which unlinks it first; with BSD's mv and with GNU's.
cat > "$tmp/stubs/ln" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$tmp/ln.calls"
exec "$(command -v ln)" "\$@"
EOF
chmod +x "$tmp/stubs/ln"
GNU_MV="$(command -v gmv || true)"; [[ -n "$GNU_MV" || "$(mv --version 2>/dev/null)" != *GNU* ]] || GNU_MV="$REAL_MV"
for gnu in "" 1; do
    if [[ -n "$gnu" ]]; then
        [[ -n "$GNU_MV" ]] || { echo "SKIP: no GNU mv here to flip current with"; continue; }
        printf '#!/bin/bash\nexec "%s" "$@"\n' "$GNU_MV" > "$tmp/stubs/mv"; chmod +x "$tmp/stubs/mv"
    fi
    new_home; release 1.0.0; get --fetch >/dev/null 2>&1; release 1.1.0; rm -f "$tmp/ln.calls"
    PATH="$tmp/stubs:$PATH" get --fetch >/dev/null 2>&1 || fail "fetch with an ln stub (gnu=$gnu)"
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.1.0 && "$(cat "$TUIDEV_HOME/previous")" == 1.0.0 ]] || fail "flip (gnu=$gnu): $(readlink "$TUIDEV_HOME/current")"
    [[ "$(cat "$tmp/ln.calls")" == "-s versions/1.1.0 $TUIDEV_HOME/.current."* ]] || fail "current was not made beside and renamed (gnu=$gnu): $(cat "$tmp/ln.calls")"
    [[ -z "$(find "$TUIDEV_HOME" -name '.current.*')" && -z "$(find "$TUIDEV_HOME/versions" -type l)" ]] || fail "the temp link stayed, or went into a version (gnu=$gnu)"
    rm -f "$tmp/stubs/mv"
done
rm -f "$tmp/stubs/ln" "$tmp/ln.calls"
# A current that is a real directory (someone's clone) is never replaced or written into.
new_home; release 1.0.0; mkdir -p "$TUIDEV_HOME/current"; echo mine > "$TUIDEV_HOME/current/f"
refused --fetch
[[ "$ERR" == *"current is not a symlink"* && "$(ls -A "$TUIDEV_HOME/current")" == f ]] || fail "a current directory: $ERR / $(ls -A "$TUIDEV_HOME/current")"
pass "current is flipped with one rename (BSD and GNU mv), never ln -sfn; a current that is a directory is refused"

# A single quote in TUIDEV_HOME: the exit trap still cleans up, no syntax error.
new_home; release 1.0.0
export TUIDEV_HOME="$tmp/it's here"; rm -rf "$TUIDEV_HOME"
out="$(get --fetch 2>&1)" || fail "TUIDEV_HOME with a quote: $out"
[[ "$out" != *"syntax error"* && "$out" != *"unexpected"* ]] || fail "quote in TUIDEV_HOME: $out"
no_leftovers
printf '%s  tuidev.tar.gz\n' "$(printf 'x' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)" > "$REL/latest/download/tuidev.tar.gz.sha256"
rm -rf "$TUIDEV_HOME"; refused --fetch
[[ "$ERR" == *"checksum mismatch"* && "$ERR" != *"syntax error"* ]] || fail "a refusal with a quote in TUIDEV_HOME: $ERR"
no_leftovers
rm -rf "$tmp/it's here"
pass "a single quote in TUIDEV_HOME: the exit trap leaves no .get.* directory, on success or refusal"

# curl: no ~/.curlrc (-q), and https stays https through redirects.
new_home; release 1.0.0
cat > "$tmp/stubs/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CURL_LOG"
out="" url=""
while [[ $# -gt 0 ]]; do
    case "$1" in -o) out="$2"; shift ;; https://*) url="$1" ;; esac
    shift
done
cp "$FIXTURES/${url#https://example.invalid/releases/}" "$out"
EOF
chmod +x "$tmp/stubs/curl"
export CURL_LOG="$tmp/curl.log" FIXTURES="$REL"; rm -f "$CURL_LOG"
PATH="$tmp/stubs:$PATH" TUIDEV_RELEASE_URL=https://example.invalid/releases get --fetch >/dev/null 2>&1 || fail "fetch through a curl stub"
[[ "$(wc -l < "$CURL_LOG" | tr -d ' ')" == 2 ]] || fail "curl calls: $(cat "$CURL_LOG")"
while IFS= read -r line; do
    [[ "$line" == "-q "* && "$line" == *"--proto =https --proto-redir =https"* ]] || fail "https curl call: $line"
    [[ "$line" == *"--max-time 300 "* && "$line" == *"--max-filesize 67108864 "* ]] || fail "a download without a time or size limit: $line"
done < "$CURL_LOG"
pass "curl runs with -q, --max-time and --max-filesize and, for an https release URL, --proto =https --proto-redir =https"

# The layout check escapes dots: tuidev-1x0x0/ is not tuidev-1.0.0/.
new_home; tree 1.0.0; mkdir -p "$tmp/build/tuidev-1x0x0"; echo x > "$tmp/build/tuidev-1x0x0/f"
pack "$REL/latest/download" "$tmp/build" tuidev-1.0.0 tuidev-1x0x0
refused --fetch; [[ "$ERR" == *"outside tuidev-1.0.0"* && ! -e "$TUIDEV_HOME/current" ]] || fail "a look-alike directory: $ERR"
no_leftovers
rm -rf "$tmp/build/tuidev-1x0x0"
pass "a tuidev-1x0x0/ entry beside tuidev-1.0.0/ is refused (dots are escaped)"

# --- 10. the first-run question -------------------------------------------------------
# With no arguments, no --yes and a terminal, get.sh runs `install.sh --choose`
# on that terminal and uses what it prints as the installer's arguments.
if [[ -z "$have_pty" ]]; then
    echo "SKIP: no python3 pty to give get.sh a terminal (the first-run question checks)"
else
    # An answer picks the arguments; the usual question follows; y installs with them.
    new_home; release 1.0.0
    TTY_INPUT=$'2\ny\n' with_tty "$SH" "$GET" >/dev/null 2>&1 || fail "chooser answer 2, then y failed"
    [[ "$(grep -c '' "$CHOOSE_LOG")" == 1 && "$(cat "$CHOOSE_LOG")" == asked-on-tty ]] || fail "the chooser was not run once on the terminal: $(cat "$CHOOSE_LOG" 2>&1)"
    [[ "$(sed -n '1,5p' "$INSTALL_LOG" | tr '\n' ' ')" == "argc=4 [--profile] [desktop] [--pack] [ai-clis] " ]] \
        || fail "answer 2 did not become --profile desktop --pack ai-clis: $(cat "$INSTALL_LOG")"
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 ]] || fail "current after the chosen install"
    pass "no arguments on a terminal: the chooser's answer 2 reaches install.sh as --profile desktop --pack ai-clis"

    for pick in "1|--profile|full" "3|--profile|remote" "4|--profile|minimal"; do
        IFS='|' read -r n flag val <<< "$pick"
        new_home; release 1.0.0
        TTY_INPUT="$n"$'\ny\n' with_tty "$SH" "$GET" >/dev/null 2>&1 || fail "chooser answer $n failed"
        [[ "$(sed -n 2p "$INSTALL_LOG")" == "[$flag]" && "$(sed -n 3p "$INSTALL_LOG")" == "[$val]" ]] || fail "answer $n: $(cat "$INSTALL_LOG")"
    done
    pass "answers 1, 3 and 4 give --profile full, remote and minimal"

    # Preview then no: the chosen arguments are what the preview ran with; nothing is installed.
    new_home; release 1.0.0
    TTY_INPUT=$'4\np\nn\n' with_tty "$SH" "$GET" >/dev/null 2>&1 || fail "chooser, preview, n"
    [[ "$(grep -c '^\[--dry-run\]' "$INSTALL_LOG")" == 1 && "$(sed -n 3p "$INSTALL_LOG")" == "[minimal]" && ! -e "$TUIDEV_HOME/current" ]] \
        || fail "preview after the chooser: $(cat "$INSTALL_LOG"); current: $(readlink "$TUIDEV_HOME/current" 2>&1)"
    pass "the preview runs with the chosen arguments and leaves current alone"

    # q: nothing is installed and an existing current is as it was.
    new_home; release 1.0.0; get --fetch >/dev/null 2>&1; release 1.1.0
    rc=0; out="$(TTY_INPUT=$'q\n' with_tty "$SH" "$GET" 2>&1)" || rc=$?
    [[ "$rc" == 0 && ! -e "$INSTALL_LOG" ]] || fail "q: rc=$rc, install ran: $(cat "$INSTALL_LOG" 2>&1)"
    [[ "$out" == *"nothing installed"* ]] || fail "q says nothing: $out"
    [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 && ! -e "$TUIDEV_HOME/previous" ]] || fail "q moved current: $(readlink "$TUIDEV_HOME/current")"
    no_leftovers
    # EOF on the terminal is a quit as well, not an install.
    rc=0; TTY_INPUT='' TTY_EOF=1 with_tty "$SH" "$GET" >/dev/null 2>&1 || rc=$?
    [[ ! -e "$INSTALL_LOG" && "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 ]] || fail "EOF at the question installed or moved current"
    # Garbage is a quit too.
    TTY_INPUT=$'seven\n' with_tty "$SH" "$GET" >/dev/null 2>&1 || true
    [[ ! -e "$INSTALL_LOG" && "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 ]] || fail "garbage at the question installed or moved current"
    pass "quitting the question (q, EOF, garbage) installs nothing and leaves current and previous alone"

    # An installer that answers with something that is not flags is refused.
    new_home; release 1.0.0; get --fetch >/dev/null 2>&1; release 1.1.0
    hostile=(
        '--profile full; rm -rf x'
        '--profile full && id'
        '--profile $(id)'
        '--profile `id`'
        '--profile full | cat'
        '--profile "full"'
        '--profile full --dry-run=x'
        'profile full'
        '-x'
        '--Profile full'
        ' --profile full'
        '--profile full '
        '--profile  full'
        $'--profile full\nrm -rf x'
        $'--profile full\n--pack tmux'
        $'\n--profile full'
        '--profile ../x'
        '--profile 1'
    )
    for h in "${hostile[@]}"; do
        rm -f "$INSTALL_LOG"
        rc=0; out="$(CHOOSE_SAYS="$h" TTY_INPUT=$'y\n' with_tty "$SH" "$GET" 2>&1)" || rc=$?
        [[ "$rc" != 0 && "$out" == *"unexpected answer from the installer"* ]] || fail "a hostile answer '$h' was not refused (rc=$rc): $out"
        [[ ! -e "$INSTALL_LOG" ]] || fail "a hostile answer '$h' reached install.sh: $(cat "$INSTALL_LOG")"
        [[ "$(readlink "$TUIDEV_HOME/current")" == versions/1.0.0 && ! -e "$TUIDEV_HOME/previous" ]] || fail "a hostile answer '$h' moved current"
    done
    no_leftovers
    pass "an answer that is not a few --lowercase words is refused: nothing runs, current stays"

    # And the shapes it does take are used as they are.
    new_home; release 1.0.0
    CHOOSE_SAYS='--profile desktop --pack ai-clis' TTY_INPUT=$'y\n' with_tty "$SH" "$GET" >/dev/null 2>&1 || fail "a well-formed answer"
    [[ "$(grep -c '^\[' "$INSTALL_LOG")" == 4 ]] || fail "word splitting of the answer: $(cat "$INSTALL_LOG")"
    pass "a well-formed answer is split into its four words"

    # --yes with no arguments never asks, terminal or not.
    new_home; release 1.0.0
    with_tty "$SH" "$GET" --yes >/dev/null 2>&1 || fail "--yes with no arguments on a terminal"
    [[ ! -e "$CHOOSE_LOG" && "$(sed -n 1p "$INSTALL_LOG")" == argc=0 && "$(grep '^stdin=' "$INSTALL_LOG")" == stdin=0 ]] \
        || fail "--yes with no arguments asked or gave the installer a terminal: choose=$(cat "$CHOOSE_LOG" 2>&1) install=$(cat "$INSTALL_LOG")"
    # Arguments given: no question either.
    new_home; release 1.0.0
    TTY_INPUT=$'y\n' with_tty "$SH" "$GET" --profile minimal >/dev/null 2>&1 || fail "arguments on a terminal"
    [[ ! -e "$CHOOSE_LOG" && "$(sed -n 3p "$INSTALL_LOG")" == "[minimal]" ]] || fail "arguments given, yet the chooser ran: $(cat "$CHOOSE_LOG" 2>&1)"
    new_home; release 1.0.0
    TTY_INPUT=$'y\n' with_tty "$SH" "$GET" --dry-run >/dev/null 2>&1 || fail "--dry-run on a terminal"
    [[ ! -e "$CHOOSE_LOG" ]] || fail "any installer argument counts as a choice already made"
    # --fetch never asks.
    new_home; release 1.0.0
    with_tty "$SH" "$GET" --fetch >/dev/null 2>&1 || fail "--fetch on a terminal"
    [[ ! -e "$CHOOSE_LOG" && ! -e "$INSTALL_LOG" ]] || fail "--fetch asked or installed"
    pass "--yes, any installer argument and --fetch never run the chooser"
fi
if [[ -n "$HAVE_PERL" ]]; then
    new_home; release 1.0.0
    refused </dev/null
    [[ ! -e "$CHOOSE_LOG" && ! -e "$INSTALL_LOG" && ! -e "$TUIDEV_HOME/current" ]] || fail "no terminal: the chooser ran or something installed"
    new_home; release 1.0.0
    get --yes </dev/null >/dev/null 2>&1 || fail "--yes without a terminal"
    [[ ! -e "$CHOOSE_LOG" && "$(sed -n 1p "$INSTALL_LOG")" == argc=0 ]] || fail "--yes without a terminal asked"
    pass "no terminal: no question; refused without --yes, plain with it"
fi

echo ""
echo "All get.sh tests passed."
