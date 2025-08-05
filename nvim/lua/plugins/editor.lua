local utils = require("config.utils")

local indent_opts = {}

local surround_opts = {}

local comment_opts = {}

local autopairs_opts = {}

local autotag_opts = {}

local nvim_highlight_colors_opts = {}

local live_rename_opts = {}

return {
  -- Detect expandtab, tabstop, softtabstop and shiftwidth automatically
  {
    "nmac427/guess-indent.nvim",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    opts = indent_opts,
  },
  -- Add parenthesis, tags, quotes with vim motions
  {
    "kylechui/nvim-surround",
    version = "*", -- Use for stability; omit to use `main` branch for the latest features
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    opts = surround_opts,
  },
  -- Close parenthesis, tags, quotes on insert
  {
    "windwp/nvim-autopairs",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    opts = autopairs_opts,
  },
  -- Close tags e.g. <div></div> on insert
  {
    "windwp/nvim-ts-autotag",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    opts = autotag_opts,
  },
  {
    "saecki/live-rename.nvim",
    keys = require("config.keymaps").live_rename,
    opts = live_rename_opts,
  },
  -- Code commenting with vim motions
  {
    "numToStr/Comment.nvim",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    opts = comment_opts,
  },
  -- Show colors like #eb6f92 with a background of its own color
  {
    "brenoprata10/nvim-highlight-colors",
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    opts = nvim_highlight_colors_opts,
  },
  -- Json tools
  {
    "VPavliashvili/json-nvim",
    ft = "json", -- only load for json filetype
  },
}
