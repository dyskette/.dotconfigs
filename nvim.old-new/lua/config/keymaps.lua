-- Clipboard
vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
vim.keymap.set({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })

-- Selection
vim.keymap.set("n", "<leader>a", ":keepjumps normal! ggVG<cr>", { desc = "Select all text in buffer" })

-- Moving text
vim.keymap.set("x", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up in visual mode" })
vim.keymap.set("x", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down in visual mode" })

-- keep cursor in the middle of the buffer vertically and unfold (zv) if there is a fold
vim.keymap.set("n", "n", "nzzzv", { desc = "Go to next coincidence" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Go to previous coincidence" })

-- Indent while remaining in visual mode
vim.keymap.set("x", "<", "<gv", { desc = "Indent backwards" })
vim.keymap.set("x", ">", ">gv", { desc = "Indent forward" })

-- Terminal
vim.keymap.set("t", "<C-|><C-n>", "<C-\\><C-n>", { desc = "Exit terminal", noremap = true })

-- Quickfix
local function toggle_quickfix()
  local wins = vim.fn.getwininfo()
  local qf_win = vim
    .iter(wins)
    :filter(function(win)
      return win.quickfix == 1
    end)
    :totable()
  if #qf_win == 0 then
    vim.cmd.copen()
  else
    vim.cmd.cclose()
  end
end
vim.keymap.set("n", "<leader>q", toggle_quickfix, { desc = "Toggle quickfix" })

-- Diagnostics

vim.keymap.set("n", "<leader>va", vim.lsp.buf.code_action, { desc = "View actions for diagnostics" })
vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, { desc = "View diagnostic" })
vim.keymap.set("n", "<leader>dk", function()
  vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })
vim.keymap.set("n", "<leader>dj", function()
  vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })
