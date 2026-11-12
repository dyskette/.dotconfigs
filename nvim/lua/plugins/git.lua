local utils = require("config.utils")

local gitsigns_opts = {}

-- lazygit (<leader>gg, config/terminals.lua) is the git UI; diffview is for
-- reading changes in nvim: the working tree diff and a file's history.
return {
  {
    "lewis6991/gitsigns.nvim",
    -- setup() attaches to buffers already open, so loading late loses nothing.
    event = utils.events.LazyFile,
    keys = require("config.keymaps").gitsigns,
    opts = gitsigns_opts,
  },
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    keys = require("config.keymaps").git_diffview,
  },
}
