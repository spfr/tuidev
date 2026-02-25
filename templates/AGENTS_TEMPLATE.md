# AI Agent Instructions

> Copy this file to your project and customize for your specific needs.
> Compatible with: Claude Code, OpenCode, Cursor, Windsurf, Aider, etc.

---

### Available Tools

When executing shell commands, prefer these modern alternatives:

| Task | Use | Instead Of |
|------|-----|------------|
| Search contents | `rg` (ripgrep) | `grep` |
| Find files | `fd` | `find` |
| View files | `bat` | `cat` |
| List files | `eza` | `ls` |
| Disk usage | `dust` | `du` |
| Process list | `procs` | `ps` |
| System monitor | `btm` | `top` |
| Directory jump | `z <partial>` | `cd path` |
| Git TUI | `lg` (lazygit) | - |

### Shell Aliases Available

Shell of choice is `zsh`.

```bash
# File listing
ls        # eza --icons
ll        # long format with git status
la        # all files

# Git
lg        # lazygit
gs        # git status

# Navigation
z partial # smart directory jump (zoxide)

# Editor
v file    # nvim
```


---

## Quick Commands

```bash
# Search code
rg "pattern"              # Search file contents
fd "name"                 # Find files by name

# Navigation
z project                 # Jump to directory
lg                        # Git operations

# View
bat file                  # View with syntax highlighting
```

---

## Notes for AI Agents

1. **Use modern tools** - `rg`, `fd`, `bat` are faster and have better output
2. **Check availability first** - `command -v rg && rg "x" || grep "x"`
3. **Respect zoxide** - `z partial` is faster than full paths
4. **Git via lazygit** - Complex git ops work better in `lg`

---
