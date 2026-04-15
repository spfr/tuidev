#!/bin/bash
# Unit tests for scripts/lib/profile.sh.
# Run: bash scripts/lib/test_profile.sh  -> exit 0 on pass.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./profile.sh disable=SC1091
. "$SCRIPT_DIR/profile.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# 1. Missing file returns 1 and resets all globals
load_tuidev_profile "$tmp/nope" && fail "missing file should return 1"
[[ "$TUIDEV_PROFILE_NAME" == "" ]] || fail "name should be empty"
[[ "$TUIDEV_PACK_CORE" == false ]] || fail "core should be false"
[[ "$TUIDEV_PROFILE_FOUND" == false ]] || fail "found should be false"
pass "missing file returns 1 + resets globals"

# 2. Full desktop manifest
cat > "$tmp/desktop" <<'EOF'
profile=desktop
core=true
remote=false
sandbox=true
ui=true
extras=false
extra_packs=zellij yazi
installed_at=2026-04-14T12:00:00Z
repo=/tmp/fake-repo
EOF
load_tuidev_profile "$tmp/desktop" || fail "should return 0 on valid file"
[[ "$TUIDEV_PROFILE_NAME" == "desktop" ]] || fail "profile name: $TUIDEV_PROFILE_NAME"
[[ "$TUIDEV_PACK_CORE" == true ]]    || fail "core"
[[ "$TUIDEV_PACK_REMOTE" == false ]] || fail "remote"
[[ "$TUIDEV_PACK_SANDBOX" == true ]] || fail "sandbox"
[[ "$TUIDEV_PACK_UI" == true ]]      || fail "ui"
[[ "$TUIDEV_PACK_EXTRAS" == false ]] || fail "extras"
[[ "$TUIDEV_EXTRA_PACKS" == "zellij yazi" ]] || fail "extra_packs: '$TUIDEV_EXTRA_PACKS'"
[[ "${TUIDEV_EXTRA_PACKS_ARR[0]}" == "zellij" ]] || fail "arr[0]"
[[ "${TUIDEV_EXTRA_PACKS_ARR[1]}" == "yazi" ]] || fail "arr[1]"
[[ "$TUIDEV_PROFILE_INSTALLED_AT" == "2026-04-14T12:00:00Z" ]] || fail "installed_at"
[[ "$TUIDEV_PROFILE_REPO" == "/tmp/fake-repo" ]] || fail "repo"
[[ "$TUIDEV_REPO" == "/tmp/fake-repo" ]] || fail "TUIDEV_REPO exported"
pass "desktop manifest parsed"

# 3. Comma-separated extra_packs
cat > "$tmp/commas" <<'EOF'
profile=desktop
core=true
extra_packs=zellij,yazi,monitoring
EOF
load_tuidev_profile "$tmp/commas"
[[ "${#TUIDEV_EXTRA_PACKS_ARR[@]}" == 3 ]] || fail "comma-separated: got ${#TUIDEV_EXTRA_PACKS_ARR[@]}"
[[ "${TUIDEV_EXTRA_PACKS_ARR[2]}" == "monitoring" ]] || fail "comma[2]"
pass "comma-separated extra_packs"

# 4. Comments and blanks ignored
cat > "$tmp/comments" <<'EOF'
# this is a comment
profile=minimal  # trailing comment

core=true
EOF
load_tuidev_profile "$tmp/comments"
[[ "$TUIDEV_PROFILE_NAME" == "minimal" ]] || fail "comments: '$TUIDEV_PROFILE_NAME'"
[[ "$TUIDEV_PACK_CORE" == true ]] || fail "core after comments"
pass "comments + blanks ignored"

# 5. Quoted values unwrapped
cat > "$tmp/quoted" <<'EOF'
profile="remote"
repo='/path/with spaces/ok'
EOF
load_tuidev_profile "$tmp/quoted"
[[ "$TUIDEV_PROFILE_NAME" == "remote" ]] || fail "quoted profile: '$TUIDEV_PROFILE_NAME'"
[[ "$TUIDEV_PROFILE_REPO" == "/path/with spaces/ok" ]] || fail "quoted repo: '$TUIDEV_PROFILE_REPO'"
pass "quoted values unwrapped"

# 6. tuidev_active_packs returns expected set
load_tuidev_profile "$tmp/desktop"
got="$(tuidev_active_packs | tr '\n' ' ')"
[[ "$got" == "core sandbox ui zellij yazi " ]] || fail "active_packs: '$got'"
pass "tuidev_active_packs"

# 7. Valid profile check
tuidev_is_valid_profile "desktop" || fail "desktop should be valid"
tuidev_is_valid_profile "nonsense" && fail "nonsense should be invalid"
pass "tuidev_is_valid_profile"

# 8. Legacy key:value syntax tolerated
cat > "$tmp/legacy" <<'EOF'
profile: desktop
core: true
EOF
load_tuidev_profile "$tmp/legacy"
[[ "$TUIDEV_PROFILE_NAME" == "desktop" ]] || fail "legacy profile: '$TUIDEV_PROFILE_NAME'"
[[ "$TUIDEV_PACK_CORE" == true ]] || fail "legacy core"
pass "legacy key:value tolerated"

echo ""
echo "All profile-lib tests passed."
