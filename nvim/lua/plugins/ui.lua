local utils = require("config.utils")

-- Terminal theme tracking.
--
-- Neovim only finds out about a terminal theme change when the terminal
-- advertises DEC mode 2031 and pushes a notification. Windows Terminal has no
-- 2031, so the mode is never enabled and nothing is ever pushed -- but it does
-- answer OSC 11 queries. So we ask on a timer rather than wait to be told.
-- Terminals that do implement 2031 keep working: whatever they push arrives on
-- the same TermResponse event, and the poll then finds nothing new to do.
local THEME_POLL_MS = 2000

local themes = {
  dark = { colorscheme = "gruvbox", bat_theme = "gruvbox" },
  light = { colorscheme = "rose-pine-dawn", bat_theme = "rose-pine-dawn" },
}

-- Last theme handed to apply_theme(), so repeated polls don't reload the
-- colorscheme (which would clear highlights and re-run every ColorScheme hook)
-- a few times a second.
local current_theme = nil

--- Switch to the colorscheme for `name`, unless it is already active.
---@param name string "dark" or "light"
local apply_theme = function(name)
  local theme = themes[name]
  if not theme or name == current_theme then
    return
  end
  current_theme = name

  -- gruvbox.nvim picks its variant from vim.o.background, so that has to be set
  -- before the colorscheme rather than left to whatever nvim inferred.
  vim.o.background = name
  vim.cmd.colorscheme(theme.colorscheme)
  vim.env.BAT_THEME = theme.bat_theme
end

--- Classify an OSC 11 background colour response as "dark" or "light".
---
--- Matched loosely on purpose: the reply may be rgb: or rgba:, and each
--- component may carry one to four hex digits depending on the terminal.
---@param sequence string Raw terminal response
---@return string|nil name "dark", "light", or nil when this is not an OSC 11 reply
local parse_osc11 = function(sequence)
  local r, g, b = sequence:match("\27%]11;rgba?:(%x+)/(%x+)/(%x+)")
  if not (r and g and b) then
    return nil
  end

  --- Scale a component to [0,1]: its value over the maximum for its width.
  local channel = function(component)
    return tonumber(component, 16) / (16 ^ #component - 1)
  end

  -- Same luminance weights nvim uses for its own background detection.
  local luminance = (0.299 * channel(r)) + (0.587 * channel(g)) + (0.114 * channel(b))
  return luminance < 0.5 and "dark" or "light"
end

--- Ask the terminal for its background colour. The reply arrives asynchronously
--- as a TermResponse event.
local query_terminal_theme = function()
  vim.api.nvim_ui_send("\27]11;?\7")
end

local theme_config = function()
  -- nvim queries OSC 11 during startup and waits for the answer before sourcing
  -- user config, so 'background' is already correct by the time we get here.
  apply_theme(vim.o.background)

  local group = vim.api.nvim_create_augroup("dyskette_theme", { clear = true })

  vim.api.nvim_create_autocmd(utils.events.TermResponse, {
    desc = "Follow the terminal background colour reported over OSC 11",
    group = group,
    -- Without this, switching the colorscheme from inside this callback fires
    -- no ColorScheme event, and everything hanging off it (the tabby theme
    -- below, for one) would keep the colours of the previous theme.
    nested = true,
    callback = function(event)
      local name = parse_osc11(event.data and event.data.sequence or "")
      if name then
        apply_theme(name)
      end
    end,
  })

  -- Polling covers an unattended nvim; this catches the common case of toggling
  -- the system theme and coming straight back, without waiting out the interval.
  vim.api.nvim_create_autocmd(utils.events.FocusGained, {
    desc = "Check the terminal theme when returning to nvim",
    group = group,
    callback = query_terminal_theme,
  })

  local timer = vim.uv.new_timer()
  timer:start(THEME_POLL_MS, THEME_POLL_MS, vim.schedule_wrap(query_terminal_theme))

  vim.api.nvim_create_autocmd(utils.events.VimLeavePre, {
    desc = "Stop polling the terminal for theme changes",
    group = group,
    callback = function()
      if not timer:is_closing() then
        timer:close()
      end
    end,
  })
end

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
    -- Gruvbox dark medium, matching tmux/gruvbox.conf so the tab line and
    -- the tmux status line read as one bar.
    theme = {
      fill = { fg = "#EBDBB2", bg = "#282828" },
      head = { fg = "#282828", bg = "#EBDBB2", style = "bold" },
      current_tab = { fg = "#282828", bg = "#928374", style = "bold" },
      tab = { fg = "#EBDBB2", bg = "#3C3836" },
      win = { fg = "#282828", bg = "#A89984" },
      tail = { fg = "#282828", bg = "#83A598", style = "bold" },
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
        {
          "searchcount",
          maxcount = 999,
          timeout = 500,
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
  -- Color schemes. Which one is active follows the terminal background colour;
  -- see the theme tracking at the top of this file.
  {
    "ellisonleao/gruvbox.nvim",
    lazy = false,
    priority = 1000,
    -- setup() has to run before the colorscheme command for opts to apply,
    -- so the theme is only applied once the plugin is configured.
    opts = {},
    config = function(_, opts)
      require("gruvbox").setup(opts)
      theme_config()
    end,
  },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    -- Loaded on demand by lazy.nvim when apply_theme() picks rose-pine-dawn.
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
