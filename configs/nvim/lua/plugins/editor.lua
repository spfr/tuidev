-- ============================================================================
-- Editor Plugins & Customizations
-- ============================================================================

return {
  -- =========================================================================
  -- Theme customization
  -- =========================================================================
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "night",
      transparent = false,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        sidebars = "dark",
        floats = "dark",
      },
    },
  },

  -- =========================================================================
  -- File Explorer (neo-tree customization)
  -- =========================================================================
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true, -- Show hidden files
          hide_dotfiles = false,
          hide_gitignored = false,
          never_show = {
            ".DS_Store",
            "thumbs.db",
          },
        },
        follow_current_file = {
          enabled = true,
        },
        use_libuv_file_watcher = true,
      },
      window = {
        width = 35,
        mappings = {
          ["<space>"] = "none",
          ["h"] = "close_node",
          ["l"] = "open",
        },
      },
    },
  },

  -- =========================================================================
  -- Telescope customization
  -- =========================================================================
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        layout_strategy = "horizontal",
        layout_config = {
          horizontal = {
            preview_width = 0.55,
            prompt_position = "top",
          },
          width = 0.87,
          height = 0.80,
        },
        sorting_strategy = "ascending",
        winblend = 0,
        file_ignore_patterns = {
          "node_modules",
          ".git/",
          "dist/",
          "build/",
          "%.lock",
        },
      },
    },
    keys = {
      -- Project-wide search
      { "<leader>sp", "<cmd>Telescope live_grep<cr>", desc = "Search in project" },
      -- Find all files (including hidden)
      { "<leader>fa", "<cmd>Telescope find_files hidden=true no_ignore=true<cr>", desc = "Find all files" },
    },
  },

  -- =========================================================================
  -- Which-key customization
  -- =========================================================================
  {
    "folke/which-key.nvim",
    opts = {
      defaults = {
        ["<leader>a"] = { name = "+ai" },
        ["<leader>t"] = { name = "+test" },
      },
    },
  },

  -- =========================================================================
  -- Buffer line customization
  -- =========================================================================
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        mode = "buffers",
        show_buffer_close_icons = true,
        show_close_icon = false,
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
        separator_style = "thin",
        offsets = {
          {
            filetype = "neo-tree",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "center",
          },
        },
      },
    },
  },

  -- =========================================================================
  -- Dashboard customization (snacks.nvim - LazyVim default)
  -- =========================================================================
  { "nvimdev/dashboard-nvim", enabled = false },
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = [[
    ███╗   ███╗ █████╗  ██████╗████████╗██╗   ██╗██╗
    ████╗ ████║██╔══██╗██╔════╝╚══██╔══╝██║   ██║██║
    ██╔████╔██║███████║██║        ██║   ██║   ██║██║
    ██║╚██╔╝██║██╔══██║██║        ██║   ██║   ██║██║
    ██║ ╚═╝ ██║██║  ██║╚██████╗   ██║   ╚██████╔╝██║
    ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝
       AI-Powered Terminal Development
          ]],
        },
      },
    },
  },

  -- =========================================================================
  -- Git enhancements
  -- =========================================================================
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 500,
      },
    },
  },

  -- =========================================================================
  -- Better notifications
  -- =========================================================================
  {
    "rcarriga/nvim-notify",
    opts = {
      timeout = 3000,
      max_height = function()
        return math.floor(vim.o.lines * 0.75)
      end,
      max_width = function()
        return math.floor(vim.o.columns * 0.75)
      end,
      render = "compact",
    },
  },

  -- =========================================================================
  -- Smooth scrolling
  -- =========================================================================
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    opts = {
      mappings = { "<C-u>", "<C-d>", "<C-b>", "<C-f>", "zt", "zz", "zb" },
      hide_cursor = true,
      stop_eof = true,
      respect_scrolloff = false,
      cursor_scrolls_alone = true,
    },
  },
}
