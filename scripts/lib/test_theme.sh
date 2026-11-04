#!/bin/bash
# scripts/lib/test_theme.sh - functional tests for scripts/theme.sh.
# Run directly: bash scripts/lib/test_theme.sh
# Exit code: 0 on success, non-zero on failure.
#
# Everything runs against scratch HOMEs and a private tmux socket dir, so the
# tests never touch the real ~/.config or a running tmux server.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THEME="$REPO_ROOT/scripts/theme.sh"

# shellcheck source=./config_write.sh disable=SC1091
. "$SCRIPT_DIR/config_write.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
# theme.sh reloads a live tmux server; point it at a private, empty socket dir.
unset TMUX
export TMUX_TMPDIR="$tmp/tmux"
mkdir -p "$TMUX_TMPDIR"
trap 'tmux kill-server >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
export TUIDEV_NO_COLOR=1
unset XDG_CONFIG_HOME TUIDEV_STATE_DIR

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
# Skipped (with a notice) without python3 or its tomllib (the Alpine test image).
starship_sane() {
    command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; return 0; }
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
grep -q "catppuccin-latte" <<< "$out" || fail "list missing catppuccin-latte"
pass "list discovers shipped themes"

out="$("$THEME" show tokyo-night)"
grep -q 'ansi_bright_white  *#c0caf5' <<< "$out" || fail "show missing ansi_bright_white"
pass "show prints the palette"

# ============================================================================
# 4-6. Normal path: install, then theme
# ============================================================================
HOME="$(new_home normal)"; export HOME
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
TMUX_THEME="$HOME/.config/tmux/theme.conf"
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
[[ -e "$TMUX_THEME" ]] && fail "dry-run wrote theme.conf"
pass "--dry-run mutates nothing"

"$THEME" apply tokyo-night >/dev/null
for f in "$TMUX_THEME" "$GHOSTTY_CONF" "$STARSHIP_CONF"; do
    grep -qF "tuidev managed (tuidev-theme)" "$f" || fail "no managed block in $f"
done
grep -qF "tuidev managed (tuidev-theme)" "$TMUX_CONF" \
    && fail "tmux theme written into tmux.conf (must go to theme.conf)"
grep -qF "USER_TMUX_LINE" "$TMUX_CONF"           || fail "user tmux line lost"
grep -qF "USER_GHOSTTY_LINE" "$GHOSTTY_CONF"     || fail "user ghostty line lost"
grep -qF "USER_STARSHIP_TRAILER" "$STARSHIP_CONF" || fail "user starship line lost"
grep -qF "1a1b26" <<< "$(read_managed_block "$GHOSTTY_CONF" tuidev-theme)" \
    || fail "tokyo-night bg not written"
[[ "$(cat "$HOME/.config/tuidev/theme")" == "tokyo-night" ]] || fail "state file wrong"
starship_sane "$STARSHIP_CONF" themed || fail "starship.toml broken after install-then-theme"
pass "install-then-theme: blocks written, user content and TOML intact"

"$THEME" apply catppuccin-mocha >/dev/null
for f in "$TMUX_THEME" "$GHOSTTY_CONF" "$STARSHIP_CONF"; do
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

"$THEME" apply catppuccin-mocha >/dev/null 2>&1
fake_install "$HOME"

theme_line="$(grep -nF '# >>> tuidev managed (tuidev-theme) >>>' "$GHOSTTY_CONF" | cut -d: -f1)"
ship_line="$(grep -nF '# >>> tuidev managed (tuidev-ghostty) >>>' "$GHOSTTY_CONF" | cut -d: -f1)"
[[ "$theme_line" -lt "$ship_line" ]] || fail "setup wrong: shipped block should follow the theme"

out="$("$THEME" apply catppuccin-mocha 2>&1)"
grep -q "moving it to the end" <<< "$out" || fail "apply did not report the reorder"

n="$(grep -cF '# >>> tuidev managed (tuidev-theme) >>>' "$GHOSTTY_CONF")"
[[ "$n" == "1" ]] || fail "reorder duplicated the theme block ($n copies)"
last="$(grep -v '^[[:space:]]*$' "$GHOSTTY_CONF" | tail -n1)"
[[ "$last" == "# <<< tuidev managed (tuidev-theme) <<<" ]] \
    || fail "theme block is not last in ghostty config (last line: $last)"
grep -qF "tuidev managed (tuidev-ghostty)" "$GHOSTTY_CONF" || fail "shipped ghostty block lost"
grep -qF "1e1e2e" <<< "$(read_managed_block "$GHOSTTY_CONF" tuidev-theme)" \
    || fail "theme colors missing after reorder"
pass "install-after-theme: theme block moved back to last, shipped block intact"

# ============================================================================
# 10. tmux: theme.conf is sourced ABOVE the TPM block
# ============================================================================
# Anything after TPM's `run` resets status-right after plugins hooked it —
# tmux-continuum's autosave dies silently. The shipped tmux.conf must source
# theme.conf before the TPM block, and nothing may be appended after it.
shipped="$REPO_ROOT/configs/tmux/tmux.conf"
src_line="$(grep -nE '^source-file -q ~/.config/tmux/theme\.conf$' "$shipped" | cut -d: -f1)"
tpm_line="$(grep -nF "run '~/.config/tmux/plugins/tpm/tpm'" "$shipped" | cut -d: -f1)"
[[ -n "$src_line" ]] || fail "shipped tmux.conf does not source theme.conf"
[[ -n "$tpm_line" ]] || fail "shipped tmux.conf has no TPM run line"
[[ "$src_line" -lt "$tpm_line" ]] || fail "theme.conf is sourced after the TPM run line"
pass "shipped tmux.conf sources theme.conf above TPM"

# ============================================================================
# 11. tmux: a pre-2.4 theme block inside tmux.conf is moved out on apply
# ============================================================================
HOME="$(new_home legacy-apply)"; export HOME
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
TMUX_THEME="$HOME/.config/tmux/theme.conf"
fake_install "$HOME"
write_managed_block "$TMUX_CONF" tuidev-theme "# LEGACY_THEME" >/dev/null

"$THEME" apply catppuccin-mocha >/dev/null
grep -qF "tuidev managed (tuidev-theme)" "$TMUX_CONF" && fail "legacy block left in tmux.conf"
grep -qF "tuidev managed (tuidev-tmux)" "$TMUX_CONF"  || fail "shipped tmux block lost"
grep -qF "1e1e2e" "$TMUX_THEME"                        || fail "theme.conf not written"
pass "apply moves a legacy tmux.conf theme block into theme.conf"

# ============================================================================
# 12. Migration 202609222000: moves the legacy block without an apply
# ============================================================================
MIGRATION="$REPO_ROOT/scripts/migrations/202609222000_tmux_theme_file.sh"
HOME="$(new_home legacy-migrate)"; export HOME
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
TMUX_THEME="$HOME/.config/tmux/theme.conf"
fake_install "$HOME"
echo "# USER_TRAILER" >> "$TMUX_CONF"
write_managed_block "$TMUX_CONF" tuidev-theme "set -g status-style 'bg=#123456'" >/dev/null

bash "$MIGRATION" >/dev/null || fail "migration failed"
grep -qF "tuidev managed (tuidev-theme)" "$TMUX_CONF" && fail "migration left the block in tmux.conf"
grep -qF "USER_TRAILER" "$TMUX_CONF"                   || fail "migration lost user content"
grep -qF "bg=#123456" <<< "$(read_managed_block "$TMUX_THEME" tuidev-theme)" \
    || fail "migration did not carry the block into theme.conf"
ls "$HOME/.config/tuidev/backups"/tmux.conf.* >/dev/null 2>&1 || fail "migration made no backup"
bash "$MIGRATION" >/dev/null || fail "migration re-run failed"
[[ "$(grep -cF 'tuidev managed (tuidev-theme) >>>' "$TMUX_THEME")" == 1 ]] \
    || fail "migration re-run duplicated the block"
pass "migration moves the legacy block, backs up, and is idempotent"

# 12b. A user-owned tmux.conf (no tuidev-tmux block, e.g. adopt-existing) gets
#      a source-file line for theme.conf: above TPM's run line when there is
#      one, else at the end. Re-running adds nothing.
HOME="$(new_home legacy-own-tpm)"; export HOME
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
printf '%s\n' "set -g mouse on" "set -g @plugin 'tmux-plugins/tpm'" "run '~/.tmux/plugins/tpm/tpm'" > "$TMUX_CONF"
write_managed_block "$TMUX_CONF" tuidev-theme "set -g status-style 'bg=#123456'" >/dev/null
bash "$MIGRATION" >/dev/null || fail "migration failed on a user-owned tmux.conf"
src_line="$(grep -nE '^source-file -q ~/.config/tmux/theme\.conf$' "$TMUX_CONF" | cut -d: -f1)"
tpm_line="$(grep -nF "run '~/.tmux/plugins/tpm/tpm'" "$TMUX_CONF" | cut -d: -f1)"
[[ -n "$src_line" && "$src_line" -lt "$tpm_line" ]] || fail "source-file line missing or not above TPM's run line"
grep -qF "set -g mouse on" "$TMUX_CONF" || fail "migration lost user content"
write_managed_block "$TMUX_CONF" tuidev-theme "set -g status-style 'bg=#654321'" >/dev/null
bash "$MIGRATION" >/dev/null || fail "migration re-run failed"
bash "$MIGRATION" >/dev/null || fail "migration re-run failed"
[[ "$(grep -c 'tmux/theme\.conf$' "$TMUX_CONF")" == 1 ]] || fail "migration re-run duplicated the source-file line"

HOME="$(new_home legacy-own-plain)"; export HOME
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
echo "set -g mouse on" > "$TMUX_CONF"
write_managed_block "$TMUX_CONF" tuidev-theme "set -g status-style 'bg=#123456'" >/dev/null
bash "$MIGRATION" >/dev/null || fail "migration failed on a tmux.conf without TPM"
[[ "$(tail -n1 "$TMUX_CONF")" == "source-file -q ~/.config/tmux/theme.conf" ]] \
    || fail "source-file line not appended at the end"
pass "migration sources theme.conf from a user-owned tmux.conf (above TPM), idempotently"

# ============================================================================
# 12c. Herdr: a [theme.custom] table, never over a [theme] of yours
# ============================================================================
# herdr_sane FILE — valid TOML, with the shipped [theme] and our custom table.
herdr_sane() {
    command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 unavailable"; return 0; }
    python3 - "$1" <<'PY'
import sys
try:
    import tomllib
except ModuleNotFoundError:
    print("SKIP: tomllib unavailable"); sys.exit(0)
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["theme"]["custom"]["red"].startswith("#"), d
assert d["ui"]["sound"] is False, "the [ui] above it was swallowed"
PY
}
HOME="$(new_home herdr)"; export HOME
HERDR_CONF="$HOME/.config/herdr/config.toml"
# No config yet: left for the pack to place, which --adopt-existing would skip.
out="$("$THEME" apply catppuccin-mocha 2>&1)"
grep -q "skipping herdr" <<< "$out" || fail "no Herdr config: no word about it"
[[ ! -e "$HERDR_CONF" ]] || fail "apply created a Herdr config before the pack"

mkdir -p "$HOME/.config/herdr"
{ cat "$REPO_ROOT/configs/herdr/config.toml"; printf '\n[ui]\nsound = false\n'; } > "$HERDR_CONF"
before="$(cat "$HERDR_CONF")"
out="$("$THEME" apply catppuccin-mocha --dry-run 2>&1)"
grep -q "f38ba8" <<< "$out" || fail "dry-run did not preview Herdr's colors"
[[ "$(cat "$HERDR_CONF")" == "$before" ]] || fail "dry-run wrote the Herdr config"
out="$("$THEME" apply catppuccin-mocha 2>&1)"
grep -q "reload-config" <<< "$out" || fail "apply does not say how to reload Herdr"
block="$(read_managed_block "$HERDR_CONF" tuidev-theme)"
grep -qF '[theme.custom]' <<< "$block" || fail "no [theme.custom] in the block"
grep -qE '^red = "#f38ba8"$' <<< "$block" || fail "blocked's red isn't the palette's"
grep -qE '^green = "#a6e3a1"$' <<< "$block" || fail "green"
grep -qE '^accent = "#89b4fa"$' <<< "$block" || fail "accent"
grep -qE '^panel_bg = "reset"$' <<< "$block" || fail "panel_bg stays the terminal's"
for t in accent panel_bg sidebar_bg active_row_bg selection_bg surface0 surface1 surface_dim overlay0 overlay1 text subtext0 mauve green yellow red blue teal peach; do
    grep -qE "^$t = " <<< "$block" || fail "Herdr token $t not set"
done
grep -qF 'name = "tokyo-night"' "$HERDR_CONF" || fail "the shipped [theme] was touched"
herdr_sane "$HERDR_CONF" || fail "Herdr config broken after apply"
"$THEME" apply tokyo-night >/dev/null 2>&1
[[ "$(grep -cF '# >>> tuidev managed (tuidev-theme) >>>' "$HERDR_CONF")" == 1 ]] || fail "re-apply duplicated the Herdr block"
grep -qE '^red = "#f7768e"$' <<< "$(read_managed_block "$HERDR_CONF" tuidev-theme)" || fail "re-apply kept the old colors"
herdr_sane "$HERDR_CONF" || fail "Herdr config broken after re-apply"
pass "herdr: a [theme.custom] block beside the shipped [theme]; valid TOML; re-apply replaces it"

# A theme of yours stays: each way TOML can say it.
for own in '[theme]\nname = "catppuccin"\n' '[theme]\nname = "tokyo-night"\nauto_switch = true\n' \
           '[theme.custom]\naccent = "#123456"\n' '[ theme ]\nname = "terminal"\n' 'theme.name = "terminal"\n[ui]\nsound = false\n' \
           '["theme"]\nname = "catppuccin"\n' "['theme']\nname = \"catppuccin\"\n" '["theme".custom]\nred = "#123456"\n' '"theme".name = "terminal"\n[ui]\nsound = false\n'; do
    HOME="$(new_home "herdr-own-$RANDOM")"; export HOME
    HERDR_CONF="$HOME/.config/herdr/config.toml"
    mkdir -p "$HOME/.config/herdr"
    # shellcheck disable=SC2059  # the fixture carries its own escapes
    printf "onboarding = false\n\n$own" > "$HERDR_CONF"
    before="$(cat "$HERDR_CONF")"
    out="$("$THEME" apply catppuccin-mocha 2>&1)" || fail "apply failed over a user's theme: $out"
    grep -q "skipping herdr" <<< "$out" || fail "no word when skipping: $own"
    grep -q 'name = \\\?"terminal' <<< "$out" || grep -q 'terminal' <<< "$out" || fail "no hint: $out"
    [[ "$(cat "$HERDR_CONF")" == "$before" ]] || fail "a user's theme was touched: $own"
    grep -qF "1e1e2e" "$HOME/.config/ghostty/config" || fail "the other targets not themed"
done
# Applied, then you set a theme: our block goes, or its tokens would override yours.
HOME="$(new_home herdr-then-own)"; export HOME
HERDR_CONF="$HOME/.config/herdr/config.toml"
mkdir -p "$HOME/.config/herdr"
printf '[theme]\nname = "tokyo-night"\n\n[ui]\nsound = false\n' > "$HERDR_CONF"
"$THEME" apply catppuccin-mocha >/dev/null 2>&1
grep -qF '[theme.custom]' "$HERDR_CONF" || fail "setup: no block"
sed -i.bak 's/name = "tokyo-night"/name = "dracula"/' "$HERDR_CONF"
out="$("$THEME" apply catppuccin-mocha --dry-run 2>&1)"
grep -qF '[theme.custom]' "$HERDR_CONF" || fail "a dry run removed the block"
grep -q "would remove tuidev's theme block" <<< "$out" || fail "the dry run doesn't say: $out"
out="$("$THEME" apply catppuccin-mocha 2>&1)"
grep -q "removed tuidev's theme block" <<< "$out" || fail "apply doesn't say it removed the block: $out"
! grep -qF 'theme.custom' "$HERDR_CONF" || fail "our block kept over the user's theme: $(cat "$HERDR_CONF")"
grep -qF 'name = "dracula"' "$HERDR_CONF" || fail "the user's theme was touched"
grep -qF 'sound = false' "$HERDR_CONF" || fail "the user's [ui] was touched"
pass "herdr: applied, then a theme of yours: our block goes, and apply says so"

# Our own block doesn't count as yours, and a file with no theme at all is fine.
HOME="$(new_home herdr-plain)"; export HOME
HERDR_CONF="$HOME/.config/herdr/config.toml"
mkdir -p "$HOME/.config/herdr"
printf 'onboarding = false\n\n[ui]\nsound = false\n' > "$HERDR_CONF"
"$THEME" apply catppuccin-mocha >/dev/null 2>&1
grep -qF '[theme.custom]' "$HERDR_CONF" || fail "a config with no theme stayed unthemed"
"$THEME" apply catppuccin-latte >/dev/null 2>&1 || fail "re-apply over our own block"
grep -qE '^red = "#d20f39"$' <<< "$(read_managed_block "$HERDR_CONF" tuidev-theme)" || fail "re-apply over our own block: not replaced"
herdr_sane "$HERDR_CONF" || fail "Herdr config broken with no [theme] of its own"
pass "herdr: a [theme] of yours is left alone, with a hint; the other targets still themed"

# ============================================================================
# 13. tmux actually loads theme.conf through the shipped tmux.conf
# ============================================================================
# A private server (socket under $TMUX_TMPDIR, scratch HOME) started from the
# installed tmux.conf must end up with the theme's status-style. Agent
# sandboxes can deny the socket; that is a SKIP, not a theme bug.
if ! command -v tmux >/dev/null 2>&1; then
    echo "SKIP: tmux not installed — live theme.conf load not checked"
# new-session exits 0 even when the server never starts; has-session tells.
elif ! { tmux -f /dev/null new-session -d 2>/dev/null && tmux has-session 2>/dev/null; }; then
    echo "SKIP: tmux cannot create a server socket here (sandboxed?) — live theme.conf load not checked"
else
    tmux kill-server >/dev/null 2>&1 || true
    HOME="$(new_home live)"; export HOME
    fake_install "$HOME"
    "$THEME" apply catppuccin-mocha >/dev/null
    got="$(tmux -f "$HOME/.config/tmux/tmux.conf" new-session -d \; show -gv status-style)"
    tmux kill-server >/dev/null 2>&1 || true
    [[ "$got" == *"1e1e2e"* ]] || fail "tmux did not load theme.conf (status-style: $got)"
    pass "tmux loads theme.conf via the shipped tmux.conf"
fi

echo ""
echo "All theme tests passed."
