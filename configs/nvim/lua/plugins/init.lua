-- ============================================================================
-- Plugin Overrides
-- Override default LazyVim plugin settings
-- ============================================================================

return {
  -- Disable Mason auto-install to prevent startup delays
  -- Run :MasonInstall manually when you need new LSP servers
  {
    "williamboman/mason-lspconfig.nvim",
    opts = {
      automatic_installation = false,
    },
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    opts = {
      automatic_installation = false,
    },
  },
  -- Disable noice.nvim - causes crash when typing : in command mode
  -- This is a known issue with recent LazyVim/noice.nvim versions
  { "folke/noice.nvim", enabled = false },
}
