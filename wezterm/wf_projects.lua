--- Project discovery and the workspace layout template.
---
--- A workspace is one git repository. Opening a project is idempotent: if the
--- workspace already exists it is activated and never rebuilt, which is what
--- makes the open key safe to mash.

local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

local settings = require("wf_settings")
local util = require("wf_util")

local M = {}

-- ── Repository discovery ───────────────────────────────────────────────────

local cache_file = wezterm.home_dir .. "/.cache/wezterm-projects.json"

--- Shell pipeline that finds repositories and orders them by recency.
---
--- Recency beats alphabet for someone who touched three repos today, so the
--- results are sorted by mtime rather than name. fd is preferred; find is the
--- fallback so the picker still works on a machine without it.
local function scan_command()
  local roots = {}
  for _, root in ipairs(settings.repo_roots) do
    roots[#roots + 1] = util.shquote(util.expand(root))
  end
  local root_list = table.concat(roots, " ")

  return table.concat({
    "for r in " .. root_list .. "; do",
    '  [ -d "$r" ] || continue;',
    "  if command -v fd >/dev/null 2>&1; then",
    "    fd -H -t d -d " .. settings.scan_depth .. " '^\\.git$' \"$r\";",
    "  else",
    '    find "$r" -maxdepth ' .. settings.scan_depth .. ' -type d -name .git 2>/dev/null;',
    "  fi;",
    "done",
    "| sed 's#/\\.git/*$##'",
    "| sort -u",
    "| while IFS= read -r d; do printf '%s\\t%s\\n' \"$(stat -c %Y \"$d\" 2>/dev/null || echo 0)\" \"$d\"; done",
    "| sort -rn",
    "| cut -f2-",
  }, " ")
end

local function read_cache()
  local handle = io.open(cache_file, "r")
  if not handle then
    return nil
  end

  local raw = handle:read("*a")
  handle:close()

  local ok, parsed = pcall(wezterm.json_parse, raw)
  if ok and type(parsed) == "table" and #parsed > 0 then
    return parsed
  end
  return nil
end

local function write_cache(projects)
  -- The parent directory may not exist on a fresh machine; ignore failure,
  -- the scan simply runs again next time.
  local handle = io.open(cache_file, "w")
  if not handle then
    return
  end

  handle:write(wezterm.json_encode(projects))
  handle:close()
end

--- All discovered projects, most recently modified first.
---
--- @param force boolean|nil Rescan instead of using the cached result.
--- @return table List of { path, client, repo } entries.
function M.scan(force)
  if not force then
    local cached = read_cache()
    if cached then
      return cached
    end
  end

  local ok, stdout = util.exec(scan_command())
  if not ok then
    return {}
  end

  local projects = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local path = util.chomp(line)
    if path ~= "" then
      local client, repo = util.project_of(path)
      projects[#projects + 1] = { path = path, client = client, repo = repo }
    end
  end

  write_cache(projects)
  return projects
end

--- Looks up a scanned project by its workspace name.
function M.by_workspace(name)
  for _, project in ipairs(M.scan(false)) do
    if project.repo == name then
      return project
    end
  end
  return nil
end

local function workspace_exists(name)
  for _, existing in ipairs(mux.get_workspace_names()) do
    if existing == name then
      return true
    end
  end
  return false
end

-- ── Layout template ────────────────────────────────────────────────────────

--- Shell command that opens a project's note file, creating it from a small
--- template on first use.
local function notes_command(project)
  local dir = util.expand(settings.notes_root) .. "/" .. project.client
  local file = dir .. "/" .. project.repo .. ".md"
  local quoted_file = util.shquote(file)

  return table.concat({
    "mkdir -p " .. util.shquote(dir),
    "[ -s " .. quoted_file .. " ] || printf '# %s\\n\\n_opened %s_\\n\\n' "
      .. util.shquote(project.client .. "/" .. project.repo)
      .. ' "$(date +%F)" > '
      .. quoted_file,
    settings.editor .. " " .. quoted_file,
  }, "; ")
end

--- Builders for each tab in the template, keyed by tab title.
---
--- Each receives the mux window and the project, and returns the created tab.
--- Commands go in the pane's argv rather than being typed in with send_text,
--- which races the shell's startup; util.shell_args keeps a shell alive after
--- the command exits, so quitting the editor does not close the pane.
M.tabs = {
  edit = function(mux_window, project)
    local tab = mux_window:spawn_tab({
      cwd = project.path,
      args = util.shell_args(settings.editor),
    })
    tab:set_title("edit")
    return tab
  end,

  run = function(mux_window, project)
    local tab, pane = mux_window:spawn_tab({ cwd = project.path })
    tab:set_title("run")
    -- Long-running output below, interactive shell above. `size` is the
    -- fraction handed to the new pane, so it is the remainder of primary.
    local split = settings.template_splits.run
    pane:split({ direction = split.direction, size = 1 - split.primary, cwd = project.path })
    return tab
  end,

  agent = function(mux_window, project)
    local split = settings.template_splits.agent
    local tab, pane = mux_window:spawn_tab({
      cwd = project.path,
      args = util.shell_args(settings.agent_cmd),
    })
    tab:set_title("agent")
    pane:split({ direction = split.direction, size = 1 - split.primary, cwd = project.path })
    return tab
  end,

  notes = function(mux_window, project)
    local tab = mux_window:spawn_tab({
      cwd = project.path,
      args = util.shell_args(notes_command(project)),
    })
    tab:set_title("notes")
    return tab
  end,
}

--- Tab order used when building a workspace from scratch.
M.tab_order = { "edit", "run", "agent", "notes" }

--- Creates the full workspace for a project. Callers must ensure the
--- workspace does not already exist.
local function build(project)
  local _, first_pane, mux_window = mux.spawn_window({
    workspace = project.repo,
    cwd = project.path,
    args = util.shell_args(settings.editor),
  })

  local edit_tab = first_pane:tab()
  edit_tab:set_title("edit")

  for _, name in ipairs(M.tab_order) do
    if name ~= "edit" then
      M.tabs[name](mux_window, project)
    end
  end

  edit_tab:activate()
end

--- Opens a project: activates its workspace, creating it only if needed.
function M.open(window, pane, project)
  if not workspace_exists(project.repo) then
    build(project)
  end
  window:perform_action(act.SwitchToWorkspace({ name = project.repo }), pane)
end

-- ── Special workspaces ─────────────────────────────────────────────────────

--- Switches to a workspace that holds scratch shells or the global notes
--- vault, creating it on first use.
---
--- @param kind string Either "notes" or "scratch".
function M.open_special(window, pane, kind)
  local name = kind == "notes" and settings.notes_workspace or settings.scratch_workspace

  if not workspace_exists(name) then
    local cwd = kind == "notes" and util.expand(settings.notes_root) or util.home()
    local notes_cmd = "mkdir -p " .. util.shquote(cwd) .. "; "
      .. settings.editor .. " " .. util.shquote(cwd)

    local _, first_pane, mux_window = mux.spawn_window({
      workspace = name,
      cwd = cwd,
      args = kind == "notes" and util.shell_args(notes_cmd) or util.shell_args(nil),
    })

    if kind == "notes" then
      first_pane:tab():set_title("notes")
      local shell_tab = mux_window:spawn_tab({ cwd = cwd })
      shell_tab:set_title("shell")
    else
      first_pane:tab():set_title("shell")
    end
  end

  window:perform_action(act.SwitchToWorkspace({ name = name }), pane)
end

-- ── Named tabs ─────────────────────────────────────────────────────────────

--- Activates a template tab by name, recreating it from the template when it
--- is missing. Closing a tab therefore degrades to a rebuild rather than an
--- error, which keeps the named jumps meaningful for the life of a workspace.
function M.activate_named_tab(window, name)
  local mux_window = window:mux_window()

  for _, tab in ipairs(mux_window:tabs()) do
    if tab:get_title() == name then
      tab:activate()
      return
    end
  end

  local builder = M.tabs[name]
  local project = M.by_workspace(mux_window:get_workspace())
  if not builder or not project then
    window:toast_notification("wezterm", "No template tab '" .. name .. "' here", nil, 2000)
    return
  end

  builder(mux_window, project):activate()
end

-- ── Pickers ────────────────────────────────────────────────────────────────

--- Fuzzy picker over every known repository. Workspaces that are already open
--- are marked, so this is a single entry point whether or not the project is
--- running.
---
--- @param force boolean|nil Rescan the repository roots first.
function M.picker(force)
  return wezterm.action_callback(function(window, pane)
    local open = {}
    for _, name in ipairs(mux.get_workspace_names()) do
      open[name] = true
    end

    local choices = {}
    for _, project in ipairs(M.scan(force)) do
      choices[#choices + 1] = {
        id = project.path,
        label = (open[project.repo] and "● " or "  ") .. project.client .. "/" .. project.repo,
      }
    end

    if #choices == 0 then
      window:toast_notification("wezterm", "No repositories found. Check wf_settings.repo_roots.", nil, 4000)
      return
    end

    window:perform_action(
      act.InputSelector({
        title = "Projects",
        fuzzy = true,
        fuzzy_description = "project> ",
        choices = choices,
        action = wezterm.action_callback(function(inner_window, inner_pane, id)
          if not id then
            return
          end
          local client, repo = util.project_of(id)
          M.open(inner_window, inner_pane, { path = id, client = client, repo = repo })
        end),
      }),
      pane
    )
  end)
end

--- Picker restricted to workspaces that are already open: a short list for the
--- common case of bouncing between today's projects.
function M.workspace_picker()
  return wezterm.action_callback(function(window, pane)
    local choices = {}
    for _, name in ipairs(mux.get_workspace_names()) do
      choices[#choices + 1] = { id = name, label = name }
    end
    table.sort(choices, function(a, b)
      return a.label < b.label
    end)

    window:perform_action(
      act.InputSelector({
        title = "Open workspaces",
        fuzzy = true,
        fuzzy_description = "workspace> ",
        choices = choices,
        action = wezterm.action_callback(function(inner_window, inner_pane, id)
          if id then
            inner_window:perform_action(act.SwitchToWorkspace({ name = id }), inner_pane)
          end
        end),
      }),
      pane
    )
  end)
end

return M
