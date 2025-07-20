local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
  config.default_prog = { "pwsh" }

  -- Show the launcher menu on startup
  wezterm.on("gui-startup", function(cmd)
    local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
    window:gui_window():perform_action(wezterm.action.ShowLauncherArgs({ flags = "DOMAINS" }), pane)
  end)
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
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

wezterm.on("format-tab-title", function(tab, tabs, panes, window_config, hover, max_width)
  return current_theme.format_tab_title(tab)
end)

config.initial_cols = 120
config.initial_rows = 32

config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
  -- Send "CTRL-A" to the terminal when pressing CTRL-A, CTRL-A
  {
    key = "a",
    mods = "LEADER|CTRL",
    action = wezterm.action.SendKey({ key = "a", mods = "CTRL" }),
  },
  -- New window
  { key = "c", mods = "LEADER", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  -- Previous and next window
  { key = "p", mods = "LEADER", action = wezterm.action.ActivateTabRelative(-1) },
  { key = "n", mods = "LEADER", action = wezterm.action.ActivateTabRelative(1) },
  -- New | split pane
  { key = "%", mods = "LEADER|SHIFT", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  -- New -- split pane
  { key = '"', mods = "LEADER|SHIFT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
  -- Move between panes
  { key = "k", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Up") },
  { key = "j", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Down") },
  { key = "h", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Left") },
  { key = "l", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Right") },

  -- Close pane/window
  { key = "x", mods = "LEADER", action = wezterm.action.CloseCurrentPane({ confirm = false }) },

  -- Copy
  { key = "[", mods = "LEADER|SHIFT", action = wezterm.action.ActivateCopyMode },
  { key = "]", mods = "LEADER|SHIFT", action = wezterm.action.PasteFrom("Clipboard") },

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
