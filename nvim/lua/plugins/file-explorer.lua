local yazi_diagnostics = require("config.yazi_diagnostics")

local oil_opts = {}

local yazi_opts = {
  -- if you want to open yazi instead of netrw, see below for more info
  open_for_directories = true,
  keymaps = {
    show_help = "<f1>",
  },
  hooks = {
    ---@param process_api YaziProcessApi
    on_yazi_ready = function(_, _, process_api)
      yazi_diagnostics.attach(process_api.yazi_id)
    end,
    yazi_closed_successfully = function()
      yazi_diagnostics.detach()
    end,
  },
}

return {
  {
    "stevearc/oil.nvim",
    opts = oil_opts,
    keys = require("config.keymaps").oil,
  },
  ---@type LazySpec
  {
    "mikavilpas/yazi.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = {
      { "nvim-lua/plenary.nvim", lazy = true },
    },
    keys = require("config.keymaps").yazi,
    ---@type YaziConfig | {}
    opts = yazi_opts,
    -- 👇 if you use `open_for_directories=true`, this is recommended
    init = function()
      -- mark netrw as loaded so it's not loaded at all.
      --
      -- More details: https://github.com/mikavilpas/yazi.nvim/issues/802
      vim.g.loaded_netrwPlugin = 1
      yazi_diagnostics.setup()
    end,
  },
}
