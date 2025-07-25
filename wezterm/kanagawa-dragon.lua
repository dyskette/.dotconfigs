-- https://github.com/miguelverissimo/dotfiles
local wezterm = require("wezterm")

local M = {}

M.color_scheme = {
  background = "#181616",
  foreground = "#C5C9C5",

  cursor_bg = "#C8C093",
  cursor_fg = "#0D0C0C",
  cursor_border = "#C8C093",

  selection_fg = "#DCD7BA",
  selection_bg = "#223249",

  scrollbar_thumb = "#223249",

  split = "#625E5A",

  ansi = {
    "#0D0C0C",
    "#C4746E",
    "#8A9A7B",
    "#C4B28A",
    "#8BA4B0",
    "#A292A3",
    "#8EA4A2",
    "#C8C093",
  },

  brights = {
    "#A6A69C",
    "#E46876",
    "#87A987",
    "#E6C384",
    "#7FB4CA",
    "#938AA9",
    "#7AA89F",
    "#C5C9C5",
  },

  indexed = { [16] = "#B6927B", [17] = "#B98D7B" },

  compose_cursor = "#7A8382",

  copy_mode_active_highlight_bg = { Color = "#223249" },
  copy_mode_active_highlight_fg = { Color = "#DCD7BA" },
  copy_mode_inactive_highlight_bg = { Color = "#43436C" },
  copy_mode_inactive_highlight_fg = { Color = "#D5CEA3" },

  quick_select_label_bg = { Color = "#C4746E" },
  quick_select_label_fg = { Color = "#C5C9C5" },
  quick_select_match_bg = { Color = "#FF9E3B" },
  quick_select_match_fg = { Color = "#C5C9C5" },

  visual_bell = "#0D0C0C",

  tab_bar = {
    background = "#0D0C0C",

    active_tab = {
      bg_color = "#8992A7",
      fg_color = "#0D0C0C",
    },

    inactive_tab = {
      bg_color = "#737C73",
      fg_color = "#0D0C0C",
    },

    inactive_tab_hover = {
      bg_color = "#223249",
      fg_color = "#737C73",
      italic = true,
    },

    new_tab = {
      bg_color = "#737C73",
      fg_color = "#0D0C0C",
    },

    new_tab_hover = {
      bg_color = "#223249",
      fg_color = "#0D0C0C",
      italic = true,
    },
  },
}

function M.format_tab_title(tab)
  local program = tab.active_pane.title
  local title = string.format(" %s | %s ", tab.tab_index + 1, program)

  if tab.is_active then
    return wezterm.format({
      { Background = { Color = "#8992A7" } },
      { Foreground = { Color = "#0D0C0C" } },
      { Text = title },
      { Background = { Color = "#0D0C0C" } },
      { Foreground = { Color = "#0D0C0C" } },
      { Text = " " }
    })
  else
    return wezterm.format({
      { Background = { Color = "#737C73" } },
      { Foreground = { Color = "#0D0C0C" } },
      { Text = title },
      { Background = { Color = "#0D0C0C" } },
      { Foreground = { Color = "#0D0C0C" } },
      { Text = " " }
    })
  end
end

return M
