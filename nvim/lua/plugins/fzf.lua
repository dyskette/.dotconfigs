return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  cmd = { "FzfLua" },
  keys = require("config.keymaps").fzf,
  opts = {
    winopts = {
      height = 0.50,
      width = 0.80,
      row = 0.35,
      border = "single",
      preview = {
        default = "bat",
        layout = "flex",
        vertical = "down:45%",
        horizontal = "right:60%",
        flip_columns = 100,
        scrollbar = "float",
        delay = 20,
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
        args = "--color=always --style=numbers,changes",
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
