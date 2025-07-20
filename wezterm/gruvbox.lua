local wezterm = require("wezterm")

local M = {}

M.color_scheme = {
  foreground = "#EBDBB2",
  background = "#282828",

  -- The text color when the current cell is occupied by a cursor
  cursor_bg = "#EBDBB2",
  cursor_fg = "#282828",
  cursor_border = "#EBDBB2",

  -- The color of selected text
  selection_fg = "none",
  selection_bg = "#504945",

  -- The color of the scrollbar "thumb"; the part that represents the current view of the buffer
  scrollbar_thumb = "#928374",

  -- The color of the split lines
  split = "#928374",

  -- The color of the compose cursor. This is used when inputting complex characters
  -- or key sequences that involve multiple key presses to form a single character.
  compose_cursor = "#D3869B",

  -- Colors for the copy mode. Copy mode allows you to select and copy text from the terminal.
  copy_mode_active_highlight_bg = { Color = "#665C54" },
  copy_mode_active_highlight_fg = { Color = "#EBDBB2" },
  copy_mode_inactive_highlight_bg = { Color = "#504945" },
  copy_mode_inactive_highlight_fg = { Color = "#A89984" },

  -- Colors for quick select mode. Quick select allows you to quickly select text by typing a few characters.
  quick_select_label_bg = { Color = "#CC241D" },
  quick_select_label_fg = { Color = "#EBDBB2" },
  quick_select_match_bg = { Color = "#D79921" },
  quick_select_match_fg = { Color = "#282828" },

  -- The color of the visual bell.
  -- This is a flash of color that indicates a bell (e.g. a notification) has occurred.
  visual_bell = "#665C54",

  -- ANSI colors
  ansi = {
    "#282828", -- black
    "#CC241D", -- red
    "#98971A", -- green
    "#D79921", -- yellow
    "#458588", -- blue
    "#B16286", -- magenta
    "#689D6A", -- cyan
    "#A89984", -- white
  },
  -- High intensity version of the ANSI colors
  brights = {
    "#928374", -- bright black
    "#FB4934", -- bright red
    "#B8BB26", -- bright green
    "#FABD2F", -- bright yellow
    "#83A598", -- bright blue
    "#D3869B", -- bright magenta
    "#8EC07C", -- bright cyan
    "#EBDBB2", -- bright white
  },

  -- ANSI and bright orange
  indexed = { [16] = "#FE8019", [17] = "#D65D0E" },

  tab_bar = {
    background = "#282828",
    active_tab = {
      bg_color = "#928374",
      fg_color = "#282828",
    },
    inactive_tab = {
      bg_color = "#3C3836",
      fg_color = "#EBDBB2",
    },
    inactive_tab_hover = {
      bg_color = "#504945",
      fg_color = "#EBDBB2",
      italic = true,
    },
    new_tab = {
      bg_color = "#282828",
      fg_color = "#928374",
    },
    new_tab_hover = {
      bg_color = "#282828",
      fg_color = "#EBDBB2",
      italic = true,
    },
  },
}

function M.format_tab_title(tab)
  local program = tab.active_pane.title
  local title = string.format(" %s | %s ", tab.tab_index + 1, program)

  if tab.is_active then
    return wezterm.format({
      { Background = { Color = "#928374" } },
      { Foreground = { Color = "#282828" } },
      { Text = title },
      { Background = { Color = "#282828" } },
      { Foreground = { Color = "#282828" } },
      { Text = " " }
    })
  else
    return wezterm.format({
      { Background = { Color = "#3C3836" } },
      { Foreground = { Color = "#EBDBB2" } },
      { Text = title },
      { Background = { Color = "#282828" } },
      { Foreground = { Color = "#282828" } },
      { Text = " " }
    })
  end
end

return M
