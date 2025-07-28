local utils = require("dyskette.utils")
local keymaps = require("dyskette.keymaps")

return {
  {
    "lewis6991/gitsigns.nvim",
    event = {
      utils.events.BufReadPre,
      utils.events.BufNewFile,
      utils.events.BufWritePre,
    },
    keys = keymaps.gitsigns,
    opts = {},
  },
  {
    "NeogitOrg/neogit",
    keys = keymaps.neogit,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    opts = {
      integrations = {
        diffview = true,
        fzf = true,
      },
      sections = {
        recent = {
          folded = false,
          hidden = false,
        },
      },
    },
  },
  {
    "sindrets/diffview.nvim",
    keys = keymaps.git_diffview,
  },
}
