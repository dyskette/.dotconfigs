return {
  "ibhagwan/fzf-lua",
  dependencies = { "folke/trouble.nvim" },
  cmd = { "FzfLua" },
  keys = require("config.keymaps").fzf,
  init = function()
    -- Stand-in until the first vim.ui.select: loading fzf-lua (config below)
    -- replaces it through register_ui_select(), and the call is passed on.
    local builtin_select = vim.ui.select
    local function stub(...)
      require("fzf-lua")
      if vim.ui.select == stub then
        vim.ui.select = builtin_select
      end
      return vim.ui.select(...)
    end
    vim.ui.select = stub
  end,
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
