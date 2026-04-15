#!/bin/bash
# scripts/lib/test_contract.sh - regression tests that guard cross-file contracts.
#
# Run: bash scripts/lib/test_contract.sh  -> exit 0 on pass.
#
# Rationale: the installer writes configs under specific block IDs and paths,
# and the updater reads them back. Those names must match or "drift detection"
# silently misreports. This test file enforces the contract so parallel edits
# can't quietly break it.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# 1. Managed-block IDs: every ID install.sh writes must appear in
#    update.sh's MANAGED_BLOCKS list so drift-detection can find them.
INSTALL_IDS="$(grep -hE -- '--managed-block' "$REPO_DIR/install.sh" "$REPO_DIR/scripts/install/"*.sh "$REPO_DIR/scripts/install/packs/"*.sh 2>/dev/null \
    | grep -oE '\-\-managed-block [a-z][a-z0-9-]+' \
    | awk '{print $2}' | sort -u)"

for id in $INSTALL_IDS; do
    # Skip IDs that are only written by pack scripts (not cross-cutting).
    # For now, tuidev-sandbox-path is written by scripts/install/sandbox.sh
    # and isn't in the cross-cutting drift list — that's intentional
    # (it's a pure PATH export, not a repo-backed config).
    case "$id" in
        tuidev-sandbox-path|tuidev-ghostty|tuidev-hammerspoon|tuidev-remote|tuidev-zellij*) continue ;;
    esac
    if ! grep -qF "|$id\"" "$REPO_DIR/scripts/update.sh"; then
        fail "install.sh writes managed-block '$id' but update.sh MANAGED_BLOCKS doesn't list it"
    fi
done
pass "managed-block IDs are consistent between installer and updater"

# 2. Seatbelt paths: update.sh security audit must point at the same paths
#    the installer uses (configs/sandbox/profiles, ~/.config/tuidev/sandbox).
if ! grep -qF 'configs/sandbox/profiles' "$REPO_DIR/scripts/update.sh"; then
    fail "update.sh should audit configs/sandbox/profiles (what install.sh writes)"
fi
if ! grep -qF '/tuidev/sandbox' "$REPO_DIR/scripts/update.sh"; then
    fail "update.sh should audit ~/.config/tuidev/sandbox (where install.sh deploys)"
fi
pass "Seatbelt audit paths match installer"

# 3. Every pack name advertised in README/docs must have a script.
#    Packs live at scripts/install/packs/<name>.sh. The five "first-class"
#    packs (core/remote/sandbox/ui/extras) live at scripts/install/<name>.sh
#    and are invoked via --<name>, not --pack <name>, so they're excluded.
FIRSTCLASS_PACKS="core remote sandbox ui extras"

DOCS_PACKS="$(grep -hoE -- '--pack [a-z][a-z0-9-]+' "$REPO_DIR"/{README.md,install.sh,docs/profiles.md,docs/migration.md} 2>/dev/null \
    | awk '{print $2}' | sort -u)"

for pack in $DOCS_PACKS; do
    [[ "$pack" == "NAME" ]] && continue
    # Skip first-class packs that happen to also appear via --pack doc wording.
    case " $FIRSTCLASS_PACKS " in *" $pack "*) continue;; esac
    if [[ ! -f "$REPO_DIR/scripts/install/packs/$pack.sh" ]]; then
        fail "docs advertise --pack $pack but scripts/install/packs/$pack.sh is missing"
    fi
done
pass "every documented --pack NAME has a script"

echo ""
echo "All cross-file contract tests passed."
