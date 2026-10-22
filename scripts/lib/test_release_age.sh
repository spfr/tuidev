#!/bin/bash
# Tests for --pack release-age: one managed block per package manager on
# PATH, a setting of the user's own left alone, the uv fragment with the age
# filled in, and a re-run that changes nothing. npm, pnpm, bun and uv are
# stubs; the real HOME is never touched.
# Run: bash scripts/lib/test_release_age.sh  -> exit 0 on pass.
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK="$LIB_DIR/../install/packs/release-age.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/state" TUIDEV_NO_COLOR=1 XDG_CONFIG_HOME="$tmp/home/.config"
mkdir -p "$HOME" "$TUIDEV_STATE_DIR" "$tmp/bin"
for t in npm pnpm bun uv; do printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/$t"; chmod +x "$tmp/bin/$t"; done
run_pack() { PATH="$tmp/bin:/usr/bin:/bin" bash "$PACK" < /dev/null 2>&1; }

# The user already set an age for npm, and has bun's [install] table.
printf '//registry.npmjs.org/:_authToken=SECRET\nmin-release-age=7\n' > "$HOME/.npmrc"
printf '[install]\nexact = true\n' > "$HOME/.bunfig.toml"

out="$(run_pack)" || fail "pack exited non-zero: $out"
[[ "$(grep -c tuidev "$HOME/.npmrc" || true)" == 0 ]] || fail "wrote over the user's npm age: $(cat "$HOME/.npmrc")"
grep -q '_authToken=SECRET' "$HOME/.npmrc" || fail "lost the user's npm token"
[[ "$(grep -c '^\[install\]' "$HOME/.bunfig.toml")" == 1 ]] || fail "second [install] table in bunfig: $(cat "$HOME/.bunfig.toml")"
pass "a setting or table of the user's own is left alone"

[[ -z "$(find "$HOME" -path '*pnpm*')" ]] || fail "wrote pnpm config: pnpm keeps its own default"
grep -qx '\[pip\]' "$XDG_CONFIG_HOME/uv/uv.toml" || fail "uv [pip] table: $(cat "$XDG_CONFIG_HOME/uv/uv.toml")"
grep -qx 'exclude-newer = "3 days"' "$XDG_CONFIG_HOME/uv/uv.toml" || fail "uv age: $(cat "$XDG_CONFIG_HOME/uv/uv.toml")"
frag="$TUIDEV_STATE_DIR/shell.d/release-age.zsh"
grep -q 'UV_EXCLUDE_NEWER:-3 days' "$frag" || fail "fragment age: $(cat "$frag")"
grep -q '@DAYS@' "$frag" && fail "fragment placeholder left in"
if command -v zsh >/dev/null 2>&1; then zsh -n "$frag" || fail "fragment is not valid zsh"; fi
pass "uv [pip] and the uvx / uv tool fragment get a 3-day age; pnpm keeps its own"

before="$(cat "$XDG_CONFIG_HOME/uv/uv.toml" "$TUIDEV_STATE_DIR/shell.d/release-age.zsh")"
run_pack >/dev/null || fail "re-run failed"
[[ "$(cat "$XDG_CONFIG_HOME/uv/uv.toml" "$TUIDEV_STATE_DIR/shell.d/release-age.zsh")" == "$before" ]] || fail "re-run changed the files"
out="$(TUIDEV_RELEASE_AGE_DAYS=7 run_pack)" || fail "7-day run failed"
grep -qx 'exclude-newer = "7 days"' "$XDG_CONFIG_HOME/uv/uv.toml" || fail "7 days not applied: $out"
pass "re-runs are idempotent and TUIDEV_RELEASE_AGE_DAYS changes the age in place"

rm -f "$tmp/bin/bun" "$HOME/.bunfig.toml"
out="$(TUIDEV_RELEASE_AGE_DAYS=soon run_pack)" || fail "bad age exited non-zero"
[[ "$out" == *"must be a whole number of days"* ]] || fail "bad age not refused: $out"
run_pack >/dev/null
[[ -e "$HOME/.bunfig.toml" ]] && fail "wrote bunfig without bun on PATH"
pass "a bad age is refused, and a tool that isn't installed gets nothing"

echo "All release-age tests passed."
