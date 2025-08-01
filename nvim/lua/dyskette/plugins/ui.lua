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

local auto_dark_opts = {
  update_interval = 1000,
  fallback = "light",
  set_dark_mode = set_dark_mode,
  set_light_mode = set_light_mode,
}

local template_onlyname = function(filetype, name)
  return {
    filetypes = { filetype },
    sections = {
      lualine_a = { {
        function()
          return name
        end,
        color = "white",
      } },
    },
  }
end

local luatab_opts = {}

local lualine_opts = function()
  local diffview_files = template_onlyname("DiffviewFiles", "Diffview Files")
  local diffview_file_history = template_onlyname("DiffviewFileHistory", "Diffview File History")

  return {
    extensions = { "lazy", "mason", "oil", "trouble", diffview_files, diffview_file_history },
    options = {
      component_separators = { left = "|", right = "|" },
      section_separators = { left = "", right = "" },
    },
  }
end

local fidget_opts = {
  notification = {
    override_vim_notify = true,
  },
}

return {
  -- Color scheme
  {
    "f-person/auto-dark-mode.nvim",
    event = utils.events.VeryLazy,
    opts = auto_dark_opts,
  },
  {
    "ellisonleao/gruvbox.nvim",
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
  -- tab bar
  {
    "alvarosevilla95/luatab.nvim",
    event = utils.events.VeryLazy,
    opts = luatab_opts,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
  },
  -- Status bar
  {
    "nvim-lualine/lualine.nvim",
    opts = lualine_opts,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
  },
  -- LSP progress/vim.notify
  {
    "j-hui/fidget.nvim",
    event = utils.events.VeryLazy,
    opts = fidget_opts,
  },
}
