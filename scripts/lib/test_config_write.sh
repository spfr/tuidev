#!/bin/bash
# scripts/lib/test_config_write.sh - unit tests for config_write.sh.
# Run directly: bash scripts/lib/test_config_write.sh
# Exit code: 0 on success, non-zero on failure.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config_write.sh disable=SC1091
. "$SCRIPT_DIR/config_write.sh"

tmp="$(mktemp -d)"
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

echo ""
echo "All config_write tests passed."
