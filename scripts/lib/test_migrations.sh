#!/bin/bash
# Unit tests for scripts/lib/migrate.sh and scripts/lib/manifest.sh.
# Run: bash scripts/lib/test_migrations.sh  -> exit 0 on pass.
#
# Everything runs against a throwaway HOME and a throwaway migrations dir; the
# real ~/.config/tuidev is never touched.

set -e
unset XDG_CONFIG_HOME   # state paths below assume $HOME/.config/tuidev

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export TUIDEV_NO_COLOR=1
# Never resolve state from the developer's real HOME.
TUIDEV_STATE_DIR="$tmp/state"   # not exported: child migrations derive it from their own HOME
export TUIDEV_MIGRATIONS_DIR="$tmp/migrations"
export TUIDEV_MIGRATIONS_STATE="$tmp/state/migrations"
export TUIDEV_MANIFEST_FILE="$tmp/state/manifest"
mkdir -p "$TUIDEV_MIGRATIONS_DIR" "$tmp/state"

# shellcheck source=./ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"
# shellcheck source=./migrate.sh disable=SC1091
. "$SCRIPT_DIR/migrate.sh"
# shellcheck source=./manifest.sh disable=SC1091
. "$SCRIPT_DIR/manifest.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Writes a migration that touches "$tmp/ran-<n>" and exits with $2 (default 0).
make_migration() {
    local id="$1" code="${2:-0}"
    cat > "$TUIDEV_MIGRATIONS_DIR/$id.sh" <<EOF
#!/bin/bash
echo "\$\$" >> "$tmp/ran-$id"
exit $code
EOF
}

# ---------------------------------------------------------------------------
# migrate.sh
# ---------------------------------------------------------------------------

# 1. Empty dir: nothing pending, run is a clean no-op.
[[ -z "$(tuidev_migrations_pending)" ]] || fail "empty dir should have no pending"
tuidev_run_migrations >/dev/null || fail "empty run should succeed"
pass "no migrations = no-op"

# 2. Pending list is chronological, by timestamp prefix — not glob order.
make_migration 202601010000_first
make_migration 202612310000_third
make_migration 202606150000_second
got="$(tuidev_migrations_pending | tr '\n' ' ')"
[[ "$got" == "202601010000_first 202606150000_second 202612310000_third " ]] \
    || fail "pending order: '$got'"
pass "pending listed in chronological order"

# 3. --list changes nothing: no state file, no migration side effects.
tuidev_run_migrations --list >/dev/null
[[ ! -f "$TUIDEV_MIGRATIONS_STATE" ]] || fail "--list wrote state"
[[ ! -e "$tmp/ran-202601010000_first" ]] || fail "--list executed a migration"
pass "--list previews without running"

# 4. DRY_RUN=true behaves like --list.
DRY_RUN=true tuidev_run_migrations >/dev/null
[[ ! -f "$TUIDEV_MIGRATIONS_STATE" ]] || fail "DRY_RUN wrote state"
[[ ! -e "$tmp/ran-202601010000_first" ]] || fail "DRY_RUN executed a migration"
pass "DRY_RUN previews without running"

# 5. A real run applies each migration once and records every id.
tuidev_run_migrations >/dev/null || fail "run should succeed"
for id in 202601010000_first 202606150000_second 202612310000_third; do
    [[ -f "$tmp/ran-$id" ]] || fail "$id did not run"
    [[ "$(wc -l < "$tmp/ran-$id" | tr -d ' ')" == 1 ]] || fail "$id ran more than once"
    grep -qxF "$id" "$TUIDEV_MIGRATIONS_STATE" || fail "$id not recorded"
done
pass "run applies each migration and records it"

# 6. Re-running is a no-op — nothing executes a second time.
tuidev_run_migrations >/dev/null || fail "second run should succeed"
[[ "$(wc -l < "$tmp/ran-202601010000_first" | tr -d ' ')" == 1 ]] \
    || fail "migration re-ran on second invocation"
[[ -z "$(tuidev_migrations_pending)" ]] || fail "nothing should be pending"
[[ "$(wc -l < "$TUIDEV_MIGRATIONS_STATE" | tr -d ' ')" == 3 ]] \
    || fail "state file gained duplicate ids"
pass "re-run is a no-op"

# 7. A failing migration stops the run, is NOT recorded, and blocks the ones
#    after it — so nothing runs out of order on the retry.
make_migration 202701010000_boom 1
make_migration 202702010000_after
if tuidev_run_migrations >/dev/null 2>&1; then
    fail "failing migration should make the run return non-zero"
fi
grep -qxF 202701010000_boom "$TUIDEV_MIGRATIONS_STATE" && fail "failed id was recorded"
[[ -e "$tmp/ran-202702010000_after" ]] && fail "later migration ran after a failure"
pass "failure stops the run and is not recorded"

# 8. The failed migration is retried next time; fixing it lets the rest proceed.
make_migration 202701010000_boom 0
tuidev_run_migrations >/dev/null || fail "run should succeed once the migration is fixed"
grep -qxF 202701010000_boom "$TUIDEV_MIGRATIONS_STATE" || fail "fixed id not recorded"
[[ -f "$tmp/ran-202702010000_after" ]] || fail "later migration still did not run"
pass "failed migration is retried on the next run"

# 9. Baseline marks everything applied without running any of it.
rm -f "$TUIDEV_MIGRATIONS_STATE"
rm -f "$tmp"/ran-*
count="$(tuidev_migrations_baseline)"
[[ "$count" == 5 ]] || fail "baseline count: '$count'"
[[ -z "$(tuidev_migrations_pending)" ]] || fail "baseline left something pending"
[[ -z "$(find "$tmp" -maxdepth 1 -name 'ran-*' -print -quit)" ]] \
    || fail "baseline executed a migration"
pass "baseline records without running"

# 10. Baseline is a no-op once state exists (never re-baselines an upgrade).
make_migration 202801010000_later
tuidev_migrations_baseline >/dev/null
got="$(tuidev_migrations_pending)"
[[ "$got" == "202801010000_later" ]] || fail "baseline clobbered pending: '$got'"
pass "baseline skipped when state already exists"

# 10b. REGRESSION: an install that predates the migration framework must NOT be
#      treated as fresh. It has a profile (and/or manifest) but no migrations
#      state file, and baselining it would suppress the very fixups it needs.
state_dir="$tmp/statedir"
mkdir -p "$state_dir"
# Later cases depend on the state test 10 left behind; put it back afterwards.
cp "$TUIDEV_MIGRATIONS_STATE" "$tmp/state.bak"
rm -f "$TUIDEV_MIGRATIONS_STATE"
tuidev_is_fresh_install "$state_dir" || fail "empty state dir should read as fresh"
: > "$state_dir/profile"
tuidev_is_fresh_install "$state_dir" && fail "a pre-existing profile means NOT fresh"
rm -f "$state_dir/profile"
: > "$state_dir/manifest"
tuidev_is_fresh_install "$state_dir" && fail "a pre-existing manifest means NOT fresh"
rm -f "$state_dir/manifest"
tuidev_migration_mark 202601010000_first
tuidev_is_fresh_install "$state_dir" && fail "an existing migrations state means NOT fresh"
mv "$tmp/state.bak" "$TUIDEV_MIGRATIONS_STATE"
pass "pre-framework installs are not mistaken for fresh machines"

# 10c. REGRESSION (end to end): the reviewer's scenario. A machine with a
#      pre-existing ~/.config/tuidev/profile and a real pre-2.0 orphan must
#      RUN the prune migration, not baseline it away. Drives install.sh's own
#      decision path via the same guard install.sh uses.
reg_home="$tmp/reginstall"
mkdir -p "$reg_home/.config/tuidev" "$reg_home/.local/bin"
printf 'profile=desktop\ncore=true\n' > "$reg_home/.config/tuidev/profile"
printf 'legacy helper\n' > "$reg_home/.local/bin/ai-workflow.sh"
# The overrides below are deliberately subshell-local so the fixture dirs the
# rest of this file uses survive; SC2030/SC2031 flag exactly that on purpose.
# shellcheck disable=SC2030
(
    export HOME="$reg_home"
    # ui.sh resolved TUIDEV_STATE_DIR from the real HOME when it was sourced;
    # without this the check reads the developer's own ~/.config/tuidev.
    export TUIDEV_STATE_DIR="$reg_home/.config/tuidev"
    export TUIDEV_MIGRATIONS_STATE="$reg_home/.config/tuidev/migrations"
    export TUIDEV_MIGRATIONS_DIR="$SCRIPT_DIR/../migrations"
    tuidev_is_fresh_install && { echo "FAIL: existing install read as fresh"; exit 1; }
    [[ -n "$(tuidev_migrations_pending)" ]] || { echo "FAIL: nothing pending"; exit 1; }
    tuidev_run_migrations >/dev/null || { echo "FAIL: migration run failed"; exit 1; }
) || fail "reviewer scenario: upgrade path did not run migrations"
[[ ! -e "$reg_home/.local/bin/ai-workflow.sh" ]] \
    || fail "reviewer scenario: orphan survived — migration was suppressed"
grep -qxF 202608310900_prune_pre2_orphans "$reg_home/.config/tuidev/migrations" \
    || fail "reviewer scenario: migration not recorded"
pass "upgrade with pre-existing profile RUNS the orphan prune"

# 10d. Wiring guard: install.sh must gate baselining on the fresh-install check,
#      never on the bare state file (the bug this suite exists to prevent).
install_sh="$SCRIPT_DIR/../../install.sh"
grep -q 'tuidev_is_fresh_install' "$install_sh" \
    || fail "install.sh no longer uses tuidev_is_fresh_install"
grep -q 'TUIDEV_MIGRATIONS_STATE' "$install_sh" \
    && fail "install.sh gates on the migrations state file again — that was the bug"
pass "install.sh gates baselining on the fresh-install check"

# 11. Files that don't match the naming convention are ignored.
# shellcheck disable=SC2031  # the subshell above intentionally did not leak
touch "$TUIDEV_MIGRATIONS_DIR/notes.md" "$TUIDEV_MIGRATIONS_DIR/helper.sh"
got="$(tuidev_migrations_pending)"
[[ "$got" == "202801010000_later" ]] || fail "non-migration files picked up: '$got'"
pass "only NNNNNNNNNNNN_slug.sh files are migrations"

# ---------------------------------------------------------------------------
# The migrations shipped in the repo
# ---------------------------------------------------------------------------

# 12. Every shipped migration is syntactically valid and correctly named.
shipped=0
for f in "$SCRIPT_DIR/../migrations/"*.sh; do
    [[ -e "$f" ]] || continue
    shipped=$((shipped + 1))
    bash -n "$f" || fail "syntax error in $f"
    base="$(basename "$f")"
    [[ "$base" =~ ^[0-9]{12}_[a-z0-9_]+\.sh$ ]] || fail "bad migration name: $base"
done
[[ $shipped -gt 0 ]] || fail "no migrations shipped in scripts/migrations/"
pass "$shipped shipped migration(s) parse and are named correctly"

# 13. The pre-2.0 orphan prune does what it claims, against a fake HOME.
fake_home="$tmp/home"
mkdir -p "$fake_home/.local/bin" "$fake_home/.config" \
         "$fake_home/.local/share/gemini" "$fake_home/.local/share/mcp"
echo "legacy" > "$fake_home/.local/bin/ai-workflow.sh"
echo "legacy" > "$fake_home/.config/mcp-env.template"
echo "mine"   > "$fake_home/.local/share/mcp/keep.json"

HOME="$fake_home" TUIDEV_NO_COLOR=1 \
    bash "$SCRIPT_DIR/../migrations/202608310900_prune_pre2_orphans.sh" >/dev/null \
    || fail "prune migration failed"

[[ ! -e "$fake_home/.local/bin/ai-workflow.sh" ]] || fail "ai-workflow.sh not removed"
[[ ! -e "$fake_home/.config/mcp-env.template" ]]  || fail "mcp-env.template not removed"
[[ ! -d "$fake_home/.local/share/gemini" ]]       || fail "empty gemini dir not removed"
[[ -f "$fake_home/.local/share/mcp/keep.json" ]]  || fail "non-empty mcp dir was destroyed"
find "$fake_home/.config/tuidev/backups" -name 'ai-workflow.sh.*' | grep -q . \
    || fail "removed file was not backed up"
pass "prune migration removes orphans, backs them up, keeps user data"

# 14. …and is safe to run a second time by hand.
HOME="$fake_home" TUIDEV_NO_COLOR=1 \
    bash "$SCRIPT_DIR/../migrations/202608310900_prune_pre2_orphans.sh" >/dev/null \
    || fail "prune migration is not re-runnable"
pass "prune migration is re-runnable"

# 14b. The opencode split carries the pack over only when OpenCode is in use.
oc_home="$tmp/oc-home"; oc_bin="$tmp/oc-bin"
mkdir -p "$oc_home/.config/tuidev" "$oc_bin"
printf '#!/bin/sh\n' > "$oc_bin/opencode"; chmod +x "$oc_bin/opencode"
oc_mig="$SCRIPT_DIR/../migrations/202609221800_split_opencode_pack.sh"
oc_packs() { grep '^extra_packs=' "$oc_home/.config/tuidev/profile" | cut -d= -f2-; }

printf 'profile=remote\nextra_packs=ai-clis herdr\n' > "$oc_home/.config/tuidev/profile"
HOME="$oc_home" PATH="/usr/bin:/bin" bash "$oc_mig" >/dev/null || fail "opencode migration failed (absent)"
[[ "$(oc_packs)" == "ai-clis herdr" ]] || fail "opencode added without the CLI: $(oc_packs)"

printf 'extra_packs=herdr\n' > "$oc_home/.config/tuidev/profile"
HOME="$oc_home" PATH="$oc_bin:/usr/bin:/bin" bash "$oc_mig" >/dev/null || fail "opencode migration failed (no ai-clis)"
[[ "$(oc_packs)" == "herdr" ]] || fail "opencode added without ai-clis: $(oc_packs)"

printf 'extra_packs=ai-clis herdr\n' > "$oc_home/.config/tuidev/profile"
HOME="$oc_home" PATH="$oc_bin:/usr/bin:/bin" bash "$oc_mig" >/dev/null || fail "opencode migration failed"
HOME="$oc_home" PATH="$oc_bin:/usr/bin:/bin" bash "$oc_mig" >/dev/null || fail "opencode migration not re-runnable"
[[ "$(oc_packs)" == "ai-clis herdr opencode" ]] || fail "opencode not carried over once: $(oc_packs)"
pass "opencode split migration: opt-in kept, carried over once when in use"

# 14c. 3.0: nvim / tmux are carried into extra_packs only where tuidev set them up.
v3_home="$tmp/v3-home"
v3_mig="$SCRIPT_DIR/../migrations/202609231200_v3_optional_nvim_tmux.sh"
v3_packs() { grep '^extra_packs=' "$v3_home/.config/tuidev/profile" | cut -d= -f2-; }
mkdir -p "$v3_home/.config/tuidev" "$v3_home/.config/nvim" "$v3_home/.config/tmux"

printf 'profile=desktop\nextra_packs=herdr\n' > "$v3_home/.config/tuidev/profile"
echo "-- my own config" > "$v3_home/.config/nvim/init.lua"
echo "set -g mouse on"  > "$v3_home/.config/tmux/tmux.conf"
HOME="$v3_home" bash "$v3_mig" >/dev/null || fail "v3 nvim/tmux migration failed (user-owned)"
[[ "$(v3_packs)" == "herdr" ]] || fail "user-owned nvim/tmux carried over: $(v3_packs)"

# A remote node records tmux (its profile includes the pack) even with a
# tmux.conf of its own; the user's Neovim config still stays out.
printf 'profile=remote\nextra_packs=herdr\n' > "$v3_home/.config/tuidev/profile"
HOME="$v3_home" bash "$v3_mig" >/dev/null || fail "v3 nvim/tmux migration failed (remote)"
[[ "$(v3_packs)" == "herdr tmux" ]] || fail "remote profile did not carry tmux: $(v3_packs)"
grep -qx 'set -g mouse on' "$v3_home/.config/tmux/tmux.conf" || fail "remote: tmux.conf touched"
printf 'profile=remote\nextra_packs=herdr\n' > "$v3_home/.config/tuidev/profile"

cp "$SCRIPT_DIR/../../configs/nvim/init.lua" "$v3_home/.config/nvim/init.lua"
printf '%s\n' "# >>> tuidev managed (tuidev-tmux) >>>" "set -g mouse on" \
    "# <<< tuidev managed (tuidev-tmux) <<<" > "$v3_home/.config/tmux/tmux.conf"
HOME="$v3_home" bash "$v3_mig" >/dev/null || fail "v3 nvim/tmux migration failed"
HOME="$v3_home" bash "$v3_mig" >/dev/null || fail "v3 nvim/tmux migration not re-runnable"
[[ "$(v3_packs)" == "herdr nvim tmux" ]] || fail "nvim/tmux not carried over once: $(v3_packs)"
pass "v3 nvim/tmux migration: carries over tuidev-owned setups once, leaves the user's alone"

# 14d. 3.0: bosun, yazi and nnn leave extra_packs; everything else stays.
drop_mig="$SCRIPT_DIR/../migrations/202609231210_v3_drop_tui_packs.sh"
printf 'profile=desktop\nextra_packs=yazi herdr bosun nnn fnm\n' > "$v3_home/.config/tuidev/profile"
HOME="$v3_home" bash "$drop_mig" >/dev/null || fail "drop-packs migration failed"
HOME="$v3_home" bash "$drop_mig" >/dev/null || fail "drop-packs migration not re-runnable"
[[ "$(v3_packs)" == "herdr fnm" ]] || fail "removed packs not dropped: $(v3_packs)"
grep -qx 'profile=desktop' "$v3_home/.config/tuidev/profile" || fail "drop-packs touched other lines"
pass "v3 drop-packs migration removes bosun/yazi/nnn only, idempotently"

# 14e. 3.0: the cc/cx fragment is backed up and removed; nothing else is touched.
wrap_mig="$SCRIPT_DIR/../migrations/202609231220_v3_drop_ai_wrappers.sh"
mkdir -p "$v3_home/.config/tuidev/shell.d"
echo "cc() { :; }" > "$v3_home/.config/tuidev/shell.d/ai-clis.zsh"
echo "oc() { :; }" > "$v3_home/.config/tuidev/shell.d/opencode.zsh"
HOME="$v3_home" bash "$wrap_mig" >/dev/null || fail "drop-wrappers migration failed"
HOME="$v3_home" bash "$wrap_mig" >/dev/null || fail "drop-wrappers migration not re-runnable"
[[ ! -e "$v3_home/.config/tuidev/shell.d/ai-clis.zsh" ]] || fail "ai-clis.zsh not removed"
[[ -f "$v3_home/.config/tuidev/shell.d/opencode.zsh" ]]  || fail "opencode.zsh was touched"
find "$v3_home/.config/tuidev/backups" -name 'ai-clis.zsh.*' | grep -q . || fail "ai-clis.zsh not backed up"
pass "v3 drop-wrappers migration removes the cc/cx fragment with a backup, idempotently"

# 14f. …and claims the native sandbox only when settings.json has the block.
mkdir -p "$v3_home/.claude"
echo '{"model":"x"}' > "$v3_home/.claude/settings.json"
echo "cc() { :; }" > "$v3_home/.config/tuidev/shell.d/ai-clis.zsh"
out="$(HOME="$v3_home" bash "$wrap_mig" 2>&1)" || fail "drop-wrappers migration failed (no sandbox)"
[[ "$out" == *"merges the sandbox block"* && "$out" != *"turns on its native sandbox"* ]] \
    || fail "user settings without sandbox: $out"
cp "$SCRIPT_DIR/../../configs/claude/settings.json" "$v3_home/.claude/settings.json"
echo "cc() { :; }" > "$v3_home/.config/tuidev/shell.d/ai-clis.zsh"
out="$(HOME="$v3_home" bash "$wrap_mig" 2>&1)" || fail "drop-wrappers migration failed (sandbox)"
[[ "$out" == *"turns on its native sandbox"* ]] || fail "settings with sandbox: $out"
cmp -s "$SCRIPT_DIR/../../configs/claude/settings.json" "$v3_home/.claude/settings.json" \
    || fail "drop-wrappers migration touched settings.json"
pass "v3 drop-wrappers migration reports the Claude sandbox state truthfully"

# ---------------------------------------------------------------------------
# manifest.sh
# ---------------------------------------------------------------------------

# 15. Recording is off until a caller opts in.
tuidev_manifest_record formula ripgrep
[[ ! -f "$TUIDEV_MANIFEST_FILE" ]] || fail "recorded while disabled"
tuidev_manifest_present && fail "manifest should not exist yet"
pass "recording is opt-in"

# 16. DRY_RUN never writes, even when enabled.
tuidev_manifest_enable
DRY_RUN=true tuidev_manifest_record formula ripgrep
[[ ! -f "$TUIDEV_MANIFEST_FILE" ]] || fail "recorded under DRY_RUN"
pass "DRY_RUN records nothing"

# 17. Records land, deduplicate, and read back by kind.
tuidev_manifest_record profile desktop
tuidev_manifest_record formula ripgrep
tuidev_manifest_record formula ripgrep
tuidev_manifest_record formula fd
tuidev_manifest_record cask ghostty
tuidev_manifest_record block tuidev-zshrc "$fake_home/.zshrc"
tuidev_manifest_record dir "$fake_home/.config/nvim"
tuidev_manifest_present || fail "manifest should exist"
got="$(tuidev_manifest_values formula | tr '\n' ' ')"
[[ "$got" == "ripgrep fd " ]] || fail "formula values: '$got'"
[[ "$(tuidev_manifest_values profile)" == "desktop" ]] || fail "profile value"
[[ "$(tuidev_manifest_values cask)" == "ghostty" ]] || fail "cask value"
[[ "$(grep -c . "$TUIDEV_MANIFEST_FILE")" == 9 ]] \
    || fail "line count (3 header + 6 unique records): $(grep -c . "$TUIDEV_MANIFEST_FILE")"
pass "records append, deduplicate, and read back by kind"

# 18. `block` records survive a path containing spaces.
spaced="$tmp/dir with spaces/.zshrc"
tuidev_manifest_record block tuidev-zshrc "$spaced"
record="$(tuidev_manifest_values block | tail -1)"
[[ "${record%% *}" == "tuidev-zshrc" ]] || fail "block id: '${record%% *}'"
[[ "${record#* }" == "$spaced" ]] || fail "block path: '${record#* }'"
pass "block records round-trip paths with spaces"

# 19. tuidev_manifest_has, and comment lines are never returned as values.
tuidev_manifest_has formula ripgrep || fail "has(formula ripgrep) should be true"
tuidev_manifest_has formula nope && fail "has(formula nope) should be false"
tuidev_manifest_values '#' | grep -q . && fail "comments returned as records"
pass "tuidev_manifest_has + comments ignored"

# 20. Reading an absent manifest is empty and quiet, not an error.
[[ -z "$(tuidev_manifest_values formula "$tmp/nonexistent")" ]] || fail "absent file"
pass "absent manifest reads as empty"

echo ""
echo "All migration + manifest lib tests passed."
