return {
  "folke/trouble.nvim",
  cond = not vim.g.vscode,
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
