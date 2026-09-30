local utils = require("config.utils")

return {
  "ibhagwan/fzf-lua",
  cond = not vim.g.vscode,
  dependencies = { "nvim-tree/nvim-web-devicons", "folke/trouble.nvim" },
  cmd = { "FzfLua" },
  event = { utils.events.VeryLazy },
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
      -- Icons make every picker spawn a headless nvim that loads
      -- nvim-web-devicons: ~800 ms and jittery per open on Windows, versus
      -- ~250 ms steady without them.
      file_icons = false,
      -- Git status icons add a `git status` per open: git_files went from
      -- ~1.1 s to ~360 ms without them.
      git_icons = false,
    },
  },
  config = function(_, opts)
    local config = require("fzf-lua.config")
    local actions = require("trouble.sources.fzf").actions
    config.defaults.actions.files["ctrl-t"] = actions.open

    require("fzf-lua").setup(opts)
    require("fzf-lua").register_ui_select()
  end,
}
