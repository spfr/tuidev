# Remote Sessions Setup

Ultimate remote access for AI agentic development - work from your phone, tablet, or anywhere.

## Quick Start

```bash
# Start remote session
remote

# Check remote access status
remote-status
```

## Remote Access Methods

### 1. Tailscale (Recommended) - Secure Mesh VPN

**Why Tailscale?**
- Zero configuration networking - no port forwarding, no firewall rules
- End-to-end encrypted WireGuard tunnels
- Works from behind any NAT/firewall
- Free for personal use (up to 100 devices)
- Stable IPs that don't change (100.x.x.x)
- Works with mosh for resilient mobile connections

**Setup:**
```bash
# 1. Tailscale is installed via install.sh
# 2. Open Tailscale from Applications and sign in
# 3. Enable SSH on your Mac:
sudo systemsetup -setremotelogin on

# 4. Check your Tailscale IP:
ts-ip

# 5. From any other Tailscale device:
ssh your-username@100.x.x.x

# 6. For mobile connections (handles network switches):
mosh your-username@100.x.x.x
```

**Shell Functions:**
```bash
ts-status       # Show Tailscale network status
ts-ip           # Show your Tailscale IPv4 address
remote-status   # Dashboard: SSH, Tailscale, Zellij sessions
tunnel          # Start public tunnel (shows Tailscale info first)
```

**Using mosh for Mobile:**

Mosh (mobile shell) handles intermittent connectivity, IP changes, and high latency. It's installed automatically.

```bash
# From another machine with mosh installed:
mosh your-username@100.x.x.x

# Then attach to your Zellij session:
zellij attach
```

### 2. Claude Code Notification Hooks

When working remotely, get notified on your Mac when Claude Code needs attention:

```bash
# Notifications are configured automatically via settings.json hooks:
# - "Approval Required" notification when Claude needs input
# - "Done" notification when a task completes

# Test notifications manually:
notify.sh "Test" "Hello from remote session"
```

The hooks are defined in `configs/claude/settings.json` and use `notify.sh` which must be in your PATH (`~/.local/bin/`).

---

## Public Access Alternatives

For accessing your Mac from outside your Tailscale network (or without Tailscale):

### 3. Cloudflare Tunnel - FREE & Secure

**Pros:**
- No port forwarding needed
- Works from behind any firewall/NAT
- Built-in authentication
- Fast with Cloudflare's network
- Completely free

**Setup:**
```bash
# Cloudflare tunnel is already installed via install.sh
tunnel  # Start tunnel on port 22 (SSH)
```

Cloudflare will give you a URL like:
```
tcp://https://v2-abc123.trycloudflare.com:22
```

**Connect from phone:**
```bash
# Use any SSH client (Termius, Blink, iOS SSH)
ssh -J v2-abc123.trycloudflare.com your-mac-user@localhost
```

Or configure in SSH client:
- Host: `v2-abc123.trycloudflare.com`
- Port: `22`
- User: `your-mac-user`
- Use jump host enabled

### 4. ngrok (Free Alternative)

```bash
# Install via Homebrew
brew install ngrok

# Start tunnel
ngrok tcp 22
```

ngrok gives you a forwarding URL to use in SSH client.

### 5. Bore (Open Source)

```bash
brew install bore-cli

# On your Mac:
bore local 22 --to bore.pub

# From anywhere:
ssh -p [port] user@bore.pub
```

### 6. localhost.run (Quickest, No Install)

```bash
ssh -R 80:localhost:22 nohup@localhost.run
```

Gives you a URL immediately. Great for quick sessions.

## Recommended SSH Clients (iOS/Android)

### iPhone
1. **Termius** (Best - syncs across devices)
   - Auto-discovery of keys
   - Beautiful interface
   - Snippets and sync
   - Free for basic use

2. **Blink Shell** ($14, excellent terminal)
   - Modern and fast
   - Good keyboard support

3. **iTerminal SSH** (Free)
   - From iTerm2 developers
   - Simple and reliable

4. **Prompt** ($14, modern)
   - Great for developers
   - Built-in file browser

### Android
1. **Termius** (Best - syncs)
2. **JuiceSSH** (Free, good)
3. **ConnectBot** (Free)

## Remote Session Workflow

### Setup Your Mac

```bash
# Option A: Tailscale (recommended - always-on, no tunnel needed)
# 1. Ensure Tailscale is running and connected
ts-status

# 2. Start zellij remote session
remote

# 3. From your phone/other device (on Tailscale network):
#    ssh your-username@100.x.x.x
#    zellij attach

# Option B: Public tunnel (for access outside Tailscale network)
# 1. Start zellij remote session
remote

# 2. In the "Tunnel" pane, start cloudflare tunnel
tunnel

# 3. Copy the URL from output
```

Example output:
```
+--------------------------------------------------------------------------+
|  Your quick Tunnel has been created!                              |
| Visit it at: https://xxxxx-xx-xxxxx.trycloudflare.com              |
+--------------------------------------------------------------------------+
```

### Connect from Phone

Using Termius (recommended):

1. **Open Termius app**
2. **Add new host** → Import from QR or manual:
   ```
   Host: xxxxx-xx-xxxxx.trycloudflare.com
   Port: 22
   User: (your username)
   Auth key: (add your SSH key to phone)
   ```

3. **Connect** → You're in your Zellij session!

### Using from Desktop

```bash
# From any other computer:
ssh -J xxxxx-xx-xxxxx.trycloudflare.com user@localhost
```

## AI Commands While Remote

Once connected, you can run AI commands in separate panes:

```bash
# In nvim (left pane):
# Edit code with LazyVim

# In Agent-1 pane (right pane):
opencode "Analyze this function"  # Run AI coding agent

# In Agent-2 pane:
claude "Write tests for this file"  # Generate tests

# In Shell pane:
lazygit  # View git status
```

## Best Practices for Remote Development

### 1. Use SSH Keys (Not Passwords)

```bash
# Generate key (if you don't have one)
ssh-keygen -t ed25519 -C "your@email.com"

# Copy to phone
# - On Mac: cat ~/.ssh/id_ed25519.pub
# - On phone: Paste in Termius → Settings → Keys
```

### 2. Keep Sessions Lightweight

- Use `ai-single` for phone work (1 agent)
- Use `ai` or `ai-triple` for desktop work (2-3 agents)

### 3. Auto-Start on Boot

Create a LaunchAgent to start tunnel automatically:

```bash
# Create: ~/Library/LaunchAgents/com.cloudflared.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/cloudflared</string>
        <string>tunnel</string>
        <string>--url</string>
        <string>tcp://localhost:22</string>
        <string>run</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>

# Load it
launchctl load ~/Library/LaunchAgents/com.cloudflared.plist
```

### 4. Quick Connect Script

Add to `~/.zshrc.local`:

```bash
# Quick connect to your Mac
connect-mac() {
    ssh -J your-tunnel-url.trycloudflare.com $(whoami)@localhost
}
```

### 5. Monitor Remote Sessions

```bash
# On your Mac, see connected sessions:
zellij list-sessions

# See active SSH connections:
who
```

## Security Tips

1. **Use SSH keys only** - Disable password authentication
   ```bash
   # /etc/ssh/sshd_config
   PasswordAuthentication no
   PubkeyAuthentication yes
   ```

2. **Use firewall rules** - Only allow from Cloudflare IPs
3. **Set timeout** - Auto-disconnect inactive sessions
4. **Monitor logs** - Check `/var/log/system.log` regularly

## Troubleshooting

### "Connection refused"
- SSH server might be down
- Check: `sudo systemsetup -getremotelogin`

### "Host key verification failed"
- Tunnel URL changed (Cloudflare refreshes sometimes)
- Delete old key from phone's known_hosts

### "Permission denied"
- SSH key not added to phone
- Check `~/.ssh/authorized_keys` on Mac

### Tunnel URL changes every time
Cloudflare free tier gives random URLs. Use paid tier for fixed URL ($5/month).

### Session times out
- Keep activity or use autossh:
  ```bash
  brew install autossh
  autossh -M 0 -J tunnel-url user@localhost
  ```

## Advanced: Collaborative Remote Work

Multiple developers can join same Zellij session!

```bash
# Developer 1 (on Mac):
remote

# Developer 2 (from anywhere):
ssh -J tunnel-url user1@localhost
zellij attach ai-dual-1234567890  # Attach to same session

# Now both can see/edit same panes!
```

Perfect for:
- Pair programming
- Debugging together
- Code reviews
- Teaching/mentoring

## Resources

- [Cloudflare Tunnels Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Termius Documentation](https://termius.com/documentation)
- [Zellij Documentation](https://zellij.dev/documentation)
- [SSH Best Practices](https://www.ssh.com/academy/ssh/best-practices)
