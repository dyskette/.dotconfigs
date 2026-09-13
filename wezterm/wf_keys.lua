--- Keymap and sticky key tables.
---
--- Frequency determines key cost: pane focus is the most frequent action in a
--- terminal and gets no prefix at all, workspace management is rarer and goes
--- behind the leader.

local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local cheatsheet = require("wf_cheatsheet")
local shells = require("wf_shells")
local projects = require("wf_projects")
local settings = require("wf_settings")
local status = require("wf_status")
local util = require("wf_util")

local M = {}

-- ── Neovim-aware pane focus ────────────────────────────────────────────────

--- Whether the pane is running Neovim.
---
--- Detection is by user var rather than process name: on Windows the visible
--- foreground process of a WSL pane is wsl.exe, so the process name never says
--- "nvim". Neovim publishes IS_NVIM over OSC 1337 instead (see the nvim-side
--- plugin), which also survives ssh. The process check remains as a fallback
--- for a native Linux WezTerm.
local function is_nvim(pane)
  local ok, vars = pcall(function()
    return pane:get_user_vars()
  end)
  if ok and vars and vars.IS_NVIM == "true" then
    return true
  end

  local proc_ok, proc = pcall(function()
    return pane:get_foreground_process_name()
  end)
  if proc_ok and proc then
    return proc:find("nvim") ~= nil or proc:find("vim") ~= nil
  end
  return false
end

--- One set of keys that moves through both Neovim splits and WezTerm panes.
--- Inside Neovim the key is forwarded; Neovim yields at its split edges and
--- focus leaves the editor.
local function pane_nav(key, direction)
  return {
    key = key,
    mods = "CTRL",
    action = wezterm.action_callback(function(window, pane)
      if is_nvim(pane) then
        window:perform_action(act.SendKey({ key = key, mods = "CTRL" }), pane)
      else
        window:perform_action(act.ActivatePaneDirection(direction), pane)
      end
    end),
  }
end

-- ── Semantic-zone actions ──────────────────────────────────────────────────

--- Copies the entire output of the last command. Requires OSC 133 shell
--- integration; without it there are no semantic zones to read.
local function copy_last_output()
  return wezterm.action_callback(function(window, pane)
    local ok, zones = pcall(function()
      return pane:get_semantic_zones("Output")
    end)

    if not ok or not zones or #zones == 0 then
      window:toast_notification(
        "wezterm",
        "No command output found. Is the OSC 133 shell integration loaded?",
        nil,
        4000
      )
      return
    end

    local text = pane:get_text_from_semantic_zone(zones[#zones])
    window:copy_to_clipboard(text, "ClipboardAndPrimarySelection")
    window:toast_notification("wezterm", "Copied last command output", nil, 1500)
  end)
end

--- Dumps the full scrollback to a file and opens it in a new tab, for the
--- times a single clipboard is not enough.
local function dump_scrollback()
  return wezterm.action_callback(function(window, pane)
    local workspace = window:active_workspace():gsub("[^%w@._-]", "_")
    local path = util.cache_dir() .. "/wf-" .. workspace .. ".log"

    local handle = io.open(path, "w")
    if not handle then
      window:toast_notification("wezterm", "Could not write " .. path, nil, 4000)
      return
    end
    handle:write(pane:get_lines_as_text(pane:get_dimensions().scrollback_rows))
    handle:close()

    local tab = window:mux_window():spawn_tab(util.view_file_opts(pane, path))
    tab:set_title("log")
  end)
end

-- ── Layout ─────────────────────────────────────────────────────────────────

--- Restores a template tab's panes to their designed proportions.
---
--- WezTerm has no native rebalance, so the current geometry is measured and
--- the divider is moved by the difference. Only the two-pane template tabs
--- have a defined shape to restore; anything else is left alone rather than
--- guessed at.
local function rebalance()
  return wezterm.action_callback(function(window, pane)
    local tab = window:active_tab()
    local split = settings.template_splits[tab:get_title()]
    local panes = tab:panes_with_info()

    if not split or #panes ~= 2 then
      window:toast_notification("wezterm", "Nothing to rebalance in this tab", nil, 2000)
      return
    end

    local vertical = split.direction == "Bottom"
    local first, second = panes[1], panes[2]
    -- panes_with_info is ordered, but be explicit about which one is primary.
    if vertical and first.top > second.top then
      first, second = second, first
    elseif not vertical and first.left > second.left then
      first, second = second, first
    end

    local size_of = function(info)
      return vertical and info.height or info.width
    end

    local total = size_of(first) + size_of(second)
    local delta = math.floor(total * split.primary) - size_of(first)
    if delta == 0 then
      return
    end

    local direction
    if vertical then
      direction = delta > 0 and "Down" or "Up"
    else
      direction = delta > 0 and "Right" or "Left"
    end

    first.pane:activate()
    window:perform_action(act.AdjustPaneSize({ direction, math.abs(delta) }), first.pane)
    pane:activate()
  end)
end

-- ── Workspace actions ──────────────────────────────────────────────────────

--- The client alt-tab: bounce to the workspace visited before this one.
local function toggle_workspace()
  return wezterm.action_callback(function(window, pane)
    local previous = status.previous_workspace()
    if previous == "" or previous == window:active_workspace() then
      window:toast_notification("wezterm", "No previous workspace yet", nil, 1500)
      return
    end
    window:perform_action(act.SwitchToWorkspace({ name = previous }), pane)
  end)
end

--- Closes every tab in the active workspace after confirmation.
local function close_workspace()
  return wezterm.action_callback(function(window, pane)
    local name = window:active_workspace()
    if name == settings.notes_workspace then
      window:toast_notification("wezterm", "@notes stays open by design", nil, 2000)
      return
    end

    window:perform_action(
      act.PromptInputLine({
        description = "Close workspace '" .. name .. "' and all its tabs? Type y to confirm.",
        action = wezterm.action_callback(function(inner_window, _, line)
          if line ~= "y" then
            return
          end
          for _, mux_window in ipairs(mux.all_windows()) do
            if mux_window:get_workspace() == name then
              for _, tab in ipairs(mux_window:tabs()) do
                tab:activate()
                inner_window:perform_action(
                  act.CloseCurrentTab({ confirm = false }),
                  mux_window:active_pane()
                )
              end
            end
          end
        end),
      }),
      pane
    )
  end)
end

local function rename_workspace()
  return act.PromptInputLine({
    description = "New workspace name:",
    action = wezterm.action_callback(function(_, _, line)
      if line and line ~= "" then
        mux.rename_workspace(mux.get_active_workspace(), line)
      end
    end),
  })
end

--- Jumps to a template tab by name, recreating it if it was closed.
local function named_tab(name)
  return wezterm.action_callback(function(window)
    projects.activate_named_tab(window, name)
  end)
end

-- ── Keymap ─────────────────────────────────────────────────────────────────

M.keys = {
  -- No prefix: focus and resize, the highest-frequency actions.
  pane_nav("h", "Left"),
  pane_nav("j", "Down"),
  pane_nav("k", "Up"),
  pane_nav("l", "Right"),

  { key = "h", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Left", settings.resize_step }) },
  { key = "j", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Down", settings.resize_step }) },
  { key = "k", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Up", settings.resize_step }) },
  { key = "l", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Right", settings.resize_step }) },

  { key = "f", mods = "CTRL|SHIFT", action = act.Search({ CaseInSensitiveString = "" }) },
  { key = "PageUp", mods = "SHIFT", action = act.ScrollByPage(-1) },
  { key = "PageDown", mods = "SHIFT", action = act.ScrollByPage(1) },
  { key = "F11", action = act.ToggleFullScreen },

  -- LEADER LEADER sends the leader through to the running program, so a
  -- remote tmux (or readline) still receives it.
  {
    key = settings.leader.key,
    mods = "LEADER|" .. settings.leader.mods,
    action = act.SendKey(settings.leader),
  },

  -- AltGr is Ctrl+Alt on Windows, and the Latin American layout needs AltGr
  -- for \ { } [ ] ~ @. WezTerm's stock Ctrl+Alt assignments sit on exactly
  -- the characters those combinations produce, so typing a backslash would
  -- otherwise split a pane instead. Arrow-key Ctrl+Alt defaults are left
  -- alone: no layout produces a character from them.
  { key = "'", mods = "CTRL|ALT", action = act.DisableDefaultAssignment },
  { key = "'", mods = "CTRL|ALT|SHIFT", action = act.DisableDefaultAssignment },
  { key = '"', mods = "CTRL|ALT", action = act.DisableDefaultAssignment },
  { key = '"', mods = "CTRL|ALT|SHIFT", action = act.DisableDefaultAssignment },
  { key = "%", mods = "CTRL|ALT", action = act.DisableDefaultAssignment },
  { key = "%", mods = "CTRL|ALT|SHIFT", action = act.DisableDefaultAssignment },
  { key = "5", mods = "CTRL|ALT|SHIFT", action = act.DisableDefaultAssignment },

  -- Projects and workspaces.
  { key = "f", mods = "LEADER", action = projects.picker(false) },
  { key = "F", mods = "LEADER|SHIFT", action = projects.picker(true) },
  { key = "w", mods = "LEADER", action = projects.workspace_picker() },
  { key = "Tab", mods = "LEADER", action = toggle_workspace() },
  {
    key = "n",
    mods = "LEADER",
    action = wezterm.action_callback(function(window, pane)
      projects.open_special(window, pane, "notes")
    end),
  },
  {
    key = ".",
    mods = "LEADER",
    action = wezterm.action_callback(function(window, pane)
      projects.open_special(window, pane, "scratch")
    end),
  },
  { key = "W", mods = "LEADER|SHIFT", action = rename_workspace() },
  { key = "X", mods = "LEADER|SHIFT", action = close_workspace() },

  -- Tabs: named jumps, because you never count tabs, you name the activity.
  { key = "e", mods = "LEADER", action = named_tab("edit") },
  { key = "r", mods = "LEADER", action = named_tab("run") },
  { key = "a", mods = "LEADER", action = named_tab("agent") },
  { key = "d", mods = "LEADER", action = named_tab("notes") },
  { key = "[", mods = "LEADER", action = act.ActivateTabRelative(-1) },
  { key = "]", mods = "LEADER", action = act.ActivateTabRelative(1) },
  { key = "t", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
  {
    key = ",",
    mods = "LEADER",
    action = act.PromptInputLine({
      description = "New tab title:",
      action = wezterm.action_callback(function(window, _, line)
        if line and line ~= "" then
          window:active_tab():set_title(line)
        end
      end),
    }),
  },
  { key = "Q", mods = "LEADER|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },

  -- Panes. The split keys look like the split they produce. On the Latin
  -- American layout "|" is unshifted and "\" needs AltGr, so "|" is primary
  -- and "\" is kept as an alias for US keyboards.
  { key = "|", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "|", mods = "LEADER|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "\\", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = " ", mods = "LEADER", action = act.PaneSelect({ mode = "Activate" }) },
  { key = "s", mods = "LEADER", action = act.PaneSelect({ mode = "SwapWithActive" }) },
  { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
  { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
  { key = "!", mods = "LEADER|SHIFT", action = act.PaneSelect({ mode = "MoveToNewTab" }) },
  -- "=" is Shift+0 on the Latin American layout; "+" is unshifted.
  { key = "=", mods = "LEADER", action = rebalance() },
  { key = "+", mods = "LEADER", action = rebalance() },
  { key = "+", mods = "LEADER|SHIFT", action = rebalance() },
  {
    key = "R",
    mods = "LEADER|SHIFT",
    action = act.ActivateKeyTable({ name = "resize", one_shot = false }),
  },

  -- Copy, search, yank.
  { key = "v", mods = "LEADER", action = act.ActivateCopyMode },
  { key = "/", mods = "LEADER", action = act.Search({ CaseInSensitiveString = "" }) },
  { key = "c", mods = "LEADER", action = act.QuickSelect },
  {
    key = "C",
    mods = "LEADER|SHIFT",
    action = act.QuickSelectArgs({
      label = "open",
      action = wezterm.action_callback(function(window, pane)
        local selection = window:get_selection_text_for_pane(pane)
        wezterm.open_with(selection)
      end),
    }),
  },
  { key = "y", mods = "LEADER", action = copy_last_output() },
  { key = "Y", mods = "LEADER|SHIFT", action = dump_scrollback() },
  { key = "p", mods = "LEADER", action = act.PasteFrom("Clipboard") },
  { key = "P", mods = "LEADER|SHIFT", action = act.PasteFrom("PrimarySelection") },
  { key = "{", mods = "LEADER|SHIFT", action = act.ScrollToPrompt(-1) },
  { key = "}", mods = "LEADER|SHIFT", action = act.ScrollToPrompt(1) },

  -- Meta.
  { key = "?", mods = "LEADER|SHIFT", action = cheatsheet.show() },
  { key = "r", mods = "LEADER|CTRL", action = act.ReloadConfiguration },
  { key = "l", mods = "LEADER|CTRL", action = act.ClearScrollback("ScrollbackAndViewport") },
  -- Shell chooser: the same list the startup picker offers, for when a window
  -- needs a tab on the other platform.
  { key = "Enter", mods = "LEADER", action = shells.picker() },
  {
    key = "Enter",
    mods = "LEADER|SHIFT",
    action = act.ShowLauncherArgs({ flags = "FUZZY|DOMAINS|LAUNCH_MENU_ITEMS" }),
  },
}

-- LEADER 1..9 jumps by index, a fallback for ad-hoc tabs.
for i = 1, 9 do
  table.insert(M.keys, {
    key = tostring(i),
    mods = "LEADER",
    action = act.ActivateTab(i - 1),
  })
end

-- ── Sticky modes ───────────────────────────────────────────────────────────

--- Resizing is never one keypress, so it gets a mode rather than a chord.
--- The status bar shows RESIZE in the accent color while this is active.
M.key_tables = {
  resize = {
    { key = "h", action = act.AdjustPaneSize({ "Left", settings.resize_step }) },
    { key = "j", action = act.AdjustPaneSize({ "Down", settings.resize_step }) },
    { key = "k", action = act.AdjustPaneSize({ "Up", settings.resize_step }) },
    { key = "l", action = act.AdjustPaneSize({ "Right", settings.resize_step }) },

    { key = "H", action = act.AdjustPaneSize({ "Left", settings.resize_step * 3 }) },
    { key = "J", action = act.AdjustPaneSize({ "Down", settings.resize_step * 3 }) },
    { key = "K", action = act.AdjustPaneSize({ "Up", settings.resize_step * 3 }) },
    { key = "L", action = act.AdjustPaneSize({ "Right", settings.resize_step * 3 }) },

    { key = "=", action = rebalance() },
    { key = "+", action = rebalance() },

    { key = "Escape", action = act.PopKeyTable },
    { key = "Enter", action = act.PopKeyTable },
  },
}

return M
