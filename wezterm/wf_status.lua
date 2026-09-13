--- Status bar, tab titles and the client-safety visual layer.
---
--- The most expensive mistake available when several clients share a day is
--- "right command, wrong client", so the client identity is always on screen
--- as a coloured badge at the top left, drawn from a palette that belongs to
--- the active theme. Recolouring the whole bar is reserved for production:
--- an alarm that fires constantly is not an alarm.

local wezterm = require("wezterm")

local settings = require("wf_settings")
local theme = require("wf_theme")
local util = require("wf_util")

local M = {}

-- ── Last-workspace tracking ────────────────────────────────────────────────
--
-- WezTerm has no "previous workspace" concept, so it is observed here: the
-- status hook runs on every workspace change, which is enough to maintain the
-- pair without polling. Stored in GLOBAL so it survives config reloads.

wezterm.GLOBAL.wf_current_workspace = wezterm.GLOBAL.wf_current_workspace or ""
wezterm.GLOBAL.wf_previous_workspace = wezterm.GLOBAL.wf_previous_workspace or ""

local function track_workspace(name)
  if name ~= wezterm.GLOBAL.wf_current_workspace then
    wezterm.GLOBAL.wf_previous_workspace = wezterm.GLOBAL.wf_current_workspace
    wezterm.GLOBAL.wf_current_workspace = name
  end
end

--- The workspace visited before the current one, or "" when there is none.
function M.previous_workspace()
  return wezterm.GLOBAL.wf_previous_workspace
end

-- ── Context derivation ─────────────────────────────────────────────────────

--- The working directory of a pane as a plain string, tolerating both the URL
--- object returned by current WezTerm versions and the older string form.
local function pane_cwd(pane)
  local ok, cwd = pcall(function()
    return pane:get_current_working_dir()
  end)
  if not ok or not cwd then
    return nil
  end

  if type(cwd) == "string" then
    return cwd
  end
  return cwd.file_path
end

--- Client name and production status for a workspace.
local function context_for(window, pane)
  local workspace = window:active_workspace()
  local client, prod

  if workspace == settings.notes_workspace or workspace == settings.scratch_workspace then
    client = workspace
  else
    local projects = require("wf_projects")
    local project = projects.by_workspace(workspace)
    client = project and project.client or workspace
  end

  local cwd = pane and pane_cwd(pane)
  prod = util.is_prod(cwd) or util.is_prod(workspace)

  return workspace, client, prod
end

-- ── Accent application ─────────────────────────────────────────────────────
--
-- set_config_overrides replaces whole top-level config keys, so the accent is
-- applied to a full copy of the active palette rather than a bare tab_bar
-- table, which would otherwise discard the theme's colors.

local applied = {}

--- Repaints the window frame.
---
--- Only production repaints the whole bar. Ordinary client colouring lives in
--- the badge on the left, because a saturated bar behind every workspace is
--- both ugly and useless as a warning: if everything is coloured, nothing is.
local function apply_frame(window, prod, accent)
  local window_key = tostring(window:window_id())
  local want = prod and accent or "theme"
  if applied[window_key] == want then
    return
  end
  applied[window_key] = want

  local colors = util.deep_copy(theme.colors)
  colors.tab_bar = colors.tab_bar or {}

  if prod then
    colors.tab_bar.background = accent
    colors.tab_bar.inactive_tab = colors.tab_bar.inactive_tab or {}
    colors.tab_bar.inactive_tab.bg_color = accent
    colors.tab_bar.inactive_tab.fg_color = util.ink_for(accent)
  end

  window:set_config_overrides({
    colors = colors,
    window_frame = {
      active_titlebar_bg = colors.tab_bar.background,
      inactive_titlebar_bg = colors.tab_bar.background,
    },
  })
end

-- ── Status bar ─────────────────────────────────────────────────────────────

--- Git state published by the shell integration as a user var, so the status
--- bar costs nothing to render. Without shell integration it is simply absent.
local function git_status(pane)
  if not pane then
    return nil
  end

  local ok, vars = pcall(function()
    return pane:get_user_vars()
  end)
  if not ok or not vars then
    return nil
  end

  local git = vars.WF_GIT
  if git and git ~= "" then
    return git
  end
  return nil
end

wezterm.on("update-status", function(window, pane)
  local workspace, client, prod = context_for(window, pane)
  track_workspace(workspace)

  local accent = prod
      and (theme.is_dark and settings.prod_color_dark or settings.prod_color_light)
    or util.client_color(client)
  local ink = util.ink_for(accent)

  apply_frame(window, prod, accent)

  -- Left: one small swatch carrying the client identity. "client ▸ repo"
  -- collapses to just the name when the workspace is not a project, rather
  -- than repeating itself.
  local label = client == workspace and workspace or (client .. " ▸ " .. workspace)
  if prod then
    label = "⚠ PROD · " .. label
  end

  window:set_left_status(wezterm.format({
    { Background = { Color = accent } },
    { Foreground = { Color = ink } },
    { Attribute = { Intensity = "Bold" } },
    { Text = " " .. label .. " " },
    { Background = { Color = theme.bar_bg } },
    { Foreground = { Color = theme.muted } },
    { Attribute = { Intensity = "Normal" } },
    { Text = " " },
  }))

  -- Right: secondary information, on the bar's own background so it stays
  -- readable. Kept short on purpose.
  local right = { { Background = { Color = theme.bar_bg } } }

  local function segment(color, text, bold)
    right[#right + 1] = { Background = { Color = theme.bar_bg } }
    right[#right + 1] = { Foreground = { Color = color } }
    right[#right + 1] = { Attribute = { Intensity = bold and "Bold" or "Normal" } }
    right[#right + 1] = { Text = text }
  end

  -- Modal state is a badge rather than coloured text: an accent legible as a
  -- swatch can still be too faint as a glyph on the bar, and an indicator you
  -- have to hunt for is the same as no indicator.
  local function badge(text)
    right[#right + 1] = { Background = { Color = accent } }
    right[#right + 1] = { Foreground = { Color = ink } }
    right[#right + 1] = { Attribute = { Intensity = "Bold" } }
    right[#right + 1] = { Text = text }
    right[#right + 1] = { Background = { Color = theme.bar_bg } }
  end

  if window:leader_is_active() then
    segment(theme.muted, " ")
    badge(" ◆ ")
  end

  local active_table = window:active_key_table()
  if active_table then
    segment(theme.muted, " ")
    badge(" " .. active_table:upper() .. " ")
  end

  local git = git_status(pane)
  if git then
    segment(theme.muted, "  " .. git)
  end

  segment(theme.bar_fg, "  " .. wezterm.strftime("%H:%M") .. "  ")

  window:set_right_status(wezterm.format(right))
end)

-- ── Tab titles ─────────────────────────────────────────────────────────────

--- Tab titles are returned as plain text so WezTerm paints them with the
--- theme's own active/inactive tab colours. Formatting them by hand is what
--- made the bar fight the colour scheme.
wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
  local title = tab.tab_title
  if not title or title == "" then
    title = tab.active_pane.title
  end

  local label = " " .. (tab.tab_index + 1) .. "  " .. title .. " "
  if #label > max_width then
    label = label:sub(1, math.max(1, max_width - 2)) .. "… "
  end
  return label
end)

return M
