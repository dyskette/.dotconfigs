-- Neovim's side of the Zellij workspace (zellij/README.md).
--
-- Keys, in every mode, so they work while typing too:
--   <M-h/j/k/l>  move between windows; at the edge of the layout the move
--                continues into the neighbouring Zellij pane (or tab)
--   <M-H/J/K/L>  move the window divider; with no divider in that direction,
--                Zellij's pane divider moves instead
-- Zellij's pilot plugin (zellij/plugins/pilot) sends both here when this nvim
-- has focus, and handles them itself in every other pane.
--
-- One editor per tab: the nvim a service tab starts registers itself as the
-- tab's editor. flatten.nvim (plugins/terminal.lua) sends files opened by
-- `nvim` anywhere else in the tab (lazygit, yazi, the shell's sf/sg, the
-- agent, Zellij's click-to-open) to it, through pipe_path() below.
--
-- The agent bridge (<leader>i...) pastes file references, selections and
-- diagnostics into the tab's agent pane. <leader>sp opens the session hub.
local M = {}

-- Directions: Zellij's name for each, and whether it moves along columns.
local dirs = {
  h = { name = "left", vertical = true },
  l = { name = "right", vertical = true },
  k = { name = "up", vertical = false },
  j = { name = "down", vertical = false },
}

---@return boolean
local function in_zellij()
  return vim.env.ZELLIJ ~= nil and vim.env.ZELLIJ_PANE_ID ~= nil
end

--- Run zellij asynchronously; failures are reported, not raised.
---@param args string[]
---@param on_done? fun(out: vim.SystemCompleted)
local function zellij(args, on_done)
  vim.system(vim.list_extend({ "zellij" }, args), { text = true }, function(out)
    if out.code ~= 0 then
      vim.schedule(function()
        local what = "zellij " .. args[1] .. " " .. (args[2] or "")
        vim.notify(what .. ": " .. vim.trim(out.stderr or ""), vim.log.levels.WARN)
      end)
    elseif on_done then
      vim.schedule(function()
        on_done(out)
      end)
    end
  end)
end

--- The terminal panes in this pane's tab, from `zellij action list-panes`.
--- Synchronous (~30 ms); nil outside Zellij or on failure.
---@return table[]?
local function tab_panes()
  if not in_zellij() then
    return nil
  end
  local out = vim.system({ "zellij", "action", "list-panes", "--json", "--tab" }, { text = true }):wait(3000)
  if out.code ~= 0 then
    return nil
  end
  local ok, panes = pcall(vim.json.decode, out.stdout)
  if not ok or type(panes) ~= "table" then
    return nil
  end
  local me = tonumber(vim.env.ZELLIJ_PANE_ID)
  local tab
  for _, pane in ipairs(panes) do
    if not pane.is_plugin and pane.id == me then
      tab = pane.tab_id
    end
  end
  return vim.tbl_filter(function(pane)
    return not pane.is_plugin and pane.tab_id == tab
  end, panes)
end

-- --- Navigation ------------------------------------------------------------------

--- Move to the window in a direction, or hand the move to Zellij at the edge.
---@param key "h"|"j"|"k"|"l"
function M.navigate(key)
  local before = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(key)
  if vim.api.nvim_get_current_win() ~= before or not in_zellij() then
    return
  end
  -- Through pilot: `zellij action move-focus` from a pane has no client to
  -- move ("No connected clients"). nav-pane skips pilot's editor check,
  -- which would send the key straight back here.
  zellij({ "pipe", "--name", "nav-pane", "--", dirs[key].name })
end

-- --- Resizing --------------------------------------------------------------------

local RESIZE_COLUMNS, RESIZE_ROWS = 5, 2

--- Move the divider in a direction: the right/bottom one when the window
--- has one, else the left/top one. With neither, Zellij's pane divider
--- moves (pilot applies the same rule).
---@param key "h"|"j"|"k"|"l"
function M.resize(key)
  local d = dirs[key]
  local after = d.vertical and "l" or "j" -- right / below
  local before = d.vertical and "h" or "k" -- left / above
  local towards_after = key == after

  local function has(neighbour)
    return vim.fn.winnr(neighbour) ~= vim.fn.winnr()
  end

  local delta
  if has(after) then
    delta = towards_after and 1 or -1 -- the divider after this window
  elseif has(before) then
    delta = towards_after and -1 or 1 -- the divider before it
  end

  if not delta then
    if in_zellij() then
      -- "resize-pane" skips pilot's editor check, which would send the key
      -- straight back here.
      zellij({ "pipe", "--name", "resize-pane", "--", d.name })
    end
    return
  end

  local win = vim.api.nvim_get_current_win()
  if d.vertical then
    vim.api.nvim_win_set_width(win, math.max(1, vim.api.nvim_win_get_width(win) + delta * RESIZE_COLUMNS))
  else
    vim.api.nvim_win_set_height(win, math.max(1, vim.api.nvim_win_get_height(win) + delta * RESIZE_ROWS))
  end
end

-- --- One editor per tab -------------------------------------------------------------

--- Where hosts record their server address: <state>/zellij/<session>/<pane id>.
---@return string?
local function registry_dir()
  local session = vim.env.ZELLIJ_SESSION_NAME
  if not in_zellij() or not session then
    return nil
  end
  return vim.fs.joinpath(vim.fn.stdpath("state"), "zellij", session)
end

--- Files this nvim must edit itself rather than hand to the tab's editor:
--- Zellij's edit-scrollback dump, which belongs to the pane it came from.
---@return boolean
local function edits_in_place()
  for _, arg in ipairs(vim.v.argv) do
    if arg:match("%.dump$") then
      return true
    end
  end
  return false
end

--- flatten.nvim's pipe_path hook: the server of the tab's editor nvim, or
--- nil to be a host. Runs at startup of every nvim, so it only asks Zellij
--- for the pane list when another editor of this session is registered.
---@return string|integer|nil
function M.pipe_path()
  if vim.env.NVIM then
    return vim.env.NVIM -- inside an nvim terminal: that nvim, as before
  end
  local dir = registry_dir()
  if not dir or edits_in_place() then
    return nil
  end

  local me = vim.env.ZELLIJ_PANE_ID
  local registered = {}
  for name in vim.fs.dir(dir) do
    if name ~= me then
      registered[tonumber(name)] = vim.fs.joinpath(dir, name)
    end
  end
  if next(registered) == nil then
    return nil
  end

  for _, pane in ipairs(tab_panes() or {}) do
    local file = registered[pane.id]
    if file then
      local fd = io.open(file, "r")
      local address = fd and fd:read("*l")
      if fd then
        fd:close()
      end
      if address then
        local ok, chan = pcall(vim.fn.sockconnect, "pipe", address, { rpc = true })
        if ok and chan > 0 then
          return chan
        end
        os.remove(file) -- a stale entry from an nvim that is gone
      end
    end
  end
  return nil
end

--- Record this nvim as its pane's editor, unless it is a flatten guest.
local function register_host()
  local dir = registry_dir()
  if not dir or edits_in_place() then
    return
  end
  local ok, flatten = pcall(require, "flatten")
  if ok and flatten.is_guest() then
    return
  end
  vim.fn.mkdir(dir, "p")
  local file = vim.fs.joinpath(dir, vim.env.ZELLIJ_PANE_ID)
  local fd = io.open(file, "w")
  if not fd then
    return
  end
  fd:write(vim.v.servername, "\n")
  fd:close()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      os.remove(file)
    end,
  })
end

--- flatten's guest_data hook: the pane the request comes from, so the host
--- can give it focus back after a blocking edit.
---@return table
function M.guest_data()
  return { zellij_pane = vim.env.ZELLIJ_PANE_ID }
end

--- Focus a Zellij terminal pane by id (this one by default), through pilot:
--- `zellij action focus-pane-id` from a pane does not move the user's client.
---@param pane? string|integer
function M.focus_pane(pane)
  pane = pane or vim.env.ZELLIJ_PANE_ID
  if in_zellij() and pane then
    zellij({ "pipe", "--name", "focus", "--", tostring(pane) })
  end
end

-- --- Agent bridge -------------------------------------------------------------------

--- The tab's agent pane id (the pane named "agent").
---@return integer?
local function agent_pane()
  for _, pane in ipairs(tab_panes() or {}) do
    if pane.title == "agent" then
      return pane.id
    end
  end
end

--- Paste text into the agent's prompt (not submitted) and focus it.
---@param text string
function M.send_to_agent(text)
  if not in_zellij() then
    vim.notify("Not inside Zellij: no agent pane to send to", vim.log.levels.WARN)
    return
  end
  local pane = agent_pane()
  if not pane then
    vim.notify("This tab has no agent pane (Alt a starts one)", vim.log.levels.WARN)
    return
  end
  zellij({ "action", "paste", "--pane-id", "terminal_" .. pane, "--", text }, function()
    M.focus_pane(pane)
  end)
end

---@return string path relative to the working directory, / separated
local function buffer_path()
  return (vim.fn.expand("%:.")):gsub("\\", "/")
end

--- @path, which agents read as "this file".
function M.send_file()
  M.send_to_agent("@" .. buffer_path() .. " ")
end

--- @path with the cursor line, or the selection as a fenced block.
function M.send_lines()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
      first, last = last, first
    end
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
    local text = ("@%s lines %d-%d:\n```%s\n%s\n```\n"):format(
      buffer_path(),
      first,
      last,
      vim.bo.filetype,
      table.concat(lines, "\n")
    )
    M.send_to_agent(text)
  else
    M.send_to_agent(("@%s line %d "):format(buffer_path(), vim.fn.line(".")))
  end
end

--- The diagnostics on the cursor line (or the whole buffer with a count).
function M.send_diagnostics()
  local opts = vim.v.count > 0 and {} or { lnum = vim.fn.line(".") - 1 }
  local diagnostics = vim.diagnostic.get(0, opts)
  if #diagnostics == 0 then
    vim.notify("No diagnostics here", vim.log.levels.INFO)
    return
  end
  local lines = { "Fix these diagnostics:" }
  for _, d in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[d.severity]
    table.insert(lines, ("- @%s:%d %s: %s"):format(buffer_path(), d.lnum + 1, severity, d.message))
  end
  M.send_to_agent(table.concat(lines, "\n") .. "\n")
end

-- --- The session hub -------------------------------------------------------------------

--- Open the session hub (zellij/README.md, "The hub"): running sessions,
--- saved sessions and projects in one list. The same popup as Alt s; pilot
--- opens it for this client.
function M.hub()
  if not in_zellij() then
    vim.notify("The session hub is part of Zellij; start nvim inside Zellij", vim.log.levels.WARN)
    return
  end
  zellij({ "pipe", "--name", "hub", "--", "open" })
end

-- --- Setup ---------------------------------------------------------------------------------

function M.setup()
  local modes = { "n", "i", "x", "t" }
  for key, d in pairs(dirs) do
    vim.keymap.set(modes, "<M-" .. key .. ">", function()
      -- Leave insert, visual or terminal mode first, then move.
      if vim.api.nvim_get_mode().mode ~= "n" then
        vim.api.nvim_feedkeys(vim.keycode("<C-\\><C-n>"), "nx", false)
      end
      M.navigate(key)
    end, { desc = "Window or Zellij pane " .. d.name })

    vim.keymap.set(modes, "<M-" .. key:upper() .. ">", function()
      M.resize(key)
    end, { desc = "Move the window (or Zellij pane) divider " .. d.name })
  end

  vim.keymap.set("n", "<leader>if", M.send_file, { desc = "Agent: send @file" })
  vim.keymap.set({ "n", "x" }, "<leader>il", M.send_lines, { desc = "Agent: send @file line, or the selection" })
  vim.keymap.set("n", "<leader>id", M.send_diagnostics, {
    desc = "Agent: send diagnostics (line, or buffer with a count)",
  })
  vim.keymap.set("n", "<leader>ii", function()
    zellij({ "pipe", "--name", "agent", "--", "toggle" })
  end, { desc = "Agent: go to the agent pane (Alt a)" })
  vim.keymap.set("n", "<leader>sp", M.hub, { desc = "Sessions and projects (the Zellij hub)" })

  if in_zellij() then
    vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = register_host })
  end
end

return M
