local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
  config.default_prog = { "wsl", "--distribution", "Ubuntu-24.04" }
else
  config.default_prog = { "toolbox", "enter" }
end

-- wezterm.gui is not available to the mux server, so take care to
-- do something reasonable when this config is evaluated by the mux
local get_appearance = function()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return "Light"
end

local themes = {
  ["kanagawa-wave"] = require("kanagawa-wave"),
  ["kanagawa-dragon"] = require("kanagawa-dragon"),
  ["kanagawa-lotus"] = require("kanagawa-lotus"),
  ["everforest"] = require("everforest"),
  ["rose-pine-dawn"] = require("rose-pine-dawn"),
  ["gruvbox"] = require("gruvbox"),
}

local get_theme_for_appearance = function(appearance)
  if appearance:find("Dark") then
    return themes["gruvbox"]
  else
    return themes["rose-pine-dawn"]
  end
end

local current_theme = get_theme_for_appearance(get_appearance())
config.colors = current_theme.color_scheme
config.font = wezterm.font("JetBrainsMonoNL Nerd Font")
config.font_size = 10.5
config.enable_tab_bar = false

config.initial_cols = 120
config.initial_rows = 32

config.keys = {
  -- Fullscreen
  { key = "F11", action = wezterm.action.ToggleFullScreen },

  -- Fix Ctrl-Space on Windows
  {
    key = " ",
    mods = "CTRL",
    action = wezterm.action.SendKey({
      key = " ",
      mods = "CTRL",
    }),
  },
}

-- Return the configuration to wezterm
return config
