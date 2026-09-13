--- Shell and domain selection.
---
--- The project system assumes one work environment, but consulting does not:
--- some clients are entirely Windows, others are mixed and reached through
--- WSL. This module makes that choice explicit at the moment a window opens,
--- and repeatable afterwards with LEADER Enter.
---
--- Once a shell is chosen, tabs and splits made from that pane inherit its
--- domain (the keymap spawns them with CurrentPaneDomain), so a window stays
--- on one platform unless you ask otherwise.

local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local settings = require("wf_settings")
local util = require("wf_util")

local M = {}

--- Shells available on this platform.
function M.list()
  return util.is_windows and settings.shells_windows or settings.shells_unix
end

--- Names of the domains WezTerm actually has, for diagnostics. Only callable
--- once the mux exists, which is why nothing here runs at config-eval time.
local function domain_names()
  local ok, domains = pcall(function()
    return mux.all_domains()
  end)
  if not ok or not domains then
    return {}
  end

  local names = {}
  for _, domain in ipairs(domains) do
    names[#names + 1] = domain:name()
  end
  return names
end

local function has_domain(name)
  for _, existing in ipairs(domain_names()) do
    if existing == name then
      return true
    end
  end
  return false
end

--- Spawn options for a shell entry, suitable for spawn_tab or spawn_window.
function M.spawn_opts(shell, cwd)
  local opts = {}

  if shell.domain then
    opts.domain = { DomainName = shell.domain }
  end
  if shell.args then
    opts.args = shell.args
  end
  if cwd then
    opts.cwd = cwd
  end

  return opts
end

--- Opens a shell in a new tab.
---
--- @param window GuiWindow
--- @param pane Pane The pane the picker was invoked from.
--- @param shell table An entry from M.list().
--- @param opts table|nil `replace_pane = true` closes `pane` afterwards, used
---   by the startup picker so choosing a shell does not leave a spare tab.
function M.spawn(window, pane, shell, opts)
  opts = opts or {}

  -- Choosing the shell the window already runs is a no-op rather than a
  -- second identical tab.
  if opts.replace_pane and shell.default then
    return
  end

  if shell.domain and not has_domain(shell.domain) then
    local available = table.concat(domain_names(), ", ")
    window:toast_notification(
      "wezterm",
      "Unknown domain '" .. shell.domain .. "'. Available: " .. available,
      nil,
      6000
    )
    return
  end

  local mux_window = window:mux_window()

  -- Captured before spawning, because spawn_tab moves the active tab.
  local previous_tab = mux_window:active_tab()

  local ok, err = pcall(function()
    local tab = mux_window:spawn_tab(M.spawn_opts(shell))
    tab:set_title(shell.short or shell.label)
  end)

  if not ok then
    wezterm.log_error("wf_shells: spawning " .. shell.label .. " failed: " .. tostring(err))
    window:toast_notification("wezterm", "Could not start " .. shell.label .. ": " .. tostring(err), nil, 6000)
    return
  end

  if opts.replace_pane then
    -- CloseCurrentPane closes whatever is active when it runs and ignores the
    -- pane handed to perform_action, so the placeholder has to be made active
    -- first. Without this it closes the shell that was just spawned, leaving
    -- the placeholder behind and making every choice look like a no-op.
    previous_tab:activate()
    window:perform_action(act.CloseCurrentPane({ confirm = false }), pane)
  end
end

--- Fuzzy picker over the platform's shells.
---
--- @param opts table|nil Forwarded to M.spawn.
function M.picker(opts)
  return wezterm.action_callback(function(window, pane)
    local shells = M.list()

    local choices = {}
    for index, shell in ipairs(shells) do
      choices[#choices + 1] = {
        id = tostring(index),
        label = (shell.default and "● " or "  ") .. shell.label,
      }
    end

    window:perform_action(
      act.InputSelector({
        title = "Shell",
        fuzzy = true,
        fuzzy_description = "shell> ",
        choices = choices,
        action = wezterm.action_callback(function(inner_window, inner_pane, id)
          -- Escape returns no id, which keeps whatever is already running.
          if not id then
            return
          end
          M.spawn(inner_window, inner_pane, shells[tonumber(id)], opts)
        end),
      }),
      pane
    )
  end)
end

--- Entries for WezTerm's own launcher, so the new-tab button and the command
--- palette offer the same list.
function M.launch_menu()
  local menu = {}
  for _, shell in ipairs(M.list()) do
    local entry = M.spawn_opts(shell)
    entry.label = shell.label
    menu[#menu + 1] = entry
  end
  return menu
end

--- Opens the initial window and offers the shell choice over it.
---
--- The window has to exist before a selector can be drawn on it, so the
--- default shell starts first and is replaced only if a different one is
--- picked. The small delay is because the GUI window is not attached to the
--- mux window at the instant gui-startup fires.
wezterm.on("gui-startup", function(cmd)
  local _, pane, window = mux.spawn_window(cmd or {})

  -- `wezterm start -- some-program` already says what to run; do not ask.
  if cmd or not settings.startup_shell_picker then
    return
  end

  wezterm.time.call_after(0.3, function()
    local gui_window = window:gui_window()
    if gui_window then
      gui_window:perform_action(M.picker({ replace_pane = true }), pane)
    end
  end)
end)

return M
