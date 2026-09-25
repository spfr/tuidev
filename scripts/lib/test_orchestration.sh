#!/bin/bash
# Unit tests for scripts/install/packs/orchestration.sh.
# Run: bash scripts/lib/test_orchestration.sh  -> exit 0 on pass.
#
# Everything runs against a throwaway HOME (with a space in its path); the real
# ~/.claude, ~/.codex and ~/.agents are never read or written.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/my home" TUIDEV_NO_COLOR=1
mkdir -p "$HOME"
export TUIDEV_STATE_DIR="$HOME/.config/tuidev"

# shellcheck source=../install/packs/orchestration.sh disable=SC1091
. "$REPO_DIR/scripts/install/packs/orchestration.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# A fake agents-orchestration checkout, under a path that itself has /build/ in it.
legacy="$tmp/build/agents orchestration"
mkdir -p "$legacy/core" "$legacy/build/skills/delegation" "$legacy/claude/agents"
echo "marker" > "$legacy/core/00-orchestration.md"
echo "legacy policy" > "$legacy/build/CLAUDE.md"
echo "legacy skill" > "$legacy/build/skills/delegation/SKILL.md"
echo "legacy reviewer" > "$legacy/claude/agents/reviewer.md"
dots="$tmp/dots"
mkdir -p "$dots"
echo "my executor" > "$dots/executor.md"

# 1. Classification.
mkdir -p "$HOME/links" "$HOME/rel/x" "$HOME/dots/claude/agents"
echo "mine" > "$HOME/dots/claude/agents/executor.md"
ln -s "$legacy/build/CLAUDE.md" "$HOME/links/abs"
ln -s "/gone/agents-orchestration/build/AGENTS.md" "$HOME/links/dangling"
# Relative, agent-shaped, and resolvable only from the link's own directory.
ln -s "../../dots/claude/agents/executor.md" "$HOME/rel/x/executor.md"
ln -s "$dots/executor.md" "$HOME/links/user"
_orchestration_is_legacy_link "$HOME/links/abs"      || fail "absolute legacy link not detected (checkout path has /build/)"
_orchestration_is_legacy_link "$HOME/links/dangling" || fail "dangling legacy link not detected"
! _orchestration_is_legacy_link "$HOME/rel/x/executor.md" || fail "relative link treated as legacy"
! _orchestration_is_legacy_link "$HOME/links/user"   || fail "user's absolute link treated as legacy"
pass "legacy links are told apart from the user's own"

# 2. Dry run writes nothing.
rm -rf "$HOME/links" "$HOME/rel" "$HOME/dots"
DRY_RUN=true orchestration_install >/dev/null
[[ -z "$(find "$HOME" -type f)" ]] || fail "dry run wrote files"
pass "dry run writes nothing"

# 3. A full install: legacy links go (and the user's pre-link file comes
#    back), user links and text stay, nothing is written through a link.
mkdir -p "$HOME/.claude/agents" "$HOME/.claude/skills/delegation" "$HOME/.codex"
ln -s "$legacy/build/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
echo "my claude notes" > "$HOME/.claude/CLAUDE.md.bak"
ln -s "$legacy/build/skills/delegation/SKILL.md" "$HOME/.claude/skills/delegation/SKILL.md"
ln -s "$legacy/claude/agents/reviewer.md" "$HOME/.claude/agents/reviewer.md"
ln -s "$dots/executor.md" "$HOME/.claude/agents/executor.md"
echo "my codex notes" > "$HOME/.codex/AGENTS.md"
orchestration_install >/dev/null

[[ "$(cat "$legacy/build/CLAUDE.md")" == "legacy policy" ]] || fail "wrote through the legacy CLAUDE.md link"
[[ "$(cat "$legacy/build/skills/delegation/SKILL.md")" == "legacy skill" ]] || fail "wrote through the legacy skill link"
[[ "$(cat "$legacy/claude/agents/reviewer.md")" == "legacy reviewer" ]] || fail "wrote through the legacy agent link"
[[ "$(cat "$dots/executor.md")" == "my executor" ]] || fail "wrote through the user's symlink"
[[ -L "$HOME/.claude/agents/executor.md" ]] || fail "replaced the user's symlink"
for f in "$HOME/.claude/rules/tuidev-orchestration.md" "$HOME/.claude/agents/reviewer.md" "$HOME/.claude/skills/delegation/SKILL.md"; do
    [[ -f "$f" && ! -L "$f" ]] || fail "$f should be a regular file now"
done
[[ "$(cat "$HOME/.claude/CLAUDE.md")" == "my claude notes" && ! -e "$HOME/.claude/CLAUDE.md.bak" ]] \
    || fail "the user's CLAUDE.md from before agents-orchestration was not restored untouched"
grep -qxF "my codex notes" "$HOME/.codex/AGENTS.md" || fail "user text in ~/.codex/AGENTS.md lost"
grep -qxF "<!-- >>> tuidev managed (tuidev-orchestration) >>> -->" "$HOME/.codex/AGENTS.md" \
    || fail "the Codex block needs HTML-comment markers (a # line is a Markdown heading)"
read_managed_block "$HOME/.codex/AGENTS.md" tuidev-orchestration | grep -q "## Codex agents" \
    || fail "Codex block lacks its agents section"
! grep -q "## Codex agents" "$HOME/.claude/rules/tuidev-orchestration.md" \
    || fail "the Claude rule carries the Codex agents section"
pass "install replaces legacy links, keeps the user's links and text"

# 4. A second run changes nothing.
before="$(find "$HOME" -type f -exec cksum {} + | sort)"
orchestration_install >/dev/null
[[ "$(find "$HOME" -type f -exec cksum {} + | sort)" == "$before" ]] || fail "second run changed files"
pass "idempotent"

# 5. A policy left as plain text (agents-orchestration --copy) is flagged.
printf '# Agent Orchestration\n\nThe main thread is the orchestrator: it plans.\n' > "$HOME/.claude/CLAUDE.md"
out="$(orchestration_install 2>&1)"
grep -qF "holds the orchestration policy as plain text" <<<"$out" \
    || fail "no warning for a plain-text copy of the policy"
cat "$REPO_DIR/configs/orchestration/global-instructions.md" > "$HOME/.claude/CLAUDE.md"
out="$(orchestration_install 2>&1)"
grep -qF "holds the orchestration policy as plain text" <<<"$out" \
    || fail "no warning for a plain-text copy of the current policy"
pass "a plain-text copy of the policy (old or current) is flagged"

# 6. Run on its own, the pack records what it wrote, so uninstall.sh can
#    remove it on a machine without the rest of tuidev.
rm -rf "$HOME/.claude" "$HOME/.codex" "$HOME/.agents" "$TUIDEV_STATE_DIR"
bash "$REPO_DIR/scripts/install/packs/orchestration.sh" >/dev/null
m="$TUIDEV_STATE_DIR/manifest"
grep -qF "file $HOME/.claude/rules/tuidev-orchestration.md" "$m" || fail "standalone run did not record the rule file"
grep -qF "block tuidev-orchestration $HOME/.codex/AGENTS.md" "$m" || fail "standalone run did not record the Codex block"
grep -qF "dir $HOME/.agents/skills/delegation" "$m" || fail "standalone run did not record the skill folder"
pass "a standalone run is recorded in the manifest"

echo "my codex notes" >> "$HOME/.codex/AGENTS.md"
bash "$REPO_DIR/uninstall.sh" --all </dev/null >/dev/null 2>&1 || fail "uninstall.sh failed"
[[ ! -e "$HOME/.claude/rules/tuidev-orchestration.md" && ! -e "$HOME/.agents/skills/delegation" \
   && ! -e "$HOME/.claude/agents/reviewer.md" ]] || fail "uninstall left pack files behind"
[[ "$(cat "$HOME/.codex/AGENTS.md")" == "my codex notes" ]] || fail "uninstall did not leave exactly the user's Codex text"
pass "uninstall.sh removes a standalone install and keeps the user's text"

echo ""
echo "All orchestration pack tests passed."
