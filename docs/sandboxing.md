# Sandboxing

An AI coding agent is a non-deterministic process with a shell. Permission prompts help, but a confused or prompt-injected agent can still read `~/.ssh`, copy a token out of `~/.aws`, or reach a host you never meant it to. tuidev ships sandboxed by default, and gives you a general-purpose tool for everything the default doesn't cover.

## Native sandboxes: the default

Plain `claude` and plain `codex` run inside their own native sandboxes, with no wrapper needed. The two confine different things (below): Claude Code's keeps its Bash tool away from your credentials, Codex's limits writes and network but not reads. `--pack ai-clis` ships the settings that turn them on:

```json
"sandbox": {
  "enabled": true,
  "autoAllowBashIfSandboxed": true,
  "allowUnsandboxedCommands": false,
  "excludedCommands": ["docker *", "docker-compose *", "gh *"],
  "filesystem": {
    "denyRead": ["~/.claude/.credentials.json", "~/.codex/auth.json"]
  }
}
```

in `~/.claude/settings.json`, and `sandbox_mode = "workspace-write"` plus `approval_policy = "on-request"` in `~/.codex/config.toml`, with network off by default.

**Claude Code's native sandbox** (`sandbox.enabled`, `/sandbox` to see what's in effect) confines the Bash tool and its children; `Read` and `Edit` follow permission rules instead, and the shipped `Read(...)` deny rules (credential paths, `.env*`) merge into the sandbox's own `denyRead`. So the [credential paths](#credentials-denied-under-strict-and-standard) are denied to Bash (by the sandbox) and to `Read` (by the deny rules); an `Edit` outside the project still asks first. The first request to a new domain prompts; allow it once or add it under `sandbox.network.allowedDomains`.

- **`allowUnsandboxedCommands: false`** removes the escape hatch that lets the agent retry a failing command outside the sandbox.
- **`excludedCommands`** run outside the sandbox but still go through your permission rules. `docker` doesn't work under Seatbelt, and `gh` needs its token from `~/.config/gh`.
- **Project settings can widen this:** arrays merge across scopes, so a repo's `filesystem.allowRead` of `~/.ssh` re-opens your keys to Bash, and a project's `sandbox.enabled: false` wins over your user setting. Check `.claude/settings*.json` in repos you clone.
- **Existing hand-edited `~/.claude/settings.json` is never overwritten** (it's `--upgrade-shipped`, not clobbered). An unmodified pre-3.0 copy is upgraded by `./scripts/update.sh --configs`; if you edited yours, merge the `sandbox` block in yourself. Until then, plain `claude` runs unsandboxed.

**Codex's native sandbox** (`workspace-write`) restricts writes and network, **not reads**: writes are limited to the workspace, network is off unless you widen it, and `approval_policy = "on-request"` means Codex asks before anything outside that boundary. Codex and the commands it runs can still read `~/.ssh`, `~/.aws` and the rest of your home directory. For credential-sensitive Codex work, run it under `sbx` instead: `sbx -- codex -s danger-full-access -a on-request` denies the credential paths at the kernel level (see below).

**These are also Seatbelt on macOS, so they don't nest with `sbx`.** A process already under `sandbox-exec` can't apply a second profile (`sandbox_apply: Operation not permitted`), so pick one boundary per process tree. With the shipped settings, a bare `sbx -- claude` breaks Claude Code's Bash tool: every command fails to start its own sandbox. To run Claude Code under `sbx`, turn its native sandbox off for that run:

```bash
sbx -- claude --settings '{"sandbox":{"enabled":false}}'
```

`--settings` takes a file path or an inline JSON string and loads it on top of your settings files, so only that run changes. Do this only when you want `sbx`'s whole-process profile instead of the native one; otherwise just run `claude`.

**Claude Code login and `sbx`.** On macOS, Claude Code keeps its login in the Keychain, which `sbx` denies (opening it would expose every Keychain item). Plain `claude`, sandboxed by its native settings, keeps working because nothing wraps the process and the Keychain stays reachable. `sbx -- claude` doesn't have that luxury: create a long-lived token once, outside the sandbox, and hand it over through the environment:

```bash
claude setup-token                               # prints a token
echo 'export CLAUDE_CODE_OAUTH_TOKEN=...' >> ~/.zshrc.local
```

Treat that token like a password. Also consider setting `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`: it strips credentials from the environment that Claude Code's subprocesses (the Bash tool, hooks) inherit, so a command the agent runs can't read the token back. It is not set in the shipped `settings.json`. Add it under `env` there, or export it.

## `sbx`: the general-purpose tool

`sbx` (from `--sandbox`, part of the `desktop` and `remote` profiles) wraps macOS's built-in `sandbox-exec`. It needs no daemon, VM or container runtime. It is a policy file applied to one process tree — and it isn't AI-CLI-specific: use it to confine any command.

```bash
sbx -- ./script.sh                     # any binary, under strict (the default profile)
sbx -- claude --settings '{"sandbox":{"enabled":false}}'   # Claude Code under sbx instead of its native sandbox
sbx -- codex -s danger-full-access -a on-request   # optional kernel-level mode for Codex
sbx --profile standard -- npm ci       # wider network for package installs
sbx --profile off -- some-tool         # no sandbox
sbx --project ~/code/api -- make test  # choose the writable project dir (default: $PWD)
sbx --dry-run -- make test             # print the sandbox-exec command
make sbx-test                          # check that the project is readable and ~/.ssh is denied
```

`sbx -- codex -s danger-full-access -a on-request` turns Codex's own sandbox off and makes `sbx` the single boundary, at the kernel level, while Codex still asks before acting (`-a on-request`). Unlike `workspace-write`, it denies the credential paths. The Claude Code line above does the same for `claude`.

`sbx` executes a **binary**, not a shell function or alias. `oc` is a zsh function (`configs/zsh/opencode.zsh`), so `sbx -- oc` fails: name the real binary, `sbx -- opencode`.

Escape hatch, one run at a time: `sbx --profile off -- CMD` runs CMD with no sandbox at all. (For `claude` that is the same as plain `claude`, whose native sandbox then applies.)

## Profiles

| | `strict` (default) | `standard` | `off` |
|---|---|---|---|
| Reads | `$HOME` except credentials; system, Homebrew, Xcode paths | same | everything |
| Writes | Project dir, `/tmp`, `/private/var/folders`, the AI CLIs' state dirs | same | everything |
| Network | Outbound TCP 443, DNS (UDP 53 and the mDNSResponder socket), loopback | adds TCP 80, 22, 9418 | everything |
| herdr socket | Only with `--allow-herdr` / `SBX_ALLOW_HERDR=1` | Always open | open |
| Use for | Agent runs: LLM APIs and HTTPS git work | `npm ci`, `pip install`, git over ssh | A trusted tool, or debugging a profile |

**The AI CLIs' state dirs** are writable so the CLIs can save sessions, logs and caches: `~/.claude`, `~/.claude.json*`, `~/.local/share/claude`, `~/.local/state/claude`, `~/.cache/claude`, `~/.codex`, `~/.local/share/opencode` and `~/.cache/opencode`.

**Except what steers a CLI outside the sandbox.** Settings, hooks and binaries are loaded by later sessions, including unsandboxed ones, so an agent that could edit them would escape on your next run. Under `strict` and `standard` these stay read-only:

```
~/.claude/settings.json  ~/.claude/settings.local.json  ~/.claude/CLAUDE.md
~/.claude/keybindings.json  ~/.claude/{hooks,commands,agents,skills,plugins}/
~/.codex/config.toml  ~/.codex/*.config.toml  ~/.codex/{rules,packages}/
~/.local/share/claude/versions/  ~/.config/opencode/
the ~/.claude, ~/.codex and ~/.local/share/claude directories themselves (no rename-and-swap)
```

So **update and configure the CLIs outside `sbx`**: `claude update`, `/config` changes that save to your settings, plugin installs, Codex trusting a new project (it writes `config.toml`) and the CLIs' self-updates all fail inside it. Run them from a plain shell.

**Residual risk: `~/.claude.json` stays writable.** Claude Code rewrites it on every start, so it can't be locked. It also holds user-scope MCP servers, so a sandboxed agent could register a server that runs the next time you start Claude outside `sbx`. Check `claude mcp list` if in doubt. And don't run `sbx` with `$HOME` itself as the project dir: that makes every other dotfile writable.

**The herdr socket** is closed under `strict` unless you opt in. Anything that can reach it can drive Herdr, and Herdr spawns panes *outside* the sandbox. Use `sbx --allow-herdr` only for agents you trust to orchestrate other agents. The allow covers `~/.config/herdr/` (the default socket and `sessions/<name>/herdr.sock`). A `HERDR_SOCKET_PATH` outside that directory is denied again.

**The network limit is honest but coarse.** Seatbelt filters by port, not hostname, so "LLM providers only" is not kernel-enforced. If you need per-host egress rules, use Tier 2.

### Credentials: denied under strict and standard

Reads and writes are both denied:

```
~/.ssh  ~/.aws  ~/.gnupg  ~/Library/Keychains  ~/.config/gh  ~/.config/gcloud
~/.config/op (1Password CLI)  ~/.azure  ~/.docker  ~/.kube  ~/.terraform.d
~/.password-store  ~/.netrc  ~/.git-credentials  ~/.npmrc  ~/.pypirc
~/.cargo/credentials[.toml]  ~/.vault-token  ~/.pgpass  ~/.config/git/credentials
~/.config/containers/auth.json (podman)  ~/.gem/credentials
```

The shipped `configs/claude/settings.json` adds matching `permissions.deny` rules, plus `.env` / `.env.*` anywhere in the project (`Read(**/.env)` and friends), so Claude Code's `Read` tool (and `Edit`, for `.env*`) respects the same boundary whether or not you're also running under `sbx`. Codex has no equivalent: under `workspace-write` it can read these paths.

**On Linux, Claude Code warns at startup** that "glob patterns in sandbox permission rules are not fully supported" and names the four `.env` rules. That's expected. Its bubblewrap sandbox can deny whole directories (`~/.ssh/**`) and literal files, but a filename pattern isn't a native bubblewrap rule. In practice, a `.env` that exists when the session starts is still denied, both to `Read` (by the permission rule) and to Bash (`cat .env` fails). Treat a `.env` created mid-session as possibly readable from Bash. The rules stay because they still do their job. The credential paths use literal files and whole directories only, so they don't trigger the warning.

Consequences to plan for:

- **`gh` doesn't work under `sbx`.** Its token lives in the denied `~/.config/gh`, so it reports that you are not logged in. `--profile standard` widens the network, not credential access. For `gh`-heavy work, run `sbx --profile off -- gh ...`, or use plain `claude`, whose native sandbox lists `gh *` in `excludedCommands` instead.
- **SSH keys are unreadable.** `~/.ssh` is denied, so a `git push` that needs your key fails inside `sbx`. Push from your own shell.

## Customizing

`sbx` looks up `<profile>.sb` in this order, and the first match wins:

1. `$TUIDEV_SANDBOX_DIR/<profile>.sb`
2. `~/.config/tuidev/sandbox/<profile>.sb` (`$XDG_CONFIG_HOME` is honored). This is where `--sandbox` installs the profiles.
3. `<repo>/configs/sandbox/profiles/<profile>.sb`

To change a policy, copy a profile and edit it rather than writing one from scratch. The syntax is TinyScheme (`;` starts a comment). `sbx` passes `PROJECT_DIR`, `HOME_DIR` and, for `--allow-herdr`, `ALLOW_HERDR`.

**Upgrades replace a profile only if you haven't edited it.** An installed profile that is byte-identical to any version tuidev shipped (fingerprinted in `configs/sandbox/profiles/shipped.sha256`) is backed up and replaced, so policy fixes reach you. One you edited is kept, and the installer prints the `diff` command to compare it with the shipped version. `make update-security` shows the same diff.

## Tier 2: containers

`./install.sh --pack sandbox-container` provides a container runtime for work that needs kernel-namespace isolation, per-host egress rules or a disposable filesystem. It picks the first runtime present, in this order:

1. Apple `container` (macOS 26+, one lightweight VM per container)
2. Podman
3. Docker

If none is present, it installs Podman and points you at Apple's signed package. Force a runtime with `TUIDEV_CONTAINER_RUNTIME=container|podman|docker`. `make sandbox-up` and `make sandbox-down` start and stop it. The pack provides the runtime only. Run your agent in a container image or devcontainer of your choice. Docker Desktop and OrbStack are never installed, because they aren't FOSS.

## Troubleshooting

- **`Operation not permitted`** from a tool inside `sbx`: Seatbelt denied an operation. Watch the log in another terminal and re-run the command:
  ```bash
  log stream --predicate 'sender == "sandboxd"' --info --debug
  ```
- **`invalid data type of path filter; expected pattern, got boolean`**: a custom profile references a `(param "…")` that `sbx` doesn't pass.
- **A network call fails**: `strict` allows only port 443. Try `--profile standard`.
- **Profile edits have no effect**: an earlier entry in the lookup order shadows your copy, or your copy predates the one you edited.

## Non-goals

Kernel exploits (Seatbelt is policy on a shared kernel), Linux namespaces (use Tier 2), and input or clipboard protection (the sandbox governs files and sockets, not the keyboard or pasteboard).
