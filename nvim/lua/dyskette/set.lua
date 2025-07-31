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

-- Yank highlight
local get_hl_name = function()
  if vim.fn.hlexists("HighlightedyankRegion") == 1 then
    return "HighlightedyankRegion"
  end

  return "IncSearch"
end

local group = vim.api.nvim_create_augroup("dyskette_text_yank_highlight", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Text yank highlight",
  group = group,
  callback = function()
    vim.highlight.on_yank({ higroup = get_hl_name(), timeout = 200 })
  end,
})
