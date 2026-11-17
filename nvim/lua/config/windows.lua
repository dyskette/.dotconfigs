--- Window keys that work from every mode, terminals included:
---
---   Alt h/j/k/l   move to the window in that direction
---   Alt H/J/K/L   move a window divider in that direction
local M = {}

local RESIZE_COLUMNS, RESIZE_ROWS = 5, 2

-- Whether each direction moves along columns (a vertical divider).
local vertical = { h = true, l = true, k = false, j = false }

--- Move the divider in a direction: the right/bottom one when the window
--- has one, else the left/top one.
---@param key "h"|"j"|"k"|"l"
function M.resize(key)
  local after = vertical[key] and "l" or "j" -- right / below
  local before = vertical[key] and "h" or "k" -- left / above
  local towards_after = key == after

  local function has(neighbour)
    return vim.fn.winnr(neighbour) ~= vim.fn.winnr()
  end

  local delta
  if has(after) then
    delta = towards_after and 1 or -1 -- the divider after this window
  elseif has(before) then
    delta = towards_after and -1 or 1 -- the divider before it
  else
    return
  end

  local win = vim.api.nvim_get_current_win()
  if vertical[key] then
    vim.api.nvim_win_set_width(win, math.max(1, vim.api.nvim_win_get_width(win) + delta * RESIZE_COLUMNS))
  else
    vim.api.nvim_win_set_height(win, math.max(1, vim.api.nvim_win_get_height(win) + delta * RESIZE_ROWS))
  end
end

function M.setup()
  local modes = { "n", "i", "x", "t" }
  for key in pairs(vertical) do
    vim.keymap.set(modes, "<M-" .. key .. ">", function()
      -- Leave insert, visual or terminal mode first, then move.
      if vim.api.nvim_get_mode().mode ~= "n" then
        vim.api.nvim_feedkeys(vim.keycode("<C-\\><C-n>"), "nx", false)
      end
      vim.cmd.wincmd(key)
    end, { desc = "Window " .. key })

    vim.keymap.set(modes, "<M-" .. key:upper() .. ">", function()
      M.resize(key)
    end, { desc = "Move the window divider " .. key })
  end
end

return M
