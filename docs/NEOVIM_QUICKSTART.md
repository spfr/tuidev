# Neovim + LazyVim Quick Start Guide

This setup uses **[LazyVim](https://www.lazyvim.org/)** - the most popular Neovim distribution. It provides a full IDE experience out of the box.

> **Note**: This setup uses terminal-based AI tools (opencode, claude) in separate Zellij panes rather than in-editor AI plugins. This keeps nvim fast and focused on editing.

## First Launch

Run `nvim` and wait for plugins to install:

```bash
nvim
```

LazyVim will automatically:
1. Clone lazy.nvim (plugin manager)
2. Install all configured plugins
3. Download language parsers (Treesitter)
4. Set up LSP servers via Mason

**First launch takes 1-2 minutes. Subsequent launches are instant.**

---

## The Leader Key

**Leader = `Space`**

Press `Space` and wait - which-key shows all available commands. This is your command palette.

---

## Essential Keybindings

### File Navigation

| Key | Action |
|-----|--------|
| `Space f f` | Find files (fuzzy) |
| `Space f g` | Live grep (search in files) |
| `Space f r` | Recent files |
| `Space e` | Toggle file explorer |
| `Space ,` | Switch buffer |
| `Space b d` | Close buffer |

### Code Navigation

| Key | Action |
|-----|--------|
| `g d` | Go to definition |
| `g r` | Go to references |
| `g I` | Go to implementation |
| `K` | Hover documentation |
| `[ d` / `] d` | Previous/next diagnostic |

### Code Actions

| Key | Action |
|-----|--------|
| `Space c a` | Code actions (quick fixes) |
| `Space c r` | Rename symbol |
| `Space c f` | Format file |
| `Space x x` | Toggle diagnostics panel |

### Window Management

| Key | Action |
|-----|--------|
| `Ctrl+h/j/k/l` | Navigate windows |
| `Space w v` | Split vertical |
| `Space w s` | Split horizontal |
| `Space w d` | Close window |
| `Space q q` | Quit all |

### Git (LazyGit)

| Key | Action |
|-----|--------|
| `Space g g` | Open LazyGit |
| `Space g b` | Git blame line |
| `] h` / `[ h` | Next/prev git hunk |

---

## File Explorer (neo-tree)

Toggle with `Space e`

| Key | Action |
|-----|--------|
| `a` | Add file/folder |
| `d` | Delete |
| `r` | Rename |
| `c` | Copy |
| `m` | Move/cut |
| `p` | Paste |
| `y` | Copy path |
| `/` | Filter |

---

## Search & Replace

| Key | Action |
|-----|--------|
| `Space s g` | Grep in project |
| `Space s r` | Search and replace |
| `Space s w` | Search word under cursor |
| `*` | Search word forward |
| `#` | Search word backward |
| `:%s/old/new/g` | Replace all in file |

---

## LSP (Language Server)

### Pre-configured Languages

Auto-installed when you open a file:

| Language | Server | Formatter |
|----------|--------|-----------|
| TypeScript/JS | ts_ls | prettier |
| Python | pyright | black, ruff |
| Rust | rust-analyzer | rustfmt |
| Go | gopls | goimports |
| Lua | lua_ls | stylua |
| JSON/YAML | jsonls, yamlls | prettier |
| HTML/CSS | html, cssls | prettier |
| Docker | dockerls | - |

### Mason (Package Manager)

```vim
:Mason          " Open Mason UI - install/update LSPs
:MasonInstall X " Install package X
:LspInfo        " Show active LSP for current file
```

---

## Vim Motions Crash Course

### The Grammar: `verb + noun`

| Verb | Meaning |
|------|---------|
| `d` | delete |
| `c` | change (delete + insert) |
| `y` | yank (copy) |
| `v` | visual select |

| Noun | Meaning |
|------|---------|
| `w` | word |
| `iw` | inner word |
| `i"` | inside quotes |
| `i(` | inside parentheses |
| `ip` | inner paragraph |
| `it` | inside tag |

### Common Combinations

```
ciw     - change inner word
di"     - delete inside quotes
yi(     - yank inside parentheses
ca{     - change around braces
dap     - delete a paragraph
ct,     - change till comma
```

### Movement

| Key | Action |
|-----|--------|
| `w` / `b` | Next/prev word |
| `e` | End of word |
| `0` / `$` | Start/end of line |
| `gg` / `G` | Start/end of file |
| `{` / `}` | Prev/next paragraph |
| `%` | Matching bracket |
| `f{char}` | Find char forward |
| `t{char}` | Till char forward |

---

## Terminal

| Key | Action |
|-----|--------|
| `Ctrl+/` | Toggle floating terminal |
| `Space f t` | Terminal in root dir |
| `Esc Esc` | Exit terminal mode |

---

## Useful Commands

```vim
:Lazy              " Plugin manager UI
:Mason             " LSP/formatter manager
:checkhealth       " System health check
:Telescope         " Fuzzy finder
:Trouble           " Diagnostics panel
:TodoTelescope     " Find TODO/FIXME comments
```

---

## Customization

### Add Plugins

Create `~/.config/nvim/lua/plugins/custom.lua`:

```lua
return {
  {
    "author/plugin-name",
    opts = {},
  },
}
```

### Change Theme

Edit `~/.config/nvim/init.lua`:

```lua
opts = {
  colorscheme = "catppuccin", -- or tokyonight, gruvbox
}
```

### Add Keymaps

Edit `~/.config/nvim/lua/config/keymaps.lua`:

```lua
vim.keymap.set("n", "<leader>xx", "<cmd>YourCommand<cr>", { desc = "Description" })
```

---

## Pro Tips

1. **Use which-key**: Press `Space` and wait - discover commands visually
2. **Repeat with `.`**: The dot repeats your last change
3. **Use marks**: `ma` sets mark 'a', `'a` jumps back
4. **Record macros**: `qa` starts recording to 'a', `q` stops, `@a` plays
5. **Quick search**: `*` on a word searches for all occurrences
6. **Visual block**: `Ctrl+v` for column editing
7. **Increment numbers**: `Ctrl+a` / `Ctrl+x`

---

## Troubleshooting

### Plugins not loading
```bash
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim  # Fresh install
```

### LSP not working
```vim
:LspInfo         " Check status
:Mason           " Install missing servers
:checkhealth lsp " Diagnostics
```

### Slow startup
```vim
:Lazy profile    " See what's slow
```

---

## Resources

- [LazyVim Documentation](https://www.lazyvim.org/)
- [LazyVim Keymaps](https://www.lazyvim.org/keymaps)
- [Vim Cheat Sheet](https://vim.rtorr.com/)
- [Learn Vim Motions](https://www.openvim.com/)
