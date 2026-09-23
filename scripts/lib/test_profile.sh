#!/bin/bash
# Unit tests for scripts/lib/profile.sh.
# Run: bash scripts/lib/test_profile.sh  -> exit 0 on pass.

set -e
unset XDG_CONFIG_HOME

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
extra_packs=herdr tmux
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
[[ "$TUIDEV_EXTRA_PACKS" == "herdr tmux" ]] || fail "extra_packs: '$TUIDEV_EXTRA_PACKS'"
[[ "${TUIDEV_EXTRA_PACKS_ARR[0]}" == "herdr" ]] || fail "arr[0]"
[[ "${TUIDEV_EXTRA_PACKS_ARR[1]}" == "tmux" ]] || fail "arr[1]"
[[ "$TUIDEV_PROFILE_INSTALLED_AT" == "2026-04-14T12:00:00Z" ]] || fail "installed_at"
[[ "$TUIDEV_PROFILE_REPO" == "/tmp/fake-repo" ]] || fail "repo"
[[ "$TUIDEV_REPO" == "/tmp/fake-repo" ]] || fail "TUIDEV_REPO exported"
pass "desktop manifest parsed"

# 3. Comma-separated extra_packs
cat > "$tmp/commas" <<'EOF'
profile=desktop
core=true
extra_packs=herdr,tmux,monitoring
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
[[ "$got" == "core sandbox ui herdr tmux " ]] || fail "active_packs: '$got'"
pass "tuidev_active_packs"

# 6b. The remote profile implies --pack tmux, once, even when extra_packs predates it.
printf 'profile=remote\ncore=true\nremote=true\nextra_packs=herdr\n' > "$tmp/remote"
load_tuidev_profile "$tmp/remote"
got="$(tuidev_active_packs | tr '\n' ' ')"
[[ "$got" == "core remote herdr tmux " ]] || fail "remote active_packs: '$got'"
printf 'profile=remote\nextra_packs=tmux herdr\n' > "$tmp/remote"
load_tuidev_profile "$tmp/remote"
[[ "$(tuidev_extra_packs | tr '\n' ' ')" == "tmux herdr " ]] || fail "remote tmux listed twice"
load_tuidev_profile "$tmp/comments"
[[ -z "$(tuidev_extra_packs)" ]] || fail "minimal should have no optional packs"
[[ "$(tuidev_extra_packs remote)" == "tmux" ]] || fail "PROFILE argument"
pass "tuidev_extra_packs: remote implies tmux"

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

# 9. tuidev_is_valid_pack
tuidev_is_valid_pack sandbox-container || fail "sandbox-container should be valid"
tuidev_is_valid_pack core && fail "core is a built-in pack, not a --pack name"
pass "tuidev_is_valid_pack"

# 10. tuidev_profile_write round-trips what load_tuidev_profile reads
load_tuidev_profile "$tmp/desktop"
TUIDEV_EXTRA_PACKS="herdr tmux fnm"
tuidev_profile_write "$tmp/written" >/dev/null
load_tuidev_profile "$tmp/written"
[[ "$TUIDEV_PROFILE_NAME" == desktop && "$TUIDEV_PACK_UI" == true && "$TUIDEV_PACK_REMOTE" == false ]] \
    || fail "write round-trip flags"
[[ "$TUIDEV_EXTRA_PACKS" == "herdr tmux fnm" ]] || fail "write round-trip packs: '$TUIDEV_EXTRA_PACKS'"
[[ "$TUIDEV_PROFILE_REPO" == "/tmp/fake-repo" ]] || fail "write round-trip repo"
DRY_RUN=true tuidev_profile_write "$tmp/dry" >/dev/null
[[ ! -e "$tmp/dry" ]] || fail "write under DRY_RUN created a file"
pass "tuidev_profile_write round-trip + dry-run"

# 11. add/remove edit only extra_packs; every other line survives verbatim
printf '# keep me\nprofile=remote\nextra_packs=ai-clis,herdr\nunknown=kept\n' > "$tmp/edit"
tuidev_profile_add_pack opencode "$tmp/edit" || fail "add should report a change"
grep -qx 'extra_packs=ai-clis herdr opencode' "$tmp/edit" || fail "add: $(grep extra_packs "$tmp/edit")"
tuidev_profile_add_pack opencode "$tmp/edit" && fail "second add should report no change"
tuidev_profile_remove_pack herdr "$tmp/edit" || fail "remove should report a change"
grep -qx 'extra_packs=ai-clis opencode' "$tmp/edit" || fail "remove: $(grep extra_packs "$tmp/edit")"
tuidev_profile_remove_pack zellij "$tmp/edit" && fail "removing an absent pack should report no change"
grep -qx '# keep me' "$tmp/edit"   || fail "add/remove dropped a comment line"
grep -qx 'unknown=kept' "$tmp/edit" || fail "add/remove dropped an unknown key"
[[ "$(grep -c '^extra_packs=' "$tmp/edit")" == 1 ]] || fail "duplicate extra_packs lines"
set +e; tuidev_profile_add_pack x "$tmp/missing"; rc=$?; set -e
[[ $rc == 2 ]] || fail "missing profile should return 2, got $rc"
pass "tuidev_profile_add_pack / remove_pack are surgical"

echo ""
echo "All profile-lib tests passed."
