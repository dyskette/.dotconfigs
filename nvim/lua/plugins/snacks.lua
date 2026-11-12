-- snacks.nvim: the pickers, notifications and indent guides. Only the modules configured
-- below are enabled; the rest stays off.
--
-- Pickers run inside nvim: listing a picker costs one fd/rg process, and
-- moving through it costs none, as the preview is an nvim buffer. fzf-lua,
-- which this replaces, ran fzf as an external program, so every preview
-- started cmd.exe, a headless nvim to call back into this one, and bat.

--- A trouble.nvim picker action that loads trouble only when it is used,
--- rather than with snacks at startup.
---@param name string action name in trouble.sources.snacks
local function trouble_action(name)
  return function(...)
    return require("trouble.sources.snacks").actions[name].action(...)
  end
end

return {
  "folke/snacks.nvim",
  -- At startup, as its modules set themselves up on the first BufReadPost and
  -- UIEnter; setup() itself only registers those autocmds.
  lazy = false,
  priority = 1000,
  keys = require("config.keymaps").picker,
  init = function()
    require("config.lsp_progress").setup()
  end,
  opts = {
    -- Previewing an image would otherwise probe the terminal, and under
    -- tmux/psmux that is a blocking `tmux` call per image. Windows Terminal
    -- cannot show inline images anyway (no Kitty graphics protocol).
    image = { enabled = false },
    -- vim.notify, LSP progress included (config/lsp_progress.lua), in the
    -- top right corner; <leader>sn lists past notifications.
    notifier = { enabled = true },
    -- Indent guides, with the current scope highlighted.
    indent = {
      enabled = true,
      animate = { enabled = false },
    },
    picker = {
      enabled = true,
      ui_select = true,
      -- Bottom panel across the full width, preview on the right: the
      -- layout fzf-lua had.
      layout = { preset = "ivy" },
      sources = {
        files = { hidden = true, follow = true },
        grep = { hidden = true },
      },
      actions = {
        trouble_open = trouble_action("trouble_open"),
      },
      win = {
        input = {
          keys = {
            ["<c-t>"] = { "trouble_open", mode = { "n", "i" } },
          },
        },
      },
    },
  },
}
