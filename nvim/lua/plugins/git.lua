local utils = require("config.utils")

local gitsigns_opts = {}

local neogit_opts = {
  integrations = {
    diffview = true, -- enables diff popup
    fzf_lua = true,  -- use fzf-lua for menu selection
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
    cond = not vim.g.vscode,
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    keys = require("config.keymaps").gitsigns,
    opts = gitsigns_opts,
  },
  {
    "NeogitOrg/neogit",
    cond = not vim.g.vscode,
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
