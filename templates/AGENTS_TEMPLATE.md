# AGENTS.md

<!--
Starter AGENTS.md for a project developed on a tuidev machine. Copy it to your
repo root, fill in the <placeholders>, and delete what doesn't apply. Keep it
short: every line loads into the agent's context at session start.

Who reads it:
  - Codex and OpenCode read AGENTS.md natively.
  - Claude Code reads AGENTS.md when the project has no CLAUDE.md. If you want
    Claude-specific notes, create a CLAUDE.md whose first line is `@AGENTS.md`
    (the import), and put only the Claude-specific lines below it.
  - Other tools: `scripts/setup_agent_configs.sh <project> --all` creates the
    legacy per-vendor files (never overwriting existing ones).

Write only what an agent can't discover on its own: commands, conventions,
the definition of done, and boundaries. Leave out generic advice ("write
clean code") and anything the agent already sees (the file tree, git status).
-->

## Project

<One or two sentences: what this is, who uses it, and the main language and framework.>

## Commands

```bash
<install deps>          # e.g. npm ci | uv sync | cargo fetch
<dev server>            # e.g. npm run dev (run it in a tmux pane, not with &)
<lint>                  # e.g. npm run lint
<typecheck>             # e.g. npx tsc --noEmit
<test one file>         # e.g. npx vitest run path/to/file.test.ts
<test all>              # e.g. npm test
<build>                 # e.g. npm run build
```

## Conventions

- <Where code lives: e.g. `src/` app, `packages/*` libraries, `tests/` mirrors `src/`.>
- <Patterns to follow, and the file that shows each best.>
- <Things not to touch: generated code, vendored dirs, migrations already applied.>
- Match the existing style over introducing a new one, and keep diffs small.
- Commits: <conventional commits? trailers? signed?>. Don't push or open PRs unless asked.

## Definition of done

A change is done only when these pass, run cheapest first:

1. `<lint>` and `<typecheck>`
2. `<targeted tests>`, then `<test all>`
3. <any manual check, e.g. "the page renders at /settings">

Report the commands you ran and their results. If you couldn't run something, say so.

## Environment (tuidev)

- **Sandbox:** you usually run under your CLI's own native sandbox now (Claude Code's `sandbox.enabled`, Codex's `sandbox_mode = "workspace-write"`), not a wrapper. You can write only to this project, `/tmp` and your CLI's own state dirs. Credential stores (`~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.npmrc`, the Keychain, and others) are denied. Don't read or write secrets there. `sbx` (macOS Seatbelt) is also available as a general-purpose wrapper for anything else.
- **Network:** outbound TCP 443 and DNS only. If a package install needs more, ask the human to run it with `sbx --profile standard -- <cmd>`. `gh` doesn't work inside the sandbox, so ask the human.
- **Long-running processes** (dev servers, watchers, test loops) go in a tmux pane, where they survive disconnects. A backgrounded `&` job dies with your session.
- **Parallel work:** use your own git worktree. For Claude Code, `claude -w NAME` or `isolation: worktree`; with any other CLI, `git worktree add` by hand. Never share a dirty index with another agent.
- **Scriptable tools to use:** `rg`, `fd`, `jq`, `yq`, `git`, `gh`, `delta`, `hyperfine`. The TUIs (`lazygit`, `btm`, `lazydocker`, `k9s`, `fzf`, `atuin`) are for the human. Don't drive them.
- **Herdr:** if `HERDR_ENV=1`, you are in a Herdr pane. Use `herdr agent list` / `herdr status`, never the TUI, and don't launch `herdr` again.
- **Node** comes from fnm or nvm and switches per `.nvmrc` / `.node-version` on `cd`. Don't edit `PATH` for it.

## Boundaries

- Never commit secrets, `.env*` files or real hostnames and IPs.
- Ask before you: <add a dependency / change a public API / run a migration / delete data / touch CI>.
- <Anything else that must never happen without a human.>
