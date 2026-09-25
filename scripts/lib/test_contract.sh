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
    # Pack-owned blocks (Ghostty, SSH) are re-applied by re-running their
    # pack, not by update.sh's cross-cutting drift list.
    case "$id" in
        tuidev-ghostty|tuidev-remote) continue ;;
    esac
    if ! grep -qF "|$id\"" "$REPO_DIR/scripts/update.sh"; then
        fail "install.sh writes managed-block '$id' but update.sh MANAGED_BLOCKS doesn't list it"
    fi
done
pass "managed-block IDs are consistent between installer and updater"

# 2. Seatbelt paths: update.sh's security audit must compare the same source
#    and destination the sandbox pack installs.
if ! grep -qF 'configs/sandbox/profiles' "$REPO_DIR/scripts/update.sh"; then
    fail "update.sh should audit configs/sandbox/profiles (what install.sh writes)"
fi
for f in scripts/update.sh scripts/install/sandbox.sh; do
    # shellcheck disable=SC2016  # the literal variable name is what we grep for
    grep -qF '$TUIDEV_STATE_DIR/sandbox' "$REPO_DIR/$f" \
        || fail "$f should use \$TUIDEV_STATE_DIR/sandbox for the installed profiles"
done
pass "Seatbelt audit paths match installer"

# 3. Every pack name advertised in README/docs must have a script.
#    Packs live at scripts/install/packs/<name>.sh. The five "first-class"
#    packs (core/remote/sandbox/ui/extras) live at scripts/install/<name>.sh
#    and are invoked via --<name>, not --pack <name>, so they're excluded.
FIRSTCLASS_PACKS="core remote sandbox ui extras"

DOCS_PACKS="$(grep -hoE -- '--pack [a-z][a-z0-9-]+' "$REPO_DIR"/{README.md,install.sh,docs/profiles.md} 2>/dev/null \
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

# 4. TUIDEV_VALID_PACKS and scripts/install/packs/ agree, and every pack
#    defines the entrypoint packs.sh will call.
# shellcheck source=./packs.sh disable=SC1091
. "$SCRIPT_DIR/packs.sh"
for pack in "${TUIDEV_BUILTIN_PACKS[@]}" "${TUIDEV_VALID_PACKS[@]}"; do
    script="$(pack_script "$pack")" || fail "pack '$pack' has no script"
    grep -qE "^$(pack_entrypoint "$pack")\(\)" "$script" \
        || fail "$script does not define $(pack_entrypoint "$pack")()"
done
for script in "$REPO_DIR"/scripts/install/packs/*.sh; do
    tuidev_is_valid_pack "$(basename "$script" .sh)" \
        || fail "$script is not registered in TUIDEV_VALID_PACKS (scripts/lib/profile.sh)"
done
pass "every pack is registered, has a script, and defines its entrypoint"

# Every shipped config the installer upgrades-if-unmodified (install_config
# --upgrade-shipped) is fingerprinted, so it can tell an unmodified old copy
# (upgrade it) from one the user edited (leave it alone). Each hash file lists
# `<basename without extension> <sha256>` for every version ever shipped.
# shellcheck source=./ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"
check_fingerprinted() {
    local shipped="$1" src name; shift
    [[ -f "$shipped" ]] || fail "missing ${shipped#"$REPO_DIR"/}"
    for src in "$@"; do
        name="$(basename "$src")"; name="${name%.*}"
        grep -qx "$name $(file_sha256 "$src")" "$shipped" \
            || fail "${src#"$REPO_DIR"/} changed but its hash is not in ${shipped#"$REPO_DIR"/} (append: $name $(file_sha256 "$src"))"
    done
}
check_fingerprinted "$REPO_DIR/configs/sandbox/profiles/shipped.sha256" "$REPO_DIR"/configs/sandbox/profiles/*.sb
check_fingerprinted "$REPO_DIR/configs/claude/shipped.sha256" "$REPO_DIR/configs/claude/settings.json"
# settings.linux.json is installed with --shipped-name settings.
grep -qx "settings $(file_sha256 "$REPO_DIR/configs/claude/settings.linux.json")" "$REPO_DIR/configs/claude/shipped.sha256" \
    || fail "configs/claude/settings.linux.json changed but its hash is not in configs/claude/shipped.sha256 (append: settings $(file_sha256 "$REPO_DIR/configs/claude/settings.linux.json"))"
check_fingerprinted "$REPO_DIR/configs/codex/shipped.sha256"  "$REPO_DIR/configs/codex/config.toml"
check_fingerprinted "$REPO_DIR/configs/vim/shipped.sha256"    "$REPO_DIR/configs/vim/vimrc"
# nvim is a tree: keyed by path relative to configs/nvim (two init.lua files).
nvim_root="$REPO_DIR/configs/nvim"
while IFS= read -r src; do
    rel="${src#"$nvim_root"/}"
    [[ "$rel" == shipped.sha256 ]] && continue
    grep -qx "$rel $(file_sha256 "$src")" "$nvim_root/shipped.sha256" \
        || fail "configs/nvim/$rel changed but its hash is not in configs/nvim/shipped.sha256 (append: $rel $(file_sha256 "$src"))"
done < <(find "$nvim_root" -type f -not -name '.*')
# And every --upgrade-shipped call site points at one of those hash files.
while IFS= read -r ref; do
    [[ -f "$REPO_DIR/$ref" ]] || fail "--upgrade-shipped names $ref, which does not exist"
done < <(grep -rhoE 'configs/[a-z/]+/shipped\.sha256' "$REPO_DIR/scripts/install" | sort -u)
pass "every shipped-config version is fingerprinted (sandbox, claude, codex, vim, nvim)"

# Claude Code's Linux sandbox enforces literal paths and whole directories
# (a trailing /**). Any other glob in a Read/Edit rule makes it walk the whole
# project for matches, repeatedly, which stalls the TUI on a large repo. Only
# the macOS settings.json may keep the **/.env rules (Seatbelt matches them
# natively); settings.linux.json spells them as literal paths.
check_linux_safe_rules() {
    local file="$1" allow_env="$2" rule path
    while IFS= read -r rule; do
        path="${rule#*(}"; path="${path%)}"
        if [[ "$allow_env" == true ]]; then
            case "$path" in **/.env|**/.env.*) continue ;; esac
        fi
        path="${path%/\*\*}"
        case "$path" in *'*'*|*'?'*|*'['*) fail "${file#"$REPO_DIR"/}: $rule uses a glob Claude Code's Linux sandbox can't enforce (use literal paths or a trailing /**)" ;; esac
    done < <(grep -oE '"(Read|Edit)\([^)]*\)"' "$file" | tr -d '"')
}
check_linux_safe_rules "$REPO_DIR/configs/claude/settings.json" true
check_linux_safe_rules "$REPO_DIR/configs/claude/settings.linux.json" false
pass "Claude Read/Edit rules use only globs the Linux sandbox supports"

# The Linux settings differ from the macOS ones only in the .env deny rules,
# and those are the full literal set (9 names, Read and Edit each).
env_rule='^[[:space:]]*"(Read|Edit)\((\*\*|\.)/\.env[^"]*\)",?$'
[[ "$(grep -cE '^[[:space:]]*"(Read|Edit)\(\./\.env[^"]*\)",?$' "$REPO_DIR/configs/claude/settings.linux.json")" == 18 ]] \
    || fail "configs/claude/settings.linux.json must deny the 18 literal ./.env* Read/Edit rules"
[[ "$(grep -vE "$env_rule" "$REPO_DIR/configs/claude/settings.json")" \
   == "$(grep -vE "$env_rule" "$REPO_DIR/configs/claude/settings.linux.json")" ]] \
    || fail "configs/claude/settings.linux.json drifted from settings.json beyond the .env rules"
pass "configs/claude/settings.linux.json mirrors settings.json apart from the .env rules"

echo ""
echo "All cross-file contract tests passed."
