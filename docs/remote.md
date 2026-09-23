# Remote and Mobile

The host runs the terminal, tmux, the editor and the agents. You connect from any client and re-attach. Work survives disconnects because tmux does. Tailscale, SSH, mosh and phone apps are only transport.

> **Only need to steer an agent from your phone?** Claude Code's native Remote Control covers that without SSH (see [agent-workflows.md](agent-workflows.md#remote-control-from-a-phone)). This doc covers the full-terminal path underneath it.

## Setup

On the machine you'll connect to:

```bash
./install.sh --profile remote     # or, on a Mac you also sit at: --profile desktop --remote --pack tmux
tailscale up && tailscale status  # join the tailnet
```

`remote` = core + remote + sandbox + `--pack tmux`, so a single `--profile remote` install gets Tailscale, mosh, SSH and a durable tmux session together — you don't add `--pack tmux` yourself. `--remote` on its own installs Tailscale (a cask on macOS; on Linux it links to the official installer), mosh, the SSH client config as a managed block, and sshd hardening snippets: key-only auth, no root login, modern ciphers. The snippets are copied into `/etc/ssh/sshd_config.d/` only when that directory is writable. Otherwise the installer prints the `sudo cp` commands. On macOS, turn on Remote Login in System Settings → General → Sharing, or run `sudo systemsetup -setremotelogin on`.

`remote-status` shows SSH, Tailscale and tmux at a glance. `ts-ip` prints the node's Tailscale address.

## Connect and re-attach

```bash
ssh devbox                  # or: tailscale ssh devbox
t myproject                 # attach-or-create a named tmux session
# ...network drops, laptop sleeps...
ssh devbox && t myproject
```

Detach with `Ctrl+a d`. `tls` lists sessions on the box. tmux-continuum saves every 15 minutes and tmux-resurrect restores sessions when tmux starts, so sessions survive a reboot too. There's no prebuilt layout anymore — `t myproject` gives you a plain session, and you run your editor of choice (`nvim`, or split a second SSH session for it) inside it.

**Why Tailscale SSH:** ACLs live in the tailnet rather than in `authorized_keys` files on every host, check mode can force re-authentication, access follows your identity provider, and a revoked device loses access immediately. Plain SSH still works as a fallback. Cloudflare and ngrok tunnels (the `tunnel` function) are a last resort, not the architecture.

## mosh for flaky networks

Use mosh on cellular, roaming Wi-Fi, or a laptop that sleeps a lot. It comes with `--remote`, or on its own with `--pack mosh`.

```bash
mosh devbox -- tmux attach -t myproject
```

mosh needs UDP 60000–61000 open on the server. Its scrollback is only partially synced, so use tmux copy mode (`Ctrl+a [`) for history. A server reboot kills mosh but not tmux: always run mosh around tmux.

## Always-on nodes

A cheap box that stays awake (a Raspberry Pi, NUC or VM) is a **node**, not a second product. Put work there that must outlive your laptop lid. `--profile remote` installs on Debian/Ubuntu without Homebrew (see [profiles.md](profiles.md)). Herdr adds a sidebar that spans machines:

```bash
herdr machine add workbox --label workbox   # once, interactively
herdr --machine workbox agent list          # from the Mac, no TUI
herdr --remote workbox                      # one-off thin client
```

On a node, `~/.local/bin` must be on `PATH` for *non-interactive* SSH too, which means adding it to `~/.profile`, not only `.zshrc`. Fleet practices are in [agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr).

## Personal hosts stay local

`devbox` and `workbox` are placeholders. Real hostnames, Tailscale IPs and usernames go in `~/.ssh/config.local`. The shipped SSH block starts with `Match all` and then `Include ~/.ssh/config.local*`, so the include applies even when the block lands after your own `Host` stanzas, and a missing file is ignored. You can also put hosts outside the tuidev markers in `~/.ssh/config`. The shipped block keeps connections alive (`ServerAliveInterval 60`) and adds `IgnoreUnknown UseKeychain`, so the same file works with Linux OpenSSH.

## iPhone and iPad

| Client | Why pick it |
|--------|-------------|
| **Blink Shell** | Power users: native mosh, a full local shell, a customizable keyboard, iCloud sync |
| **Moshi** | Agent-first: native mosh, an agent inbox, Live Activities and Apple Watch actions, voice input for prompts |
| Termius | Cross-platform host and key sync, SFTP, snippets |
| a-Shell / Prompt | Lightweight options for occasional local-network SSH |

Setup is the same for every client:

1. Install Tailscale on the phone and sign in to the same tailnet.
2. Generate an **Ed25519** key in the app, and append its public key to `~/.ssh/authorized_keys` on the host (`chmod 600` the file, `chmod 700 ~/.ssh`). The shipped sshd snippet disables password login.
3. Add a host with the node's Tailscale name or `100.x` address (`ts-ip`), your user, port 22, and **mosh** as the protocol if the app offers it.
4. Connect and run `t myproject`.

Tips:

- The prefix `Ctrl+a` comes from the app's extra key row. Map a snippet to `Ctrl+a d` to detach quickly.
- Bigger fonts help on a phone screen; a single tmux pane reads better than a cramped split.
- A Bluetooth keyboard makes every tmux and nvim binding usable.
- *Connection refused:* check that Remote Login is on (`sudo systemsetup -getremotelogin`) and that the Mac isn't asleep.
- *Laggy over cellular:* switch the host to mosh. *Keeps dropping:* the shipped keepalives help, and mosh plus tmux makes drops irrelevant.

## Anti-patterns

- Hand-rolled key rotation when Tailscale SSH already owns access control.
- `screen`. tmux-resurrect and continuum target tmux.
- Agents on the host filesystem with no sandbox. See [sandboxing.md](sandboxing.md).
- Committing real hostnames or IPs. See [CONTRIBUTING.md](../CONTRIBUTING.md#personal-vs-published).
