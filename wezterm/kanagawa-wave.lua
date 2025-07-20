-- https://github.com/miguelverissimo/dotfiles
local wezterm = require("wezterm")

local M = {}

M.color_scheme = {
  background = "#1F1F28",
  foreground = "#DCD7BA",

  cursor_bg = "#C8C093",
  cursor_fg = "#16161D",
  cursor_border = "#C8C093",

  selection_bg = "#223249",
  selection_fg = "#DCD7BA",

  scrollbar_thumb = "#223249",

  split = "#54546D",

  ansi = {
    "#090618",
    "#C34043",
    "#76946A",
    "#C0A36E",
    "#7E9CD8",
    "#957FB8",
    "#6A9589",
    "#C8C093",
  },

  brights = {
    "#727169",
    "#E82424",
    "#98BB6C",
    "#E6C384",
    "#7FB4CA",
    "#938AA9",
    "#7AA89F",
    "#DCD7BA",
  },

  indexed = { [16] = "#FFA066", [17] = "#FF5D62" },

  compose_cursor = "#938AA9",

  copy_mode_active_highlight_bg = { Color = "#223249" },
  copy_mode_active_highlight_fg = { Color = "#DCD7BA" },
  copy_mode_inactive_highlight_bg = { Color = "#C8C093" },
  copy_mode_inactive_highlight_fg = { Color = "#16161D" },

  quick_select_label_bg = { Color = "#FF5D62" },
  quick_select_label_fg = { Color = "#DCD7BA" },
  quick_select_match_bg = { Color = "#FF9E3B" },
  quick_select_match_fg = { Color = "#DCD7BA" },

  visual_bell = "#16161D",

  tab_bar = {
    background = "#16161D",

    active_tab = {
      bg_color = "#7E9CD8",
      fg_color = "#1F1F28",
    },

    inactive_tab = {
      bg_color = "#727169",
      fg_color = "#181820",
    },

    inactive_tab_hover = {
      bg_color = "#223249",
      fg_color = "#727169",
      italic = true,
    },

    new_tab = {
      bg_color = "#727169",
      fg_color = "#181820",
    },

    new_tab_hover = {
      bg_color = "#9CABCA",
      fg_color = "#181820",
      italic = true,
    },
  },
}

function M.format_tab_title(tab)
  local program = tab.active_pane.title
  local title = string.format(" %s | %s ", tab.tab_index + 1, program)

  if tab.is_active then
    return wezterm.format({
      { Background = { Color = "#7E9CD8" } },
      { Foreground = { Color = "#1F1F28" } },
      { Text = title },
      { Background = { Color = "#16161D" } },
      { Foreground = { Color = "#16161D" } },
      { Text = " " }
    })
  else
    return wezterm.format({
      { Background = { Color = "#727169" } },
      { Foreground = { Color = "#181820" } },
      { Text = title },
      { Background = { Color = "#16161D" } },
      { Foreground = { Color = "#16161D" } },
      { Text = " " }
    })
  end
end

return M
