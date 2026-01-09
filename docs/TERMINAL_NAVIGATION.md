# Terminal Navigation Guide

> Fixing common keyboard issues in macOS terminals with Zellij

---

## Quick Fixes

### Arrow Keys Not Working in Command Line

**Problem:** Arrow keys navigate Zellij panes instead of moving in the command line.

**Solution:** Press `Ctrl+g` to enter **Locked Mode** - this passes all keys directly to the terminal.

| Key | Action |
|-----|--------|
| `Ctrl+g` | Toggle Locked Mode (pass keys to terminal) |
| `Esc` | Return to Normal Mode |

---

## Common Issues & Solutions

### 1. Arrow keys navigate panes, not command line

```
Symptom: Pressing left/right moves to different panes
Fix: Ctrl+g (Locked Mode)
```

### 2. fn+Delete triggers Caps Lock

```
Symptom: Forward delete activates caps lock indicator
Fix: Already configured in Ghostty config
```

### 3. Option+Arrow doesn't skip words

```
Symptom: Option+Arrow outputs special characters instead of word-jumping
Fix: Already configured in Ghostty with macos-option-as-alt = true
```

### 4. Home/End keys don't work

```
Symptom: Home/End do nothing or trigger wrong actions
Fix: Mapped in Ghostty config to standard sequences
```

---

## Ghostty Key Mappings

The setup includes these key fixes in `~/.config/ghostty/config`:

```
# Navigation keys (fn+arrows for Home/End/PageUp/PageDown)
keybind = fn+left=text:\x1b[1~
keybind = fn+right=text:\x1b[4~
keybind = fn+up=text:\x1b[5~
keybind = fn+down=text:\x1b[6~

# Home/End keys
keybind = home=text:\x1b[1~
keybind = end=text:\x1b[4~

# Ctrl+p pass-through (for Zellij)
keybind = ctrl+p=text:\x10

macos-option-as-alt = true
```

---

## Zellij Modes Explained

| Mode | Purpose | Enter | Exit |
|------|---------|-------|------|
| **Normal** | Default, pane navigation with Alt | Default | - |
| **Locked** | Pass all keys to terminal | `Ctrl+g` | `Ctrl+g` |
| **Pane** | Manage panes | `Alt+p` | `Esc` |
| **Tab** | Manage tabs | `Ctrl+t` | `Esc` |
| **Scroll** | Scroll and search | `Ctrl+s` | `Esc` |

---

## Shell Line Editing Keys

When in **Locked Mode** or using keys that aren't captured by Zellij:

| Key | Action |
|-----|--------|
| `Ctrl+a` | Beginning of line |
| `Ctrl+e` | End of line |
| `Ctrl+u` | Delete to beginning |
| `Ctrl+k` | Delete to end |
| `Ctrl+w` | Delete word backward |
| `Alt+b` | Move word backward |
| `Alt+f` | Move word forward |
| `Ctrl+l` | Clear screen |
| `Ctrl+r` | Search history (atuin) |

---

## Troubleshooting Workflow

1. **Keys not responding as expected?**
   - Check if you're in a Zellij mode (look at status bar)
   - Try `Esc` to exit current mode
   - Try `Ctrl+g` for Locked Mode

2. **Still not working?**
   - Verify Ghostty config: `cat ~/.config/ghostty/config`
   - Verify Zellij config: `cat ~/.config/zellij/config.kdl`

3. **Need to debug key sequences?**
   - Run `cat -v` and press keys to see raw sequences
   - Press `Ctrl+c` to exit

---

## Terminal Emulator Settings

### Ghostty (Recommended)
Already configured with this setup. Verify settings:
```bash
cat ~/.config/ghostty/config
```

### iTerm2
If using iTerm2, configure:
- Preferences > Profiles > Keys > Left Option key: `Esc+`
- Preferences > Profiles > Keys > Right Option key: `Esc+`

### Terminal.app
Limited support. Consider switching to Ghostty.

---

## See Also

- [CHEATSHEET.md](CHEATSHEET.md) - Full keybinding reference
- [ZELLIJ_TROUBLESHOOTING.md](ZELLIJ_TROUBLESHOOTING.md) - Zellij-specific issues
