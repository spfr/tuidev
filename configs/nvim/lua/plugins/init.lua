-- ============================================================================
-- Plugin Overrides
-- Override default LazyVim plugin settings
-- ============================================================================

return {
  -- Don't auto-install debug adapters (dap.core enables it); run
  -- :MasonInstall when you need one.
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
