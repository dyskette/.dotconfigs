local utils = require("config.utils")

local gitsigns_opts = {}

local neogit_opts = {
  integrations = {
    diffview = true, -- enables diff popup
    snacks = true,   -- use the snacks picker for menu selection
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
    -- setup() attaches to buffers already open, so loading late loses nothing.
    event = utils.events.LazyFile,
    keys = require("config.keymaps").gitsigns,
    opts = gitsigns_opts,
  },
  {
    "NeogitOrg/neogit",
    -- <leader>gg opens lazygit in a toggleterm float (config/terminals.lua);
    -- Neogit stays available as :Neogit.
    cmd = "Neogit",
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
