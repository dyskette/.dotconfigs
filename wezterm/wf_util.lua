--- Shared helpers: platform differences, shell execution, path and color math.

local wezterm = require("wezterm")
local settings = require("wf_settings")

local M = {}

--- True when the config is being evaluated by a WezTerm running on Windows,
--- where work is split between the drive and one or more WSL distributions
--- and reaching a distribution means crossing through wsl.exe.
M.is_windows = wezterm.target_triple:find("windows") ~= nil

-- ── Work environments ──────────────────────────────────────────────────────
--
-- A "work environment" is somewhere repositories live and panes can run. On
-- Windows that is each WSL distribution plus the Windows drive itself;
-- everywhere else there is exactly one. The helpers below express that as a
-- list either way, so callers iterate rather than branch on platform, and
-- `distro = nil` consistently means "this platform's native environment" —
-- the Windows side on Windows, the machine itself anywhere else.

--- True when a distribution has claimed the default role. Off Windows there
--- are no distributions to claim it.
local function wsl_claims_default()
  if not M.is_windows then
    return false
  end
  for _, entry in ipairs(settings.wsl_distros) do
    if entry.default then
      return true
    end
  end
  return false
end

--- The native environment: the Windows side on Windows, the machine itself
--- anywhere else.
---
--- It holds the default role unless a distribution takes it, which is the one
--- switch that decides where a new window opens. Off Windows nothing can take
--- it. On Windows, marking a wsl_distros entry `default` moves new windows,
--- the notes and scratch workspaces, and the unqualified workspace names into
--- that distribution; leaving every entry unmarked keeps them here, in
--- PowerShell.
local native_env = { default = not wsl_claims_default(), short = settings.windows_short }

--- Every work environment, as configured entries.
---
--- The native entry is always present on Windows, even with no Windows
--- repository roots configured: it is somewhere shells run, not only somewhere
--- repositories live, and dropping it would take PowerShell out of the
--- environment picker on a machine that keeps all its code in WSL.
function M.distros()
  if not M.is_windows then
    return { native_env }
  end

  local list = {}
  for _, entry in ipairs(settings.wsl_distros) do
    list[#list + 1] = entry
  end
  list[#list + 1] = native_env
  return list
end

--- The environment new windows and the notes workspace belong to: the entry
--- marked `default`, or the first one if none is.
function M.default_distro()
  local list = M.distros()
  for _, entry in ipairs(list) do
    if entry.default then
      return entry
    end
  end
  -- distros() always yields at least the native environment, so this is a
  -- guard against a wsl_distros list with no entry marked default rather than
  -- against an empty list.
  return list[1] or native_env
end

--- The configured entry for a distribution name, or nil when it is not one of
--- ours — a cached project whose distro has since left wsl_distros.
function M.distro_entry(distro)
  for _, entry in ipairs(M.distros()) do
    if entry.distro == distro then
      return entry
    end
  end
  return nil
end

--- The WezTerm domain hosting a distribution. Written once here because
--- wezterm.lua registers the domains under these names and everything else
--- resolves them by name; the two must not drift.
function M.wsl_domain_name(distro)
  return "WSL:" .. distro
end

--- The WezTerm domain a work environment's panes belong to. The native
--- environment is WezTerm's built-in "local" domain on every platform.
---
--- Always a name, never nil: this is both what panes are spawned into and what
--- a pane's own domain is matched against to decide which environment it is
--- in, and a nil on either side of that comparison would quietly match the
--- wrong thing.
function M.domain_for(distro)
  if distro then
    return M.wsl_domain_name(distro)
  end
  return "local"
end

--- The work environment a domain belongs to, or nil when the domain is not
--- one of ours — an SSH or mux domain has no repository roots and no business
--- being offered a project list built for somewhere else.
function M.env_of_domain(domain)
  for _, entry in ipairs(M.distros()) do
    if M.domain_for(entry.distro) == domain then
      return entry
    end
  end
  return nil
end

--- Short human name for a work environment, for picker titles.
function M.env_label(entry)
  if entry.distro then
    return entry.short or entry.distro
  end
  return M.is_windows and "windows" or "local"
end

--- Full name for a work environment, for menu entries. env_label is the short
--- form, for titles and tags where the context is already established.
function M.env_title(entry)
  if entry.distro then
    return "WSL · " .. entry.distro
  end
  return M.is_windows and "Windows" or "Local"
end

--- Runs a shell command inside a work environment and captures its output.
---
--- On Windows the config runs as a native process while most repositories,
--- notes and tools live inside WSL, so a command aimed at a distribution has
--- to cross that boundary explicitly.
---
--- The Windows side is reached through Git Bash rather than PowerShell so that
--- one pipeline serves every environment: the scan is find/sed/stat either
--- way, and only the interpreter that runs it changes. This is a detail of
--- discovery alone — Windows projects open in settings.windows_shell.
---
--- @param cmd string Shell command, interpreted by bash.
--- @param distro string|nil Distribution to run in. nil means the native
---   environment: the Windows drive on Windows, the machine itself elsewhere.
--- @return boolean ok, string stdout
function M.exec(cmd, distro)
  local argv
  if not M.is_windows then
    argv = { "bash", "-lc", cmd }
  elseif distro then
    argv = { "wsl.exe", "-d", distro, "--", "bash", "-lc", cmd }
  else
    argv = { settings.windows_bash, "-lc", cmd }
  end

  local ok, stdout = wezterm.run_child_process(argv)
  return ok, stdout or ""
end

--- Strips trailing whitespace, including the newline every shell adds.
function M.chomp(s)
  return (s:gsub("%s+$", ""))
end

--- Keyed by distro, because two distributions need not agree on $HOME and
--- resolving one to the other's home would send the scan somewhere empty.
local home_cache = {}

--- Home directory *inside a work environment*, which on Windows is a WSL home
--- and not wezterm.home_dir. Resolved once per distro per config load.
---
--- @param distro string|nil Defaults to the default distribution.
--- The answer is fenced by a sentinel rather than taken as the whole output,
--- because `bash -l` runs the user's rc files first and one of them printing
--- to stdout — a title escape, a greeting, a version notice — would otherwise
--- be prepended to the home directory. Every path built from it then fails
--- its `[ -d ]` test and the scan silently finds nothing, which is a long way
--- to debug from the symptom.
local home_pattern = "WF_HOME=([^\r\n]*)"

function M.home(distro)
  local key = distro or ""

  if not home_cache[key] then
    if M.is_windows and not distro then
      -- Known without asking, and spelled with forward slashes so the one
      -- string works both as a Git Bash argument and as a Windows working
      -- directory.
      home_cache[key] = (wezterm.home_dir:gsub("\\", "/"))
    else
      local ok, out = M.exec('printf "WF_HOME=%s\\n" "$HOME"', distro)
      local home = ok and out:match(home_pattern)
      home_cache[key] = (home and home ~= "") and home or "~"
    end
  end
  return home_cache[key]
end

--- Expands a leading ~ against a work environment's home directory.
---
--- @param distro string|nil Defaults to the default distribution.
function M.expand(path, distro)
  if path:sub(1, 1) ~= "~" then
    return path
  end
  return M.home(distro) .. path:sub(2)
end

--- Quotes a string for safe interpolation into a bash command.
function M.shquote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Quotes a string as a PowerShell single-quoted literal, where the only
--- escape is a doubled quote and nothing else expands.
function M.psquote(s)
  return "'" .. s:gsub("'", "''") .. "'"
end

--- Splits an absolute path into its components.
local function segments(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  return parts
end

--- Derives the workspace and client names from a repository path.
--- `~/code/acme/billing-api` yields client "acme", repo "billing-api".
---
--- @param path string Absolute repository path.
--- @return string client, string repo
function M.project_of(path)
  local parts = segments(path)
  local repo = parts[#parts] or path
  local client = parts[#parts - 1] or "?"
  return client, repo
end

--- Maps a client name onto a fixed palette entry. Deterministic, so a client
--- keeps its slot across restarts and machines; position-weighted so that
--- names sharing letters ("acme" / "acem") do not collide.
---
--- The palette follows the active appearance, and the two palettes line up by
--- hue, so the same client reads as the same colour in light and dark without
--- either one clashing with the theme.
function M.client_color(client)
  local theme = require("wf_theme")
  local palette = theme.is_dark and settings.client_colors_dark or settings.client_colors_light

  if not client or client == "" then
    return palette[1]
  end

  local sum = 0
  for i = 1, #client do
    sum = sum + client:byte(i) * i
  end
  return palette[(sum % #palette) + 1]
end

--- Relative luminance of a "#rrggbb" colour, per WCAG.
function M.luminance(hex)
  local digits = hex:gsub("#", "")

  local function channel(offset)
    local value = tonumber(digits:sub(offset, offset + 1), 16) / 255
    if value <= 0.03928 then
      return value / 12.92
    end
    return ((value + 0.055) / 1.055) ^ 2.4
  end

  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
end

--- WCAG contrast ratio between two colours, from 1 (identical) to 21.
function M.contrast(a, b)
  local la, lb = M.luminance(a), M.luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

--- Blends `amount` of `b` into `a`.
function M.mix(a, b, amount)
  local da, db = a:gsub("#", ""), b:gsub("#", "")

  local out = "#"
  for offset = 1, 5, 2 do
    local ca = tonumber(da:sub(offset, offset + 1), 16)
    local cb = tonumber(db:sub(offset, offset + 1), 16)
    out = out .. string.format("%02x", math.floor(ca + (cb - ca) * amount + 0.5))
  end
  return out
end

--- Picks readable text for a coloured background.
---
--- Whichever ink actually contrasts better wins, rather than a luminance
--- threshold: mid-tone swatches like gold sit near any threshold you choose,
--- and guessing wrong there is what made the gold badge unreadable.
function M.ink_for(background)
  local theme = require("wf_theme")

  if M.contrast(background, theme.ink_dark) >= M.contrast(background, theme.ink_light) then
    return theme.ink_dark
  end
  return theme.ink_light
end

--- Pulls `color` toward `toward` until it reads against `background`.
---
--- Some themes pick a muted tab colour that is fine behind a tab but too faint
--- for status text; this moves it just far enough to clear the floor, keeping
--- the hierarchy without losing the text. `toward` is a parameter rather than
--- read from the theme because this runs while the theme module is still
--- loading, and requiring it back would be circular.
function M.legible(color, background, toward, floor)
  local result = color

  for _ = 1, 6 do
    if M.contrast(result, background) >= floor then
      break
    end
    result = M.mix(result, toward, 0.3)
  end
  return result
end

--- True when the text looks like a production context.
function M.is_prod(text)
  if not text or text == "" then
    return false
  end

  local lower = text:lower()
  for _, pattern in ipairs(settings.prod_patterns) do
    if lower:find(pattern) then
      return true
    end
  end
  return false
end

--- Renders a path written by this config (a Windows path when WezTerm runs on
--- Windows) as a shell expression the work environment can open.
---
--- @param host_path string Path as seen by the WezTerm process.
--- @return string Shell word, already quoted.
function M.work_path(host_path)
  if M.is_windows then
    return '"$(wslpath -u ' .. M.shquote(host_path) .. ')"'
  end
  return M.shquote(host_path)
end

--- The name of the domain a pane belongs to, or "" when it cannot be read.
function M.domain_of(pane)
  local ok, name = pcall(function()
    return pane:get_domain_name()
  end)
  if ok and name then
    return name
  end
  return ""
end

--- Spawn options that open a file for reading in the domain of the pane the
--- request came from.
---
--- Without this, a helper spawned from a PowerShell pane lands in the default
--- domain and starts the whole WSL VM just to display a file. Only a WSL pane
--- needs the path translated, and only it should pay that cost.
---
--- @param pane Pane The pane the action was invoked from.
--- @param host_path string Path as written by this config.
--- @return table Spawn options for spawn_tab.
function M.view_file_opts(pane, host_path)
  local settings = require("wf_settings")
  local domain = M.domain_of(pane)

  -- Name the domain rather than using "CurrentPaneDomain": that resolves
  -- against the window's *active* pane when the tab is spawned, which is only
  -- incidentally the pane the action came from.
  local spawn_domain = domain ~= "" and { DomainName = domain } or "CurrentPaneDomain"

  if M.is_windows and domain ~= "local" then
    return {
      domain = spawn_domain,
      args = { "bash", "-lc", settings.editor .. " -R " .. M.work_path(host_path) },
    }
  end

  return {
    domain = spawn_domain,
    args = { settings.editor, "-R", host_path },
  }
end

--- Builds an argv that runs a command and then leaves an interactive shell in
--- the pane.
---
--- Spawning with argv rather than typing into a new pane with send_text is not
--- cosmetic: send_text writes to the pty immediately, and anything written
--- before the shell has finished starting is echoed to the screen but never
--- executed. The trailing `exec bash` preserves the property send_text gave
--- for free, that quitting the editor or agent leaves a usable shell rather
--- than closing the pane.
---
--- The directory is entered by the command itself rather than left to the
--- spawn's `cwd`, because a WSL pane that carries its own program does not
--- reliably get one: the Linux path reaches wsl.exe as a *Windows* working
--- directory, fails, and the pane starts in the Windows home instead — which
--- from inside the distribution reads as /mnt/c/Users/<user>. Panes with no
--- program of their own are unaffected, which is why the editor, agent and
--- notes tabs drifted while the plain shells and every split stayed put.
---
--- @param cmd string|nil Shell command; omitted for a plain shell.
--- @param distro string|nil The environment the pane runs in. nil on Windows
---   means the Windows side, whose command is PowerShell, not bash.
--- @param cwd string|nil Directory to enter before running `cmd`. Ignored
---   without a command, where the spawn's own cwd is honoured.
--- @return table argv
function M.shell_args(cmd, distro, cwd)
  if M.is_windows and not distro then
    if not cmd or cmd == "" then
      return { settings.windows_shell, "-NoLogo" }
    end
    if cwd then
      cmd = "Set-Location -LiteralPath " .. M.psquote(cwd) .. "; " .. cmd
    end
    -- -NoExit is the PowerShell spelling of the trailing `exec bash` below:
    -- the pane outlives the command instead of closing with it.
    return { settings.windows_shell, "-NoLogo", "-NoExit", "-Command", cmd }
  end

  if not cmd or cmd == "" then
    return { "bash", "-l" }
  end
  if cwd then
    -- && so a directory that has gone missing does not run the command
    -- somewhere arbitrary; the shell that follows still opens for the repair.
    cmd = "cd " .. M.shquote(cwd) .. " && " .. cmd
  end
  return { "bash", "-lc", cmd .. "; exec bash" }
end

--- Directory for files this config generates: scrollback dumps, the cheat
--- sheet, the project cache. Created on demand, best effort.
function M.cache_dir()
  local dir = (require("wezterm").home_dir) .. "/.cache"
  return dir
end

--- Recursive table copy, used to derive config overrides from a theme without
--- mutating it. set_config_overrides replaces whole top-level keys, so the
--- accent colors must be applied to a full copy of the palette.
function M.deep_copy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for k, v in pairs(value) do
    copy[k] = M.deep_copy(v)
  end
  return copy
end

return M
