local utils = require("dyskette.utils")

return {
  "toppair/peek.nvim",
  build = "deno task --quiet build:fast",
  cmd = { "PeekOpen", "PeekClose" },
  init = function()
    vim.api.nvim_create_user_command("PeekOpen", "require('peek').open()", {})
    vim.api.nvim_create_user_command("PeekClose", "require('peek').open()", {})
  end,
  opts = {
    app = "browser",
  },
}
