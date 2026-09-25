#!/bin/bash
# Unit tests for scripts/lib/gitconfig.sh.
# Run: bash scripts/lib/test_gitconfig.sh  -> exit 0 on pass.
#
# Everything runs against a throwaway HOME; the real ~/.gitconfig is never read
# or written (GIT_CONFIG_NOSYSTEM keeps the system file out as well).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" TUIDEV_NO_COLOR=1 GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL
mkdir -p "$HOME"
TUIDEV_STATE_DIR="$HOME/.config/tuidev"
export TUIDEV_MANIFEST_FILE="$TUIDEV_STATE_DIR/manifest"

# shellcheck source=./ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"
# shellcheck source=./manifest.sh disable=SC1091
. "$SCRIPT_DIR/manifest.sh"
# shellcheck source=./gitconfig.sh disable=SC1091
. "$SCRIPT_DIR/gitconfig.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
get() { git config --global --includes --get "$1" 2>/dev/null || true; }

# 1. DRY_RUN writes nothing.
DRY_RUN=true tuidev_git_defaults >/dev/null
[[ ! -f "$HOME/.gitconfig" ]] || fail "DRY_RUN wrote ~/.gitconfig"
pass "dry run writes nothing"

# 2. A value the user set — directly or through an [include] — is never touched.
printf '[pager]\n' > "$HOME/.gitconfig.inc"
git config --file "$HOME/.gitconfig.inc" diff.algorithm patience
git config --global include.path "$HOME/.gitconfig.inc"
git config --global rerere.enabled false
tuidev_manifest_enable
tuidev_git_defaults >/dev/null
[[ "$(get diff.algorithm)" == patience ]] || fail "included diff.algorithm overridden: $(get diff.algorithm)"
[[ "$(get rerere.enabled)" == false ]] || fail "user rerere.enabled overridden"
[[ "$(git config --global --no-includes --get diff.algorithm || true)" == "" ]] \
    || fail "wrote diff.algorithm into ~/.gitconfig despite the include"
pass "user values (direct and [include]d) win"

# 3. Unset keys get the default and are recorded for uninstall.
[[ "$(get rebase.updateRefs)" == true ]] || fail "rebase.updateRefs not set"
[[ "$(get push.autoSetupRemote)" == true ]] || fail "push.autoSetupRemote not set"
tuidev_manifest_values gitconfig | grep -q '^rebase.updateRefs true$' || fail "set key not recorded"
tuidev_manifest_values gitconfig | grep -q '^diff.algorithm ' && fail "recorded a key it did not set"
pass "unset keys are defaulted and recorded"

# 4. Idempotent: a second run changes nothing.
before="$(cat "$HOME/.gitconfig")"
tuidev_git_defaults >/dev/null
[[ "$(cat "$HOME/.gitconfig")" == "$before" ]] || fail "second run changed ~/.gitconfig"
pass "re-run is a no-op"

echo ""
echo "All gitconfig lib tests passed."
