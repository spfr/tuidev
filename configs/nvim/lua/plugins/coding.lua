-- ============================================================================
-- Coding Plugins & Enhancements
-- No in-editor AI (using side terminal for claude/codex instead)
-- ============================================================================

return {
  -- =========================================================================
  -- Completion customization (blink.cmp - LazyVim default since late 2024)
  -- =========================================================================
  {
    "saghen/blink.cmp",
    opts = {
      -- Keymaps (similar to old nvim-cmp bindings)
      keymap = {
        preset = "default",
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"] = { "hide", "fallback" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "fallback" },
        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },
        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
      },
      -- Appearance
      completion = {
        menu = {
          border = "rounded",
          draw = {
            columns = { { "kind_icon" }, { "label", "label_description", gap = 1 } },
          },
        },
        documentation = {
          window = { border = "rounded" },
        },
      },
    },
  },

  -- =========================================================================
  -- LSP enhancements
  -- =========================================================================
  {
    "neovim/nvim-lspconfig",
    opts = {
      codelens = { enabled = true },
      diagnostics = {
        virtual_text = { prefix = "icons" },
        float = {
          border = "rounded",
          source = true,
        },
      },
    },
  },

  -- =========================================================================
  -- Treesitter: parsers beyond LazyVim's defaults and the enabled lang extras
  -- (LazyVim appends this list to its own)
  -- =========================================================================
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "cpp",
        "css",
        "graphql",
        "scss",
        "sql",
        "svelte",
      },
    },
  },

  -- =========================================================================
  -- Formatting: only where we differ from LazyVim and its extras. LazyVim
  -- formats on save itself (toggle with <leader>uf); never set format_on_save.
  -- =========================================================================
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "black", "isort" },
        rust = { "rustfmt" },
        go = { "goimports", "gofmt" },
      },
    },
  },
}
