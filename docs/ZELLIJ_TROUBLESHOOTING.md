# Zellij Session Troubleshooting

## Problem: Old Orphaned Sessions

If you see sessions like:
```
auspicious-cuckoo [Created 20h 35m 58s ago] (EXITED - attach to resurrect)
exquisite-cowbell [Created 4h 18m 59s ago] (EXITED - attach to resurrect)
...
```

These are **orphaned "resurrect" sessions** that failed to restore. They're not actually running.

## Quick Fix

```bash
# 1. Kill all sessions
zellij kill-all-sessions

# 2. If that fails (as we saw), run clean script
./scripts/clean-zellij.sh

# 3. Verify
zellij list-sessions
# Should show: No sessions or only active ones
```

## Complete Clean (If Still Issues)

```bash
# 1. Kill processes
pkill -f zellij

# 2. Remove zellij data
rm -rf ~/Library/Application\ Support/Zellij
rm -rf ~/.local/state/zellij
rm -rf ~/.local/share/zellij

# 3. Start fresh
ai  # Should work now
```

## Why This Happens

Zellij has **session resurrection** - it tries to save your session state and restore it when you restart. Sometimes:

1. A restoration fails (e.g., system crash)
2. The failed restoration stays in the list
3. These are marked as "EXITED - attach to resurrect"

They're harmless but confusing. They don't affect actual running sessions.

## Permanent Fix

Disable session resurrection in `~/.config/zellij/config.kdl`:

```kdl
session_serialization false
```

Or keep it (you can restore sessions after crash), but run `clean-zellij.sh` regularly.

## Testing

After fixing, test:

```bash
# Should create NEW session, not fail
ai

# Check it's actually running
zellij list-sessions
# Should show: ai-dual-<timestamp> [Created Xs ago]

# It should NOT show: EXITED - attach to resurrect
```

## Session Management Commands

```bash
# Kill all sessions
zellij kill-all-sessions

# Or kill specific session
zellij kill-session <session-name>

# List sessions
zellij list-sessions

# Clean up script (does thorough cleanup)
./scripts/clean-zellij.sh
```

## AI Workflow (Fixed)

The `ai`, `ai-single`, `ai-triple`, and `remote` commands now:

1. Check if session exists (won't create duplicate)
2. Attach to existing if found
3. Create new session if not found
4. Use correct syntax: `zellij -n session-name layout`

```bash
# This now works properly:
ai              # AI dual agents
ai-single       # AI single agent  
ai-triple       # AI triple agents
remote          # Remote with tunnel
```

## Getting Help

```bash
# Check zellij help
zellij --help

# Check specific command
zellij <subcommand> --help

# Example:
zellij ls --help          # List sessions help
zellij kill-session --help  # Kill session help
```

## Common Issues

### "Session not found"
- Means session name changed (timestamp)
- Run: `zellij list-sessions` to see actual names
- Use `ai` function to create fresh one

### "Too many sessions"
- Run: `./scripts/clean-zellij.sh`
- Or: `zellij kill-all-sessions`

### "Sessions showing EXITED"
- These are orphaned resurrection sessions
- Run: `./scripts/clean-zellij.sh`
- They don't affect anything, just confusing

---

**Remember:** The `clean-zellij.sh` script is your friend when zellij gets confused!
