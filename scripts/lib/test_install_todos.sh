#!/bin/bash
# Tests for the end-of-install follow-ups: print_todo / print_todos (collected,
# de-duplicated, numbered, silent when empty), the warning counter, and that
# install.sh lists the todos of the packs it ran and the warning total.
# Run: bash scripts/lib/test_install_todos.sh  -> exit 0 on pass (also under /bin/bash).
#
# shellcheck disable=SC2015,SC2016  # `a && b || fail` checks

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-todos.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home"
mkdir -p "$HOME"
unset TUIDEV_STATE_DIR TUIDEV_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CONFIG_HOME

# --- 1. the lib: empty, numbering, de-duplication, the counter ---------------------
# shellcheck source=scripts/lib/ui.sh disable=SC1091
. "$REPO_DIR/scripts/lib/ui.sh"
strip() { sed $'s/\033\\[[0-9;]*m//g'; }

[[ -z "$(print_todos)" ]] || fail "an empty list printed something"
pass "an empty list prints nothing"

print_todo "first step: run one"
print_todo "second step: run two"
print_todo "first step: run one"
print_todo ""
out="$(print_todos | strip)"
[[ "$(printf '%s\n' "$out" | grep -c '^  [0-9]\. ')" == 2 ]] || fail "expected 2 steps, got: $out"
printf '%s\n' "$out" | grep -qx '  1\. first step: run one'   || fail "step 1 missing: $out"
printf '%s\n' "$out" | grep -qx '  2\. second step: run two'  || fail "step 2 missing: $out"
printf '%s\n' "$out" | head -1 | grep -q 'To do by hand' || fail "no heading: $out"
pass "numbered, de-duplicated, empty lines skipped"

print_todo "first step: run on"   # a prefix of another line is not a duplicate
[[ "$(print_todos | strip | grep -c '^  [0-9]\. ')" == 3 ]] || fail "a near-duplicate was dropped"
pass "a near-duplicate line is kept"

DRY_RUN=true
print_todos | strip | head -1 | grep -q 'dry run' || fail "dry-run heading not worded as would-be"
DRY_RUN=false
pass "dry-run wording"

before="$TUIDEV_WARNINGS"
print_warning "one" > "$tmp/w1"
print_warning "two" > "$tmp/w2"
[[ "$TUIDEV_WARNINGS" == $((before + 2)) ]] || fail "warning counter is $TUIDEV_WARNINGS, expected $((before + 2))"
[[ "$(strip < "$tmp/w1")" == "⚠ one" ]] || fail "print_warning output changed: $(cat "$tmp/w1")"
pass "warnings are counted and print as before"

# --- 2. install.sh: the end of a dry run -------------------------------------------
tail_of() {  # tail_of ARGS... -> the text after "Installation Complete"
    "$SH" "$INSTALL" "$@" --dry-run < /dev/null 2>&1 | strip | sed -n '/Installation Complete/,$p'
}

min="$(tail_of --profile minimal)"
printf '%s\n' "$min" | grep -q 'Restart your shell' || fail "minimal: the always-steps are gone"
printf '%s\n' "$min" | grep -qE '^  - Agents, sandboxed: +tuidev install --pack ai-clis' \
    || fail "minimal: the ai-clis offer is missing: $min"
printf '%s\n' "$min" | grep -qE '^ +[0-9]+\. .*--pack ai-clis' && fail "minimal: the ai-clis offer is a numbered step: $min"
pass "minimal dry run offers ai-clis, outside the numbered steps"

with="$(tail_of --profile minimal --pack ai-clis)"
printf '%s\n' "$with" | grep -q 'tuidev install --pack ai-clis' && fail "ai-clis installed, but still asked for: $with"
pass "a run that installs ai-clis does not ask for it"

if [[ "$(uname)" == Darwin ]]; then
    full="$(tail_of --profile full)"
    printf '%s\n' "$full" | grep -q 'Open SwiftBar once' || fail "full: the SwiftBar step is missing: $full"
    [[ "$full" != "$min" ]] || fail "minimal and full ended with the same text"
    pass "full lists the steps of its packs, not minimal's"
fi

# The warnings line appears only with warnings, and names the way to find them.
for p in minimal full; do
    out="$(tail_of --profile "$p")"
    n="$(printf '%s\n' "$out" | sed -n 's/^ℹ \([0-9][0-9]*\) warnings\{0,1\} above: scroll up, or run `tuidev check`$/\1/p')"
    if [[ -n "$n" ]]; then
        [[ "$n" -gt 0 ]] || fail "$p: warning line with a zero count"
    fi
done
pass "the warning line, when shown, has a count above zero"

echo "all install todo tests passed"
