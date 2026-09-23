-- ============================================================================
-- Custom Keymaps (only additions to LazyVim's defaults)
-- https://www.lazyvim.org/configuration/keymaps
-- ============================================================================
-- LazyVim already maps <C-s>, <leader>qq, window resize/move, <A-j>/<A-k>,
-- buffers (<S-h>/<S-l>, [b/]b), <Esc> to clear search, lazygit (<leader>gg),
-- the explorer (<leader>e/E) and format (<leader>cf). <leader>d is the debug
-- prefix (dap.core extra).

local map = vim.keymap.set

-- ============================================================================
-- General
-- ============================================================================

-- Better escape
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("i", "jj", "<Esc>", { desc = "Exit insert mode" })

-- ============================================================================
-- Editing
-- ============================================================================

-- Don't yank on delete
map({ "n", "v" }, "x", '"_x', { desc = "Delete without yank" })

-- ============================================================================
-- Search
-- ============================================================================

-- Center search results (keeps LazyVim's direction-aware n/N)
map("n", "n", "'Nn'[v:searchforward].'zzzv'", { expr = true, desc = "Next Search Result (centered)" })
map("n", "N", "'nN'[v:searchforward].'zzzv'", { expr = true, desc = "Prev Search Result (centered)" })

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

-- Format asynchronously (LazyVim's <leader>cf formats synchronously)
map("n", "<leader>F", function()
  require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "Format file (async)" })
