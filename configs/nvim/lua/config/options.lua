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
