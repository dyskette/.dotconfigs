return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  cmd = { "FzfLua" },
  keys = require("config.keymaps").fzf,
  opts = {
    defaults = {
      file_icons = true,
      color_icons = true,
    },
  },
}
