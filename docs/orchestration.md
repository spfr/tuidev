# Orchestration

`--pack orchestration` installs one multi-agent policy for Claude Code and Codex. The main session is the orchestrator: it plans, delegates bounded work to subagents pinned to the cheapest tier that does the job reliably, reviews and verifies what comes back, and stops review-ready. The always-on part is a few paragraphs; the depth loads as skills only when a multi-agent task is underway.

```bash
./install.sh --pack ai-clis --pack orchestration   # the usual pair: gates + policy
```

## Just this pack

You don't need the rest of tuidev. From a clone, the pack installs on its own: no shell, theme or package changes.

```bash
git clone https://github.com/spfr/tuidev.git && cd tuidev
bash scripts/install/packs/orchestration.sh    # add DRY_RUN=true in front to preview
bash scripts/install/packs/ai-clis.sh          # optional: the git and gh write gates (see below)
```

Update with `git pull` and the same command. The run is recorded in `~/.config/tuidev/manifest`, so `./uninstall.sh` removes exactly what it wrote, and leaves your own text in `~/.codex/AGENTS.md`. `ai-clis.sh` adopts `~/.claude/settings.json` and `~/.codex/config.toml` only where they're absent or an unmodified tuidev copy, so it never overwrites settings you already have.

## What it installs

| Source (`configs/orchestration/`) | Installed to | How |
|---|---|---|
| `global-instructions.md` | `~/.claude/rules/tuidev-orchestration.md` | overwrite (tuidev-owned) |
| `global-instructions.md` + `codex/global-instructions.md` | `~/.codex/AGENTS.md` | managed block `tuidev-orchestration` |
| `claude/agents/*.md` | `~/.claude/agents/` | overwrite (tuidev-owned names) |
| `codex/agents/*.toml` | `~/.codex/agents/` | overwrite |
| `skills/<name>/SKILL.md` | `~/.claude/skills/<name>/` and `~/.agents/skills/<name>/` | overwrite |

Claude Code loads every file in `~/.claude/rules/` at session start, like `~/.claude/CLAUDE.md`, so the policy lives in a file of its own and your `CLAUDE.md` stays entirely yours. Codex has no rules folder for instructions: it reads `~/.codex/AGENTS.md` (or `AGENTS.override.md`, which then hides it; the pack warns), so the policy goes there as a managed block between HTML-comment markers, and your text outside it stays yours. Codex reads user skills from `~/.agents/skills/`.

Agent and skill files carry generic names (`reviewer`, `executor`, `delegation`, …): the pack owns them, replaces your edits on every `update.sh --configs` (backing them up first), and skips any of them that is a symlink of yours.

The git and gh write gates are not in this pack. They belong to `--pack ai-clis`, which owns the CLIs' settings: Claude Code `ask` rules for `git add|commit|push|merge|tag` and `gh pr create|merge`, `gh release`, `gh api`, and the same list as Codex `prefix_rule`s in `~/.codex/rules/tuidev.rules`. Both match command prefixes, so `git -C . push` or a script that runs git itself gets past them: a colleague-grade guard, not a security boundary.

The gates also cover the one git write the `delegation` skill allows, a scratch commit on a throwaway branch in an isolated worktree, and its `git merge --squash` harvest. Those prompt you too, on purpose: bringing parallel work back is a step you approve.

## Tiers

| Role | Claude Code | Codex | Definition |
|---|---|---|---|
| Orchestrator (main session) | your session model and effort | your session model and effort | — |
| Complex implementor | `opus` · `high` | `gpt-6-sol` · `high` | `implementor-complex` |
| Reviewer (independent, read-only) | `opus` · `high` | `gpt-6-sol` · `high` | `reviewer` |
| Standard implementor | `sonnet` · `medium` | `gpt-6-luna` · `high` | `implementor-standard` |
| Executor (builds, suites, logs, browser runs) | `haiku` | `gpt-6-luna` · `low` | `executor` |
| Explore (search fan-out) | `haiku` | built-in `explorer` | `Explore` (overrides Claude's built-in) |

Claude definitions pin family aliases, which follow each new generation. Codex pins exact model ids: bump them when OpenAI ships a new family, and re-read each agent's instructions at the same time. Codex efforts follow OpenAI's starting points (Luna at `high` for implementation, `low` for mechanical runs; Sol higher than its `medium` default for the complex tier and review). The session model and effort are left to each CLI's default; raise effort per session (`/effort`, a Codex `--profile`) when the task is hard.

The `Explore` override exists because Claude's built-in Explore inherits the session model (capped at Opus), and a user-level agent named `Explore` keeps its own `model`. It sets `omitClaudeMd`, like the built-in.

## Why it looks like this

- **Delegation pays for context isolation, parallel independent work and fresh-context review**, and not for a dependent chain that fits in one context: a subagent starts uncached, and the orchestrator's cached history is the cheapest context there is. Bounded high-output work (full builds and suites, long logs, browser runs, multi-source research) always goes to a subagent so its output never lands in the orchestrator's context.
- **As little direction as works.** Both vendors now say current models do more on their own and that leftover scaffolding hurts: Anthropic cut most of Claude Code's system prompt for Claude 5, and OpenAI warns that emphatic or stop-early rules make GPT-6 halt work you'd want finished. So every line has to prevent a real mistake. The always-on text is about 150 words: when delegation pays, and the few rules neither CLI applies by default. Agent bodies are a few sentences plus a report format. Skill descriptions only say when to load them.
- **Delegation is stated, not assumed.** Codex delegates only when asked at most effort levels, so the Codex block names the tiers and says to use them.
- **Enforced where it can be.** Secrets and git writes are permission rules the CLI applies, not prose the model reads. The prose says to leave work uncommitted, not to stop early.

## CI runners and sandboxes

Install it as in [Just this pack](#just-this-pack).

In headless `claude -p`, an `ask` rule has nobody to ask, so it denies: an agent on a runner cannot stage, commit or push. That is the intended shape — the agent leaves a diff, and a pipeline step you control commits it. On company-managed machines, the enforced route for policy is each CLI's managed configuration (Claude Code's managed settings, Codex's `requirements.toml`), which users cannot override; this pack only writes user-level files.

## Coming from agents-orchestration

This pack replaces the standalone agents-orchestration repo. On its first run it removes the symlinks that repo's installer left in `~/.claude`, `~/.codex` and `~/.agents` (only links into that repo's `build/` or agent files) before writing. Where that installer had set your own `CLAUDE.md` or `AGENTS.md` aside as `.bak`, the pack moves it back. If you installed that repo with `--copy`, its policy is plain text in those files; the pack warns, and you delete it (it would otherwise load twice). If you kept your own fragments in that checkout's gitignored `local/*.md`, move them before you delete it: into `~/.claude/rules/` for Claude Code, and into `~/.codex/AGENTS.md` outside the tuidev block for Codex. Both load every session. Keys that repo merged into your settings stay yours: `effortLevel`, `permissions.ask` and the `.env` rules in `~/.claude/settings.json`, and the `model` and `model_reasoning_effort` lines in `~/.codex/config.toml`, which pin the Codex session. Delete those two lines to follow Codex's defaults; the pack warns when `model` pins a superseded `gpt-5.6` model. Because of those merges, `--pack ai-clis` sees both files as edited by you and never upgrades them: compare them with `configs/claude/settings.json` and `configs/codex/config.toml` once, by hand.

Re-audit the policy at every model release: for each line, ask whether removing it would cause a mistake. A line that is load-bearing on one generation is dead weight on the next.
