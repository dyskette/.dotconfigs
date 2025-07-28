local utils = require("dyskette.utils")

local set_dark_mode = function()
  vim.api.nvim_set_option_value("background", "dark", {})
  vim.cmd.colorscheme("gruvbox")
  vim.env.BAT_THEME = "gruvbox"
end

local set_light_mode = function()
  vim.api.nvim_set_option_value("background", "light", {})
  vim.cmd.colorscheme("rose-pine-dawn")
  vim.env.BAT_THEME = "rose-pine-dawn"
end

local zen_mode_config = function()
  require("dyskette.keymaps").zen_mode()
end

return {
  -- Color scheme
  {
    "f-person/auto-dark-mode.nvim",
    opts = {
      update_interval = 1000,
      fallback = "light",
      set_dark_mode = set_dark_mode,
      set_light_mode = set_light_mode,
    },
    dependencies = {
      {
        "ellisonleao/gruvbox.nvim",
        opts = {
          terminal_colors = true, -- add neovim terminal colors
          undercurl = true,
          underline = true,
          bold = true,
          italic = {
            strings = true,
            emphasis = true,
            comments = true,
            operators = false,
            folds = true,
          },
          strikethrough = true,
          invert_selection = false,
          invert_signs = false,
          invert_tabline = false,
          inverse = true, -- invert background for search, diffs, statuslines and errors
          contrast = "", -- can be "hard", "soft" or empty string
          palette_overrides = {},
          overrides = {},
          dim_inactive = false,
          transparent_mode = false,
        },
        init = function()
          if vim.env.SYSTEM_COLOR_THEME == "dark" then
            set_dark_mode()
          end
        end,
      },
      {
        "rose-pine/neovim",
        name = "rose-pine",
        init = function()
          if vim.env.SYSTEM_COLOR_THEME == "light" then
            set_light_mode()
          end
        end,
      },
    },
  },
  -- tab bar
  {
    "alvarosevilla95/luatab.nvim",
    event = utils.events.VeryLazy,
    opts = {},
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
  },
  -- Status bar
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      extensions = {
        "lazy",
        "mason",
        "oil",
        "trouble",
        {
          filetypes = { "DiffviewFiles" },
          sections = {
            lualine_a = {
              {
                function()
                  return "Diffview Files"
                end,
                color = "white",
              },
            },
          },
        },
        {
          filetypes = { "DiffviewFileHistory" },
          sections = {
            lualine_a = {
              {
                function()
                  return "Diffview File History"
                end,
                color = "white",
              },
            },
          },
        },
      },
      options = {
        component_separators = { left = "|", right = "|" },
        section_separators = { left = "", right = "" },
      },
    },
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
  },
  -- LSP progress/vim.notify
  {
    "j-hui/fidget.nvim",
    event = utils.events.VeryLazy,
    opts = {
      notification = {
        override_vim_notify = true,
      },
    },
  },
}
