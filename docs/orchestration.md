# Orchestration

Get the cheapest model that does each job reliably, on both Claude Code and Codex, without writing the policy yourself. `--pack orchestration` installs one multi-agent policy for them. The main session is the orchestrator: it plans, delegates bounded work to subagents pinned to the cheapest tier that does the job reliably, reviews and verifies what comes back, and stops review-ready. The always-on part is a few rules the CLIs don't apply by default; the `delegation` skill loads only when parallel worktrees are in play.

```bash
tuidev install --pack ai-clis --pack orchestration   # the usual pair: gates + policy
```

## Just this pack

You don't need the rest of tuidev. Run the pack's script from a clone, or from the release `get.sh --fetch` downloads, and it installs on its own: no shell, theme or package changes, and no `tuidev` command, so use the script paths below.

```bash
git clone https://github.com/spfr/tuidev.git && cd tuidev
# without git: curl -fsSLO https://github.com/spfr/tuidev/releases/latest/download/get.sh && cd "$(bash get.sh --fetch)"
bash scripts/install/packs/orchestration.sh    # add DRY_RUN=true in front to preview
bash scripts/install/packs/ai-clis.sh          # optional: the git and gh write gates (see below)
```

To update, `git pull` (or fetch the new release the same way) and run the same command. The run is recorded in `~/.config/tuidev/manifest`, so `./uninstall.sh` in that directory removes exactly what it wrote, and leaves your own text in `~/.codex/AGENTS.md`. `ai-clis.sh` adopts `~/.claude/settings.json` and `~/.codex/config.toml` only where they're absent or an unmodified tuidev copy, so it never overwrites settings you already have.

## What it installs

| Source (`configs/orchestration/`) | Installed to | How |
|---|---|---|
| `global-instructions.md` | `~/.claude/rules/tuidev-orchestration.md` | overwrite (tuidev-owned) |
| `global-instructions.md` + `codex/global-instructions.md` | `~/.codex/AGENTS.md` | managed block `tuidev-orchestration` |
| `claude/agents/*.md` | `~/.claude/agents/` | overwrite (tuidev-owned names) |
| `codex/agents/*.toml` | `~/.codex/agents/` | overwrite |
| `skills/<name>/SKILL.md` | `~/.claude/skills/<name>/` and `~/.agents/skills/<name>/` | overwrite |

Claude Code loads every file in `~/.claude/rules/` at session start, like `~/.claude/CLAUDE.md`, so the policy lives in a file of its own and your `CLAUDE.md` stays entirely yours. Codex has no rules folder for instructions: it reads `~/.codex/AGENTS.md` (or `AGENTS.override.md`, which then hides it; the pack warns), so the policy goes there as a managed block between HTML-comment markers, and your text outside it stays yours. Codex reads user skills from `~/.agents/skills/`.

Agent and skill files carry generic names (`reviewer`, `executor`, `delegation`, …): the pack owns them, replaces your edits on every `tuidev update --configs` (backing them up first), and skips any of them that is a symlink of yours.

The git and gh write gates are not in this pack. They belong to `--pack ai-clis`, which owns the CLIs' settings: Claude Code `ask` rules for `git add|commit|push|merge|tag` and `gh pr create|merge`, `gh release`, `gh api`, and the same list as Codex `prefix_rule`s in `~/.codex/rules/tuidev.rules`. Both match command prefixes, so `git -C . push` or a script that runs git itself gets past them: a colleague-grade guard, not a security boundary.

The gates also cover the one git write the `delegation` skill allows, a scratch commit on a throwaway branch in an isolated worktree, and its `git merge --squash` harvest. Those prompt you too, on purpose: bringing parallel work back is a step you approve.

## Tiers

| Role | Claude Code | Codex | Definition |
|---|---|---|---|
| Orchestrator (main session) | your session model and effort | your session model and effort | — |
| Complex implementor | `fable` · `high` | `gpt-6.2-astra` · `high` | `implementor-complex` |
| Reviewer (independent, read-only) | `opus` · `high` | `gpt-6.2-astra` · `high` | `reviewer` |
| Standard implementor | `sonnet` · `medium` | `gpt-6.2-sol` · `medium` | `implementor-standard` |
| Executor (builds, suites, logs, browser runs) | `haiku` · model default | `gpt-6-luna` · `low` | `executor` |
| Explore (search fan-out) | `haiku` · model default | `gpt-6-luna` · `high` | `Explore` / `explorer` (each replaces its CLI's built-in) |

Claude definitions use family aliases, which follow each new generation; `haiku` without an `effort` runs at the model's default, `medium` on Haiku 5.5. The complex tier is on `fable`, which Anthropic describes as the model "for your hardest and longest-running tasks" (Fable 5.2 needs Claude Code 2.1.321 or later, costs twice Opus 5.5 per token, and on some plans bills to usage credits); the reviewer stays on `opus`, so a hard change is checked by a different model from the one that wrote it. Codex has no aliases, so its tiers name OpenAI's current models (November 2026): `gpt-6.2-astra`, which OpenAI recommends "for demanding work across code", for complex changes and review; `gpt-6.2-sol`, its model for "everyday tasks like editing code", for routine implementation; and `gpt-6-luna`, for "fast, narrowly scoped agents", for command runs and search. These need a paid Codex plan that lists the 6.2 models (`codex debug models` shows yours); on one, Codex 0.170 started each of the five roles on its pinned model. A role pinned to a model the account lacks can fail to spawn (`Unknown model … for spawn_agent`) instead of falling back: the Free plan lists only `gpt-6-luna`, `gpt-5.6-terra` and `gpt-5.6-luna`, so there, override the two upper tiers as below. Efforts follow each vendor's guidance: `high` where edge cases and review matter, `medium` for well-specified coding on Sonnet and Sol, Luna at `high` (OpenAI's starting point) except `low` for the executor's straightforward runs.

The `Explore` and `explorer` agents exist because both built-ins run on the session model, and an agent of yours with the same name replaces the built-in. `Explore` sets `omitClaudeMd`, like the built-in. Read-only roles are enforced where the CLI allows it: Claude's `reviewer`, `executor` and `Explore` drop the edit tools and `Agent` (a nested subagent would get them back). A Codex agent file can't narrow the session's sandbox, so the Codex `reviewer` and `explorer` are read-only by instruction only.

### Choosing other models

The pack owns these files and rewrites them on `tuidev update --configs`, so override them elsewhere:

- **Claude, every tier:** point the aliases with `ANTHROPIC_DEFAULT_FABLE_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` (the `env` block of `~/.claude/settings.json`). On Amazon Bedrock, Google Cloud and Microsoft Foundry the aliases lag (`sonnet` is Sonnet 4.5 there), so set them to current ids. `ANTHROPIC_DEFAULT_OPUS_MODEL=claude-fable-5-2` runs the complex and review tiers on Fable, at twice Opus's price ($8/$40 per million input/output tokens against $4/$20).
- **Claude, one tier:** a project agent of the same name (`.claude/agents/reviewer.md`) wins over the user-level one. To keep the complex tier off Fable, give the project an `implementor-complex.md` with `model: opus`.
- **Codex on a plan without the 6.2 models:** put project agents of the same names (`.codex/agents/reviewer.toml` in the repo) without a `model` line, so they run on your session's model, or with a model your plan lists. Don't edit the copies in `~/.codex/agents/`: the next update rewrites them.
- **Codex, one tier:** a project agent of the same name (`.codex/agents/reviewer.toml`). `codex debug models` lists the ids your Codex knows.

When either vendor ships a new family, re-read each agent's instructions. For Codex, check that the three pinned models are still current and listed, and put any new pin in the allow-list at the top of `scripts/lib/test_orchestration.sh`.

## Why it looks like this

- **The tiers are the value.** Claude already orchestrates subagents on its own, but it runs them on the session model unless an agent definition pins a cheaper one. The definitions send search and command runs to Haiku and standard implementation to Sonnet, and keep Fable for the complex tier and Opus for review.
- **As little direction as works.** Both vendors now say current models do more on their own and that leftover scaffolding hurts: Anthropic cut most of Claude Code's system prompt for Claude 5, and OpenAI warns that emphatic or stop-early rules make GPT-6 halt work you'd want finished. So every line has to prevent a real mistake. The always-on text is six rules neither CLI applies by default (the fifth makes file paths clickable: written as `file://` Markdown links, they become OSC 8 links that Ghostty and Herdr open; the sixth stops leaked background processes: foreground or harness-reported tasks, no `sleep` polling, stop what you started), and says nothing about when to delegate: Claude Code's own harness covers that, and each agent's `description` says when it fits. Agent bodies hold only what the frontmatter can't: the uncommitted-work rule for implementors, a carry-through-and-stay-in-scope line for the Sonnet implementor (Anthropic's Sonnet 5.5 notes say that at `medium` it can stop to check in before a task is done, and add tests or docs nobody asked for), the verdict format for the reviewer, the digest and stop-on-failure rules for the executor, the report format for Explore, and "don't edit files" where Codex can't enforce it. Skill descriptions only say when to load them.
- **Don't push delegation on Claude.** Anthropic's Opus 5 notes say these models over-delegate and check their own work, and that telling them to verify through a subagent causes over-verification. So nothing in the policy pushes delegation or verification: there is no verification skill, the `reviewer` is offered, not required, and fan-out width is Claude Code's setting (the workflow size in `/config`), not policy text. Agent teams are off in the shipped settings for the same reason: while they're on, every subagent Claude names becomes a full teammate session.
- **Delegation is stated, not assumed.** Codex delegates only when asked at most effort levels, so the Codex block names the tiers, says to use them, and sends high-output runs to `executor`. OpenAI's GPT-6 guidance says the opposite of Anthropic's here: its models "may delegate less often than desired".
- **Enforced where it can be.** Secrets and git writes are permission rules the CLI applies, not prose the model reads. The prose says to leave work uncommitted, not to stop early.

## CI runners and sandboxes

Install it as in [Just this pack](#just-this-pack).

In headless `claude -p`, an `ask` rule has nobody to ask, so it denies: an agent on a runner cannot stage, commit or push. That is the intended shape — the agent leaves a diff, and a pipeline step you control commits it. On company-managed machines, the enforced route for policy is each CLI's managed configuration (Claude Code's managed settings, Codex's `requirements.toml`), which users cannot override; this pack only writes user-level files.

## Coming from the earlier standalone installer

The pack replaces the standalone orchestration installer that came before it. On its first run it removes the symlinks that installer left in `~/.claude`, `~/.codex` and `~/.agents`, and moves back any `CLAUDE.md` or `AGENTS.md` of yours it had set aside as `.bak`. A copy-mode install left the policy as plain text in those files: the pack warns, and you delete it (it would otherwise load twice). Keys it merged into your settings stay yours: `effortLevel`, `permissions.ask` and the `.env` rules in `~/.claude/settings.json`, and the `model` and `model_reasoning_effort` lines in `~/.codex/config.toml`, which pin the Codex session. Delete those two lines to follow Codex's defaults; the pack warns when `model` pins a superseded `gpt-5.6` model. Because of those merges, `--pack ai-clis` sees both files as edited by you and never upgrades them: compare them with `configs/claude/settings.json` (`settings.linux.json` on Linux) and `configs/codex/config.toml` once, by hand.

Re-audit the policy at every model release: for each line, ask whether removing it would cause a mistake. A line that is load-bearing on one generation is dead weight on the next.
