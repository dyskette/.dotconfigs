-- Pretty colors
vim.api.nvim_set_option_value("termguicolors", true, {})

-- Line numbers
vim.api.nvim_set_option_value("number", true, {})
vim.api.nvim_set_option_value("relativenumber", true, {})

-- show <Tab> and <EOL>
vim.api.nvim_set_option_value("list", true, {})

-- Minimum number of lines to keep above and below the cursor (keeps the cursor vertically centered)
vim.api.nvim_set_option_value("scrolloff", 999, {})

-- No line wrapping
vim.api.nvim_set_option_value("wrap", false, {})

-- Rulers
vim.api.nvim_set_option_value("colorcolumn", "120", {})

-- Default indentation
-- When guess-indent detects spaces, it will override: 'expandtab', 'tabstop', 'softtabstop', 'shiftwidth'
-- When guess-indent detects tabs, it will use 'tabstop'
vim.api.nvim_set_option_value("expandtab", true, {})
vim.api.nvim_set_option_value("tabstop", 4, {})
vim.api.nvim_set_option_value("softtabstop", 4, {})
vim.api.nvim_set_option_value("shiftwidth", 4, {})
vim.api.nvim_set_option_value("smartindent", true, {})
