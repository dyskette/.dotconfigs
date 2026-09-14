local utils = require("config.utils")

-- Default indentation
-- When guess-indent detects spaces, it will override: 'expandtab', 'tabstop', 'softtabstop', 'shiftwidth'
-- When guess-indent detects tabs, it will use 'tabstop'
-- Inside VS Code the extension syncs these from the editor's own detection
-- instead, so what is set here is only the starting point.
vim.o.expandtab = true
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.smartindent = true

-- Highlight the copied text
local group = vim.api.nvim_create_augroup("dyskette_text_yank_highlight", { clear = true })
vim.api.nvim_create_autocmd(utils.events.TextYankPost, {
  desc = "Highlight yanked text",
  group = group,
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
})

-- Everything below draws the terminal UI, and none of it survives inside VS
-- Code: the editor owns line numbers, scrolloff, rulers and wrapping through
-- its own settings, diagnostics come from the extension host rather than from a
-- language server nvim ever talks to, and vscode-neovim force-sets 'list',
-- 'wrap', 'winborder' and 'colorcolumn' on every BufEnter regardless.
if vim.g.vscode then
  return
end

-- Pretty colors
vim.o.termguicolors = true
vim.o.winborder = "single"

-- Line numbers
vim.o.number = true
vim.o.relativenumber = true

-- show <Tab> and <EOL>
vim.o.list = true

-- Minimum number of lines to keep above and below the cursor (keeps the cursor vertically centered)
vim.o.scrolloff = 999

-- No line wrapping
vim.o.wrap = false

-- Rulers
vim.o.colorcolumn = "120"

-- Diagnostic
vim.diagnostic.config({
  severity_sort = true,
  virtual_lines = false,
  virtual_text = {
    prefix = utils.icons.square,
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = utils.icons.error,
      [vim.diagnostic.severity.WARN] = utils.icons.warn,
      [vim.diagnostic.severity.HINT] = utils.icons.hint,
      [vim.diagnostic.severity.INFO] = utils.icons.info,
    },
  },
  float = { border = "single", title = " Diagnostic " },
})

-- Relative numbers in normal mode, absolute in insert mode
local number_toggle_group = vim.api.nvim_create_augroup("dyskette_number_toggle", { clear = true })
vim.api.nvim_create_autocmd({ utils.events.InsertEnter }, {
  desc = "Switch to absolute line numbers in insert mode",
  group = number_toggle_group,
  callback = function()
    vim.opt.relativenumber = false
  end,
})
vim.api.nvim_create_autocmd({ utils.events.InsertLeave }, {
  desc = "Switch to relative line numbers when leaving insert mode",
  group = number_toggle_group,
  callback = function()
    vim.opt.relativenumber = true
  end,
})
