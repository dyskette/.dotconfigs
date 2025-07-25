-- https://github.com/miguelverissimo/dotfiles
local wezterm = require("wezterm")

local M = {}

M.color_scheme = {
  background = "#F2ECBC",
  foreground = "#545464",

  cursor_bg = "#43436C",
  cursor_fg = "#D5CEA3",
  cursor_border = "#43436C",

  selection_fg = "#43436C",
  selection_bg = "#C9CBD1",

  scrollbar_thumb = "#C7D7E0",

  split = "#A09CAC",

  ansi = {
    "#1F1F28",
    "#C84053",
    "#6F894E",
    "#77713F",
    "#4D699B",
    "#B35B79",
    "#597B75",
    "#545464",
  },

  brights = {
    "#8A8980",
    "#D7474B",
    "#6E915F",
    "#836F4A",
    "#6693BF",
    "#624C83",
    "#5E857A",
    "#43436C",
  },

  indexed = { [16] = "#E98A00", [17] = "#E82424" },

  compose_cursor = "#766B90",

  copy_mode_active_highlight_bg = { Color = "#C9CBD1" },
  copy_mode_active_highlight_fg = { Color = "#43436C" },
  copy_mode_inactive_highlight_bg = { Color = "#43436C" },
  copy_mode_inactive_highlight_fg = { Color = "#D5CEA3" },

  quick_select_label_bg = { Color = "#C84053" },
  quick_select_label_fg = { Color = "#DCD7BA" },
  quick_select_match_bg = { Color = "#E98A00" },
  quick_select_match_fg = { Color = "#DCD7BA" },

  visual_bell = "#D5CEA3",

  tab_bar = {
    background = "#D5CEA3",

    active_tab = {
      bg_color = "#624C83",
      fg_color = "#D5CEA3",
    },

    inactive_tab = {
      bg_color = "#8A8980",
      fg_color = "#D5CEA3",
    },

    inactive_tab_hover = {
      bg_color = "#C9CBD1",
      fg_color = "#8A8980",
      italic = true,
    },

    new_tab = {
      bg_color = "#8A8980",
      fg_color = "#D5CEA3",
    },

    new_tab_hover = {
      bg_color = "#4E8CA2",
      fg_color = "#D5CEA3",
      italic = true,
    },
  },
}

function M.format_tab_title(tab)
  local program = tab.active_pane.title
  local title = string.format(" %s | %s ", tab.tab_index + 1, program)

  if tab.is_active then
    return wezterm.format({
      { Background = { Color = "#624C83" } },
      { Foreground = { Color = "#D5CEA3" } },
      { Text = title },
      { Background = { Color = "#D5CEA3" } },
      { Foreground = { Color = "#D5CEA3" } },
      { Text = " " }
    })
  else
    return wezterm.format({
      { Background = { Color = "#8A8980" } },
      { Foreground = { Color = "#D5CEA3" } },
      { Text = title },
      { Background = { Color = "#D5CEA3" } },
      { Foreground = { Color = "#D5CEA3" } },
      { Text = " " }
    })
  end
end

return M
