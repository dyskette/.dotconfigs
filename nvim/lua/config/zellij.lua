-- One set of keys, Alt+h/j/k/l, across Neovim windows and Zellij panes.
--
-- Zellij's pilot plugin (zellij/plugins/pilot) sends Alt+h/j/k/l here when
-- this nvim has focus, and moves between panes itself otherwise. Here they
-- move between windows; at the edge of the layout the move goes back to
-- Zellij, into the neighbouring pane (or tab, left and right), the way
-- Zellij would have moved had the key never come here.
--
-- Outside Zellij the keys still move between windows, so muscle memory works
-- in a plain terminal too.
local M = {}

-- Zellij's action for leaving nvim in each direction: left and right cross
-- into the next tab at the screen edge, as the plugin does for other panes.
local zellij_action = {
  h = { "move-focus-or-tab", "left" },
  j = { "move-focus", "down" },
  k = { "move-focus", "up" },
  l = { "move-focus-or-tab", "right" },
}

---@param key "h"|"j"|"k"|"l"
local function navigate(key)
  local before = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(key)
  if vim.api.nvim_get_current_win() ~= before or not vim.env.ZELLIJ then
    return
  end
  -- Already at the edge: hand the move to Zellij. Asynchronous, so nvim does
  -- not wait on the zellij CLI.
  vim.system(vim.list_extend({ "zellij", "action" }, zellij_action[key]), { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("zellij action failed: " .. (result.stderr or ""), vim.log.levels.WARN)
      end)
    end
  end)
end

function M.setup()
  for key in pairs(zellij_action) do
    local lhs = "<M-" .. key .. ">"
    local desc = "Window or Zellij pane " .. ({ h = "left", j = "below", k = "above", l = "right" })[key]
    vim.keymap.set("n", lhs, function()
      navigate(key)
    end, { desc = desc })
    -- From a terminal buffer, leave terminal mode first.
    vim.keymap.set("t", lhs, function()
      vim.cmd.stopinsert()
      vim.schedule(function()
        navigate(key)
      end)
    end, { desc = desc })
  end
end

return M
