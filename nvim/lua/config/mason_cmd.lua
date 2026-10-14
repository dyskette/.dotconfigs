--- The program behind a mason tool, to start it without its Windows shim.
---
--- On Windows mason installs every tool as a .cmd file in its bin/, so
--- starting one costs a cmd.exe first, and an npm package's shim calls a
--- second .cmd that finally runs node. Each cmd.exe is ~25 ms. This reads the
--- shims instead and returns the command they end up running: the .exe, or
--- node with the package's script. Reading them is cheap, and it follows
--- whatever layout a package update brings, where hard-coded paths would not.
local M = {}

local bin = vim.fn.stdpath("data") .. "/mason/bin/"
local cache = {}

--- The quoted words of a shim's final command line, %dp0% (the shim's own
--- directory) expanded.
--- @param shim string
--- @return string[]?
local function shim_words(shim)
  local file = io.open(shim, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()

  -- Both mason's and npm's shims end with `... title %COMSPEC% & <command> %*`
  local command = content:match("%%COMSPEC%% & ([^\r\n]*)%s*$")
  if not command then
    return nil
  end
  local dir = vim.fs.dirname(shim)
  local words = {}
  for word in command:gmatch('"([^"]+)"') do
    words[#words + 1] = word:gsub("%%dp0%%", dir)
  end
  return words
end

--- @param path string
--- @return string? the normalized path, if it exists
local function existing(path)
  return vim.uv.fs_realpath(path)
end

--- @param shim string
--- @param depth integer
--- @return string[]?
local function resolve_shim(shim, depth)
  local words = depth < 3 and shim_words(shim)
  if not words then
    return nil
  end
  -- npm: "%_prog%" "<script>", where %_prog% is node.
  if words[1] == "%_prog%" and words[2] then
    local script = existing(words[2])
    return script and { "node", script }
  end
  -- mason: "<program>", which is either the program or another shim.
  if #words == 1 then
    local program = existing(words[1])
    if not program then
      return nil
    end
    if program:lower():match("%.cmd$") then
      return resolve_shim(program, depth + 1)
    end
    return { program }
  end
  return nil
end

--- The command a mason tool's shim runs, or nil (not on Windows, not a mason
--- tool, or a shim this does not recognise), in which case the caller keeps
--- the original command.
--- @param name string a command name as on PATH, e.g. "lua-language-server"
--- @return string[]? argv prefix: the program, and for node tools the script
function M.resolve(name)
  if vim.fn.has("win32") == 0 then
    return nil
  end
  if cache[name] == nil then
    cache[name] = resolve_shim(bin .. name .. ".cmd", 0) or false
  end
  return cache[name] and vim.deepcopy(cache[name]) or nil
end

return M
