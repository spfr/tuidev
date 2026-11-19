# CLAUDE.md

@AGENTS.md

## Claude Code specifics

- **Settings are the authoritative policy.** `configs/claude/settings.json` ships:
  - `sandbox.enabled = true` — Claude's own native sandbox is on by default, so plain `claude` is confined without a wrapper (`autoAllowBashIfSandboxed`, `excludedCommands` for `docker`/`gh`, `filesystem.denyRead` for the AI CLIs' own token files, `credentials.envVars` for third-party tokens, mirrored in Codex's `shell_environment_policy.filters`);
  - a read-only `allow` list;
  - `ask` rules for git and gh writes (`git add|commit|push|merge|tag`, `gh pr create|merge`, `gh release`, `gh api`), mirrored for Codex in `configs/codex/rules/tuidev.rules`;
  - `deny` rules for the same credential paths `sbx` blocks, plus `.env*` (these merge into the sandbox's `denyRead` too);
  - empty `attribution` with `sessionUrl: false` (no `Co-Authored-By`, "Generated with" or session links);
  - `env.NODE_OPTIONS=--max-old-space-size=4096`, which pins Node's heap limit to 4 GB on every machine (about Node's own default on a 16 GB+ one); the memory guard, not this, is what stops a runaway (Codex: `shell_environment_policy.set`);
  - `Notification`, `TeammateIdle` and `PermissionDenied` hooks that call `~/.local/bin/notify.sh`;
  - a `statusLine` that runs `~/.local/bin/agents statusline` (it records Claude's usage limits, then prints a compact line or `AGENTS_STATUSLINE_CMD`'s; nothing without the `monitoring` pack, and a user's own `statusLine` survives the merge);
  - `SubagentStop` and `SessionEnd` (`clear|resume`) hooks that run `~/.local/bin/agents hook` to stop the background commands a finished subagent or cleared session left running (a no-op without the `monitoring` pack; `AGENTS_HOOK_REAP=0` turns them off);
  - wait hooks for `waits.tsv`: a `PermissionRequest` hook and a second `Notification` hook (`agents hook wait-start`; the `PermissionRequest` one prints nothing, so it never answers the dialog, and starts `agents` only when a wait could open) and `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure` and `Stop` hooks (`agents hook wait-end`, started only while that session has a wait open);
  - menu bar pokes (`agents bar poke`, which refreshes the SwiftBar plugin at most once every 2 s): a guard in front of the first `UserPromptSubmit` and the `Stop` hook, and a `SessionEnd` hook on every reason (`--settle`), each two `[ -e ]` tests that start `agents` only while SwiftBar runs the plugin (`bar.alive`) and no poke went out in the last 2 s (`bar.busy`); never on a tool call. `agents hook wait-start`, `subagent-stop` and a `wait-end` that ended a wait poke from inside;
  - a second `UserPromptSubmit` hook, `agents link drop`, started only while a link watcher is attached to this machine from another one: a file path pasted into the prompt that exists only on that other machine is asked for, and sent only when its owner says yes there ([docs/remote.md](docs/remote.md)).

  The credential paths live in `configs/sandbox/credential-paths.txt`; `test_contract.sh` fails until `bin/sbx`, the `.sb` profiles, those deny rules and the docs match it.
- **Agent teams are off by default.** While they are on, every subagent Claude names launches as a teammate. Use plain subagents; turn teams on (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) only when teammates must talk to each other. `teammateMode: "auto"` then gives them tmux panes.
- **Parallel work uses worktrees.** Use `claude -w NAME` (under `.claude/worktrees/`), or give subagents `isolation: worktree`. Both stay inside the repo, where the sandbox allows writes.
- **`sbx` or the native sandbox, never both.** Seatbelt doesn't nest. With the shipped settings, plain `claude` already runs under its own native sandbox; running it under `sbx` too (`sbx -- claude`) stacks two Seatbelt profiles and fails. Pick one: to use `sbx`, turn the native one off for that run (`sbx -- claude --settings '{"sandbox":{"enabled":false}}'`). Under `sbx` on macOS, the Keychain is denied, so log in with `claude setup-token` and `CLAUDE_CODE_OAUTH_TOKEN`. `gh` doesn't work under `sbx --profile strict`/`standard`; under the native sandbox it's in `excludedCommands` instead. See [docs/sandboxing.md](docs/sandboxing.md).
- **`CLAUDE.local.md` is personal and gitignored**, and so is `.local/`. Machine-specific hosts, services and notes go there, never in this file or `AGENTS.md`.
- Keep this file Claude-specific and short. Shared instructions belong in `AGENTS.md`, which loads through the import above.
