local utils = require("dyskette.utils")

local yazi_config = function()
  require("yazi").setup({
    open_for_directories = true,
    keymaps = {
      show_help = "<f1>",
    },
  })
end

local oil_config = function()
  require("oil").setup()
end

return {
  {
    "stevearc/oil.nvim",
    config = oil_config,
    keys = require("dyskette.keymaps").oil,
  },
  {
    "mikavilpas/yazi.nvim",
    keys = require("dyskette.keymaps").yazi,
    config = yazi_config,
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
      { "folke/snacks.nvim", lazy = true },
    },
  },
}
