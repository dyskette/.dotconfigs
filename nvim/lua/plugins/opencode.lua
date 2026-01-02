local utils = require("config.utils")

return {
  {
    "NickvanDyke/opencode.nvim",
    event = utils.events.VeryLazy,
    keys = require("config.keymaps").opencode,
    dependencies = {
      -- Recommended for `ask()` and `select()`.
      -- Required for `snacks` provider.
      { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        -- Your configuration, if any — see `lua/opencode/config.lua`
      }

      -- Required for `opts.events.reload`
      vim.o.autoread = true
    end,
  },
}
