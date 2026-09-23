-- ============================================================================
-- Custom Autocommands (only additions to LazyVim's defaults)
-- https://www.lazyvim.org/configuration/general#auto-commands
-- ============================================================================
-- LazyVim already handles yank highlight, split resize, close-with-q, parent
-- dir creation, last cursor position and big files (snacks.bigfile). Neovim's
-- ftplugins already indent Python and Rust with 4 spaces and Go with tabs.

-- Show Go's tabs 4 columns wide (LazyVim's global tabstop is 2)
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("custom_go_tabstop", { clear = true }),
  pattern = "go",
  callback = function()
    vim.opt_local.tabstop = 4
  end,
})
