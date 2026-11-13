-- Terminals inside nvim, and nvim inside them.
--
-- toggleterm.nvim gives floats and splits for the shell and lazygit
-- (config/terminals.lua). flatten.nvim makes any `nvim` started in one of
-- them, by hand or by a tool (lazygit's `e`, git commit, yazi, sf/sg in the
-- shell), open its files in this nvim instead of a nested one. No per-tool
-- editor settings: lazygit/config.yml just says `nvim`.
--
-- Inside Zellij the same goes for every pane of the tab: the tab's editor
-- nvim is the host (config/zellij.lua finds it), takes focus when a file
-- arrives, and gives it back to the pane that asked once a blocking edit
-- (commit message, an agent's prompt) is written.
local terminals = require("config.terminals")

--- Whether argv edits a file in the temp folder: the prompt files agents
--- (OpenCode's editor key, Claude Code's Ctrl+g) hand to $EDITOR and read
--- back when it exits, so the caller has to wait for the edit.
---@param argv string[]
---@return boolean
local function edits_temp_file(argv)
  local temp = vim.fs.normalize(vim.env.TEMP or vim.env.TMPDIR or "/tmp"):lower()
  for i = 2, #argv do
    local arg = argv[i]
    if not arg:match("^[-+]") and vim.startswith(vim.fs.normalize(vim.fn.fnamemodify(arg, ":p")):lower(), temp) then
      return true
    end
  end
  return false
end

--- flatten's hooks, wired to toggleterm and Zellij: a float hides while its
--- file is edited, and a blocking edit brings it back when done.
local flatten_opts = function()
  ---@type Terminal?
  local saved_terminal
  local zellij = require("config.zellij")

  return {
    -- The window the terminal was opened from, not the float itself.
    window = { open = "alternate" },
    -- A bare `nvim` in a terminal starts a real nested nvim rather than doing
    -- nothing; with files (or -d, -q) it is flattened.
    nest_if_no_args = true,
    hooks = {
      -- The host: this nvim's parent terminal, or the Zellij tab's editor.
      pipe_path = zellij.pipe_path,
      -- Tells the host which Zellij pane to give focus back to.
      guest_data = zellij.guest_data,
      -- Always hand files over once a host is found (the default nests when
      -- not inside an nvim terminal); no-argument runs still nest.
      should_nest = function()
        return false
      end,
      -- `nvim -b file` waits until the file is closed, like a commit message
      -- does on its own (block_for: gitcommit, gitrebase), and so does an
      -- agent's prompt file.
      should_block = function(argv)
        return vim.tbl_contains(argv, "-b") or edits_temp_file(argv)
      end,

      pre_open = function()
        -- Only if toggleterm is loaded: a plain :terminal has nothing to hide.
        -- include_hidden: the lazygit terminals are `hidden` (kept off <C-\>
        -- and :TermSelect), and get() skips those otherwise.
        local term_module = package.loaded["toggleterm.terminal"]
        local id = term_module and term_module.get_focused_id()
        saved_terminal = id and term_module.get(id, true) or nil
      end,

      post_open = function(ctx)
        -- terminals.hide_focused_float() can't serve here: by now the file's
        -- window has focus, so the terminal is the one pre_open saved.
        if saved_terminal and (ctx.is_blocking or saved_terminal:is_float()) then
          -- Out of the way while editing; a blocked program (git commit in
          -- lazygit) waits hidden, a non-blocked one keeps running hidden.
          saved_terminal:close()
        end
        if not ctx.is_blocking then
          vim.api.nvim_set_current_win(ctx.winnr)
          saved_terminal = nil
        end

        -- Sent from another Zellij pane: bring this editor's pane forward.
        if type(ctx.data) == "table" and ctx.data.zellij_pane then
          zellij.focus_pane()
        end

        -- A blocking edit (commit or rebase message, an agent's prompt) ends
        -- with :w; the buffer goes so the waiting program carries on (:wq
        -- would try to close the window too).
        if ctx.is_blocking then
          vim.api.nvim_create_autocmd("BufWritePost", {
            buffer = ctx.bufnr,
            once = true,
            callback = vim.schedule_wrap(function()
              if vim.api.nvim_buf_is_valid(ctx.bufnr) then
                vim.api.nvim_buf_delete(ctx.bufnr, {})
              end
            end),
          })
        end
      end,

      block_end = function(ctx)
        -- Back to the program that was waiting for the edit: a toggleterm
        -- float here, or the Zellij pane it runs in.
        vim.schedule(function()
          if saved_terminal then
            saved_terminal:open()
            saved_terminal = nil
          end
          if type(ctx.data) == "table" and ctx.data.zellij_pane then
            zellij.focus_pane(ctx.data.zellij_pane)
          end
        end)
      end,
    },
  }
end

local toggleterm_opts = {
  -- <C-\> toggles the last terminal, from normal and terminal mode; a count
  -- picks another (2<C-\>). <C-|> still leaves terminal mode (keymaps.lua).
  open_mapping = [[<C-\>]],
  direction = "float",
  -- pwsh with its profile (fzf key bindings, sf, sg, y, lg) on Windows. nvim's
  -- own 'shell' stays cmd.exe: toggleterm starts every terminal through it,
  -- and plugins calling vim.fn.system() expect it.
  shell = vim.fn.has("win32") == 1 and "pwsh -NoLogo" or vim.o.shell,
  shade_terminals = false,
  start_in_insert = true,
  persist_mode = false,
  float_opts = {
    -- Shared with the yazi float (plugins/file-explorer.lua).
    border = terminals.float_border,
    width = terminals.float_width,
    row = 1,
    height = terminals.float_height,
    title_pos = "center",
  },
  size = function(term)
    if term.direction == "horizontal" then
      return math.floor(vim.o.lines * 0.35)
    end
    return math.floor(vim.o.columns * 0.4)
  end,
  on_open = terminals.on_open,
}

return {
  {
    "willothy/flatten.nvim",
    -- Before everything else: in a nested nvim, flatten hands the files over
    -- and exits, so the less that loads first the faster that is.
    lazy = false,
    priority = 1001,
    -- :QuickfixLoad, which the shells' `sg` sends here for several hits.
    init = terminals.create_commands,
    opts = flatten_opts,
  },
  {
    "akinsho/toggleterm.nvim",
    cmd = { "ToggleTerm", "TermExec", "TermSelect", "ToggleTermToggleAll" },
    keys = vim.list_extend(vim.deepcopy(require("config.keymaps").toggleterm), require("config.keymaps").lazygit),
    opts = toggleterm_opts,
  },
}
