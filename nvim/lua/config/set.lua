local utils = require("config.utils")

-- Pretty colors
vim.o.termguicolors = true
vim.o.winborder = "rounded"

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

-- Merge status line with command line
vim.o.laststatus = 3  -- Global status line
vim.o.cmdheight = 0   -- Hide command line when not in use

-- Default indentation
-- When guess-indent detects spaces, it will override: 'expandtab', 'tabstop', 'softtabstop', 'shiftwidth'
-- When guess-indent detects tabs, it will use 'tabstop'
vim.o.expandtab = true
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.smartindent = true

-- Diagnostic
vim.fn.sign_define("DiagnosticSignError", { texthl = "DiagnosticSignError", text = "" })
vim.fn.sign_define("DiagnosticSignWarn", { texthl = "DiagnosticSignWarn", text = "" })
vim.fn.sign_define("DiagnosticSignInfo", { texthl = "DiagnosticSignInfo", text = "" })
vim.fn.sign_define("DiagnosticSignHint", { texthl = "DiagnosticSignHint", text = "" })

vim.diagnostic.config({
  virtual_text = {
    prefix = "",
  },
  float = { border = "rounded", title = " Diagnostic " },
})

-- Highlight the copied text
local group = vim.api.nvim_create_augroup("dyskette_text_yank_highlight", { clear = true })
vim.api.nvim_create_autocmd(utils.events.TextYankPost, {
  desc = "Highlight yanked text",
  group = group,
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
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
