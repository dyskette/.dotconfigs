-- https://github.com/miguelverissimo/dotfiles
return {
  foreground = "#C5C9C5",
  background = "#181616",

  cursor_bg = "#43436C",
  cursor_fg = "#d5cea3",
  cursor_border = "#43436C",

  selection_fg = "#43436c",
  selection_bg = "#C9CBD1",

  scrollbar_thumb = "#c7d7e0",

  split = "#A09CAC",

  ansi = {
    "#1F1F28",
    "#C84053",
    "#6f894e",
    "#77713F",
    "#4d699b",
    "#B35B79",
    "#597b75",
    "#545464",
  },

  brights = {
    "#8a8980",
    "#D7474B",
    "#6e915f",
    "#836F4A",
    "#6693bf",
    "#624C83",
    "#5e857a",
    "#43436C",
  },

  indexed = { [16] = "#E98A00", [17] = "#E82424" },

  compose_cursor = "#766b90",

  copy_mode_active_highlight_bg = { Color = "#C9CBD1" },
  copy_mode_active_highlight_fg = { Color = "#43436c" },
  copy_mode_inactive_highlight_bg = { Color = "#43436C" },
  copy_mode_inactive_highlight_fg = { Color = "#d5cea3" },

  quick_select_label_bg = { Color = "#C84053" },
  quick_select_label_fg = { Color = "#dcd7ba" },
  quick_select_match_bg = { Color = "#E98A00" },
  quick_select_match_fg = { Color = "#dcd7ba" },

  visual_bell = "#D5CEA3",

  tab_bar = {
    background = "#d5cea3",

    active_tab = {
      bg_color = "#624C83",
      fg_color = "#d5cea3",
    },

    inactive_tab = {
      bg_color = "#8A8980",
      fg_color = "#d5cea3",
    },

    inactive_tab_hover = {
      bg_color = "#C9CBD1",
      fg_color = "#8a8980",
      italic = true,
    },

    new_tab = {
      bg_color = "#8A8980",
      fg_color = "#d5cea3",
    },

    new_tab_hover = {
      bg_color = "#4E8CA2",
      fg_color = "#d5cea3",
      italic = true,
    },
  },
}
