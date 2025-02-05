-- Pretty colors
vim.opt.termguicolors = true

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- show <Tab> and <EOL>
vim.opt.list = true

-- Minimum number of lines to keep above and below the cursor (keeps the cursor vertically centered)
vim.opt.scrolloff = 999

-- No line wrapping
vim.opt.wrap = false

-- Rulers
vim.api.nvim_set_option_value("colorcolumn", "120", {})

-- Default indentation
-- When guess-indent detects spaces, it will override: 'expandtab', 'tabstop', 'softtabstop', 'shiftwidth'
-- When guess-indent detects tabs, it will use 'tabstop'
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.smartindent = true
