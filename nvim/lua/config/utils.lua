local utils = {}

utils.events = {
  -- After doing all the startup stuff, including loading vimrc files
  VimEnter = "VimEnter",
  -- When lazy has finished starting up and loaded your config
  LazyDone = "LazyDone",
  -- After `LazyDone` and processing `VimEnter` auto commands
  VeryLazy = "VeryLazy",
  -- First file read or created; after the first screen for files given on
  -- the command line, and never when nvim starts without one (config.lazy)
  LazyFile = "User LazyFile",
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
  -- After the terminal replies to a query (OSC/DEC responses, see `:h TermResponse`)
  TermResponse = "TermResponse",
  -- When Nvim gains focus (requires a terminal that reports focus events)
  FocusGained = "FocusGained",
  -- Before exiting, while it is still possible to interact with the editor
  VimLeavePre = "VimLeavePre",
}

-- DOCS: Sets up icons used everywhere else. These require a Nerd Font to be
-- installed. Find more and customize from here: https://www.nerdfonts.com/cheat-sheet
utils.icons = {
  error = " ",
  info = " ",
  hint = "",
  warn = " ",
  square = "",
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
