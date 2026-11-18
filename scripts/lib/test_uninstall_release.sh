#!/bin/bash
# uninstall.sh and the no-git install: it removes the update-check cache and
# the releases get.sh unpacked (even when it runs from one of them), keeps a
# clone that is not tuidev's to delete, and --dry-run removes nothing.
# Run: bash scripts/lib/test_uninstall_release.sh  -> exit 0 on pass (also /bin/bash).
#
# A throwaway HOME and a stub brew; the real HOME is never touched.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-unrel.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

for v in XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_DATA_HOME TUIDEV_REPO TUIDEV_HOME; do unset "$v"; done
export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/home/.config/tuidev" TUIDEV_NO_COLOR=1 NO_COLOR=1
export TUIDEV_HOME="$HOME/.local/share/tuidev"
mkdir -p "$HOME" "$tmp/stub"
printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/brew"; chmod +x "$tmp/stub/brew"   # no manifest: uninstall probes brew
export PATH="$tmp/stub:/usr/bin:/bin"

# A release as get.sh leaves it, with the real uninstall.sh and its libs in it.
tree="$tmp/tuidev-9.9.9"
mkdir -p "$tree"
cp -R "$REPO_DIR/scripts" "$REPO_DIR/lib" "$REPO_DIR/configs" "$REPO_DIR/bin" "$REPO_DIR/templates" \
      "$REPO_DIR/install.sh" "$REPO_DIR/uninstall.sh" "$REPO_DIR/get.sh" "$tree/"
echo 9.9.9 > "$tree/VERSION"

setup() {
    rm -rf "$HOME"; mkdir -p "$HOME/.cache/tuidev" "$HOME/.local/bin" "$TUIDEV_HOME/versions"
    cp -R "$tree" "$TUIDEV_HOME/versions/9.9.9"; cp -R "$tree" "$TUIDEV_HOME/versions/9.9.8"
    ln -s versions/9.9.9 "$TUIDEV_HOME/current"; echo 9.9.8 > "$TUIDEV_HOME/previous"
    echo "9.9.9 1 1" > "$HOME/.cache/tuidev/latest"; echo 9.9.9 > "$HOME/.cache/tuidev/notified"; mkdir "$HOME/.cache/tuidev/notified.9.9.9"; echo keep > "$HOME/.cache/tuidev/other"
    echo "9.9.9 1 1" > "$HOME/.cache/tuidev/latest.12345"; mkdir -p "$HOME/.cache/tuidev/lock"; echo 1 > "$HOME/.cache/tuidev/lock/at"
    cp "$tree/bin/tuidev" "$HOME/.local/bin/tuidev"; chmod +x "$HOME/.local/bin/tuidev"
}

# 1. --dry-run changes nothing.
setup
bash "$TUIDEV_HOME/current/uninstall.sh" --all --dry-run </dev/null > "$tmp/log" 2>&1 || fail "--dry-run: $(tail -8 "$tmp/log")"
[[ -d "$TUIDEV_HOME/versions/9.9.9" && -L "$TUIDEV_HOME/current" && -e "$HOME/.cache/tuidev/latest" && -e "$HOME/.local/bin/tuidev" ]] || fail "--dry-run removed something"
pass "--dry-run removes nothing"

# 2. From inside the release being removed.
setup
bash "$TUIDEV_HOME/current/uninstall.sh" --all </dev/null > "$tmp/log" 2>&1 || fail "uninstall: $(tail -8 "$tmp/log")"
[[ ! -e "$HOME/.cache/tuidev/latest" && ! -e "$HOME/.cache/tuidev/notified" && ! -e "$HOME/.cache/tuidev/notified.9.9.9" ]] || fail "the update-check cache stayed"
[[ "$(cat "$HOME/.cache/tuidev/other")" == keep ]] || fail "a file that is not tuidev's was removed"
[[ ! -e "$HOME/.cache/tuidev/latest.12345" && ! -e "$HOME/.cache/tuidev/lock" ]] || fail "a half-written latest.N or the check lock stayed: $(ls -A "$HOME/.cache/tuidev")"
[[ ! -e "$TUIDEV_HOME" ]] || fail "the unpacked releases stayed: $(ls -A "$TUIDEV_HOME")"
[[ ! -e "$HOME/.local/bin/tuidev" ]] || fail "$HOME/.local/bin/tuidev stayed"
grep -q "removed the tuidev releases" "$tmp/log" || fail "no note about the releases: $(tail -8 "$tmp/log")"
pass "uninstall from inside a release removes the cache, the releases and the command, nothing else"

# 2b. Nothing else in the cache directory: the directory goes too.
setup; rm -f "$HOME/.cache/tuidev/other"
bash "$TUIDEV_HOME/current/uninstall.sh" --all </dev/null > "$tmp/log" 2>&1 || fail "uninstall: $(tail -8 "$tmp/log")"
[[ ! -e "$HOME/.cache/tuidev" ]] || fail "an empty ~/.cache/tuidev stayed: $(ls -A "$HOME/.cache/tuidev")"
pass "uninstall also removes latest.N, the check lock and an emptied ~/.cache/tuidev (a directory with other files stays)"

# 2c. The home is the one the release lives in, not what TUIDEV_HOME says now
# (unset, or another); run through current/ or through versions/X.Y.Z.
for via in current versions/9.9.9; do
    setup; rm -rf "$TUIDEV_HOME"; elsewhere="$tmp/elsewhere"; rm -rf "$elsewhere"; mkdir -p "$elsewhere/versions"
    cp -R "$tree" "$elsewhere/versions/9.9.9"; ln -s versions/9.9.9 "$elsewhere/current"
    mkdir -p "$TUIDEV_HOME/versions"; echo other > "$TUIDEV_HOME/versions/mine"; ln -s versions/mine "$TUIDEV_HOME/current"
    (unset TUIDEV_HOME; bash "$elsewhere/$via/uninstall.sh" --all </dev/null > "$tmp/log" 2>&1) || fail "uninstall via $via: $(tail -8 "$tmp/log")"
    [[ ! -e "$elsewhere" ]] || fail "via $via: the home the release lives in stayed: $(ls -A "$elsewhere")"
    [[ -e "$TUIDEV_HOME/versions/mine" ]] || fail "via $via: another home was removed"
done
rm -rf "$TUIDEV_HOME" "$tmp/elsewhere"
pass "uninstall removes the releases of the home it runs from, through current/ or versions/X.Y.Z"

# 3. A clone is the user's: current that is not a symlink to versions/ stays.
setup; rm -rf "$TUIDEV_HOME"; mkdir -p "$TUIDEV_HOME"; cp -R "$tree" "$TUIDEV_HOME/current"; mkdir "$TUIDEV_HOME/current/.git"
bash "$TUIDEV_HOME/current/uninstall.sh" --all </dev/null > "$tmp/log" 2>&1 || fail "uninstall with a clone: $(tail -8 "$tmp/log")"
[[ -d "$TUIDEV_HOME/current/.git" ]] || fail "a plain directory named current was deleted"
[[ ! -e "$HOME/.cache/tuidev/latest" ]] || fail "the cache stayed with a clone"
pass "a git clone (current not a symlink) is left alone; the cache still goes"

echo ""
echo "All uninstall release tests passed."
