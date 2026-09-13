--- WezTerm workflow system.
---
--- Three levels, and only three:
---   WORKSPACE = a project = one git repo
---     TAB     = an activity inside that project (edit / run / agent / notes)
---       PANE  = a surface inside that activity
---
--- Keymap reference: LEADER ? (Ctrl+Space, then ?).
--- Tunable settings: wf_settings.lua

local wezterm = require("wezterm")
local config = wezterm.config_builder()

local keys = require("wf_keys")
local settings = require("wf_settings")
local theme = require("wf_theme")

-- Registers the update-status and format-tab-title handlers.
require("wf_status")

config.automatically_reload_config = true

-- ── Where shells run ───────────────────────────────────────────────────────
--
-- On Windows the work happens inside WSL. Declaring it as a domain rather than
-- a default_prog means spawned tabs and splits inherit a working directory
-- that WezTerm understands, which is what lets the project template place
-- panes in a repository.

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
  config.wsl_domains = {
    {
      name = "WSL:" .. settings.wsl_distro,
      distribution = settings.wsl_distro,
      default_cwd = "~",
    },
  }
  -- WSL is what a window starts in, and what Escape at the shell picker keeps.
  config.default_domain = "WSL:" .. settings.wsl_distro
  -- ...while the local domain runs PowerShell, so a tab opened from a native
  -- Windows pane stays PowerShell instead of falling back to cmd.
  config.default_prog = { "pwsh.exe", "-NoLogo" }
else
  config.default_prog = { "toolbox", "enter" }
end

-- Registers the gui-startup handler that offers the shell choice.
local shells = require("wf_shells")
config.launch_menu = shells.launch_menu()

-- Tell spawned programs what the appearance is, since they cannot ask: see
-- wf_theme.name. WSLENV is what carries a variable across the Windows/WSL
-- boundary, and it is appended to rather than replaced, because Windows
-- Terminal already publishes WT_SESSION and WT_PROFILE_ID through it.
local env = { WEZTERM_THEME = theme.name }

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
  local wslenv = os.getenv("WSLENV") or ""
  if not wslenv:find("WEZTERM_THEME", 1, true) then
    if wslenv ~= "" and not wslenv:match(":$") then
      wslenv = wslenv .. ":"
    end
    wslenv = wslenv .. "WEZTERM_THEME"
  end
  env.WSLENV = wslenv
end

config.set_environment_variables = env

-- ── Appearance ─────────────────────────────────────────────────────────────

config.colors = theme.colors
config.font = wezterm.font("JetBrainsMonoNL Nerd Font")
config.font_size = 10.5

config.initial_cols = 120
config.initial_rows = 32

-- The tab bar is the client-safety surface: it carries the accent color, so it
-- stays visible even with a single tab.
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = false
config.tab_max_width = 24
config.show_new_tab_button_in_tab_bar = false

config.scrollback_lines = 20000
config.window_padding = { left = 6, right = 6, top = 4, bottom = 2 }

-- ── Input ──────────────────────────────────────────────────────────────────

config.leader = {
  key = settings.leader.key,
  mods = settings.leader.mods,
  timeout_milliseconds = settings.leader_timeout_ms,
}

-- AltGr handling for the Latin American ISO layout. The right Alt key must
-- compose characters (\ { } [ ] ~ @) rather than be reported as a bare Alt
-- modifier, while the left Alt stays a modifier for keybindings.
config.send_composed_key_when_right_alt_is_pressed = true
config.send_composed_key_when_left_alt_is_pressed = false

-- Dead keys stay enabled: ´ and ¨ compose the accents Spanish needs. Set this
-- to false if you would rather each press emit the character immediately.
config.use_dead_keys = true

config.keys = keys.keys
config.key_tables = keys.key_tables
config.quick_select_patterns = settings.quick_select_patterns

return config
