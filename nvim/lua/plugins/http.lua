local utils = require("config.utils")

local kulala_opts = {
  -- Keymaps
  global_keymaps = true,
  global_keymaps_prefix = "<leader>h",
  kulala_keymaps_prefix = "",

  -- UI
  ui = {
    display_mode = "split",
    split_direction = "vertical",
    default_view = "body",
    winbar = true,
  },

  -- LSP integrado
  lsp = {
    enable = true,
  },

  -- Otros
  default_env = "dev",
  debug = false,
}

return {
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    keys = require("config.keymaps").kulala,
    opts = kulala_opts,
  },
}
