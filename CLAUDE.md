# CLAUDE.md

@AGENTS.md

## Claude Code specifics

- **Settings are the authoritative policy.** `configs/claude/settings.json` ships:
  - `sandbox.enabled = true` — Claude's own native sandbox is on by default, so plain `claude` is confined without a wrapper (`autoAllowBashIfSandboxed`, `excludedCommands` for `docker`/`gh`, `filesystem.denyRead` for the AI CLIs' own token files);
  - a read-only `allow` list;
  - `ask` rules for `git push`, `gh pr merge` and `gh api`;
  - `deny` rules for the same credential paths `sbx` blocks, plus `.env*` (these merge into the sandbox's `denyRead` too);
  - empty `attribution` (no `Co-Authored-By`);
  - `Notification`, `TeammateIdle` and `PermissionDenied` hooks that call `~/.local/bin/notify.sh`.

  Keep `bin/sbx`, the `.sb` profiles and those deny rules in sync when you change any of them.
- **Agent teams are on** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `teammateMode: "auto"`). Inside tmux, teammates get their own panes. Elsewhere they run in-process. Prefer plain subagents for focused work, and a team only when teammates must talk to each other.
- **Parallel work uses worktrees.** Use `claude -w NAME` (under `.claude/worktrees/`), or give subagents `isolation: worktree`. Both stay inside the repo, where the sandbox allows writes.
- **`sbx` or the native sandbox, never both.** Seatbelt doesn't nest. With the shipped settings, plain `claude` already runs under its own native sandbox; running it under `sbx` too (`sbx -- claude`) stacks two Seatbelt profiles and fails. Pick one: to use `sbx`, turn the native one off for that run (`sbx -- claude --settings '{"sandbox":{"enabled":false}}'`). Under `sbx` on macOS, the Keychain is denied, so log in with `claude setup-token` and `CLAUDE_CODE_OAUTH_TOKEN`. `gh` doesn't work under `sbx --profile strict`/`standard`; under the native sandbox it's in `excludedCommands` instead. See [docs/sandboxing.md](docs/sandboxing.md).
- **`CLAUDE.local.md` is personal and gitignored**, and so is `.local/`. Machine-specific hosts, services and notes go there, never in this file or `AGENTS.md`.
- Keep this file Claude-specific and short. Shared instructions belong in `AGENTS.md`, which loads through the import above.
