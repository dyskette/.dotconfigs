local utils = require("dyskette.utils")

local treesitter_build = function()
  require("nvim-treesitter.install").update({ with_sync = true })()
end

---@param lang string
---@param buffer_number number
local treesitter_disable = function(lang, buffer_number)
  return vim.api.nvim_buf_line_count(buffer_number) > 8000
end

local treesitterconfig_init = function()
  -- Disable default vim syntax highlighting
  vim.cmd.syntax("off")
end

local treesitterconfig_opts = {
  highlight = {
    enable = true,
    disable = treesitter_disable,
    additional_vim_regex_highlighting = false,
  },
  indent = {
    enable = true,
  },
  auto_install = true,
  sync_install = true,
  modules = {},
  ignore_install = {},
  ensure_installed = {
    -- The following parsers should always be installed
    "c",
    "lua",
    "markdown",
    "markdown_inline",
    "vim",
    "vimdoc",
    "query",
    -- Other parsers
    "javascript",
    "typescript",
    "c_sharp",
    "razor",
    "html",
    "python",
    "gitcommit",
    "sql",
    "css",
    "vue",
  },
}

local indent_blankline_opts = {
  scope = {
    show_start = false,
  },
}

return {
  "nvim-treesitter/nvim-treesitter",
  event = { utils.events.BufReadPre, utils.events.BufNewFile },
  build = treesitter_build,
  init = treesitterconfig_init,
  opts = treesitterconfig_opts,
  main = "nvim-treesitter.configs",
  dependencies = {
    { "windwp/nvim-ts-autotag" },
    {
      "lukas-reineke/indent-blankline.nvim",
      main = "ibl",
      opts = indent_blankline_opts,
    },
  },
}
