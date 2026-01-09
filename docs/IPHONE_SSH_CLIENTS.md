# SSH Clients for iPhone

Top recommendations for connecting to your Mac from iPhone:

## 1. Termius (Best Overall) ⭐

**App Store:** https://apps.apple.com/app/termius/id549039008

**Pros:**
- ✅ Beautiful, modern UI
- ✅ Excellent SSH key management
- ✅ Supports Mosh for poor connections
- ✅ SFTP file browser built-in
- ✅ Synchronizes hosts across devices
- ✅ Snippets for common commands
- ✅ Port forwarding support

**Pricing:** Free tier available, Pro for advanced features

**Setup:**
1. Download Termius from App Store
2. Tap "+" to add new host
3. Fill in:
   - **Alias:** My Mac
   - **Hostname:** your-mac-ip (or 100.x.x.x if using Tailscale)
   - **Port:** 22
   - **Username:** your-username
4. Tap "Key" and generate or import SSH key
5. Copy public key to your Mac: `cat ~/.ssh/id_ed25519.pub`
6. On Mac: `cat >> ~/.ssh/authorized_keys` (paste your key)
7. Connect and run: `zellij attach ai-dev`

---

## 2. Blink Shell (Most Powerful)

**App Store:** https://apps.apple.com/app/blink-shell/id1594703786

**Pros:**
- ✅ Full zsh shell
- ✅ Supports tmux/zellij perfectly
- ✅ Mosh integration for mobile
- ✅ iCloud sync
- ✅ Customizable keyboard
- ✅ AWS/GCP/Azure integrations
- ✅ Support for TermInfo

**Cons:**
- Higher learning curve
- More expensive ($29.99/year)

**Best for:** Power users who need full shell control

---

## 3. a-Shell (Free, Local Network Only)

**App Store:** https://apps.apple.com/app/a-shell-icmd/id1473805434

**Pros:**
- ✅ Completely free
- ✅ Full Unix shell locally
- ✅ SSH built-in
- ✅ Runs Python, Node.js, Lua locally
- ✅ No ads, no tracking

**Cons:**
- No cloud sync
- No key management (manual)
- Basic UI

**Setup:**
```bash
# On iPhone in a-Shell
ssh username@192.168.1.x
zellij attach ai-dev
```

**Best for:** Quick connections on local network, budget-conscious users

---

## 4. Prompt (Simple & Beautiful)

**App Store:** https://apps.apple.com/app/prompt/id1465280838

**Pros:**
- ✅ Clean, minimal UI
- ✅ Touch ID for authentication
- ✅ SSH key management
- ✅ Supports Mosh

**Cons:**
- Basic features
- No file browser
- No snippet support

**Pricing:** $14.99 one-time purchase

**Best for:** Users who want a simple, no-fuss experience

---

## 5. SecureCRT (Enterprise)

**App Store:** https://apps.apple.com/app/secureshell-ssh-client/id1330623518

**Pros:**
- ✅ Highly customizable
- ✅ Scripting support
- ✅ Enterprise features
- ✅ Multiple protocols (SSH, Telnet, etc.)

**Cons:**
- Expensive ($29.99)
- Complex UI
- Overkill for most users

**Best for:** Network engineers, enterprise users

---

## Quick Comparison

| App | Price | Best For | Key Features |
|-----|-------|-----------|--------------|
| **Termius** | Free/Pro | Everyone | Beautiful UI, sync, file browser |
| **Blink Shell** | $29.99/yr | Power users | Full shell, Mosh, iCloud |
| **a-Shell** | Free | Local network | No cost, runs Python/Node |
| **Prompt** | $14.99 | Simplicity | Clean UI, Touch ID |
| **SecureCRT** | $29.99 | Enterprise | Scripting, customization |

---

## My Recommendation

**For Most Users:** Termius
- Best balance of features and usability
- Great for Zellij sessions
- Excellent SSH key management

**For Power Users:** Blink Shell
- Full shell capabilities
- Best for complex workflows
- Mosh for unstable connections

**For Free/Quick:** a-Shell
- Completely free
- Great for testing
- Works fine for basic SSH

---

## Setting Up Termius (Recommended)

### Step 1: Install & Configure

1. Download Termius from App Store
2. Open app and tap "Get Started"
3. Create account (optional, for sync)

### Step 2: Add Your Mac

1. Tap "+" (New Host)
2. Fill in the details:
   - **Label:** My Mac
   - **Hostname:** `192.168.1.x` (local) or `100.x.x.x` (Tailscale)
   - **Port:** 22
   - **Username:** `your-mac-username`

### Step 3: Set Up SSH Keys

1. In Termius, tap "Key" tab
2. Tap "+" to generate new key
3. Choose: **ED25519** (modern, secure)
4. Name it: `iPhone`
5. Copy the public key

6. On your Mac, add the key:
   ```bash
   # Copy Termius key to Mac
   cat >> ~/.ssh/authorized_keys
   # Paste the key from Termius
   # Press Ctrl+D to save

   # Set correct permissions
   chmod 600 ~/.ssh/authorized_keys
   chmod 700 ~/.ssh
   ```

### Step 4: Connect & Use Zellij

1. In Termius, tap on your Mac host
2. First time: Accept the fingerprint
3. You're now connected!

4. Attach to your Zellij session:
   ```bash
   zellij attach ai-dev
   # or
   zellij list-sessions
   ```

### Step 5: Zellij Tips for Mobile

#### Keyboard Shortcuts in Termius

Termius provides a special keyboard row for Zellij:

- **Esc** - Escape key (important for Zellij)
- **Tab** - Tab completion
- **Ctrl** - Control key combinations
- **Arrow keys** - Navigate panes
- **Function keys** - F1-F12 for modes

#### Managing Sessions

```bash
# List sessions
zellij list-sessions

# Attach to specific session
zellij attach ai-dev

# Attach to latest session (interactive picker)
zellij attach

 # Show session info while attached
 # Press Alt+p, then ? in Zellij
```

#### Copy/Paste in Termius

- **Copy:** Long press text, select, tap "Copy"
- **Paste:** Tap the text area, tap "Paste" button

#### Disconnecting

- **Detach from Zellij:** `Ctrl+o`, then `d`
- **Keep session running:** Just close Termius
- **Reconnect later:** Open Termius, run `zellij attach ai-dev`

---

## Optimizing for Mobile

### 1. Use Simplified Zellij UI

Edit `~/.config/zellij/config.kdl`:
```kdl
ui {
    simplified_ui true  // Simplified UI for mobile
    pane_frames true
}
```

### 2. Reduce Scrollback

```kdl
scrollback_lines 1000  // Less scrollback = faster
```

### 3. Use Larger Fonts

In Termius: Settings → Appearance → Font Size → Increase

### 4. Enable External Keyboard

If using a Bluetooth keyboard:
- Termius Settings → Keyboard → Use External Keyboard
- Enables full keyboard shortcuts

### 5. Set Up Snippets

In Termius, create common commands:
- `zellij attach ai-dev` → `zj`
- `zellij list-sessions` → `zls`
- `tmux attach -t dev` → `tad`

---

## Common Issues

### Issue: Connection Refused

**Solution:**
```bash
# On Mac, check SSH is running
sudo systemsetup -getremotelogin

# If "Remote Login: Off", enable:
sudo systemsetup -setremotelogin on

# Check firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

### Issue: Too Slow Over Cellular

**Solution:** Use Tailscale or Mosh:

**Mosh in Termius:**
1. Host settings → Advanced → Protocol: Mosh
2. Install on Mac: `brew install mosh-server`

### Issue: Keys Don't Work in Zellij

**Solution:** In Termius:
- Settings → Keyboard → Show Ctrl keys: On
- Settings → Keyboard → Custom Esc key: On

### Issue: Can't Type Special Characters

**Solution:**
- Long-press keys for variants (e.g., long-press 0 for `°`)
- Enable "Use External Keyboard" for physical keyboards
- Use Termius's special key row

### Issue: Session Keeps Disconnecting

**Solution:**
1. Use Tailscale for stable connection
2. Enable Mosh in Termius
3. Increase keepalive in `~/.ssh/config`:
   ```ssh
   Host *
       ServerAliveInterval 60
       ServerAliveCountMax 5
       TCPKeepAlive yes
   ```

---

## Security Tips

1. **Use SSH keys instead of passwords** (Termius manages this well)
2. **Enable two-factor authentication** on your Mac
3. **Use Tailscale** instead of exposing SSH to internet
4. **Disable password authentication:**
   ```bash
   # On Mac
   sudo nano /etc/ssh/sshd_config
   # Change: PasswordAuthentication no
   sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
   sudo launchctl load /System/Library/LaunchDaemons/ssh.plist
   ```

---

## Alternative: Web-Based Access

### Zellij Web Interface

Zellij has built-in web support:

```bash
# On Mac, start web server
zellij web --port 8080

# On iPhone, open Safari
http://your-mac-ip:8080
```

**Pros:**
- No app needed
- Works in any browser

**Cons:**
- Less responsive than native app
- Requires opening port (security risk)

---

## Summary

**Best Overall:** Termius (Free tier is excellent)
**Most Powerful:** Blink Shell ($29.99/year)
**Free Alternative:** a-Shell (completely free)

**Quick Start with Termius:**
1. Download Termius
2. Add Mac host
3. Generate SSH key
4. Copy key to Mac
5. Connect: `zellij attach ai-dev`

Happy coding from anywhere! 📱
