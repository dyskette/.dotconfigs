-- https://github.com/neanias/config
local wezterm = require("wezterm")

local M = {}

M.color_scheme = {
  background = "#2D353B",
  foreground = "#D3C6AA",

  cursor_bg = "#D3C6AA",
  cursor_fg = "#272E33",
  cursor_border = "#D3C6AA",

  selection_fg = "#272E33",
  selection_bg = "#4C3743",

  scrollbar_thumb = "#312C44",

  split = "#374145",

  ansi = {
    "#4B565C",
    "#E67E80",
    "#A7C080",
    "#DBBC7F",
    "#7FBBB3",
    "#D699B6",
    "#83C092",
    "#D3C6AA",
  },

  brights = {
    "#5C6A72",
    "#F85552",
    "#8DA101",
    "#DFA000",
    "#3A94C5",
    "#DF69BA",
    "#35A77C",
    "#DFDDC8",
  },

  indexed = { [16] = "#DFA00F", [17] = "#F8555F" },

  compose_cursor = "#E69875",

  copy_mode_active_highlight_bg = { Color = "#374145" },
  copy_mode_active_highlight_fg = { Color = "#9DA9A0" },
  copy_mode_inactive_highlight_bg = { Color = "#A6D5A7" },
  copy_mode_inactive_highlight_fg = { Color = "#151025" },

  quick_select_label_bg = { Color = "#2E383C" },
  quick_select_label_fg = { Color = "#E69875" },
  quick_select_match_bg = { Color = "#2E383C" },
  quick_select_match_fg = { Color = "#9DA9A0" },

  visual_bell = "#D5CEA3",

  tab_bar = {
    background = "#2D353B",
    inactive_tab_edge = "#232A2E",

    active_tab = {
      bg_color = "#232A2E",
      fg_color = "#7FBBB3",
    },

    inactive_tab = {
      bg_color = "#4F585E",
      fg_color = "#343F44",
    },

    inactive_tab_hover = {
      bg_color = "#7FBBB3",
      fg_color = "#343F44",
      italic = true,
    },

    new_tab = {
      bg_color = "#2D353B",
      fg_color = "#D3C6AA",
    },

    new_tab_hover = {
      bg_color = "#4B565C",
      fg_color = "#DFDDC8",
      italic = true,
    },
  },
}

function M.format_tab_title(tab)
  local program = tab.active_pane.title
  local title = string.format(" %s | %s ", tab.tab_index + 1, program)

  if tab.is_active then
    return wezterm.format({
      { Background = { Color = "#232A2E" } },
      { Foreground = { Color = "#7FBBB3" } },
      { Text = title },
      { Background = { Color = "#2D353B" } },
      { Foreground = { Color = "#2D353B" } },
      { Text = " " }
    })
  else
    return wezterm.format({
      { Background = { Color = "#4F585E" } },
      { Foreground = { Color = "#343F44" } },
      { Text = title },
      { Background = { Color = "#2D353B" } },
      { Foreground = { Color = "#2D353B" } },
      { Text = " " }
    })
  end
end

return M
