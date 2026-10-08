return {
  "folke/trouble.nvim",
  opts = {
    ---@type trouble.Window.opts
    preview = {
      type = "split",
      relative = "win",
      position = "top",
    },
  },
  cmd = "Trouble",
  keys = require("config.keymaps").trouble,
}
