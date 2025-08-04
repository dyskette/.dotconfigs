local utils = require("config.utils")

return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = {
    ignored_buftypes = {
      "nofile",
      "quickfix",
      "prompt",
    },
    ignored_filetypes = { "NvimTree" },
    default_amount = 3,
    at_edge = "wrap",
    float_win_behavior = "previous",
    move_cursor_same_row = false,
    cursor_follows_swapped_bufs = false,
    ignored_events = {
      "BufEnter",
      "WinEnter",
    },
    multiplexer_integration = "tmux",
    disable_multiplexer_nav_when_zoomed = true,
    log_level = "info",
  },
  config = function(_, opts)
    require("smart-splits").setup(opts)
    
    local keymaps = require("config.keymaps")
    for _, keymap in ipairs(keymaps.smart_splits) do
      vim.keymap.set(keymap.mode or "n", keymap[1], keymap[2], { desc = keymap.desc })
    end
  end,
}