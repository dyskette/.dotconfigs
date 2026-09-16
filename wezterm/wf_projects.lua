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

--- Bumped whenever the cache's shape changes. A file written by an older
--- config is discarded rather than half-understood: v2 held one flat list for
--- every environment at once, and reading it as this version's per-environment
--- map would offer Windows repositories to a WSL pane.
local cache_version = 3

--- The roots to scan in one environment.
---
--- The Windows roots are a separate list because they are separate places:
--- ~/Projects on a drive has nothing to do with ~/Projects in a distribution,
--- and scanning either list in the wrong environment would find nothing at
--- best and the wrong repositories at worst.
local function repo_roots_for(distro)
  if util.is_windows and not distro then
    return settings.repo_roots_windows
  end
  return settings.repo_roots
end

--- Command that finds repositories in one environment.
---
--- Deliberately free of shell variables, and not because that reads nicer.
--- `wsl.exe -d X -- bash -lc <script>` does not deliver a script intact: a
--- variable the script assigns and then expands comes back EMPTY, while ones
--- already in the environment like $HOME survive. A `for r in ...; do ... $r`
--- loop therefore searched nothing at all, silently, in every distribution —
--- the Windows side went through Git Bash and was unaffected, which is what
--- made it look like a Windows feature working and WSL being empty.
---
--- So find does the whole job on its own: it takes the roots as literal
--- arguments, and -printf reports each repository and its mtime directly, with
--- no loop, no sed and no stat to need a variable. Single-quoted roots do
--- survive the trip, so paths are still quoted.
---
--- Each line is "WF=<mtime>\t<path>". The sentinel is there because a login
--- shell whose rc files write to stdout prepends that noise to the first line;
--- matching on the sentinel rather than the start of the line keeps that
--- line's repository instead of dropping it.
---
--- Errors are discarded and the output goes through `sort -u`, so the exit
--- status is sort's rather than find's: a root that does not exist then costs
--- nothing, instead of reading as "this whole environment is unavailable".
---
--- @param distro string|nil Environment whose roots to scan and whose home
---   they expand against.
local function scan_command(distro)
  local roots = {}
  for _, root in ipairs(repo_roots_for(distro)) do
    roots[#roots + 1] = util.shquote(util.expand(root, distro))
  end

  return "find "
    .. table.concat(roots, " ")
    .. " -maxdepth "
    .. settings.scan_depth
    .. ' -type d -name .git -printf "WF=%T@\\t%h\\n" 2>/dev/null | sort -u'
end

--- Scan results, keyed by distribution name — "" for the native environment.
---
--- Kept per environment rather than as one list because that is how they are
--- used: a pane belongs to exactly one environment and is only ever offered
--- that environment's repositories. It also means a rescan in a PowerShell
--- pane does not start a stopped distribution's VM to refresh a list that
--- pane will never be shown.
---
--- Held in memory as well as on disk, so a lookup costs neither a file read
--- nor a round trip into a distribution.
local cache

local function cache_key(distro)
  return distro or ""
end

--- Loads the cache on first use and returns the per-environment map.
local function load_cache()
  if cache then
    return cache
  end
  cache = {}

  local handle = io.open(cache_file, "r")
  if not handle then
    return cache
  end

  local raw = handle:read("*a")
  handle:close()

  local ok, parsed = pcall(wezterm.json_parse, raw)
  if ok and type(parsed) == "table" and parsed.version == cache_version and type(parsed.envs) == "table" then
    cache = parsed.envs
  end
  return cache
end

local function save_cache()
  -- The parent directory may not exist on a fresh machine; ignore failure,
  -- the scan simply runs again next time.
  local handle = io.open(cache_file, "w")
  if not handle then
    return
  end

  handle:write(wezterm.json_encode({ version = cache_version, envs = cache }))
  handle:close()
end

--- Repositories in one work environment, most recently modified first.
---
--- Only the named environment is touched. One that fails to answer — not
--- installed, not running, removed since it was configured — keeps whatever
--- was last known about it, rather than caching an empty list and then looking
--- permanently empty until someone thinks to force a rescan.
---
--- @param distro string|nil Environment to scan; nil is the native one.
--- @param force boolean|nil Rescan instead of using the cached result.
--- @return table List of { path, client, repo, distro } entries.
function M.scan(distro, force)
  -- An environment with no roots has nothing to look in. Without this, find
  -- would be handed no path at all and would fall back to searching the
  -- working directory of the WezTerm process.
  if #repo_roots_for(distro) == 0 then
    return {}
  end

  local envs = load_cache()
  local key = cache_key(distro)

  if not force and envs[key] then
    return envs[key]
  end

  local ok, stdout = util.exec(scan_command(distro), distro)
  if not ok then
    return envs[key] or {}
  end

  local found = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local mtime, path = line:match("WF=(%d+)[^\t]*\t(.+)$")
    if path then
      local client, repo = util.project_of(path)
      found[#found + 1] = {
        mtime = tonumber(mtime) or 0,
        path = path,
        client = client,
        repo = repo,
        distro = distro,
      }
    end
  end

  -- Path breaks ties so the order is stable across scans: Lua's sort is not
  -- stable, and repositories that never got an mtime all share 0.
  table.sort(found, function(a, b)
    if a.mtime == b.mtime then
      return a.path < b.path
    end
    return a.mtime > b.mtime
  end)

  -- The mtime has done its job once the order is fixed, and keeping it would
  -- put a timestamp in the cache that nothing reads and age would invalidate.
  for _, project in ipairs(found) do
    project.mtime = nil
  end

  envs[key] = found
  save_cache()
  return found
end

--- The workspace a project opens in.
---
--- Repositories in the default distribution keep the bare repo name, so the
--- everyday case reads and types exactly as it did before there was a second
--- distro. A secondary distro is tagged, because the same repo cloned into two
--- distributions is two projects and must not collapse into one workspace.
---
--- Windows projects are deliberately bare as well: they are a different kind
--- of repository rather than a second copy of the same one, and tagging them
--- would put a suffix on names that never had a twin. The cost is that a repo
--- of the same name on the Windows side and in the default distro shares one
--- workspace, and whichever is opened first wins.
---
--- @param project table A scanned project.
--- @return string
function M.workspace_name(project)
  local entry = util.distro_entry(project.distro)
  if not entry or entry.default or not entry.short then
    return project.repo
  end
  return project.repo .. "@" .. entry.short
end

--- Looks up an open workspace's project among everything already scanned.
---
--- Deliberately does not scan: this runs from the status bar on every redraw,
--- and starting a distribution in order to paint a tab bar would be absurd.
--- Anything open was picked from a list, so its environment is already cached.
function M.by_workspace(name)
  for _, projects in pairs(load_cache()) do
    for _, project in ipairs(projects) do
      if M.workspace_name(project) == name then
        return project
      end
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

--- Spawn options placing a pane in a project's directory and environment.
---
--- The domain is named rather than left to WezTerm: a tab spawned without one
--- lands in the window's current domain, which is the right answer only while
--- every project lives in the same place. The command is turned into argv here
--- too, because which shell interprets it is a property of the environment —
--- bash in a distribution, PowerShell on the Windows side.
---
--- @param project table A scanned project.
--- @param cmd string|nil Command to run in the pane; omitted for a plain
---   shell, which lets the domain's own default program start.
local function project_opts(project, cmd)
  local opts = {
    cwd = project.path,
    domain = { DomainName = util.domain_for(project.distro) },
  }

  if cmd then
    opts.args = util.shell_args(cmd, project.distro, project.path)
  end

  return opts
end

--- Spawn options for dividing a project pane.
---
--- The domain is named here too, rather than left to `pane:split`'s default of
--- "CurrentPaneDomain". That name is misleading: it resolves against the
--- window's *active* pane, not the pane the method was called on, and while a
--- workspace is being built the active pane is still whichever one the picker
--- was invoked from. So a Windows project got its splits from the default WSL
--- domain -- bash in the bottom of `run` and the right of `agent`, while every
--- unsplit pane in the same workspace was correctly PowerShell.
---
--- @param project table A scanned project.
--- @param split table An entry from settings.template_splits.
local function split_opts(project, split)
  local opts = project_opts(project)

  opts.direction = split.direction
  -- `size` is the fraction handed to the new pane, so it is the remainder of
  -- what the primary one keeps.
  opts.size = 1 - split.primary

  return opts
end

--- Command that opens a project's note file, creating it from a small
--- template on first use.
---
--- The notes root is expanded in the project's own environment: the tab runs
--- there, and two distros need not agree on $HOME, let alone agree with the
--- Windows profile directory.
---
--- There are two spellings because there are two interpreters. The PowerShell
--- one avoids double quotes and backticks entirely — it crosses into the pane
--- as a single argv element, and Windows argument encoding is the wrong place
--- to find out which of those survive — so the template is an array of
--- single-quoted lines that Set-Content writes one per line.
local function notes_command(project)
  local dir = util.expand(settings.notes_root, project.distro) .. "/" .. project.client
  local file = dir .. "/" .. project.repo .. ".md"
  local heading = "# " .. project.client .. "/" .. project.repo

  if util.is_windows and not project.distro then
    local quoted_file = util.psquote(file)

    return table.concat({
      "New-Item -ItemType Directory -Force -Path " .. util.psquote(dir) .. " > $null",
      "if (-not (Test-Path " .. quoted_file .. ")) { Set-Content -Path " .. quoted_file .. " -Value ("
        .. util.psquote(heading)
        .. ", '', ('_opened ' + (Get-Date -Format 'yyyy-MM-dd') + '_'), '') }",
      settings.editor .. " " .. quoted_file,
    }, "; ")
  end

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
--- Splits are given their domain explicitly by split_opts; nothing here may
--- rely on a new pane inheriting one.
M.tabs = {
  edit = function(mux_window, project)
    local tab = mux_window:spawn_tab(project_opts(project, settings.editor))
    tab:set_title("edit")
    return tab
  end,

  run = function(mux_window, project)
    local tab, pane = mux_window:spawn_tab(project_opts(project))
    tab:set_title("run")
    -- Long-running output below, interactive shell above.
    pane:split(split_opts(project, settings.template_splits.run))
    return tab
  end,

  agent = function(mux_window, project)
    local tab, pane = mux_window:spawn_tab(project_opts(project, settings.agent_cmd))
    tab:set_title("agent")
    pane:split(split_opts(project, settings.template_splits.agent))
    return tab
  end,

  notes = function(mux_window, project)
    local tab = mux_window:spawn_tab(project_opts(project, notes_command(project)))
    tab:set_title("notes")
    return tab
  end,
}

--- Tab order used when building a workspace from scratch.
M.tab_order = { "edit", "run", "agent", "notes" }

--- Creates the full workspace for a project. Callers must ensure the
--- workspace does not already exist.
local function build(project, workspace)
  local opts = project_opts(project, settings.editor)
  opts.workspace = workspace

  local _, first_pane, mux_window = mux.spawn_window(opts)

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
  local workspace = M.workspace_name(project)

  if not workspace_exists(workspace) then
    build(project, workspace)
  end
  window:perform_action(act.SwitchToWorkspace({ name = workspace }), pane)
end

-- ── Special workspaces ─────────────────────────────────────────────────────

--- Switches to a workspace that holds scratch shells or the global notes
--- vault, creating it on first use.
---
--- These belong to the default environment and say so: they spawn without a
--- domain, which is config.default_domain, so every path and command here has
--- to be built for that same environment rather than for the native one.
---
--- @param kind string Either "notes" or "scratch".
function M.open_special(window, pane, kind)
  local name = kind == "notes" and settings.notes_workspace or settings.scratch_workspace
  local distro = util.default_distro().distro

  if not workspace_exists(name) then
    local cwd = kind == "notes" and util.expand(settings.notes_root, distro) or util.home(distro)
    -- The cd follows the mkdir rather than being handed to shell_args, because
    -- on first use the directory does not exist yet and cd would fail before
    -- mkdir ever ran.
    local quoted = util.shquote(cwd)
    local notes_cmd = "mkdir -p " .. quoted .. "; cd " .. quoted .. " && "
      .. settings.editor .. " " .. quoted

    local _, first_pane, mux_window = mux.spawn_window({
      workspace = name,
      cwd = cwd,
      args = kind == "notes" and util.shell_args(notes_cmd, distro) or util.shell_args(nil, distro),
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

--- Fuzzy picker over the repositories of the pane's own work environment.
---
--- Scoped to one environment on purpose. A pane is in exactly one domain, and
--- everything a project opens — its editor, its toolchain, its notes — belongs
--- to that domain; offering a Windows repository to a WSL pane invites opening
--- something that cannot run there. So the list a pane sees is the list it can
--- actually use, and the title says which environment that is.
---
--- Workspaces already open are marked, so this is a single entry point whether
--- or not the project is running.
---
--- @param force boolean|nil Rescan this environment's roots first.
function M.picker(force)
  return wezterm.action_callback(function(window, pane)
    local domain = util.domain_of(pane)
    local env = util.env_of_domain(domain)

    -- An SSH or mux domain has no roots of its own, and falling back to some
    -- other environment's list would be exactly the mixing this avoids.
    if not env then
      window:toast_notification("wezterm", "No project roots for domain '" .. domain .. "'", nil, 4000)
      return
    end

    local label = util.env_label(env)

    local open = {}
    for _, name in ipairs(mux.get_workspace_names()) do
      open[name] = true
    end

    -- The id is an index rather than the path, because a project is a path
    -- *and* an environment: two distros can hold the same path, and rebuilding
    -- the entry from the id alone would pick whichever came first.
    local projects = M.scan(env.distro, force)

    local choices = {}
    for index, project in ipairs(projects) do
      local workspace = M.workspace_name(project)
      choices[#choices + 1] = {
        id = tostring(index),
        label = (open[workspace] and "● " or "  ") .. project.client .. "/" .. workspace,
      }
    end

    if #choices == 0 then
      local setting = env.distro and "repo_roots" or "repo_roots_windows"
      window:toast_notification("wezterm", "No repositories in " .. label .. ". Check wf_settings." .. setting .. ".", nil, 4000)
      return
    end

    window:perform_action(
      act.InputSelector({
        title = "Projects · " .. label,
        fuzzy = true,
        fuzzy_description = label .. " project> ",
        choices = choices,
        action = wezterm.action_callback(function(inner_window, inner_pane, id)
          if not id then
            return
          end
          M.open(inner_window, inner_pane, projects[tonumber(id)])
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
