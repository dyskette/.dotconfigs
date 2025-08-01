local utils = require("config.utils")

local yazi_opts = {
  open_for_directories = true,
  keymaps = {
    show_help = "<f1>",
  },
}

local oil_opts = {}

return {
  {
    "stevearc/oil.nvim",
    opts = oil_opts,
    keys = require("config.keymaps").oil,
  },
  {
    "mikavilpas/yazi.nvim",
    keys = require("config.keymaps").yazi,
    opts = yazi_opts,
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
      { "folke/snacks.nvim", lazy = true },
    },
  },
}
