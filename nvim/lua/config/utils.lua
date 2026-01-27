local utils = {}

function utils.has_plugin(plugin)
  return require("lazy.core.config").plugins[plugin] ~= nil
end

---@param bufnr number
---@return integer|nil size in bytes if buffer is valid, nil otherwise
local get_buf_size = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ok, stat = pcall(function()
    return vim.uv.fs_stat(vim.api.nvim_buf_get_name(bufnr))
  end)

  if not (ok and stat) then
    return
  end

  return stat.size
end

---@param bufnr number
---@return integer|nil line_count number of lines in the buffer if valid, nil otherwise
local function get_buf_line_count(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ok, line_count = pcall(function()
    return vim.api.nvim_buf_line_count(bufnr)
  end)
  if not (ok and line_count) then
    return
  end
  return line_count
end

local max_bytes_per_line = 5000

---Determine if file looks to be minifed. Criteria is a large file with few lines
---@param bufnr number
---@return boolean
function utils.check_file_minified(bufnr)
  local filesize = get_buf_size(bufnr) or 0
  local line_count = get_buf_line_count(bufnr) or 0

  return filesize / line_count > max_bytes_per_line
end

utils.events = {
  -- After doing all the startup stuff, including loading vimrc files
  VimEnter = "VimEnter",
  -- When lazy has finished starting up and loaded your config
  LazyDone = "LazyDone",
  -- After `LazyDone` and processing `VimEnter` auto commands
  VeryLazy = "VeryLazy",
  -- After entering (visiting, switching-to) a new or existing buffer
  BufEnter = "BufEnter",
  -- After creating a new buffer (except during startup, see `VimEnter`) or renaming an existing buffer
  BufNew = "BufNew",
  -- When starting to edit a new buffer, before reading the file into the buffer
  BufReadPre = "BufReadPre",
  -- When starting to edit a new buffer, after reading the file into the buffer, before processing models
  BufReadPost = "BufReadPost",
  -- When starting to edit a file that doesn't exist
  BufNewFile = "BufNewFile",
  -- Just before starting Insert mode
  InsertEnter = "InsertEnter",
  -- Just after leaving Insert mode
  InsertLeave = "InsertLeave",
  -- After entering the command-line (including non-interactive use of ":" in a mapping)
  CmdlineEnter = "CmdlineEnter",
  -- After writing the whole buffer to a file
  BufWritePost = "BufWritePost",
  -- Just after a yank or deleting command, but not
  TextYankPost = "TextYankPost",
  -- When the 'filetype' option has been set
  FileType = "FileType",
  -- After loading a color scheme.
  ColorScheme = "ColorScheme",
  -- When an option is set (use with pattern for specific option, e.g., "background")
  OptionSet = "OptionSet",
}

-- DOCS: Sets up icons used everywhere else. These require a Nerd Font to be
-- installed. Find more and customize from here: https://www.nerdfonts.com/cheat-sheet
utils.icons = {
  error = " ",
  info = " ",
  hint = "",
  warn = " ",
  square = "",
  dap = {
    step_into = "",
    step_over = "",
    step_out = "",
    step_back = "",
    run_last = "",
    terminate = "",
  },
  git = {
    branch = "",
    added = "",
    modified = "",
    removed = "",
    renamed = "➜",
    untracked = "★",
    ignored = "◌",
    unstaged = "✗",
    staged = "✓",
    conflict = "",
  },
  separators = {
    triple_dash_vertical = "┋",
  },
  folders = {
    closed = "",
    open = "",
    empty = "",
    default = "",
  },
  files = {
    code = "󰎧",
    find = "󰱼",
    new = "",
  },
  coding = {
    class = "",
    color = "",
    constant = "",
    constructor = "",
    enum = "",
    field = "",
    func = "󰊕",
    interface = "",
    keyword = "",
    method = "m",
    module = "",
    operator = "",
    property = "",
    reference = "",
    snippet = "",
    struct = "",
    type = "",
    unit = "",
    value = "",
    variable = "󰫧",
  },
}

return utils
