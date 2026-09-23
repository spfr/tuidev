# Vim (`--pack vim`)

`--pack vim` is the lightweight terminal editor: plain Vim 9 with a zero-plugin vimrc. It suits servers and small boxes (a Raspberry Pi, a VM, a CI runner you SSH into), where [`--pack nvim`](nvim.md) and LazyVim would bring hundreds of megabytes of plugins, parsers and language servers you don't need. It starts in milliseconds and has nothing to update.

```bash
./install.sh --pack vim
```

The pack installs `vim`. On macOS it uses the system `/usr/bin/vim`, which is already Vim 9, and skips Homebrew's build with its language runtimes. The config lands in `~/.vim/vimrc` and is upgraded in place while you haven't edited it, like the other shipped configs. Vim reads `~/.vimrc` before `~/.vim/vimrc`, so a `~/.vimrc` of your own wins, and the pack leaves it alone.

`$EDITOR` over SSH is the first of `nvim`, `vim`, `vi` and `nano` that is installed (see `~/.zshrc`). Without `--pack nvim`, that's this Vim.

## What it uses

Everything comes from Vim itself or from the core pack:

- **Vim 9.1 built-in packages:** `comment` (`gcc`), `editorconfig`, `matchit`, `hlyank`, `nohlsearch`. An older Vim skips each one silently.
- **fzf's own Vim plugin** (`:FZF`), which ships with the `fzf` package. The vimrc finds it under Homebrew or Debian's `/usr/share/doc/fzf/examples`. Without fzf, the file and buffer keys fall back to `:find` and `:buffer` with the fuzzy wildmenu.
- **ripgrep** as `:grep`, with results in the quickfix list.
- **netrw** as the file explorer.
- **The `habamax` colorscheme**, with true colour when the terminal advertises it.
- **Persistent undo, swap files and viminfo** under `~/.local/state/vim`, not next to your files.
- **OSC 52 yanks.** When Vim has no clipboard of its own (the usual case on a server), `y` also sends the text to your local clipboard through SSH and tmux. The tmux pack's `set-clipboard on` passes it along.
- **Autoread.** Files an agent or `git` changed on disk are reloaded when you switch back to them.

## Keys

The leader is `Space`.

| Keys | Action |
|------|--------|
| `Space Space` | Find files (fzf) |
| `Space b` / `Space r` | Buffers / recent files |
| `Space /` | Grep the project: type the pattern, results open in quickfix |
| `Space *` | Grep the word under the cursor |
| `]q` / `[q` | Next/previous quickfix entry |
| `]b` / `[b` | Next/previous buffer |
| `Space e` | netrw explorer (`-` goes up a directory, `%` creates a new file, `d` a directory) |
| `Space w` / `Space q` / `Space x` | Write / quit / close the buffer |
| `Space o` | Close the other windows |
| `Ctrl+h/j/k/l` | Move between windows |
| `gcc` / `gc{motion}` | Toggle comment |
| `J` / `K` (visual) | Move the selection down/up |
| `%` | Jump between matching pairs, including `if`/`else`/`end` |

## Customising

Put your changes in `~/.vimrc` and source the shipped file first:

```vim
source ~/.vim/vimrc
colorscheme retrobox
```

Or edit `~/.vim/vimrc` directly. The pack then stops upgrading it, and `./scripts/update.sh --configs` prints the `diff` to compare against the new version.

Add plugins as native packages, without a plugin manager: `git clone URL ~/.vim/pack/plugins/start/NAME`.
