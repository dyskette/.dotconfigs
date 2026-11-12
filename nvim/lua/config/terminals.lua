--- Terminals inside nvim (toggleterm.nvim) for the command-line tools.
---
--- Each one runs the real program: lazygit with lazygit/config.yml, the shell
--- with its fzf key bindings. Files they open come back to this nvim through
--- flatten.nvim (plugins/terminal.lua), which hides the float while you edit.
local M = {}

--- Keys a float hands to the program instead of nvim. The global terminal
--- maps send <C-h/j/k/l> to window moves, which are meaningless from a float
--- and are what fzf and lazygit use to move up and down.
local passthrough_keys = { "<C-h>", "<C-j>", "<C-k>", "<C-l>" }

--- Border of every tool float: toggleterm's (shell, lazygit) and yazi's.
M.float_border = "single"

--- Width of the tool floats, centred: 92% of the editor.
---@return integer
function M.float_width()
  return math.floor(vim.o.columns * 0.92)
end

--- Height of the tool floats. They start on row 1 with one free row above and
--- below, so the bottom border stops above the status line
--- (config/statusline.lua) instead of covering it: rows 1 .. lines-cmdheight-3,
--- borders included.
---@return integer
function M.float_height()
  return vim.o.lines - vim.o.cmdheight - 5
end

--- Where the tool floats go, as nvim_open_win() takes it. Same placement as
--- toggleterm computes from float_opts, so a non-toggleterm float (yazi) lines
--- up with lazygit exactly.
---@return { row: integer, col: number, width: integer, height: integer }
function M.float_geometry()
  local width = M.float_width()
  return {
    row = 1,
    -- toggleterm's own centring formula (ui.lua), fractional result included.
    col = math.ceil(vim.o.columns - width) * 0.5 - 1,
    width = width,
    height = M.float_height(),
  }
end

--- Give a float terminal's keys to the program running in it.
---@param term Terminal
function M.on_open(term)
  if term.direction ~= "float" then
    return
  end
  for _, key in ipairs(passthrough_keys) do
    vim.keymap.set("t", key, key, { buffer = term.bufnr, nowait = true })
  end
end

--- Hide the toggleterm float that has focus, if any. The program in it keeps
--- running; toggling the terminal brings it back.
function M.hide_focused_float()
  local term_module = package.loaded["toggleterm.terminal"]
  local id = term_module and term_module.get_focused_id()
  local term = id and term_module.get(id, true)
  if term and term:is_float() then
    term:close()
  end
end

--- :QuickfixLoad FILE -- load FILE (file:line:col:text lines, as ripgrep
--- prints them) as the quickfix list, open it and jump to the first entry.
---
--- For the shells' `sg` with several hits. Not `nvim -q FILE`: flatten.nvim
--- hands that list over but neither opens it nor hides the terminal, while
--- `nvim +QuickfixLoad FILE` runs here as a command, in this nvim or a fresh
--- one alike.
function M.create_commands()
  vim.api.nvim_create_user_command("QuickfixLoad", function(opts)
    -- :copen cannot split a floating window.
    M.hide_focused_float()
    vim.cmd.cgetfile(vim.fn.fnameescape(opts.args))
    vim.cmd.copen()
    vim.cmd.cfirst()
  end, { nargs = 1, complete = "file", desc = "Load a file:line:col:text list into quickfix and open it" })
end

--- The repository the current buffer belongs to, else the working directory.
---@return string
local function project_root()
  return vim.fs.root(0, ".git") or vim.fn.getcwd()
end

---@type table<string, Terminal> one lazygit per repository, kept while it runs
local lazygits = {}

--- Toggle lazygit for the current buffer's repository. It keeps running when
--- hidden, so toggling back returns to where you were in it.
function M.lazygit()
  local root = project_root()
  local term = lazygits[root]
  if not term then
    term = require("toggleterm.terminal").Terminal:new({
      cmd = "lazygit",
      dir = root,
      direction = "float",
      display_name = "lazygit " .. vim.fs.basename(root),
      -- Not listed by :TermSelect or toggled by <C-\>: it has its own key.
      hidden = true,
      close_on_exit = true,
      on_open = M.on_open,
      on_exit = function()
        lazygits[root] = nil
      end,
    })
    lazygits[root] = term
  end
  term:toggle()
end

--- lazygit showing only the commits that touched the current file, in a
--- throwaway float.
function M.lazygit_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("lazygit: this buffer has no file", vim.log.levels.WARN)
    return
  end
  require("toggleterm.terminal").Terminal
    :new({
      cmd = "lazygit --filter " .. vim.fn.shellescape(file),
      dir = project_root(),
      direction = "float",
      display_name = "lazygit " .. vim.fs.basename(file),
      hidden = true,
      close_on_exit = true,
      on_open = M.on_open,
    })
    :open()
end

return M
