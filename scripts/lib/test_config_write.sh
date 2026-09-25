#!/bin/bash
# scripts/lib/test_config_write.sh - unit tests for config_write.sh.
# Run directly: bash scripts/lib/test_config_write.sh
# Exit code: 0 on success, non-zero on failure.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# An explicit template: a bare `mktemp -d` ignores TMPDIR on recent macOS.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test-cfgw.XXXXXX")"
export TUIDEV_BACKUP_DIR="$tmp/backups"
# The --merge-json base lives under the state dir: keep it out of $HOME.
export TUIDEV_STATE_DIR="$tmp/state"

# shellcheck source=./config_write.sh disable=SC1091
. "$SCRIPT_DIR/config_write.sh"

trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# 1. Append block to existing non-empty file
echo "line1" > "$tmp/rc"
echo "line2" >> "$tmp/rc"
write_managed_block "$tmp/rc" "b1" "content-1" >/dev/null
grep -qF "line1" "$tmp/rc" || fail "original content lost"
grep -qF "tuidev managed (b1)" "$tmp/rc" || fail "marker missing"
grep -qF "content-1" "$tmp/rc" || fail "block content missing"
pass "append to existing file"

# 2. Replace existing block in-place
write_managed_block "$tmp/rc" "b1" "content-2" >/dev/null
grep -qF "content-2" "$tmp/rc" || fail "block not updated"
grep -qF "content-1" "$tmp/rc" && fail "old content still present"
pass "replace in place"

# 3. Multiple blocks coexist
write_managed_block "$tmp/rc" "b2" "content-b2" >/dev/null
grep -qF "tuidev managed (b1)" "$tmp/rc" || fail "b1 marker lost"
grep -qF "tuidev managed (b2)" "$tmp/rc" || fail "b2 marker missing"
pass "multiple blocks coexist"

# 4. User edits outside block survive block replace
echo "USER_LINE" >> "$tmp/rc"
write_managed_block "$tmp/rc" "b1" "content-3" >/dev/null
grep -qF "USER_LINE" "$tmp/rc" || fail "user line lost"
grep -qF "content-3" "$tmp/rc" || fail "block update failed"
pass "user edits preserved"

# 5. Remove block preserves siblings and user edits
remove_managed_block "$tmp/rc" "b1" >/dev/null
grep -qF "tuidev managed (b1)" "$tmp/rc" && fail "b1 still present"
grep -qF "tuidev managed (b2)" "$tmp/rc" || fail "b2 removed by mistake"
grep -qF "USER_LINE" "$tmp/rc" || fail "user line removed"
pass "remove is surgical"

# 6. install_config --adopt-existing is a no-op on existing files
echo "src-content" > "$tmp/src"
echo "dst-content" > "$tmp/dst"
install_config "$tmp/dst" "$tmp/src" --adopt-existing >/dev/null
[[ "$(cat "$tmp/dst")" == "dst-content" ]] || fail "adopt-existing overwrote"
pass "adopt-existing preserves"

# 7. install_config --managed-block injects source as block
install_config "$tmp/dst" "$tmp/src" --managed-block cfg7 >/dev/null
grep -qF "tuidev managed (cfg7)" "$tmp/dst" || fail "cfg7 marker missing"
grep -qF "src-content" "$tmp/dst" || fail "src content missing"
pass "install_config managed-block"

# 8. install_config --overwrite backs up existing
install_config "$tmp/dst" "$tmp/src" --overwrite >/dev/null
[[ "$(cat "$tmp/dst")" == "src-content" ]] || fail "overwrite did not write"
# Backup dir uses $HOME; we don't assert its content here to avoid polluting
# the real home dir during tests. The backup write is covered by the
# behavior contract of install_config and verified by read-back above.
pass "install_config overwrite"

# 8b. --overwrite on an identical file neither copies nor backs up
cp "$tmp/src" "$tmp/same"
before="$(find "$TUIDEV_BACKUP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
install_config "$tmp/same" "$tmp/src" --overwrite >/dev/null
after="$(find "$TUIDEV_BACKUP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
[[ "$before" == "$after" ]] || fail "identical --overwrite made a backup"
pass "install_config overwrite skips identical files"

# 9. Dry-run mutates nothing
echo "unchanged" > "$tmp/dry"
DRY_RUN=true write_managed_block "$tmp/dry" "dryid" "should not appear" >/dev/null
grep -qF "should not appear" "$tmp/dry" && fail "dry-run wrote content"
pass "dry-run is inert"

# 9.5 tuidev_backup rotates to TUIDEV_BACKUP_KEEP
(
    export TUIDEV_BACKUP_DIR="$tmp/backups"
    export TUIDEV_BACKUP_KEEP=3
    mkdir -p "$TUIDEV_BACKUP_DIR"
    for d in 01 02 03 04 05; do
        touch "$TUIDEV_BACKUP_DIR/foo.2026010${d}-000000"
        sleep 0.01
    done
    echo src > "$tmp/backup-src"
    tuidev_backup "$tmp/backup-src" foo >/dev/null
    count=$(find "$TUIDEV_BACKUP_DIR" -mindepth 1 -maxdepth 1 -name 'foo.*' | wc -l | tr -d ' ')
    [[ "$count" == "3" ]] || fail "rotation: expected 3, got $count"
)
pass "tuidev_backup rotates to N"

# 10. read_managed_block round-trips content and reports absence correctly
echo "user line" > "$tmp/rb"
write_managed_block "$tmp/rb" "readid" "line-a"$'\n'"line-b" >/dev/null
got="$(read_managed_block "$tmp/rb" "readid")"
[[ "$got" == "line-a"$'\n'"line-b" ]] || fail "read_managed_block content mismatch: got <$got>"
read_managed_block "$tmp/rb" "nope" >/dev/null && fail "read_managed_block should fail on missing block"
pass "read_managed_block round-trip and absence"

# 11. --upgrade-shipped: absent -> placed; an unmodified shipped copy ->
#     upgraded with a backup; a user-edited copy -> kept; hashes are keyed by
#     name, so another file's shipped hash does not count.
mkdir -p "$tmp/up"
printf 'v1\n' > "$tmp/up/old"
printf 'v2\n' > "$tmp/up/cfg.json"
{ echo "# comment"; echo "cfg $(file_sha256 "$tmp/up/old")"; } > "$tmp/up/shipped.sha256"
install_config "$tmp/up/new/cfg.json" "$tmp/up/cfg.json" --upgrade-shipped "$tmp/up/shipped.sha256" >/dev/null
cmp -s "$tmp/up/new/cfg.json" "$tmp/up/cfg.json" || fail "upgrade-shipped did not place an absent file"
cp "$tmp/up/old" "$tmp/up/dst.json"
install_config "$tmp/up/dst.json" "$tmp/up/cfg.json" --upgrade-shipped "$tmp/up/shipped.sha256" >/dev/null
cmp -s "$tmp/up/dst.json" "$tmp/up/cfg.json" || fail "upgrade-shipped kept an unmodified shipped copy"
ls "$tmp/backups"/dst.json.* >/dev/null 2>&1 || fail "upgrade-shipped replaced without a backup"
printf 'v1\nmy edit\n' > "$tmp/up/edited.json"
out="$(install_config "$tmp/up/edited.json" "$tmp/up/cfg.json" --upgrade-shipped "$tmp/up/shipped.sha256")"
grep -qF "my edit" "$tmp/up/edited.json" || fail "upgrade-shipped clobbered a user edit"
grep -qF "diff $tmp/up/edited.json $tmp/up/cfg.json" <<< "$out" || fail "upgrade-shipped printed no diff hint"
cp "$tmp/up/old" "$tmp/up/other.json"
printf 'v2\n' > "$tmp/up/other-src.json"
install_config "$tmp/up/other.json" "$tmp/up/other-src.json" --upgrade-shipped "$tmp/up/shipped.sha256" >/dev/null
[[ "$(cat "$tmp/up/other.json")" == v1 ]] || fail "upgrade-shipped matched another file's hash"
pass "install_config --upgrade-shipped: place, upgrade unmodified, keep edited"

# 12. --shipped-name keys a tree by relative path: two files share a basename
#     (init.lua), and only the one whose key matches the hash is upgraded.
mkdir -p "$tmp/tree/src/lua" "$tmp/tree/dst/lua"
printf 'new root\n' > "$tmp/tree/src/init.lua"
printf 'new nested\n' > "$tmp/tree/src/lua/init.lua"
printf 'old\n' > "$tmp/tree/dst/init.lua"
printf 'old\n' > "$tmp/tree/dst/lua/init.lua"
printf 'lua/init.lua %s\n' "$(file_sha256 "$tmp/tree/dst/lua/init.lua")" > "$tmp/tree/shipped.sha256"
install_config "$tmp/tree/dst/init.lua" "$tmp/tree/src/init.lua" \
    --upgrade-shipped "$tmp/tree/shipped.sha256" --shipped-name init.lua >/dev/null
install_config "$tmp/tree/dst/lua/init.lua" "$tmp/tree/src/lua/init.lua" \
    --upgrade-shipped "$tmp/tree/shipped.sha256" --shipped-name lua/init.lua >/dev/null
[[ "$(cat "$tmp/tree/dst/init.lua")" == old ]] || fail "--shipped-name matched another path's hash"
[[ "$(cat "$tmp/tree/dst/lua/init.lua")" == "new nested" ]] || fail "--shipped-name did not upgrade its own key"
pass "install_config --shipped-name keys by relative path"

# 13. --merge-json: three-way merge of a user-edited JSON file.
if command -v jq >/dev/null 2>&1; then
    mj="$tmp/mj"
    mkdir -p "$mj"
    base_file="$TUIDEV_STATE_DIR/shipped/settings.json"
    hashes="$mj/shipped.sha256"
    # jq -e EXPR FILE: assert on a JSON file.
    jqt() { jq -e "$1" "$2" >/dev/null || fail "$3"; }
    nbackups() { find "$tmp/backups" -name "$1.*" 2>/dev/null | wc -l | tr -d ' '; }
    merge() { install_config "$1" "$2" --upgrade-shipped "$hashes" --shipped-name settings --merge-json; }

    # v1 is an old release, v2 the current one.
    cat > "$mj/v1.json" <<'JSON'
{
  "model": "old",
  "keep": 1,
  "legacy": true,
  "permissions": { "allow": ["Read", "Grep", "Old"], "deny": ["Read(~/.ssh/**)"] },
  "hooks": { "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "notify.sh" }] }] }
}
JSON
    cat > "$mj/v2.json" <<'JSON'
{
  "model": "new",
  "keep": 1,
  "permissions": { "allow": ["Read", "Grep", "New"], "deny": ["Read(~/.ssh/**)"] },
  "hooks": {
    "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "notify.sh" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "stop.sh" }] }]
  },
  "sandbox": { "enabled": true }
}
JSON
    printf 'settings %s\n' "$(file_sha256 "$mj/v1.json")" > "$hashes"

    # 13a. Absent: installed, and the base recorded.
    merge "$mj/a.json" "$mj/v2.json" >/dev/null
    cmp -s "$mj/a.json" "$mj/v2.json" || fail "merge-json did not place an absent file"
    cmp -s "$base_file" "$mj/v2.json" || fail "merge-json stored no base on install"
    rm -f "$base_file"
    pass "merge-json: absent -> installed, base stored"

    # 13b. An unmodified shipped copy: replaced (with a backup), base recorded.
    cp "$mj/v1.json" "$mj/b.json"
    merge "$mj/b.json" "$mj/v2.json" >/dev/null
    cmp -s "$mj/b.json" "$mj/v2.json" || fail "merge-json kept an unmodified shipped copy"
    [[ "$(nbackups b.json)" == 1 ]] || fail "merge-json replaced a shipped copy without a backup"
    cmp -s "$base_file" "$mj/v2.json" || fail "merge-json stored no base on replace"
    rm -f "$base_file"
    pass "merge-json: shipped copy -> replaced, base stored"

    # 13c. Edited, no base (installs that predate --merge-json): additions
    #      only. New keys and list entries arrive; every user value stays,
    #      including ones upstream changed or dropped since.
    jq '.model = "mine" | .mykey = "x" | .permissions.allow += ["Mine"]' "$mj/v1.json" > "$mj/c.json"
    out="$(merge "$mj/c.json" "$mj/v2.json")"
    jqt '.sandbox.enabled == true' "$mj/c.json" "no-base merge did not add a new key"
    jqt '.hooks.Stop | length == 1' "$mj/c.json" "no-base merge did not add a new hook"
    jqt '.permissions.allow == ["Read", "Grep", "Old", "Mine", "New"]' "$mj/c.json" \
        "no-base merge: wrong allow list"
    jqt '.model == "mine" and .mykey == "x" and .legacy == true' "$mj/c.json" \
        "no-base merge changed or removed a user value"
    grep -qF "additions only" <<< "$out" || fail "no-base merge did not say additions only"
    cmp -s "$base_file" "$mj/v2.json" || fail "merge-json stored no base after a merge"
    [[ "$(nbackups c.json)" == 1 ]] || fail "merge-json wrote without a backup"
    pass "merge-json: edited, no base -> additions only, backup, base stored"

    # 13d. Edited, with a base: a three-way merge.
    cp "$mj/v1.json" "$base_file"
    jq '.keep = 2 | .permissions.allow = ["Mine", "Read", "Grep", "Old", "Mine2"]
        | .hooks.Notification += [{ "matcher": "x", "hooks": [] }]' "$mj/v1.json" > "$mj/d.json"
    out="$(merge "$mj/d.json" "$mj/v2.json")"
    jqt '.permissions.allow == ["Mine", "Read", "Grep", "Mine2", "New"]' "$mj/d.json" \
        "three-way merge: wrong allow list (upstream removal, user entries in place, new entry)"
    jqt '.model == "new"' "$mj/d.json" "three-way merge: an untouched value did not follow upstream"
    jqt 'has("legacy") | not' "$mj/d.json" "three-way merge: a key removed upstream survived"
    jqt '.keep == 2' "$mj/d.json" "three-way merge: a user-changed value was not kept"
    jqt '.hooks.Notification | length == 2' "$mj/d.json" "three-way merge: hooks duplicated or lost"
    jqt '.hooks.Stop | length == 1' "$mj/d.json" "three-way merge: new hook missing"
    jqt '.sandbox.enabled == true' "$mj/d.json" "three-way merge: new key missing"
    # keep: the user changed it (1 -> 2) and so did upstream (1 -> 3).
    jq '.keep = 3' "$mj/v2.json" > "$mj/v3.json"
    cp "$mj/v2.json" "$base_file"
    out="$(merge "$mj/d.json" "$mj/v3.json")"
    jqt '.keep == 2' "$mj/d.json" "conflict: the user value was not kept"
    grep -qF "different one: keep" <<< "$out" || fail "conflict not reported"
    tuidev_json_merge3_conflicts "$mj/v2.json" "$mj/d.json" "$mj/v3.json" | grep -qx keep \
        || fail "tuidev_json_merge3_conflicts did not list keep"
    cmp -s "$base_file" "$mj/v3.json" || fail "base did not advance past a conflict"
    pass "merge-json: edited, with base -> three-way merge, conflict reported"

    # 13e. A key the user deleted stays deleted, even if upstream changed it
    #      (reported); one upstream left alone stays deleted silently.
    jq 'del(.model, .keep)' "$mj/v1.json" > "$mj/e.json"
    cp "$mj/v1.json" "$base_file"
    out="$(merge "$mj/e.json" "$mj/v2.json")"
    jqt 'has("model") or has("keep") | not' "$mj/e.json" "a key the user deleted came back"
    # Exactly one conflict: model. keep (upstream unchanged) is no conflict.
    grep -qF "different one: model (compare" <<< "$out" || fail "deleted-vs-changed conflict not reported"
    pass "merge-json: user deletions stick"

    # 13f. Merged == ours: no write, no backup; the base still advances.
    #      d.json already holds v3's changes, except `keep`, which the user
    #      changed: a conflict, so the merge is d.json itself.
    cp "$mj/d.json" "$mj/f.json"
    touch -t 202001010000 "$mj/f.json"
    cp "$mj/v2.json" "$base_file"
    before="$(nbackups f.json)"
    out="$(merge "$mj/f.json" "$mj/v3.json")"
    cmp -s "$mj/f.json" "$mj/d.json" || fail "merged == ours still rewrote the file"
    [[ -z "$(find "$mj/f.json" -newer "$mj/v3.json")" ]] || fail "merged == ours touched the file"
    [[ "$(nbackups f.json)" == "$before" ]] || fail "merged == ours made a backup"
    grep -qF "up to date" <<< "$out" || fail "merged == ours did not say up to date"
    cmp -s "$base_file" "$mj/v3.json" || fail "merged == ours did not advance the base"
    pass "merge-json: nothing to merge -> no write, no backup, base advances"

    # 13g. DRY_RUN: neither DEST nor the base changes.
    jq '.model = "mine"' "$mj/v1.json" > "$mj/g.json"
    cp "$mj/g.json" "$mj/g.orig"
    cp "$mj/v1.json" "$base_file"
    out="$(DRY_RUN=true merge "$mj/g.json" "$mj/v2.json")"
    cmp -s "$mj/g.json" "$mj/g.orig" || fail "dry-run merge wrote DEST"
    cmp -s "$base_file" "$mj/v1.json" || fail "dry-run merge moved the base"
    [[ "$(nbackups g.json)" == 0 ]] || fail "dry-run merge made a backup"
    grep -qF "DRY RUN" <<< "$out" || fail "dry-run merge printed no preview"
    rm -f "$base_file"
    out="$(DRY_RUN=true merge "$mj/g-new.json" "$mj/v2.json")"
    [[ ! -e "$mj/g-new.json" && ! -e "$base_file" ]] || fail "dry-run install wrote DEST or the base"
    pass "merge-json: dry-run writes nothing"

    # 13h. Invalid JSON in DEST: untouched, with a warning; no base recorded.
    printf '{ "model": "mine", // a comment\n}\n' > "$mj/h.json"
    cp "$mj/h.json" "$mj/h.orig"
    out="$(merge "$mj/h.json" "$mj/v2.json")"
    cmp -s "$mj/h.json" "$mj/h.orig" || fail "invalid DEST was rewritten"
    grep -qF "not valid JSON" <<< "$out" || fail "invalid DEST: no warning"
    [[ ! -e "$base_file" ]] || fail "invalid DEST: base recorded anyway"
    pass "merge-json: invalid JSON is kept, with a warning"

    # 13j. A symlinked DEST (dotfiles): the backup is a regular file holding
    #      the pre-merge content, the link stays a link, the target keeps its
    #      mode and receives the merge.
    mkdir -p "$mj/dotfiles"
    jq '.model = "mine"' "$mj/v1.json" > "$mj/dotfiles/settings.json"
    chmod 600 "$mj/dotfiles/settings.json"
    cp "$mj/dotfiles/settings.json" "$mj/j.orig"
    ln -s "$mj/dotfiles/settings.json" "$mj/j.json"
    cp "$mj/v1.json" "$base_file"
    merge "$mj/j.json" "$mj/v2.json" >/dev/null
    [[ -L "$mj/j.json" ]] || fail "symlinked DEST: the link was replaced"
    jqt '.sandbox.enabled == true and .model == "mine"' "$mj/dotfiles/settings.json" \
        "symlinked DEST: the link target did not receive the merge"
    [[ "$(file_mode "$mj/dotfiles/settings.json")" == 600 ]] || fail "symlinked DEST: mode not kept"
    bk="$(find "$tmp/backups" -name 'j.json.*' | head -n 1)"
    [[ -n "$bk" && -f "$bk" && ! -L "$bk" ]] || fail "symlinked DEST: the backup is not a regular file"
    cmp -s "$bk" "$mj/j.orig" || fail "symlinked DEST: the backup does not hold the pre-merge content"
    [[ "$(file_mode "$bk")" == 600 ]] || fail "symlinked DEST: the backup lost the mode"
    pass "merge-json: symlinked DEST -> real backup, link kept, target merged"

    # 13k. A failed backup: nothing is written and the base stays put.
    jq '.model = "mine"' "$mj/v1.json" > "$mj/k.json"
    cp "$mj/k.json" "$mj/k.orig"
    cp "$mj/v1.json" "$base_file"
    : > "$mj/blocker"    # a file where the backup dir would have to go
    out="$(TUIDEV_BACKUP_DIR="$mj/blocker/backups" merge "$mj/k.json" "$mj/v2.json" 2>/dev/null)"
    cmp -s "$mj/k.json" "$mj/k.orig" || fail "failed backup: DEST was written anyway"
    cmp -s "$base_file" "$mj/v1.json" || fail "failed backup: the base moved"
    grep -qF "could not back up" <<< "$out" || fail "failed backup: no warning"
    pass "merge-json: a failed backup writes nothing"

    # 13l. A merge into a user-owned file does not record it in the manifest,
    #      so uninstall.sh leaves it alone.
    (
        export TUIDEV_MANIFEST_FILE="$tmp/state/manifest"
        tuidev_manifest_enable
        jq '.model = "mine"' "$mj/v1.json" > "$mj/l.json"
        cp "$mj/v1.json" "$base_file"
        merge "$mj/l.json" "$mj/v2.json" >/dev/null
        jqt '.sandbox.enabled == true' "$mj/l.json" "manifest case: no merge happened"
        if tuidev_manifest_has file "$mj/l.json"; then
            fail "a merge recorded a user-owned file in the manifest"
        fi
    )
    pass "merge-json: a merged user file is not recorded in the manifest"

    # 13i. --merge-json without --upgrade-shipped is refused.
    install_config "$mj/i.json" "$mj/v2.json" --overwrite --merge-json >/dev/null \
        && fail "--merge-json without --upgrade-shipped was accepted"
    [[ ! -e "$mj/i.json" ]] || fail "refused --merge-json still wrote"
    pass "merge-json: needs --upgrade-shipped"
else
    echo "SKIP: --merge-json tests (jq not installed)"
fi

echo ""
echo "All config_write tests passed."
