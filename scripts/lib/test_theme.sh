#!/bin/bash
# scripts/lib/test_theme.sh - functional tests for scripts/theme.sh.
# Run directly: bash scripts/lib/test_theme.sh
# Exit code: 0 on success, non-zero on failure.
#
# Everything runs against scratch HOMEs, so the tests never touch the real
# ~/.config.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THEME="$REPO_ROOT/scripts/theme.sh"

# shellcheck source=./config_write.sh disable=SC1091
. "$SCRIPT_DIR/config_write.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export TUIDEV_NO_COLOR=1

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# fake_install HOME_DIR — reproduce what install.sh's _install_cross_cutting and
# the ui pack do: append each shipped config as its own managed block.
fake_install() {
    write_managed_block "$1/.config/starship.toml"  tuidev-starship \
        "$(cat "$REPO_ROOT/configs/starship/starship.toml")" >/dev/null
    write_managed_block "$1/.config/tmux/tmux.conf" tuidev-tmux \
        "$(cat "$REPO_ROOT/configs/tmux/tmux.conf")" >/dev/null
    write_managed_block "$1/.config/ghostty/config" tuidev-ghostty \
        "$(cat "$REPO_ROOT/configs/ghostty/config")" >/dev/null
}

# starship_sane FILE [themed] — the whole point of the ordering guard: the
# shipped prompt config must still be top-level TOML, not swallowed by our
# palette table. Pass "themed" to also require the palette table itself.
# Skipped (with a notice) if python3 has no tomllib.
starship_sane() {
    python3 - "$1" "${2:-}" <<'PY'
import sys
try:
    import tomllib
except ModuleNotFoundError:
    print("SKIP: tomllib unavailable"); sys.exit(0)
d = tomllib.load(open(sys.argv[1], "rb"))
assert d.get("palette") == "tuidev", f"top-level palette is {d.get('palette')!r}"
assert isinstance(d.get("format"), str), "shipped `format` is not top-level"
tuidev = d.get("palettes", {}).get("tuidev", {})
assert "format" not in tuidev, "shipped config leaked into palettes.tuidev"
if sys.argv[2] == "themed":
    assert tuidev.get("green"), "palettes.tuidev missing colors"
PY
}

new_home() {
    local h="$tmp/$1"
    mkdir -p "$h/.config/tmux" "$h/.config/ghostty"
    printf '%s' "$h"
}

# ============================================================================
# 1. Palette contract
# ============================================================================
keys_of() { grep -oE '^[a-z0-9_]+ = "#[0-9a-f]{6}"' "$1" | cut -d' ' -f1 | sort; }
ref=""
for palette in "$REPO_ROOT"/configs/themes/*/palette.toml; do
    got="$(keys_of "$palette")"
    if [[ -z "$ref" ]]; then
        ref="$got"
    elif [[ "$got" != "$ref" ]]; then
        fail "palette key sets differ: $palette"
    fi
done
count="$(printf '%s\n' "$ref" | grep -c .)"
[[ "$count" == "26" ]] || fail "expected 26 contract keys, got $count"
pass "all palettes share one 26-key contract"

# ============================================================================
# 2-3. Discovery and inspection
# ============================================================================
HOME="$(new_home discovery)" out="$("$THEME" list)"
grep -q "tokyo-night" <<< "$out"      || fail "list missing tokyo-night"
grep -q "catppuccin-mocha" <<< "$out" || fail "list missing catppuccin-mocha"
pass "list discovers shipped themes"

out="$("$THEME" show tokyo-night)"
grep -q 'ansi_bright_white  *#c0caf5' <<< "$out" || fail "show missing ansi_bright_white"
pass "show prints the palette"

# ============================================================================
# 4-6. Normal path: install, then theme
# ============================================================================
HOME="$(new_home normal)"; export HOME
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
GHOSTTY_CONF="$HOME/.config/ghostty/config"
STARSHIP_CONF="$HOME/.config/starship.toml"

echo "# USER_TMUX_LINE" > "$TMUX_CONF"
echo "# USER_GHOSTTY_LINE" > "$GHOSTTY_CONF"
fake_install "$HOME"
echo "# USER_STARSHIP_TRAILER" >> "$STARSHIP_CONF"

before="$(cat "$TMUX_CONF" "$GHOSTTY_CONF" "$STARSHIP_CONF")"
out="$("$THEME" apply catppuccin-mocha --dry-run)"
grep -q "1e1e2e" <<< "$out" || fail "dry-run did not preview colors"
[[ "$(cat "$TMUX_CONF" "$GHOSTTY_CONF" "$STARSHIP_CONF")" == "$before" ]] \
    || fail "dry-run mutated a config"
[[ -f "$HOME/.config/tuidev/theme" ]] && fail "dry-run wrote the state file"
pass "--dry-run mutates nothing"

"$THEME" apply tokyo-night >/dev/null
for f in "$TMUX_CONF" "$GHOSTTY_CONF" "$STARSHIP_CONF"; do
    grep -qF "tuidev managed (tuidev-theme)" "$f" || fail "no managed block in $f"
done
grep -qF "USER_TMUX_LINE" "$TMUX_CONF"           || fail "user tmux line lost"
grep -qF "USER_GHOSTTY_LINE" "$GHOSTTY_CONF"     || fail "user ghostty line lost"
grep -qF "USER_STARSHIP_TRAILER" "$STARSHIP_CONF" || fail "user starship line lost"
grep -qF "1a1b26" <<< "$(read_managed_block "$GHOSTTY_CONF" tuidev-theme)" \
    || fail "tokyo-night bg not written"
[[ "$(cat "$HOME/.config/tuidev/theme")" == "tokyo-night" ]] || fail "state file wrong"
starship_sane "$STARSHIP_CONF" themed || fail "starship.toml broken after install-then-theme"
pass "install-then-theme: blocks written, user content and TOML intact"

"$THEME" apply catppuccin-mocha >/dev/null
for f in "$TMUX_CONF" "$GHOSTTY_CONF" "$STARSHIP_CONF"; do
    n="$(grep -cF "# >>> tuidev managed (tuidev-theme) >>>" "$f")"
    [[ "$n" == "1" ]] || fail "block duplicated in $f ($n copies)"
done
# Assert inside the theme block: the shipped tuidev-ghostty block legitimately
# still carries Tokyo Night's own hexes.
block="$(read_managed_block "$GHOSTTY_CONF" tuidev-theme)"
grep -qF "1e1e2e" <<< "$block" || fail "catppuccin bg not written"
grep -qF "1a1b26" <<< "$block" && fail "tokyo-night bg survived the swap"
grep -qF "USER_GHOSTTY_LINE" "$GHOSTTY_CONF" || fail "user line lost on re-apply"
starship_sane "$STARSHIP_CONF" themed || fail "starship.toml broken after re-apply"
pass "re-apply replaces, never duplicates"

# ============================================================================
# 7. A palette missing a contract key fails loudly and writes nothing
# ============================================================================
(
    export TUIDEV_THEMES_DIR="$tmp/themes"
    mkdir -p "$TUIDEV_THEMES_DIR/broken"
    grep -v '^accent = ' "$REPO_ROOT/configs/themes/tokyo-night/palette.toml" \
        > "$TUIDEV_THEMES_DIR/broken/palette.toml"
    snapshot="$(cat "$GHOSTTY_CONF")"
    if out="$("$THEME" apply broken 2>&1)"; then
        fail "apply of a broken palette succeeded"
    fi
    grep -q "accent" <<< "$out" || fail "error did not name the missing key"
    [[ "$(cat "$GHOSTTY_CONF")" == "$snapshot" ]] || fail "broken apply mutated a config"
)
pass "missing key fails loudly, writes nothing"

# ============================================================================
# 8. Regression: theme applied BEFORE install must not corrupt starship.toml
# ============================================================================
# TOML has no way to close a table, so a [palettes.tuidev] table written into a
# not-yet-installed starship.toml would swallow everything install.sh appends
# after it. apply must refuse instead.
HOME="$(new_home preinstall)"; export HOME
STARSHIP_CONF="$HOME/.config/starship.toml"

out="$("$THEME" apply tokyo-night 2>&1)"
grep -q "skipping starship" <<< "$out" || fail "apply did not skip an uninstalled starship.toml"
grep -q "install.sh" <<< "$out"        || fail "skip message does not say how to fix it"
if [[ -f "$STARSHIP_CONF" ]]; then
    grep -qF "palettes.tuidev" "$STARSHIP_CONF" && fail "wrote a palette table pre-install"
fi
grep -qF "1a1b26" "$HOME/.config/ghostty/config" || fail "ghostty should still be themed"
pass "theme-before-install: starship refused, other targets still themed"

fake_install "$HOME"
starship_sane "$STARSHIP_CONF" || fail "fake install produced a broken starship.toml"
"$THEME" apply catppuccin-mocha >/dev/null
starship_sane "$STARSHIP_CONF" themed || fail "starship.toml broken after install-then-reapply"
grep -qF "89b4fa" "$STARSHIP_CONF" || fail "palette not written after install"
pass "theme-before-install then install then re-apply: config sane and themed"

# ============================================================================
# 9. Regression: an install that lands AFTER the theme must not win
# ============================================================================
# install.sh appends tuidev-ghostty below our block, and ghostty is
# last-write-wins, so the shipped colors would silently override the theme.
# apply must move its block back to the end.
HOME="$(new_home reorder)"; export HOME
GHOSTTY_CONF="$HOME/.config/ghostty/config"
TMUX_CONF="$HOME/.config/tmux/tmux.conf"

"$THEME" apply catppuccin-mocha >/dev/null 2>&1
fake_install "$HOME"

theme_line="$(grep -nF '# >>> tuidev managed (tuidev-theme) >>>' "$GHOSTTY_CONF" | cut -d: -f1)"
ship_line="$(grep -nF '# >>> tuidev managed (tuidev-ghostty) >>>' "$GHOSTTY_CONF" | cut -d: -f1)"
[[ "$theme_line" -lt "$ship_line" ]] || fail "setup wrong: shipped block should follow the theme"

out="$("$THEME" apply catppuccin-mocha 2>&1)"
grep -q "moving it to the end" <<< "$out" || fail "apply did not report the reorder"

for f in "$GHOSTTY_CONF" "$TMUX_CONF"; do
    n="$(grep -cF '# >>> tuidev managed (tuidev-theme) >>>' "$f")"
    [[ "$n" == "1" ]] || fail "reorder duplicated the theme block in $f ($n copies)"
    last="$(grep -v '^[[:space:]]*$' "$f" | tail -n1)"
    [[ "$last" == "# <<< tuidev managed (tuidev-theme) <<<" ]] \
        || fail "theme block is not last in $f (last line: $last)"
done
grep -qF "tuidev managed (tuidev-ghostty)" "$GHOSTTY_CONF" || fail "shipped ghostty block lost"
grep -qF "1e1e2e" <<< "$(read_managed_block "$GHOSTTY_CONF" tuidev-theme)" \
    || fail "theme colors missing after reorder"
pass "install-after-theme: theme block moved back to last, shipped block intact"

echo ""
echo "All theme tests passed."
