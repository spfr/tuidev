# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 3.x (latest minor on `main`) | :white_check_mark: |
| 2.x and earlier | :x: |

## Reporting a vulnerability

Please do **not** open a public issue. Use GitHub's private vulnerability reporting (Security → Report a vulnerability) or email the maintainers. Include the affected file or command, your tuidev version (`git describe --tags`), your OS, and reproduction steps. Give us a reasonable window to fix the issue before you disclose it.

Especially in scope: a Seatbelt profile (`configs/sandbox/profiles/*.sb`) or `bin/sbx` that lets a sandboxed process read a denied credential path or write outside the project directory; an installer or uninstaller step that destroys user data outside what the manifest records; and shipped agent settings that weaken the documented boundary.

## Security model

- **Sandboxed agents.** `--pack ai-clis` ships Claude Code and Codex with their native sandboxes on, so plain `claude` and `codex` run confined. Codex's `workspace-write` limits writes and network but not reads; for credential-sensitive Codex work use `sbx -- codex -s danger-full-access -a on-request`. `sbx` (macOS Seatbelt) confines any other command. Under `sbx` (and, for Claude Code's Bash tool and `Read`, under its native sandbox and shipped deny rules), credential stores such as `~/.ssh`, `~/.aws`, `~/.gnupg`, the Keychain, `~/.config/gh`, cloud CLIs, package-registry tokens and password stores are denied for both reads and writes. The full list, and what Seatbelt cannot do (per-host network rules), is in [docs/sandboxing.md](docs/sandboxing.md).
- **Secrets stay out of the repo.** Put tokens and API keys in `~/.zshrc.local`, which is never written by tuidev and is gitignored in a clone. Set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` to keep them out of the environment that agent subprocesses inherit.
- **Nothing is piped into a shell.** When a package manager can't provide a tool, the installer prints the vendor's official install command for you to review and run. Read any `curl … | sh` command before you run it yourself.
- **Non-destructive by default.** `--dry-run` previews every mutation, overwritten files are backed up to `~/.config/tuidev/backups/`, and `./uninstall.sh` removes only what the install manifest records.
- **Pinned CI.** GitHub Actions are pinned to commit SHAs and updated by Dependabot.

Keep tools current with `make update-packages`, and audit Tailscale, SSH permissions and Seatbelt profile drift with `make update-security`.
