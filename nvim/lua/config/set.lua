local utils = require("config.utils")

-- Default indentation
-- When guess-indent detects spaces, it will override: 'expandtab', 'tabstop', 'softtabstop', 'shiftwidth'
-- When guess-indent detects tabs, it will use 'tabstop'
vim.o.expandtab = true
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.smartindent = true

-- Highlight the copied text
local group = vim.api.nvim_create_augroup("dyskette_text_yank_highlight", { clear = true })
vim.api.nvim_create_autocmd(utils.events.TextYankPost, {
  desc = "Highlight yanked text",
  group = group,
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
})

-- Copy with OSC 52 everywhere: the terminal drawing nvim owns the clipboard, so a copy lands on the machine you are
-- looking at, locally or over SSH (where win32yank/xclip would copy to the remote machine instead).
-- Paste can't use OSC 52, since most terminals refuse to let programs read the clipboard and nvim would hang waiting.
-- Locally it reads the real clipboard with the native tool; over SSH (or without a tool) it reads back the last yank.
local function clipboard_paste_commands()
  if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
    return nil
  end
  local executable = function(name)
    return vim.fn.executable(name) == 1
  end
  if vim.fn.has("win32") == 1 and executable("win32yank.exe") then
    return { ["+"] = { "win32yank.exe", "-o", "--lf" }, ["*"] = { "win32yank.exe", "-o", "--lf" } }
  elseif vim.fn.has("mac") == 1 and executable("pbpaste") then
    return { ["+"] = { "pbpaste" }, ["*"] = { "pbpaste" } }
  elseif vim.env.WAYLAND_DISPLAY and executable("wl-paste") then
    return { ["+"] = { "wl-paste", "--no-newline" }, ["*"] = { "wl-paste", "--no-newline", "--primary" } }
  elseif vim.env.DISPLAY and executable("xclip") then
    return { ["+"] = { "xclip", "-o", "-selection", "clipboard" }, ["*"] = { "xclip", "-o", "-selection", "primary" } }
  end
  return nil
end

local function paste_last_yank()
  return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end

local osc52 = require("vim.ui.clipboard.osc52")
vim.g.clipboard = {
  name = "OSC 52 copy",
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = clipboard_paste_commands() or { ["+"] = paste_last_yank, ["*"] = paste_last_yank },
}

-- Windows: nvim takes 'shell' from $SHELL, which the PowerShell profile sets
-- to pwsh, but keeps cmd.exe's flags (/s /c) -- so :!, system() with a string
-- and every toggleterm terminal ran `pwsh /s /c ...` and failed. Back to
-- cmd.exe with its own flags: the default nvim and its plugins are written
-- for, and ~5x faster to start than pwsh. Interactive terminals still run
-- pwsh (toggleterm's `shell`, plugins/terminal.lua).
if vim.fn.has("win32") == 1 and not vim.o.shell:lower():find("cmd") then
  vim.o.shell = "cmd.exe"
  vim.o.shellcmdflag = "/s /c"
  vim.o.shellxquote = '"'
  vim.o.shellquote = ""
  vim.o.shellpipe = ">%s 2>&1"
  vim.o.shellredir = ">%s 2>&1"
end

-- :grep through ripgrep with the shared defaults (ripgrep/config: smart case,
-- hidden files, .gitignore respected). nvim's own default adds -uu, which
-- searches ignored files and .git too. The shells set RIPGREP_CONFIG_PATH; this
-- covers an nvim started some other way (a desktop shortcut).
if vim.fn.executable("rg") == 1 then
  vim.env.RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH
    or vim.fs.joinpath(vim.env.HOME or vim.env.USERPROFILE, ".dotconfigs", "ripgrep", "config")
  vim.o.grepprg = "rg --vimgrep"
  vim.o.grepformat = "%f:%l:%c:%m"
end

-- Pretty colors
vim.o.termguicolors = true
vim.o.winborder = "single"

-- Terminal title: the file being edited, so a tmux/psmux window and the
-- terminal tab read "nvim lspconfig.lua"; %m adds [+] while it is modified.
vim.o.title = true
vim.o.titlestring = "nvim %t%( %m%)"

-- Line numbers
vim.o.number = true
vim.o.relativenumber = true

-- show <Tab> and <EOL>
vim.o.list = true

-- Minimum number of lines to keep above and below the cursor (keeps the cursor vertically centered)
vim.o.scrolloff = 5

-- No line wrapping
vim.o.wrap = false

-- Rulers
vim.o.colorcolumn = "120"

-- Diagnostic
vim.diagnostic.config({
  severity_sort = true,
  virtual_lines = false,
  virtual_text = {
    prefix = utils.icons.square,
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = utils.icons.error,
      [vim.diagnostic.severity.WARN] = utils.icons.warn,
      [vim.diagnostic.severity.HINT] = utils.icons.hint,
      [vim.diagnostic.severity.INFO] = utils.icons.info,
    },
  },
  float = { border = "single", title = " Diagnostic " },
})

-- Relative numbers in normal mode, absolute in insert mode
local number_toggle_group = vim.api.nvim_create_augroup("dyskette_number_toggle", { clear = true })
vim.api.nvim_create_autocmd({ utils.events.InsertEnter }, {
  desc = "Switch to absolute line numbers in insert mode",
  group = number_toggle_group,
  callback = function()
    vim.opt.relativenumber = false
  end,
})
vim.api.nvim_create_autocmd({ utils.events.InsertLeave }, {
  desc = "Switch to relative line numbers when leaving insert mode",
  group = number_toggle_group,
  callback = function()
    vim.opt.relativenumber = true
  end,
})
