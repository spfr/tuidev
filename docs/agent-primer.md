# Agent Primer

A short, paste-it-into-the-chat brief that teaches an agentic CLI how to use this
terminal environment well — **from the first message**, without burning turns
rediscovering the conventions.

It deliberately leaves out things a capable agent already knows or auto-detects
(see ["What's intentionally omitted"](#whats-intentionally-omitted)) and keeps
only what's *non-obvious about this machine*. The exhaustive reference is
[`AGENTS.md`](../AGENTS.md).

> Tip: keep this in your project's `AGENTS.md` / `CLAUDE.md` so every agent picks
> it up automatically — then you never have to paste it.

## Copy this

```text
This machine is "tuidev" — a terminal-first, tmux-durable dev environment.
Conventions that aren't obvious:

DURABILITY — long-lived processes go in tmux, not a backgrounded shell job.
  Dev servers, watchers, test loops: start them in a tmux pane (`work`, `dev`,
  and `ai` are attach-or-create layouts) so they survive disconnect/SSH-reattach.
  A `command &` from your shell dies with the session; a tmux pane doesn't.

SANDBOX (macOS) — commands may run under Seatbelt. You can read most of $HOME but
  NOT ~/.ssh, ~/.aws, ~/.gnupg, keychains, ~/.config/gh, ~/.docker, ~/.kube,
  ~/.netrc — don't read or write secrets there. If a network install is blocked
  (npm/pip/cargo to the public internet), rerun it as:
    sbx --profile standard -- <your command>

NODE — managed by fnm or nvm; `node`/`npx` work from the first prompt and Node
  auto-switches per .nvmrc / .node-version on cd. Don't hand-edit PATH for Node.

SCRIPTABLE TOOLS worth reaching for in Bash (installed, fast, non-interactive):
  gh      — GitHub: PRs, issues, CI logs, releases (`gh pr view`, `gh run view`)
  jq / yq — query/transform JSON / YAML in pipelines
  rg / fd — search contents / find files (sane defaults, respect .gitignore)
  delta   — readable diffs; hyperfine — benchmarks; tokei — LOC counts

DON'T script the TUIs — lazygit, btm/bottom, lazydocker, k9s, yazi, fzf, atuin
  are interactive apps for the human, not you. Use git/gh, kubectl, `git diff`,
  plain commands instead.

HYGIENE — quote paths; use $HOME, never /Users/<name>; small, idempotent changes;
  match the project's existing patterns over introducing new ones.
```

## What's intentionally omitted

These are already handled, so the primer doesn't waste context on them — most of
all for Claude Code, which:

- **Reads `CLAUDE.md` / `AGENTS.md` automatically** — anything there is loaded; a
  primer that repeats it is pure duplication.
- **Has native Grep (ripgrep), Glob, and Read** — it doesn't shell out to
  `grep`/`find`/`cat`, so "use `rg` not `grep`" is a no-op for it (those rows in
  `AGENTS.md` earn their keep for *other* CLIs and for humans).
- **Already knows** the platform, cwd, and git status (injected into context), and
  already quotes paths, prefers `[[ ]]`, probes with `command -v`, and keeps
  diffs minimal.
- **Adapts to sandbox errors** on its own — the primer just front-loads the deny
  list and the `sbx --profile standard` escape hatch to save a failed turn.

What's left in the block above is the genuinely machine-specific part: tmux
durability, the exact sandbox boundary, Node auto-switching, and which tools are
*scriptable* vs. *human-only TUIs*.

## Note on AI CLIs

This primer says nothing about `cc`/`cx`/`oc` — if you're reading it, you *are* the
agent. Those wrappers (and Seatbelt routing) ship in the opt-in
[`--pack ai-clis`](agent-workflows.md); the core environment is CLI-agnostic on
purpose, since the CLIs churn faster than the terminal tools do.
