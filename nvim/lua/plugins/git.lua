local utils = require("config.utils")

local gitsigns_opts = {}

local neogit_opts = {
  integrations = {
    diffview = true,
    telescope = true,
  },
  sections = {
    recent = {
      folded = false,
      hidden = false,
    },
  },
}

return {
  {
    "lewis6991/gitsigns.nvim",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    keys = require("config.keymaps").gitsigns,
    opts = gitsigns_opts,
  },
  {
    "NeogitOrg/neogit",
    keys = require("config.keymaps").neogit,
    opts = neogit_opts,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "sindrets/diffview.nvim",
        keys = require("config.keymaps").git_diffview,
      },
    },
  },
}
