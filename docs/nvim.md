# Neovim (`--pack nvim`)

`--pack nvim` installs Neovim and deploys a [LazyVim](https://www.lazyvim.org/) config — a full IDE experience for the sessions where a terminal editor, not a GUI one, is what you want. It's optional: see [VISION.md](../VISION.md) for why the GUI editor is the default now.

> **AI tools run in separate panes, not as in-editor plugins.** Claude Code and Codex (`--pack ai-clis`), OpenCode (`--pack opencode`). Copilot, CopilotChat, CodeCompanion and Avante are explicitly disabled in `configs/nvim/init.lua`.

> **Versions:** tested against Neovim 0.12.x (current stable). The config tracks LazyVim upstream (`version = false`, see `configs/nvim/init.lua`), so plugins update on each `:Lazy sync`. Run `:checkhealth` after upgrading Neovim — LazyVim surfaces any breaking changes there.

## First launch

```bash
nvim
```

LazyVim clones lazy.nvim, installs plugins, downloads Treesitter parsers and sets up LSP servers via Mason. First launch takes 1-2 minutes; later launches are instant.

## The leader key

**Leader = `Space`**. Press it and wait — which-key shows every available command. This is your command palette.

## Essential keybindings

### File navigation

The picker and the explorer are LazyVim's [snacks.nvim](https://github.com/folke/snacks.nvim) defaults.

| Key | Action |
|-----|--------|
| `Space Space` / `Space f f` | Find files (fuzzy) |
| `Space /` | Grep the project |
| `Space f r` | Recent files |
| `Space e` | Toggle the snacks file explorer |
| `Space f m` | mini.files (column browser; edit the buffer to rename or move) |
| `Space ,` | Switch buffer |
| `Space b d` | Close buffer |

### Code navigation and actions

| Key | Action |
|-----|--------|
| `g d` / `g r` / `g I` | Go to definition / references / implementation |
| `K` | Hover documentation |
| `[ d` / `] d` | Previous/next diagnostic |
| `Space c a` | Code actions (quick fixes) |
| `Space c r` | Rename symbol |
| `Space c f` | Format file |
| `Space x x` | Toggle diagnostics panel |

### Windows and git

| Key | Action |
|-----|--------|
| `Ctrl+h/j/k/l` | Navigate windows |
| `Space w v` / `Space w s` | Split vertical / horizontal |
| `Space q q` | Quit all |
| `Space g g` | Open lazygit (snacks) |
| `Space g b` | Git blame line |
| `] h` / `[ h` | Next/prev git hunk |

### Search and replace

| Key | Action |
|-----|--------|
| `Space s g` | Grep in project |
| `Space s r` | Search and replace (grug-far) |
| `Space s w` | Search word under cursor |
| `:%s/old/new/g` | Replace all in file |

## LSP

`configs/nvim/init.lua` enables LazyVim's language extras for TypeScript, JSON, Python, Rust, Go, Java, YAML, Docker, Terraform and Tailwind, plus Prettier and ESLint. Mason installs each extra's language server when you first open a matching file. `lua/plugins/coding.lua` overrides the formatters: `black` + `isort` for Python, `rustfmt`, and `goimports` + `gofmt`. LazyVim formats on save; toggle it with `Space u f`.

```vim
:Mason          " Open Mason UI - install/update LSPs
:MasonInstall X " Install package X
:LspInfo        " Show active LSP for current file
```

## Terminal and useful commands

| Key | Action |
|-----|--------|
| `Ctrl+/` | Toggle floating terminal |
| `Space f t` | Terminal in root dir |
| `Esc Esc` | Exit terminal mode |

```vim
:Lazy              " Plugin manager UI
:LazyExtras        " Enable or disable LazyVim extras
:checkhealth       " System health check
:Trouble           " Diagnostics panel
```

Pickers are on keys rather than commands: `Space s k` lists keymaps, `Space s t` finds TODO/FIXME comments, `Space s h` searches help.

## Customization

Add a plugin in `~/.config/nvim/lua/plugins/custom.lua`:

```lua
return {
  { "author/plugin-name", opts = {} },
}
```

`tokyonight-night` is set in the `LazyVim/LazyVim` spec in `~/.config/nvim/init.lua`. `make theme` does not touch Neovim, so switch the colorscheme there (see [theming.md](theming.md#neovim-is-not-themed-by-this-pipeline)).

Edit `~/.config/nvim/lua/config/keymaps.lua` to add keymaps:

```lua
vim.keymap.set("n", "<leader>xx", "<cmd>YourCommand<cr>", { desc = "Description" })
```

## Troubleshooting

**Plugins not loading:**

```bash
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim  # Fresh install
```

**LSP not working:** `:LspInfo`, then `:Mason` to install the missing server, then `:checkhealth lsp`.

**Slow startup:** `:Lazy profile`.

## Resources

- [LazyVim Documentation](https://www.lazyvim.org/)
- [LazyVim Keymaps](https://www.lazyvim.org/keymaps)
- [Vim Cheat Sheet](https://vim.rtorr.com/)
