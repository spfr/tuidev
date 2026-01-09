-- ============================================================================
-- Custom Keymaps (extends LazyVim defaults)
-- https://www.lazyvim.org/configuration/keymaps
-- ============================================================================
-- LazyVim already provides excellent keymaps, these are additions

local map = vim.keymap.set

-- ============================================================================
-- General
-- ============================================================================

-- Better escape
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("i", "jj", "<Esc>", { desc = "Exit insert mode" })

-- Save file
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Quit
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })

-- ============================================================================
-- Navigation
-- ============================================================================

-- Move between windows (LazyVim uses <C-hjkl> by default)
map("n", "<leader>wh", "<C-w>h", { desc = "Go to left window" })
map("n", "<leader>wj", "<C-w>j", { desc = "Go to lower window" })
map("n", "<leader>wk", "<C-w>k", { desc = "Go to upper window" })
map("n", "<leader>wl", "<C-w>l", { desc = "Go to right window" })

-- Resize windows
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- ============================================================================
-- Editing
-- ============================================================================

-- Move lines up/down (LazyVim provides Alt+j/k)
map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move up" })

-- Better indenting (stay in visual mode)
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Don't yank on delete/change
map({ "n", "v" }, "x", '"_x', { desc = "Delete without yank" })

-- Duplicate line
map("n", "<leader>d", "<cmd>t.<cr>", { desc = "Duplicate line" })

-- ============================================================================
-- Buffers
-- ============================================================================

-- Navigate buffers
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "]b", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- ============================================================================
-- Search
-- ============================================================================

-- Clear search highlights
map("n", "<Esc>", "<cmd>noh<cr><esc>", { desc = "Clear highlights" })

-- Center search results
map("n", "n", "nzzzv", { desc = "Next search result (centered)" })
map("n", "N", "Nzzzv", { desc = "Prev search result (centered)" })

-- ============================================================================
-- Terminal
-- ============================================================================

-- Exit terminal mode
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Navigate from terminal
map("t", "<C-h>", "<cmd>wincmd h<cr>", { desc = "Go to left window" })
map("t", "<C-j>", "<cmd>wincmd j<cr>", { desc = "Go to lower window" })
map("t", "<C-k>", "<cmd>wincmd k<cr>", { desc = "Go to upper window" })
map("t", "<C-l>", "<cmd>wincmd l<cr>", { desc = "Go to right window" })

-- ============================================================================
-- Quick Actions
-- ============================================================================

-- Open lazygit (LazyVim provides <leader>gg)
map("n", "<leader>gl", "<cmd>LazyGit<cr>", { desc = "LazyGit" })

-- Toggle file explorer (LazyVim uses <leader>e)
map("n", "<leader>E", "<cmd>Neotree toggle<cr>", { desc = "Toggle Explorer" })

-- Format file (LazyVim provides <leader>cf)
map("n", "<leader>F", function()
  require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format file" })
