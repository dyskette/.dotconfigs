local utils = require("config.utils")

return {
  {
    "NickvanDyke/opencode.nvim",
    event = utils.events.VeryLazy,
    keys = require("config.keymaps").opencode,
    dependencies = {
      -- Recommended for `ask()` and `select()`.
      -- Required for `toggle()`.
      { "folke/snacks.nvim", opts = { input = {}, picker = {} } },
    },
    config = function()
      vim.g.opencode_opts = {
        -- Your configuration, if any — see `lua/opencode/config.lua`
      }

      -- Required for `vim.g.opencode_opts.auto_reload`
      vim.opt.autoread = true
    end,
  },
  {
    "supermaven-inc/supermaven-nvim",
    event = utils.events.VeryLazy,
    config = function()
      require("supermaven-nvim").setup({})
    end,
  },
}
