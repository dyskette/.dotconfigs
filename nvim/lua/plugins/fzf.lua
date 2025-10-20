return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  cmd = { "FzfLua" },
  keys = require("config.keymaps").fzf,
  opts = {
    winopts = {
      height = 0.50,
      width = 1.00,
      row = 1.00,
      border = "border-top",
      preview = {
        default = "bat",
        vertical = "down:50%",
        horizontal = "right:50%",
      },
    },
    fzf_opts = {
      ["--layout"] = "reverse",
      ["--info"] = "inline-right",
      ["--height"] = "100%",
      ["--border"] = "none",
      ["--preview-window"] = "border-left",
    },
    previewers = {
      bat = {
        cmd = "bat",
        args = "--color=always --style=default",
      },
    },
    files = {
      cmd = "fd --type f --hidden --follow --exclude .git",
      fd_opts = "--type f --hidden --follow --exclude .git",
    },
    grep = {
      cmd = "rg --column --line-number --no-heading --color=always --smart-case",
      rg_opts = "--column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e",
    },
    defaults = {
      file_icons = true,
      color_icons = true,
    },
  },
}
