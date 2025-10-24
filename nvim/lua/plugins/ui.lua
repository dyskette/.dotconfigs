local utils = require("config.utils")

local set_dark_mode = function()
  vim.o.background = "dark"
  vim.cmd.colorscheme("gruvbox")
  vim.env.BAT_THEME = "gruvbox"
end

local set_light_mode = function()
  vim.o.background = "light"
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

local tabby_opts = function()
  -- Build theme matching your tmux configs exactly
  local is_dark = vim.o.background == "dark"
  local theme = {}

  if is_dark then
    -- Gruvbox colors from your tmux config
    theme = {
      fill = { fg = "#ebdbb2", bg = "#282828" },
      head = { fg = "#282828", bg = "#ebdbb2", style = "bold" },
      current_tab = { fg = "#282828", bg = "#928374", style = "bold" },
      tab = { fg = "#ebdbb2", bg = "#3c3836" },
      win = { fg = "#282828", bg = "#a89984" },
      tail = { fg = "#282828", bg = "#83a598", style = "bold" },
    }
  else
    -- Rose Pine Dawn colors from your tmux config
    theme = {
      fill = { fg = "#575279", bg = "#faf4ed" },
      head = { fg = "#f2e9e1", bg = "#907aa9", style = "bold" },
      current_tab = { fg = "#575279", bg = "#d7827e", style = "bold" },
      tab = { fg = "#575279", bg = "#f2e9e1" },
      win = { fg = "#f2e9e1", bg = "#56949f" },
      tail = { fg = "#f2e9e1", bg = "#ea9d34", style = "bold" },
    }
  end

  return {
    line = function(line)
      return {
        {
          { " 󰓩  ", hl = theme.head },
          line.sep("", theme.head, theme.fill),
        },
        line.tabs().foreach(function(tab)
          local hl = tab.is_current() and theme.current_tab or theme.tab
          return {
            line.sep("", hl, theme.fill),
            tab.is_current() and " " or " ",
            tab.number(),
            " ",
            tab.name(),
            tab.close_btn(" 󰅖 "),
            line.sep("", hl, theme.fill),
            hl = hl,
            margin = " ",
          }
        end),
        line.spacer(),
        line.wins_in_tab(line.api.get_current_tab()).foreach(function(win)
          local hl = win.is_current() and theme.current_tab or theme.win
          return {
            line.sep("", hl, theme.fill),
            win.is_current() and " " or " ",
            win.file_icon(),
            " ",
            win.buf_name(),
            line.sep("", hl, theme.fill),
            hl = hl,
            margin = " ",
          }
        end),
        {
          line.sep("", theme.tail, theme.fill),
          { " 󰘲 ", hl = theme.tail },
        },
        hl = theme.fill,
      }
    end,
    option = {
      buf_name = {
        mode = "unique",
      },
    },
  }
end

local tabby_config = function()
  local setup_tabby = function()
    require("tabby").setup(tabby_opts())
  end

  setup_tabby()

  -- Call tabby setup when colorscheme changes
  local tabby_config_group = vim.api.nvim_create_augroup("dyskette_tabby_config", { clear = true })
  vim.api.nvim_create_autocmd({ utils.events.ColorScheme }, {
    desc = "Update tabby configuration on colorscheme change",
    group = tabby_config_group,
    callback = setup_tabby,
  })
end

local lualine_opts = function()
  local diffview_files = template_onlyname("DiffviewFiles", "Diffview Files")
  local diffview_file_history = template_onlyname("DiffviewFileHistory", "Diffview File History")

  local trouble = require("trouble")
  local symbols = trouble.statusline({
    mode = "lsp_document_symbols",
    groups = {},
    title = false,
    filter = { range = true },
    format = "{kind_icon}{symbol.name:Normal}",
    hl_group = "lualine_c_normal",
  })

  return {
    extensions = { "lazy", "mason", "oil", "trouble", diffview_files, diffview_file_history },
    options = {
      component_separators = {
        left = utils.icons.separators.triple_dash_vertical,
        right = utils.icons.separators.triple_dash_vertical,
      },
      section_separators = { left = "", right = "" },
      globalstatus = true,
    },
    sections = {
      lualine_b = {
        "branch",
        "diff",
        {
          "diagnostics",
          symbols = {
            error = utils.icons.error,
            warn = utils.icons.warn,
            info = utils.icons.info,
            hint = utils.icons.hint .. " ",
          },
        },
      },
      lualine_c = {
        {
          symbols.get,
          cond = symbols.has,
        },
      },
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
    "nanozuki/tabby.nvim",
    event = utils.events.VeryLazy,
    config = tabby_config,
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
      "folke/trouble.nvim",
    },
  },
  -- LSP progress/vim.notify
  {
    "j-hui/fidget.nvim",
    event = utils.events.VeryLazy,
    opts = fidget_opts,
  },
  {
    "folke/which-key.nvim",
    event = utils.events.VeryLazy,
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
    },
  },
}
