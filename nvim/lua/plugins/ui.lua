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

-- One colorscheme for both: everforest picks its dark or light palette from
-- 'background'. bat_theme names the matching bat/themes file.
local themes = {
  dark = { colorscheme = "everforest", bat_theme = "everforest-dark-medium" },
  light = { colorscheme = "everforest", bat_theme = "everforest-light-medium" },
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

  -- everforest picks its palette from vim.o.background, so that has to be set
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
  -- user config, so on a terminal that answers, 'background' is already correct
  -- by the time we get here.
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

local tabby_opts = function()
  -- Build theme matching your tmux configs exactly
  local is_dark = vim.o.background == "dark"
  local theme = {}

  -- Everforest medium, matching tmux/everforest-*-medium.conf so the tab line
  -- and the tmux status line read as one bar: head and tail are the session
  -- and host blocks, tabs the window list, windows the date block.
  if is_dark then
    theme = {
      fill = { fg = "#D3C6AA", bg = "#343F44" },
      head = { fg = "#2D353B", bg = "#A7C080", style = "bold" },
      current_tab = { fg = "#D3C6AA", bg = "#425047", style = "bold" },
      tab = { fg = "#9DA9A0", bg = "#3D484D" },
      win = { fg = "#D3C6AA", bg = "#475258" },
      tail = { fg = "#2D353B", bg = "#A7C080", style = "bold" },
    }
  else
    -- Inverted fg blocks: text on the light greens would be 2.7:1 at best.
    theme = {
      fill = { fg = "#5C6A72", bg = "#F4F0D9" },
      head = { fg = "#FDF6E3", bg = "#5C6A72", style = "bold" },
      current_tab = { fg = "#5C6A72", bg = "#F0F1D2", style = "bold" },
      tab = { fg = "#5C6A72", bg = "#EFEBD4" },
      win = { fg = "#5C6A72", bg = "#E6E2CC" },
      tail = { fg = "#FDF6E3", bg = "#5C6A72", style = "bold" },
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

return {
  -- Color schemes. Which one is active follows the terminal background colour;
  -- see the theme tracking at the top of this file.
  {
    "sainnhe/everforest",
    lazy = false,
    priority = 1000,
    config = function()
      -- Read when the colorscheme loads, so they are set before theme_config()
      -- runs :colorscheme. Medium is the default; spelled out to match the
      -- terminals and tmux.
      vim.g.everforest_background = "medium"
      vim.g.everforest_better_performance = 1
      theme_config()
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
  -- The status bar is config/statusline.lua: native, no plugin.
  -- vim.notify and LSP progress are snacks.notifier (plugins/snacks.lua).
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
