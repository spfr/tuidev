-- ============================================================================
-- Custom Options (extends LazyVim defaults)
-- https://www.lazyvim.org/configuration/general
-- ============================================================================

local opt = vim.opt

-- UI
opt.relativenumber = true -- Relative line numbers
opt.number = true -- Show current line number
opt.cursorline = true -- Highlight current line
opt.signcolumn = "yes" -- Always show sign column
opt.termguicolors = true -- True color support
opt.scrolloff = 8 -- Lines of context
opt.sidescrolloff = 8 -- Columns of context

-- Editing
opt.expandtab = true -- Use spaces instead of tabs
opt.shiftwidth = 2 -- Size of an indent
opt.tabstop = 2 -- Number of spaces tabs count for
opt.smartindent = true -- Insert indents automatically
opt.wrap = false -- Disable line wrap

-- Search
opt.ignorecase = true -- Ignore case
opt.smartcase = true -- Don't ignore case with capitals
opt.hlsearch = true -- Highlight search results
opt.incsearch = true -- Show search matches as you type

-- Behavior
opt.clipboard = "unnamedplus" -- Sync with system clipboard
-- Over SSH there is no local clipboard tool, so ship yanks to the *local*
-- terminal's clipboard with OSC 52 (Ghostty allows clipboard-write; tmux
-- passes it through with set-clipboard on). Paste falls back to Neovim's own
-- unnamed register: terminals rarely answer OSC 52 reads, and the terminal's
-- native paste (Cmd+V) already inserts the system clipboard.
if os.getenv("SSH_TTY") and vim.fn.has("nvim-0.10") == 1 then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste_unnamed()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52 (ssh)",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste_unnamed, ["*"] = paste_unnamed },
  }
end
opt.mouse = "a" -- Enable mouse
opt.undofile = true -- Persistent undo
opt.undolevels = 10000 -- Maximum number of changes that can be undone
opt.updatetime = 200 -- Faster completion
opt.timeoutlen = 300 -- Time to wait for a mapped sequence

-- Splits
opt.splitbelow = true -- Put new windows below current
opt.splitright = true -- Put new windows right of current
opt.splitkeep = "screen" -- Keep screen position on split

-- Completion
opt.completeopt = "menu,menuone,noselect"
opt.pumheight = 10 -- Maximum number of entries in a popup

-- Files
opt.autowrite = true -- Enable auto write
opt.confirm = true -- Confirm to save changes before exiting
opt.swapfile = false -- Disable swap files
opt.backup = false -- Disable backup files

-- Folding (using treesitter)
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true

-- Grep
opt.grepformat = "%f:%l:%c:%m"
opt.grepprg = "rg --vimgrep"
