--- Shared helpers: platform differences, shell execution, path and color math.

local wezterm = require("wezterm")
local settings = require("wf_settings")

local M = {}

--- True when the config is being evaluated by a WezTerm running on Windows,
--- where the work environment lives behind wsl.exe rather than in-process.
M.is_windows = wezterm.target_triple:find("windows") ~= nil

--- Runs a shell command inside the work environment and captures its output.
---
--- On Windows the config runs as a native process while the repositories,
--- notes and tools live inside WSL, so every command has to cross that
--- boundary explicitly.
---
--- @param cmd string Shell command, interpreted by bash.
--- @return boolean ok, string stdout
function M.exec(cmd)
  local argv
  if M.is_windows then
    argv = { "wsl.exe", "-d", settings.wsl_distro, "--", "bash", "-lc", cmd }
  else
    argv = { "bash", "-lc", cmd }
  end

  local ok, stdout = wezterm.run_child_process(argv)
  return ok, stdout or ""
end

--- Strips trailing whitespace, including the newline every shell adds.
function M.chomp(s)
  return (s:gsub("%s+$", ""))
end

local home_cache

--- Home directory *inside the work environment*, which on Windows is the WSL
--- home and not wezterm.home_dir. Resolved once per config load.
function M.home()
  if not home_cache then
    local ok, out = M.exec('printf %s "$HOME"')
    home_cache = ok and M.chomp(out) or "~"
  end
  return home_cache
end

--- Expands a leading ~ against the work environment's home directory.
function M.expand(path)
  if path:sub(1, 1) ~= "~" then
    return path
  end
  return M.home() .. path:sub(2)
end

--- Quotes a string for safe interpolation into a bash command.
function M.shquote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
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
--- @param cmd string|nil Shell command; omitted for a plain shell.
--- @return table argv
function M.shell_args(cmd)
  if not cmd or cmd == "" then
    return { "bash", "-l" }
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
