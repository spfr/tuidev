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

# The models agent files may pin: aliases, or ids every Codex plan can run.
# Change a pin here, in the agent file and in docs/orchestration.md's tier
# table together. A Codex agent may also leave `model` out to run on the
# session's model.
ORCH_CLAUDE_MODELS="haiku sonnet opus fable inherit"
ORCH_CODEX_MODELS="gpt-6-luna gpt-6.2-sol gpt-6.2-astra"
ORCH_EFFORTS="low medium high xhigh max"

agents_src="$REPO_DIR/configs/orchestration"
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
# The YAML between line 1's `---` and the next `---`; fails without both.
frontmatter() {
    awk 'NR == 1 { if ($0 != "---") exit 1; next } /^---$/ { done = 1; exit } { print } END { if (!done) exit 1 }' "$1"
}
# fm_value FILE KEY: a top-level scalar, unquoted.
fm_value() {
    frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | sed "s/^['\"]//; s/['\"]\$//"
}
# toml_value FILE KEY: a top-level string.
toml_value() { sed -n "s/^$2[[:space:]]*=[[:space:]]*\"\\(.*\\)\"[[:space:]]*\$/\\1/p" "$1"; }

# 0. Every agent and skill file parses, names an allowed model and effort, and
#    each Claude tier has its Codex counterpart.
for f in "$agents_src"/claude/agents/*.md "$agents_src"/skills/*/SKILL.md; do
    rel="${f#"$REPO_DIR"/}"
    fm="$(frontmatter "$f")" || fail "$rel: no frontmatter between --- lines"
    # The YAML Claude Code reads: `key: value` or `  - item`. A plain value
    # can't hold ": " or " #", so such values must be quoted.
    bad="$(awk '/^  - [A-Za-z0-9_()*-]+$/ { next }
        /^[A-Za-z][A-Za-z0-9_]*:/ { v = $0; sub(/^[^:]*:[ ]*/, "", v)
            if (v ~ /^'\''.*'\''$/ || v ~ /^".*"$/) next
            if (v ~ /: / || v ~ / #/ || v ~ /^[][{}&*!|>%@`'\''"]/) print; next }
        { print }' <<<"$fm")"
    [[ -z "$bad" ]] || fail "$rel: frontmatter line is not plain YAML: $bad"
    if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q mikefarah; then
        yq --front-matter=extract '.' "$f" >/dev/null 2>&1 || fail "$rel: yq can't parse its frontmatter"
    elif command -v ruby >/dev/null 2>&1; then
        ruby -ryaml -e 'YAML.safe_load(ARGF.read)' <<<"$fm" 2>/dev/null || fail "$rel: Ruby's YAML can't parse its frontmatter"
    fi
    [[ -n "$(fm_value "$f" name)" && -n "$(fm_value "$f" description)" ]] || fail "$rel: needs name and description"
    case "$f" in */SKILL.md) continue ;; esac
    model="$(fm_value "$f" model)"
    in_list "$model" "$ORCH_CLAUDE_MODELS" || fail "$rel: model '$model' is not in ORCH_CLAUDE_MODELS"
    effort="$(fm_value "$f" effort)"
    [[ -z "$effort" ]] || in_list "$effort" "$ORCH_EFFORTS" || fail "$rel: effort '$effort' is not one of: $ORCH_EFFORTS"
    name="$(basename "$f" .md)"
    [[ "$name" == explore ]] && name=explorer
    [[ -f "$agents_src/codex/agents/$name.toml" ]] || fail "$rel has no Codex counterpart codex/agents/$name.toml"
done
for f in "$agents_src"/codex/agents/*.toml; do
    rel="${f#"$REPO_DIR"/}"
    if python3 -c 'import tomllib' 2>/dev/null; then
        python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$f" 2>/dev/null \
            || fail "$rel is not valid TOML"
    fi
    for key in name description developer_instructions; do
        grep -qE "^${key}[[:space:]]*=" "$f" || fail "$rel: missing $key"
    done
    [[ "$(toml_value "$f" name)" == "$(basename "$f" .toml)" ]] || fail "$rel: name doesn't match the file name"
    # Codex ignores these in an agent file: they'd only look like a guard.
    for key in sandbox_mode approval_policy model_provider mcp_servers; do
        ! grep -qE "^\\[?$key" "$f" || fail "$rel sets $key, which Codex ignores in agent files"
    done
    model="$(toml_value "$f" model)"
    [[ -z "$model" ]] || in_list "$model" "$ORCH_CODEX_MODELS" || fail "$rel: model '$model' is not in ORCH_CODEX_MODELS"
    effort="$(toml_value "$f" model_reasoning_effort)"
    [[ -z "$effort" ]] || in_list "$effort" "$ORCH_EFFORTS" || fail "$rel: effort '$effort' is not one of: $ORCH_EFFORTS"
done
for model in $ORCH_CODEX_MODELS; do
    grep -qF "\`$model\`" "$REPO_DIR/docs/orchestration.md" || fail "docs/orchestration.md doesn't name the pinned $model"
done
pass "agent files parse and pin only allowed models and efforts"
# The parsers may leave caches in HOME (a python3 or ruby shim); start clean.
rm -rf "$HOME" && mkdir -p "$HOME"

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
wrote="$(find "$HOME" -type f)"
[[ -z "$wrote" ]] || fail "dry run wrote files: $wrote"
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
