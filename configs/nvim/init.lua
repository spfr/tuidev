-- ============================================================================
-- LazyVim Configuration
-- Elite Engineer Terminal-First Setup
-- AI runs in CLI terminals, not in editor (see CLAUDE.md)
-- https://www.lazyvim.org/
-- ============================================================================

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Set leader key before loading lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Setup lazy.nvim with LazyVim
require("lazy").setup({
  spec = {
    -- Import LazyVim and its plugins
    {
      "LazyVim/LazyVim",
      import = "lazyvim.plugins",
      opts = {
        colorscheme = "tokyonight-night",
        news = { lazyvim = true, neovim = true },
      },
    },

    -- =========================================================================
    -- LazyVim Extras - Enable the features you need
    -- Full list: https://www.lazyvim.org/extras
    -- =========================================================================

    -- Language Support
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.rust" },
    { import = "lazyvim.plugins.extras.lang.go" },
    { import = "lazyvim.plugins.extras.lang.java" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.lang.docker" },
    { import = "lazyvim.plugins.extras.lang.terraform" },
    { import = "lazyvim.plugins.extras.lang.tailwind" },

    -- Coding Enhancements
    { import = "lazyvim.plugins.extras.coding.mini-surround" },
    { import = "lazyvim.plugins.extras.coding.yanky" },

    -- Editor Enhancements
    { import = "lazyvim.plugins.extras.editor.mini-files" },
    { import = "lazyvim.plugins.extras.editor.outline" },

    -- Formatting & Linting
    { import = "lazyvim.plugins.extras.formatting.prettier" },
    { import = "lazyvim.plugins.extras.linting.eslint" },

    -- UI Enhancements
    { import = "lazyvim.plugins.extras.ui.mini-animate" },

    -- DAP (Debugging)
    { import = "lazyvim.plugins.extras.dap.core" },

    -- Testing
    { import = "lazyvim.plugins.extras.test.core" },

    -- =========================================================================
    -- Disable AI Plugins - AI runs in terminal, not in editor
    -- This is intentional: see CLAUDE.md for architecture rationale
    -- =========================================================================
    { "zbirenbaum/copilot.lua", enabled = false },
    { "zbirenbaum/copilot-cmp", enabled = false },
    { "CopilotC-Nvim/CopilotChat.nvim", enabled = false },
    { "olimorris/codecompanion.nvim", enabled = false },
    { "yetone/avante.nvim", enabled = false },

    -- =========================================================================
    -- Custom Plugins - Add your own plugins here
    -- =========================================================================
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- Always use latest git commit
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true,
    notify = false, -- Don't spam notifications
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
