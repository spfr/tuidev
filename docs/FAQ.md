# FAQ

Troubleshooting, one question at a time. Each topic's full reference is in its own doc: [profiles](profiles.md), [sandboxing](sandboxing.md), [agent workflows](agent-workflows.md), [remote](remote.md), [updating](updating.md).

## Install and update

**Does it work on Intel Macs?** Yes. Homebrew's prefix (`/opt/homebrew` or `/usr/local`) is detected at shell start.

**Does it work on Linux?** `minimal` and `remote` do. Without Homebrew, packages come from `apt-get`, `dnf` or `pacman`, and Debian/Ubuntu (arm64 boards such as a Raspberry Pi included) is the tested path. Anything the distro doesn't package, such as `starship` or `eza` on older Debian releases, is skipped with a link to the upstream install page. On Debian, `fdfind` and `batcat` are symlinked to `fd` and `bat` in `~/.local/bin`. The `ui` pack, Ghostty and Seatbelt (`sbx`) are macOS-only.

**apt wants a password and the installer didn't prompt.** By design: system package managers run only as root or through `sudo -n`. The installer prints the exact command to run yourself.

**`--pack foo` fails immediately.** `--pack` names are checked before anything runs. `core`, `remote`, `sandbox`, `ui` and `extras` are flags (`--sandbox`), not `--pack` names. The valid pack names are listed in [profiles.md](profiles.md#optional-packs).

**The installer stopped halfway. How do I retry?** Re-run the same command. Every step is idempotent. `--dry-run` shows what it would do. A pack that fails to install a tool warns and continues. A failed migration stops the run before any pack runs.

**Where are my backups?** `~/.config/tuidev/backups/` (or `$XDG_CONFIG_HOME/tuidev/backups/`). tuidev backs up a file there before it overwrites or removes it, and keeps the most recent copies of each.

**How do I undo everything?** Run `./uninstall.sh`, or `--dry-run` it first. It removes only what `~/.config/tuidev/manifest` records: the managed blocks, `~/.local/bin` helpers, the git defaults tuidev set (while they still hold tuidev's value) and, if you agree, the configs and Homebrew packages tuidev installed. CLI auth and session state are never touched. See [updating.md](updating.md#uninstall).

**Something broke after an update.** Run `make check`, then `make update-check` to see config drift and pending migrations. A failed migration is not recorded, so the next `make update-migrations` retries it.

## Shell and terminal

**`work`, `dev`, `ai`, `ai-triple` and the other tmux layouts are gone.** 3.0 dropped every tmux-wrapper function and its ten layouts, along with `tk`/`tka` and `make test-layouts`. tmux itself is now optional (`--pack tmux`), not baked into any profile except `remote`. `.zshrc` keeps only a small attach-or-create helper: `t [NAME]` (default session name `main`) and `tls` to list sessions. See [remote.md](remote.md#connect-and-re-attach).

**`ld` no longer opens lazydocker.** It is `lzd` now. An `ld` alias shadowed the linker for builds and agents.

**Up arrow doesn't open atuin.** By design: Up recalls history entries that start with what you have typed. `Ctrl+r` opens atuin.

**The shell is slow to start.** A stock shell starts in about 70 ms. Measure it with `time zsh -i -c exit`. Tool init scripts (starship, zoxide, atuin, fzf) are cached in `~/.cache/zsh/init-*.zsh` and regenerate when the tool's binary changes. jenv and nvm load lazily, on first use. Look in `~/.zshrc.local` for anything that sources `nvm.sh` or runs `eval "$(tool init)"` eagerly. After installing new completions, run `rm ~/.cache/zsh/zcompdump-*`.

**Word jumps, Home or End print garbage.** In Ghostty, Option acts as Alt (`macos-option-as-alt = true`), so `Alt+b` / `Alt+f` move by word, and the shipped `.zshrc` binds Home, End and Delete. In iTerm2, set Preferences → Profiles → Keys → Left/Right Option key to `Esc+`. To see what a key actually sends, run `cat -v` and press it.

**Keys work in plain zsh but not inside tmux.** Only relevant with `--pack tmux` installed. Check `echo $TERM`: it should be `tmux-256color` inside tmux and `xterm-ghostty` (or `xterm-*`) outside. Shift+Enter and modified keys depend on `extended-keys`: run `tmux show -s extended-keys`. Reload with `Ctrl+a r`, or restart the tmux server after a tmux upgrade.

**Ghostty tabs broke on macOS 27.** Stable Ghostty 1.3.1 collapses the titlebar tab strip (ghostty-org/ghostty#13070). The shipped config keeps the default `transparent` titlebar, which works. For titlebar tabs, add `auto-update-channel = tip` and `macos-titlebar-style = tabs` to `~/.config/ghostty/config`, outside the managed block, then restart Ghostty.

**Where do my own aliases and SSH hosts go?** In `~/.zshrc.local` and `~/.ssh/config.local`. Both are sourced or included, and never overwritten. Keep personal hosts out of the repo.

## tmux

tmux is optional now (`--pack tmux`), bundled automatically by the `remote` profile. These only apply once it's installed.

**The theme didn't apply to tmux.** Themes live in `~/.config/tmux/theme.conf`, which the shipped `tmux.conf` sources above its plugin block. If your managed `tmux.conf` predates the theme-file split, run `make update-configs`, then `make theme NAME=...` again.

**tmux-continuum stopped auto-saving.** Older configs appended the theme below the TPM line, which reset `status-right` after continuum hooked it. Migration `202609222000_tmux_theme_file` moves that block into `theme.conf`. Run `make update-migrations`, then `make update-configs`.

**Agent-team teammates don't open as panes.** Split panes need `claude` to run inside tmux (the shipped `teammateMode` is `auto`), which means `--pack tmux` installed and a session already attached. Outside tmux, teammates run in-process. See [agent-workflows.md](agent-workflows.md#agent-teams).

## Sandbox

**Do I still need `sbx` if I run plain `claude` or `codex`?** Usually not: their own native sandboxes are on by default (`sandbox.enabled` in `~/.claude/settings.json`, `sandbox_mode = "workspace-write"` in `~/.codex/config.toml`). They differ, though: Claude Code's denies the credential paths to its Bash tool, while Codex's `workspace-write` limits writes and network but not reads. For credential-sensitive Codex work, use `sbx -- codex -s danger-full-access -a on-request`. `sbx` is also the general-purpose wrapper for anything else you want confined. Never wrap a CLI whose native sandbox is on with `sbx` — Seatbelt doesn't nest; turn the native one off for that run (`sbx -- claude --settings '{"sandbox":{"enabled":false}}'`).

**Claude Code asks me to log in.** Under the native sandbox (the shipped default) the Keychain works normally, so this shouldn't happen. If you instead run Claude Code under `sbx` (`sbx -- claude --settings '{"sandbox":{"enabled":false}}'`), the Keychain is denied inside `sbx`; run `claude setup-token` once and export the result as `CLAUDE_CODE_OAUTH_TOKEN` in `~/.zshrc.local`. See [sandboxing.md](sandboxing.md#native-sandboxes-the-default).

**`gh` says I'm not logged in.** `~/.config/gh` is on the credential deny list under every `sbx` profile, and `--profile standard` does not change that. Under the native sandbox, `gh *` is in `excludedCommands`, so it runs outside the sandbox and just needs your normal permission approval. Under `sbx`, run `sbx --profile off -- gh ...`.

**`npm install`, `pip install` or `git push` over ssh fails.** `strict` allows only TCP 443. Use `sbx --profile standard -- CMD`, which adds ports 80, 22 and 9418.

**Codex or Claude Code reports `sandbox_apply: Operation not permitted`.** Seatbelt profiles don't nest. This happens if you run `sbx -- codex` or `sbx -- claude` without telling the CLI to step aside: pass `-s danger-full-access -a on-request` to Codex, or `--settings '{"sandbox":{"enabled":false}}'` to Claude Code, so `sbx` is the only sandbox. Otherwise just run plain `codex` or `claude`: their own sandboxes are the default and need no `sbx` at all.

**The sandbox blocks something legitimate.** For `sbx`, copy the profile into `~/.config/tuidev/sandbox/<name>.sb` and edit it: that copy takes precedence over the shipped one. To find the rule that fired, see the [sandboxing troubleshooting](sandboxing.md#troubleshooting). For the native sandboxes, adjust `excludedCommands` / `allowedDomains` in `~/.claude/settings.json` or `approval_policy` in `~/.codex/config.toml`. Don't punch holes in the credential deny list.

**How do I turn the sandbox off?** For `claude`/`codex`, set `sandbox.enabled: false` in `~/.claude/settings.json` or `sandbox_mode = "danger-full-access"` / `approval_policy = "never"` in `~/.codex/config.toml`, from your own shell. For `sbx`: `sbx --profile off -- CMD`, or don't install `--sandbox`.

## AI CLIs

`--pack ai-clis` adopts/upgrades `~/.claude/settings.json` and `~/.codex/config.toml`, which turn on the native sandboxes; it doesn't install `claude` or `codex` themselves. `oc` (OpenCode) needs `--pack opencode`.

**`claude` or `codex` not found.** They update themselves and aren't installed by tuidev. Follow each CLI's own install instructions, then open a new shell so `--pack ai-clis`'s settings apply.

**Which instruction file does each CLI read?** See the table in [agent-workflows.md](agent-workflows.md#instruction-files).

## Neovim

Neovim is optional now (`--pack nvim`).

**Plugins are broken.** Run `rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim`, then start `nvim`. LazyVim reinstalls everything.

**The LSP doesn't work.** Run `:LspInfo`, then `:Mason` to install the missing server, then `:checkhealth`.

## Getting help

Open an issue that includes your tuidev version (`git describe --tags`), your OS version, your profile and packs (`cat ~/.config/tuidev/profile`) and the output of `make check`. Report security issues through [SECURITY.md](../SECURITY.md).
