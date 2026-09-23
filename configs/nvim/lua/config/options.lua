-- ============================================================================
-- Custom Options (only what differs from LazyVim's defaults)
-- https://www.lazyvim.org/configuration/general
-- ============================================================================

local opt = vim.opt

opt.scrolloff = 8 -- Lines of context (LazyVim: 4)
opt.swapfile = false -- Undo is persistent (LazyVim sets undofile); no swap files

-- Clipboard. LazyVim turns system-clipboard sync off over SSH; keep it on and,
-- over SSH, where there is no local clipboard tool, ship yanks to the *local*
-- terminal's clipboard with OSC 52 (Ghostty allows clipboard-write; tmux
-- passes it through with set-clipboard on). Paste falls back to Neovim's own
-- unnamed register: terminals rarely answer OSC 52 reads, and the terminal's
-- native paste (Cmd+V) already inserts the system clipboard.
opt.clipboard = "unnamedplus"
if os.getenv("SSH_TTY") then
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
