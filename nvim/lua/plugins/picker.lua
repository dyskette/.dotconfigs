-- Pickers run inside nvim: listing a picker costs one fd/rg process, and
-- moving through it costs none, as the preview is an nvim buffer. fzf-lua,
-- which this replaces, ran fzf as an external program, so every preview
-- started cmd.exe, a headless nvim to call back into this one, and bat.
--
-- Only the picker module of snacks.nvim is enabled; the rest stays off.
return {
  "folke/snacks.nvim",
  dependencies = { "folke/trouble.nvim" },
  keys = require("config.keymaps").picker,
  init = function()
    -- Stand-in until the first vim.ui.select: loading snacks (config below)
    -- replaces it with the picker's, and the call is passed on.
    local builtin_select = vim.ui.select
    local function stub(...)
      require("snacks")
      if vim.ui.select == stub then
        vim.ui.select = builtin_select
      end
      return vim.ui.select(...)
    end
    vim.ui.select = stub
  end,
  opts = function()
    return {
      -- Previewing an image would otherwise probe the terminal, and under
      -- tmux/psmux that is a blocking `tmux` call per image. Windows Terminal
      -- cannot show inline images anyway (no Kitty graphics protocol).
      image = { enabled = false },
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
        actions = require("trouble.sources.snacks").actions,
        win = {
          input = {
            keys = {
              ["<c-t>"] = { "trouble_open", mode = { "n", "i" } },
            },
          },
        },
      },
    }
  end,
}
