--- Theme selection, following the terminal's light/dark appearance.
---
--- Resolved once per config load and shared with the status bar, which derives
--- its accent overrides from the same palette.

local wezterm = require("wezterm")

local M = {}

M.themes = {
  ["kanagawa-wave"] = require("kanagawa-wave"),
  ["kanagawa-dragon"] = require("kanagawa-dragon"),
  ["kanagawa-lotus"] = require("kanagawa-lotus"),
  ["everforest"] = require("everforest"),
  ["rose-pine-dawn"] = require("rose-pine-dawn"),
  ["gruvbox"] = require("gruvbox"),
  ["adwaita"] = require("adwaita"),
}

--- Theme used for each appearance.
M.dark = "gruvbox"
M.light = "rose-pine-dawn"

--- wezterm.gui is unavailable to the mux server, so fall back to a sane
--- default when this config is evaluated outside the GUI process.
local function appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return "Dark"
end

--- Whether the active theme is a dark one, for contrast decisions elsewhere.
M.is_dark = appearance():find("Dark") ~= nil

--- The appearance as "dark" or "light", for programs that cannot ask.
---
--- WezTerm implements OSC 11 only for *setting* the background: it never
--- answers a query, so anything that detects the theme by asking the terminal
--- (Neovim's startup detection, the bash prompt) gets silence and falls back to
--- dark. Exporting the answer gives those programs something to read. It is
--- deliberately only a fallback on the consuming side: a terminal that does
--- answer the query must win, otherwise this value would be wrong the moment a
--- different terminal inherits it.
M.name = M.is_dark and "dark" or "light"

--- The resolved theme module.
M.current = M.themes[M.is_dark and M.dark or M.light]

--- The resolved color scheme, as assigned to config.colors.
M.colors = M.current.color_scheme

-- Status bar colours, taken from the theme's own tab bar palette rather than
-- invented, so the bar belongs to the colour scheme instead of sitting on top
-- of it.
local tab_bar = M.colors.tab_bar or {}

--- Background of the tab bar and status line.
M.bar_bg = tab_bar.background or M.colors.background

--- Primary text on the bar.
M.bar_fg = M.colors.foreground

--- Inks for text placed on a coloured swatch; util.ink_for picks whichever of
--- the two actually contrasts better with that swatch.
M.ink_dark = M.is_dark and "#1d2021" or "#26233a"
M.ink_light = M.is_dark and "#fbf1c7" or "#faf4ed"

--- Secondary text on the bar: git state, the clock.
---
--- Nudged toward the primary foreground when the theme's own muted tone is too
--- faint to read as status text, which several light themes are.
local raw_muted = (tab_bar.new_tab and tab_bar.new_tab.fg_color)
  or (tab_bar.inactive_tab and tab_bar.inactive_tab.fg_color)
  or M.colors.foreground

M.muted = require("wf_util").legible(raw_muted, M.bar_bg, M.bar_fg, 3.5)

return M
