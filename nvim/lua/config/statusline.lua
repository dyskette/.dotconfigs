--- The status line: nvim's own 'statusline', no plugin.
---
--- The rule: the bar never computes anything, it only displays. nvim
--- evaluates 'statusline' on every redraw (each cursor move, for %l:%c), so
--- the option holds a finished string: native items (%f, %l, %c, %m...) and
--- text that is already formatted. Each segment is cached in a buffer (or
--- global) variable by the event that changes it, and that event rebuilds the
--- string from the current buffer's caches (render()):
---
---   segment       written on                         source
---   mode          ModeChanged                        nvim_get_mode()
---   name          BufEnter, TermOpen (terminals)     toggleterm's display name
---   file icon     BufEnter, FileType                 nvim-web-devicons
---   git           User GitSignsUpdate                gitsigns (runs git async, watches .git)
---   diagnostics   DiagnosticChanged, BufEnter        vim.diagnostic.count()
---   lsp           LspAttach, LspDetach               vim.lsp.get_clients()
---   format        BufEnter, BufWritePost, OptionSet  'fileformat', 'fileencoding'
---
--- Not %{%get(b:,'st_git','')%} lookups in the option: measured with
--- nvim_eval_statusline, those cost ~7 us more per redraw than a finished
--- string, which costs the same as a bar of native items alone.
---
--- The cached strings are statusline format, %#Group# highlights included;
--- text from outside (branch, client names) is escaped (% -> %%).
local utils = require("config.utils")

local M = {}

-- Where each segment is cached (vim.b, or vim.g for the mode); render()
-- reads them back by the same names.
local VAR = {
  mode = "st_mode",
  name = "st_name",
  icon = "st_icon",
  git = "st_git",
  diag = "st_diag",
  lsp = "st_lsp",
  format = "st_format",
}

--- Escape text for use inside a statusline format.
---@param text string
---@return string
local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

local render

-- Mode -------------------------------------------------------------------------

-- Keyed by nvim_get_mode().mode; anything not listed falls back to its first
-- character (e.g. "niI" -> "n").
local modes = {
  n = { "NORMAL", "Normal" },
  no = { "PENDING", "Normal" },
  nt = { "NORMAL", "Terminal" },
  v = { "VISUAL", "Visual" },
  V = { "V-LINE", "Visual" },
  ["\22"] = { "V-BLOCK", "Visual" },
  s = { "SELECT", "Visual" },
  S = { "S-LINE", "Visual" },
  ["\19"] = { "S-BLOCK", "Visual" },
  i = { "INSERT", "Insert" },
  R = { "REPLACE", "Replace" },
  c = { "COMMAND", "Command" },
  r = { "PROMPT", "Command" },
  ["!"] = { "SHELL", "Terminal" },
  t = { "TERMINAL", "Terminal" },
}

local function update_mode()
  local mode = vim.api.nvim_get_mode().mode
  local entry = modes[mode] or modes[mode:sub(1, 1)] or { mode:upper(), "Normal" }
  vim.g[VAR.mode] = ("%%#StMode%s# %s %%#StatusLine#"):format(entry[2], entry[1])
  render()
end

-- File icon --------------------------------------------------------------------

---@param buf integer
local function update_icon(buf)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local icon, group = devicons.get_icon(vim.fs.basename(name), nil, { default = false })
  if not icon then
    icon, group = devicons.get_icon_by_filetype(vim.bo[buf].filetype, { default = true })
  end
  vim.b[buf][VAR.icon] = icon and ("%%#%s#%s%%#StatusLine# "):format(group, icon) or ""
end

-- Git --------------------------------------------------------------------------

--- From gitsigns' status for the buffer: branch, then +added ~changed
--- -removed when non-zero. Buffers gitsigns does not track (terminals, the
--- lazygit float) get the working directory's branch, g:gitsigns_head.
---@param buf integer
local function update_git(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local status = vim.b[buf].gitsigns_status_dict
  local head = status and status.head or vim.g.gitsigns_head
  if not head or head == "" then
    vim.b[buf][VAR.git] = ""
    return
  end

  local parts = { ("  %%#StGit#%s %s%%#StatusLine#"):format(utils.icons.git.branch, escape(head)) }
  if status then
    for _, item in ipairs({
      { "added", "+", "GitSignsAdd" },
      { "changed", "~", "GitSignsChange" },
      { "removed", "-", "GitSignsDelete" },
    }) do
      local count = status[item[1]]
      if count and count > 0 then
        parts[#parts + 1] = ("%%#%s#%s%d%%#StatusLine#"):format(item[3], item[2], count)
      end
    end
  end
  vim.b[buf][VAR.git] = table.concat(parts, " ")
end

-- Diagnostics ------------------------------------------------------------------

local severities = {
  { vim.diagnostic.severity.ERROR, "error", "DiagnosticError" },
  { vim.diagnostic.severity.WARN, "warn", "DiagnosticWarn" },
  { vim.diagnostic.severity.INFO, "info", "DiagnosticInfo" },
  { vim.diagnostic.severity.HINT, "hint", "DiagnosticHint" },
}

---@param buf integer
local function update_diagnostics(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local counts = vim.diagnostic.count(buf)
  local parts = {}
  for _, s in ipairs(severities) do
    if counts[s[1]] then
      -- Trimmed and re-spaced: utils.icons has a trailing space on some
      -- icons but not on hint, whose wide glyph then ran into the count.
      parts[#parts + 1] = ("%%#%s#%s %d"):format(s[3], vim.trim(utils.icons[s[2]]), counts[s[1]])
    end
  end
  vim.b[buf][VAR.diag] = #parts > 0 and (table.concat(parts, " ") .. "%#StatusLine#  ") or ""
end

-- LSP --------------------------------------------------------------------------

--- Names of the language servers attached to the buffer. On LspDetach the
--- leaving client is still listed, hence `except`.
---@param buf integer
---@param except? integer client id to leave out
local function update_lsp(buf, except)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.id ~= except then
      names[#names + 1] = escape(client.name)
    end
  end
  vim.b[buf][VAR.lsp] = #names > 0 and ("%%#StLsp# %s%%#StatusLine#  "):format(table.concat(names, " ")) or ""
end

-- Name -------------------------------------------------------------------------

--- Terminals get a readable name instead of term://cwd//pid:command: the
--- toggleterm terminal's display name ("lazygit .dotconfigs"), else the
--- command without toggleterm's "&::toggleterm::1" / ";#toggleterm#1" tag.
--- Other buffers keep nvim's %f (path relative to the working directory, kept
--- current by nvim itself) and their modified/read-only flags.
---@param buf integer
local function update_name(buf)
  if vim.bo[buf].buftype ~= "terminal" then
    vim.b[buf][VAR.name] = nil
    return
  end
  local name
  local term_module = package.loaded["toggleterm.terminal"]
  local id = vim.b[buf].toggle_number
  if term_module and id then
    local term = term_module.get(id, true)
    name = term and term.display_name
  end
  if not name then
    name = vim.api.nvim_buf_get_name(buf):match("//%d+:(.*)$") or "terminal"
    name = name:gsub("[&;]+%s*[:#]+%s*toggleterm[:#]+%d+$", "")
  end
  vim.b[buf][VAR.name] = escape(name)
end

-- File format ------------------------------------------------------------------

--- Only what differs from utf-8 + unix: a CRLF or latin1 file is worth
--- knowing about before saving it, a normal one is not worth the space.
---@param buf integer
local function update_format(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- Only files have a format worth showing; a terminal is "dos" on Windows.
  if vim.bo[buf].buftype ~= "" then
    vim.b[buf][VAR.format] = ""
    return
  end
  local parts = {}
  local encoding = vim.bo[buf].fileencoding
  if encoding ~= "" and encoding ~= "utf-8" then
    parts[#parts + 1] = encoding
  end
  if vim.bo[buf].bomb then
    parts[#parts + 1] = "bom"
  end
  if vim.bo[buf].fileformat ~= "unix" then
    parts[#parts + 1] = vim.bo[buf].fileformat == "dos" and "crlf" or vim.bo[buf].fileformat
  end
  vim.b[buf][VAR.format] = #parts > 0 and ("%%#StFormat#%s%%#StatusLine#  "):format(table.concat(parts, " ")) or ""
end

-- Highlights -------------------------------------------------------------------

--- Foreground colour of the first group in `groups` that has one.
---@param groups string[]
---@return integer?
local function fg_of(groups)
  for _, name in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    if hl.fg then
      return hl.fg
    end
  end
end

--- Mode blocks take their colour from the colorscheme (everforest's Green,
--- Blue, ... with fallbacks any scheme has), text in the editor background,
--- so they follow light/dark with it. Rebuilt on ColorScheme only.
local function define_highlights()
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  local accents = {
    Normal = { "Green", "String" },
    Insert = { "Blue", "Function" },
    Visual = { "Purple", "Statement" },
    Replace = { "Red", "DiagnosticError" },
    Command = { "Yellow", "DiagnosticWarn" },
    Terminal = { "Aqua", "Special" },
  }
  for mode, groups in pairs(accents) do
    vim.api.nvim_set_hl(0, "StMode" .. mode, { fg = bg, bg = fg_of(groups), bold = true })
  end
  vim.api.nvim_set_hl(0, "StGit", { fg = fg_of({ "Orange", "Constant" }), bold = true })
  vim.api.nvim_set_hl(0, "StLsp", { fg = fg_of({ "Grey", "Comment" }) })
  vim.api.nvim_set_hl(0, "StFormat", { fg = fg_of({ "Yellow", "WarningMsg" }), bold = true })
end

-- Setup ------------------------------------------------------------------------

--- Rebuild 'statusline' from the current buffer's caches. Setting the option
--- redraws the bar; nothing else is evaluated until the next event. Groups
--- that only set a foreground (DevIcon*, Diagnostic*) are combined with
--- StatusLine, so they keep the bar's background.
render = function()
  local b, g = vim.b, vim.g
  vim.o.statusline = table.concat({
    g[VAR.mode] or "",
    " ",
    b[VAR.icon] or "",
    -- Path relative to the working directory, truncated from the left (%<)
    -- when the bar runs out of room, and the modified/read-only flags; or a
    -- terminal's name.
    "%<",
    b[VAR.name] or "%f%( %m%r%)",
    b[VAR.git] or "",
    "%=",
    b[VAR.diag] or "",
    b[VAR.lsp] or "",
    b[VAR.format] or "",
    -- Line:column, then the position as a percentage (Top/Bot/All).
    "%#StatusLine#%l:%c  %P ",
  })
end

--- Rebuild only when `buf` is the one on screen: with one global bar, other
--- buffers' updates just wait in their cache for their BufEnter.
---@param buf integer
local function render_if_current(buf)
  if buf == vim.api.nvim_get_current_buf() then
    render()
  end
end
function M.setup()
  -- One bar for all windows, as lualine had; the mode lives in it.
  vim.o.laststatus = 3
  vim.o.showmode = false

  define_highlights()
  update_mode()

  local group = vim.api.nvim_create_augroup("dyskette_statusline", { clear = true })
  local function on(events, opts)
    opts.group = group
    vim.api.nvim_create_autocmd(events, opts)
  end

  on(utils.events.ColorScheme, { callback = define_highlights })
  on("ModeChanged", { callback = update_mode })

  on({ utils.events.BufEnter, utils.events.FileType }, {
    callback = function(args)
      update_name(args.buf)
      update_icon(args.buf)
      update_format(args.buf)
      update_diagnostics(args.buf)
      update_git(args.buf)
      render()
    end,
  })

  -- Scheduled: toggleterm sets b:toggle_number right after the job starts.
  on("TermOpen", {
    callback = function(args)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          update_name(args.buf)
          update_format(args.buf)
          render_if_current(args.buf)
        end
      end)
    end,
  })

  on({ utils.events.BufWritePost }, {
    callback = function(args)
      update_format(args.buf)
      render_if_current(args.buf)
    end,
  })
  on(utils.events.OptionSet, {
    pattern = { "fileformat", "fileencoding", "bomb" },
    callback = function()
      update_format(vim.api.nvim_get_current_buf())
      render()
    end,
  })

  on("DiagnosticChanged", {
    callback = function(args)
      update_diagnostics(args.buf)
      render_if_current(args.buf)
    end,
  })

  on("LspAttach", {
    callback = function(args)
      update_lsp(args.buf)
      render_if_current(args.buf)
    end,
  })
  on("LspDetach", {
    callback = function(args)
      update_lsp(args.buf, args.data.client_id)
      render_if_current(args.buf)
    end,
  })

  -- gitsigns' docs name the field `bufnr`, its example `buffer`; a head
  -- change for the working directory comes without either.
  on("User", {
    pattern = "GitSignsUpdate",
    callback = function(args)
      local data = args.data or {}
      local buf = data.buffer or data.bufnr or vim.api.nvim_get_current_buf()
      update_git(buf)
      render_if_current(buf)
    end,
  })
end

return M
