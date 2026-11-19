# Secrets

Keep your API tokens where agents can't read them. They belong in an encrypted store, typed once, never in a dotfile or your shell history, and handed only to the commands that need them. `secret` (in `~/.local/bin`, installed by the core pack on every profile) does that with the store your OS already has. This page is the practice; the sandbox side is in [sandboxing.md](sandboxing.md).

## Why not in `.zshrc`

An `export NPM_TOKEN=...` line in `~/.zshrc`:

- is plain text on disk, in every backup, and in any dotfiles repo you sync;
- is readable by every process running as you, agents included: `~/.zshrc` can't be denied to them, since their shells read it;
- is exported into everything that shell starts: the agent CLI, every command it runs, MCP servers, `npm install` scripts;
- usually got there by pasting, so it is in your history as well.

## `secret`

| Command | What it does |
|---------|--------------|
| `secret set NAME` | Stores a value read from a hidden prompt, or from stdin when piped (`pbpaste \| secret set NAME`). Never from the command line, which shows in `ps` and history. Setting it again replaces it. |
| `secret get NAME` | Prints the value, for `$(...)`. |
| `secret ls`, `secret rm NAME` | Lists names (never values), deletes one. |
| `secret run -n NAME [-n NAME]... -- CMD` | Runs CMD with those secrets in its environment, and nothing in your shell. `--all` passes every secret (an empty store passes none and still runs CMD; a store that can't be listed stops it, exit 1); `--optional` starts CMD even when one can't be read or the store can't be listed. |
| `secret export NAME...` | Prints `export NAME='value'` lines for `eval`. |
| `secret scan [FILE...]` | Lists token-looking literal exports as `FILE:LINE: NAME`, never the value. Exit 1 on a hit. Default files: `~/.zshrc`, `~/.zshrc.local`, `~/.zprofile`, `~/.zshenv`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.config/zsh/*.zsh`. |
| `secret import [--dry-run] [--remove] FILE [NAME...]` | Stores FILE's literal `NAME=value` lines (the ones `scan` flags, or the NAMEs given). It lists names and line numbers first. `--remove` then replaces each line with a comment, after writing `FILE.secret-backup-<time>` (mode 600) with the values taken out. `--dry-run` only lists. |

**Stores**, picked in this order: the macOS login Keychain (generic passwords, service `tuidev`, account NAME; Keychain Access lists each under its own name, kind `secret`); libsecret through `secret-tool` when a desktop session bus is running (GNOME Keyring, KWallet); `pass` (entries `tuidev/NAME`). With none, `secret` says what to install and exits 3; it never writes a plaintext file. `TUIDEV_SECRET_BACKEND=keychain|secret-tool|pass` picks one.

**Names** are shell variable names (`[A-Za-z_][A-Za-z0-9_]*`). **A value is one line**: one trailing `\n`, `\r\n` or `\r` is dropped, and a value with a newline or NUL inside is refused. Any other byte is kept as is.

**How a value travels.** It never goes into an external command's argv, a temp file or `eval` inside `secret`. On macOS it reaches `security` on stdin (`security -i`, as hex with `-X`), because `add-generic-password -w VALUE` would put it in argv; after each write `secret` reads it back and fails unless it matches. A value with bytes outside printable ASCII is stored as `tuidev-hex:` plus hex, because `security -w` prints such values as hex itself; Keychain Access shows it that way. `secret-tool store` and `pass insert -m` take it on stdin.

## Three ways to use one

**1. Per command (recommended).** The value exists only in that command's environment:

```bash
secret run -n NPM_TOKEN -- npm publish
secret run -n DEPLOY_TOKEN -n DEPLOY_URL -- ./scripts/deploy.sh
```

For a tool you run all day, wrap it in your own `~/.zshrc.local`; `--optional` suits a token the tool can do without, such as a remote build cache:

```zsh
buildtool() { secret run --optional -n BUILD_CACHE_TOKEN -- command buildtool "$@"; }
```

**2. Per shell.** For a variable every command needs, in `~/.zshrc.local`:

```zsh
eval "$(secret export BUILD_CACHE_TOKEN SIGNING_KEY)"
```

It costs one store call per name at every shell start. `secret` itself adds about 12 to 17 ms for two names (measured with a stub store on an Apple silicon Mac, bash 3.2 and 5); the Keychain lookups come on top, so time yours with `time (secret export A B >/dev/null)`. The values are then in that shell's environment, and so in every agent CLI you start from it (below).

**3. A mode-600 file.** `~/.config/zsh/secrets.zsh` sourced from `.zshrc` keeps the values out of `.zshrc`, and tuidev denies that one path to `sbx` and Claude Code. It is still plaintext on disk and in backups, readable by any unconfined process running as you, and exported to everything like level 2. Use it only where no store works, and move off it with `secret import --remove`.

## What an agent can reach

A variable exported in the shell you start `claude` or `codex` from is in the agent's environment and in every command it runs. `secret run` never puts anything there. So level 1 keeps values away from agents and level 2 hands them over, unless you also strip them:

- **Claude Code** unsets the variables listed in `sandbox.credentials.envVars` before each sandboxed command and the processes it starts. The shipped settings list publish and cloud tokens (`GITHUB_TOKEN`, `NPM_TOKEN`, `GITLAB_TOKEN`, `HF_TOKEN`, `CLOUDFLARE_API_TOKEN`, `VERCEL_TOKEN`, `STRIPE_API_KEY` and others); add your level-2 names in your own `~/.claude/settings.json` (`{ "name": "BUILD_CACHE_TOKEN", "mode": "deny" }`). Names are exact: no wildcards. Claude Code itself, hooks, MCP servers and the unsandboxed `gh` still have them.
- **Codex** removes the same names, plus `TF_TOKEN_*`, from every command it runs, inside its sandbox or not (`[shell_environment_policy.filters]` in `~/.codex/config.toml`; patterns take `*` and `?`). Add yours there as `NAME = "exclude"`.
- **The model providers' own keys are on the list** (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY`): the CLI keeps its login, the commands it runs don't get the key. A test or eval that calls the model API, or a nested `claude -p` or `codex exec` that logs in by key, then needs the key in its own command (`secret run -n ANTHROPIC_API_KEY -- npm run eval`, run by you) or that name removed from your copy of the settings.
- **Not on the list:** `DATABASE_URL` and `PGPASSWORD` (tests often need a local one). Add them the same way if your shell exports production values.

Reading the store directly is the other way in. What stops an agent's command from doing that, by store and by sandbox:

| Store | `sbx` (`strict`, `standard`) | Claude Code, shipped settings | Codex `workspace-write` |
|-------|------------------------------|-------------------------------|--------------------------|
| macOS Keychain | Blocked: `~/Library/Keychains` is denied. Lookups to the Keychain service are not denied; the file deny is what stops it, and Claude Code's own Keychain login fails under `sbx` for the same reason. | Bash runs under the same `~/Library/Keychains` deny (not yet checked against `security`), and deny rules refuse `secret get`, `secret export`, `secret run` and `security find-generic-password`, `find-internet-password`, `dump-keychain`. | **Not blocked by the sandbox**: it doesn't limit reads. `forbidden` command rules for the same commands. |
| libsecret (Linux) | `sbx` is macOS only. | The keyring files (`~/.local/share/keyrings`) are denied, but the unlocked keyring answers over D-Bus; whether the sandbox lets a command reach the session bus is not checked. Deny rules refuse `secret-tool lookup` and `search`. Treat as **not blocked** beyond the rules. | **Not blocked** by the sandbox; command rules only. |
| `pass` | Blocked: `~/.password-store` and `~/.gnupg` are denied. | Blocked for Bash and `Read`: the same two paths. Deny rule for `pass show`. | **Not blocked**: Codex can read the store and use an unlocked `gpg-agent`; command rules only. |

Command rules match the plain command (`secret get X`), not a script or `sh -c` that runs it, so they catch a mistake, not a determined agent. The sandbox is the boundary. That gives the recommendation:

- Use `secret run`, and don't export secrets in the shell you start agents from. If you must, list the names in `sandbox.credentials.envVars` and Codex's `[shell_environment_policy.filters]`.
- For Codex near secrets that matter, run it under `sbx` (`sbx -- codex -s danger-full-access -a on-request`), which denies the stores, instead of `workspace-write`.
- `secret run -n NAME -- claude` hands NAME to the agent. Do it only when you mean to.
- On macOS, items written by `security` trust `/usr/bin/security`, so any unconfined process running as you reads them without a prompt. For a high-value token, open it in Keychain Access, Access Control, and set "Ask for Keychain password".

**Check it on your machine** with a throwaway value, so nothing real lands in a transcript:

```bash
printf 'probe\n' | secret set TUIDEV_PROBE
sbx -- secret get TUIDEV_PROBE                 # expect: "the Keychain refused to read TUIDEV_PROBE", exit 1
# In a Claude Code session, ask it to run:
#   secret get TUIDEV_PROBE                    # expect: refused by a deny rule
#   sh -c 'secret get TUIDEV_PROBE'            # expect: the Keychain refused to read (the sandbox); "probe" means it isn't blocked
# In a Codex session (workspace-write), the same two:
#   the first is forbidden by a rule; the second prints "probe": Codex's sandbox does not stop it
secret rm TUIDEV_PROBE
```

## Moving tokens out of a file

```bash
secret scan                                             # which files, which names
secret import --dry-run --remove ~/.config/zsh/secrets.zsh
secret import --remove ~/.config/zsh/secrets.zsh        # store, then take the lines out
```

Then use them with `secret run` or `secret export` as above, delete the backup once the shell works, and remove a file that is now empty along with the line that sources it. A token that was ever in a synced dotfiles repo or a shared history should be rotated too.

## Per-project secrets

Claude Code's `Read` is denied `.env` and `.env.*` (and so is Bash on macOS; on Linux only the literal names, see [sandboxing.md](sandboxing.md#credentials-denied-under-strict-and-standard)), and Codex isn't denied them at all. A `.env` file is still plaintext in the tree the agent works in. Prefer the store, and have the project read environment variables:

```bash
secret run -n DATABASE_URL -n STRIPE_KEY -- pnpm dev
```

For a team, the project's README lists the names each developer stores with `secret set`, never the values. A `.envrc` that runs `export X="$(secret get X)"` works with direnv, but it is level 2: the value is exported in that directory's shells, and in an agent started there.

## When to use something else

`secret` is one person's tokens on one machine, with the store the OS already has. If you need more than that, these do it better:

- **1Password CLI (`op run`)** injects secrets into one command's environment from secret references, with biometric unlock and sharing across a team. If you already pay for 1Password, use it. `secret` is for no account and no app. They are not exclusive: `~/.config/op` is on the sandbox's credential list too.
- **direnv** loads per-directory environment into your shell, which is the inheritance this page warns about: every agent started there gets the values, and a plain `.envrc` holds them in plaintext. Keep it for non-secret settings.
- **sops** encrypts secret files you commit and share (with age, KMS or PGP). It is the better choice for team and deployment secrets. It does not stop an exported token from being inherited on your laptop.
- **envchain** already does the core of `secret run`: Keychain or Secret Service, a namespace per set of variables, a command run with them. If that is all you need, it is a fine choice. `secret` adds the scan and the migration of startup files, a `pass` backend, and a store on the same sandbox list as the rest of tuidev.
- **aws-vault** is the better choice for AWS credentials: short-lived sessions, not just storage.
- **Doppler, Infisical** and similar hosted or self-hosted platforms are for secrets shared across a team and its environments.

`secret` is not a sandbox. The command you pass a token to has it, and so does anything that command starts; `secret run` only narrows that from every process you start. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` strips credentials from what Claude Code's subprocesses inherit, which helps for Claude Code only. Use both.

## After a leak

1. Revoke or rotate the token where it was issued. That is the fix; everything else is cleanup.
2. Store the new one: `secret set NAME` (it replaces the old).
3. Find the copies with file names only, never printing the value: `rg -l -F 'FIRST-CHARS' ~/.zsh_history ~/.claude/projects ~/.codex/sessions <dotfiles repo>`, and atuin's history if you use it. Agent transcripts hold whatever a command printed.
4. A token pushed to git stays in its history and forks: rotating, not rewriting history, is what makes it harmless.

`tuidev uninstall` removes the `secret` command but not your stored secrets; `secret rm` them first if you want them gone.
