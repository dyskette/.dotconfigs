local wezterm = require("wezterm")

local M = {}

M.color_scheme = {
  foreground = "#DEDDDA",
  background = "#1D1D20",

  cursor_bg = "#DEDDDA",
  cursor_fg = "#1D1D20",
  cursor_border = "#DEDDDA",

  selection_fg = "none",
  selection_bg = "#193D66",

  scrollbar_thumb = "#2E2E32",

  split = "#2E2E32",

  compose_cursor = "#C061CB",

  copy_mode_active_highlight_bg = { Color = "#193D66" },
  copy_mode_active_highlight_fg = { Color = "#DEDDDA" },
  copy_mode_inactive_highlight_bg = { Color = "#2E2E32" },
  copy_mode_inactive_highlight_fg = { Color = "#9A9996" },

  quick_select_label_bg = { Color = "#ED333B" },
  quick_select_label_fg = { Color = "#DEDDDA" },
  quick_select_match_bg = { Color = "#F5C211" },
  quick_select_match_fg = { Color = "#3D3D3D" },

  visual_bell = "#2E2E32",

  ansi = {
    "#1D1D20", -- black
    "#ED333B", -- red
    "#57E389", -- green
    "#FF7800", -- yellow
    "#62A0EA", -- blue
    "#9141AC", -- magenta
    "#5BC8AF", -- cyan
    "#DEDDDA", -- white
  },
  brights = {
    "#9A9996", -- bright black
    "#F66151", -- bright red
    "#8FF0A4", -- bright green
    "#FFA348", -- bright yellow
    "#99C1F1", -- bright blue
    "#DC8ADD", -- bright magenta
    "#93DDC2", -- bright cyan
    "#F6F5F4", -- bright white
  },

  tab_bar = {
    background = "#1D1D20",
    active_tab = {
      bg_color = "#36363A",
      fg_color = "#DEDDDA",
    },
    inactive_tab = {
      bg_color = "#242428",
      fg_color = "#9A9996",
    },
    inactive_tab_hover = {
      bg_color = "#2E2E32",
      fg_color = "#DEDDDA",
      italic = true,
    },
    new_tab = {
      bg_color = "#1D1D20",
      fg_color = "#5E5E5E",
    },
    new_tab_hover = {
      bg_color = "#1D1D20",
      fg_color = "#DEDDDA",
      italic = true,
    },
  },
}

function M.format_tab_title(tab)
  local program = tab.active_pane.title
  local title = string.format(" %s | %s ", tab.tab_index + 1, program)

  if tab.is_active then
    return wezterm.format({
      { Background = { Color = "#36363A" } },
      { Foreground = { Color = "#DEDDDA" } },
      { Text = title },
      { Background = { Color = "#1D1D20" } },
      { Foreground = { Color = "#1D1D20" } },
      { Text = " " }
    })
  else
    return wezterm.format({
      { Background = { Color = "#242428" } },
      { Foreground = { Color = "#9A9996" } },
      { Text = title },
      { Background = { Color = "#1D1D20" } },
      { Foreground = { Color = "#1D1D20" } },
      { Text = " " }
    })
  end
end

return M
