return {
  -- Also check ":help normal-index" and ":help visual-index" for default key mappings
  vanilla = function()
    vim.g.mapleader = " "

    vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
    vim.keymap.set({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })

    vim.keymap.set("n", "<leader>yl", function()
      local path = vim.fn.expand("%:.")
      local line = vim.fn.line(".")
      local location = path .. ":" .. line
      vim.fn.setreg("+", location)
      vim.notify("Copied: " .. location)
    end, { desc = "Copy file:line location to clipboard" })

    vim.keymap.set("x", "<leader>yl", function()
      local path = vim.fn.expand("%:.")
      local start_line = vim.fn.line("v")
      local end_line = vim.fn.line(".")
      if start_line > end_line then
        start_line, end_line = end_line, start_line
      end
      local location = path .. ":" .. start_line .. "-" .. end_line
      vim.fn.setreg("+", location)
      vim.notify("Copied: " .. location)
    end, { desc = "Copy file:line range to clipboard" })

    vim.keymap.set("n", "<leader>a", ":keepjumps normal! ggVG<cr>", { desc = "Select all text in buffer" })

    vim.keymap.set("x", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up in visual mode" })
    vim.keymap.set("x", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down in visual mode" })

    vim.keymap.set(
      "n",
      "<leader>O",
      '<Cmd>call append(line(".") - 1, repeat([""], v:count1))<CR>',
      { desc = "Append a new line without entering insert mode" }
    )
    vim.keymap.set(
      "n",
      "<leader>o",
      '<Cmd>call append(line("."),     repeat([""], v:count1))<CR>',
      { desc = "Append a new line without entering insert mode" }
    )

    -- Indent while remaining in visual mode
    vim.keymap.set("x", "<", "<gv", { desc = "Indent backwards" })
    vim.keymap.set("x", ">", ">gv", { desc = "Indent forward" })

    -- keep cursor in the middle of the buffer vertically and unfold (zv) if there is a fold
    vim.keymap.set("n", "n", "nzzzv", { desc = "Go to next coincidence" })
    vim.keymap.set("n", "N", "Nzzzv", { desc = "Go to previous coincidence" })

    -- Window resizing on the native <C-w> keys, made repeatable like tmux's
    -- `bind-key -r`: after <C-w>> (or <, +, -), further >, <, + and - keep
    -- resizing without <C-w>. Any other key ends it and is handled as usual;
    -- there is no timeout, so pausing does not drop out of it. Each step is 5
    -- columns or 2 rows instead of the native 1, or the count when one is given.
    local resize_steps = {
      [">"] = { cmd = "vertical resize +", step = 5 },
      ["<"] = { cmd = "vertical resize -", step = 5 },
      ["+"] = { cmd = "resize +", step = 2 },
      ["-"] = { cmd = "resize -", step = 2 },
    }
    local function resize_mode(key, count)
      while resize_steps[key] do
        vim.cmd(resize_steps[key].cmd .. (count or resize_steps[key].step))
        vim.cmd.redraw()
        vim.api.nvim_echo({ { "-- RESIZE --  > < wider/narrower, + - taller/shorter, any other key ends", "ModeMsg" } }, false, {})
        local ok, next_key = pcall(vim.fn.getcharstr)
        key = ok and next_key or nil
      end
      vim.api.nvim_echo({ { "" } }, false, {})
      -- Hand the ending key back unless it was only meant to end the mode.
      if key and key ~= "\27" then
        vim.api.nvim_feedkeys(key, "m", false)
      end
    end
    for key, def in pairs(resize_steps) do
      vim.keymap.set("n", "<C-w>" .. key, function()
        resize_mode(key, vim.v.count > 0 and vim.v.count or nil)
      end, { desc = "Resize window (" .. def.cmd .. def.step .. "), repeat with " .. key })
    end

    -- Terminal
    vim.keymap.set("t", "<C-|>", "<C-\\><C-n>", { desc = "Exit terminal", noremap = true })
    vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Move to left window from terminal" })
    vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Move to bottom window from terminal" })
    vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Move to top window from terminal" })
    vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Move to right window from terminal" })

    -- Quickfix
    local function toggle_quickfix()
      local wins = vim.fn.getwininfo()
      local qf_win = vim
        .iter(wins)
        :filter(function(win)
          return win.quickfix == 1
        end)
        :totable()
      if #qf_win == 0 then
        vim.cmd.copen()
      else
        vim.cmd.cclose()
      end
    end
    vim.keymap.set("n", "<leader>q", toggle_quickfix, { desc = "Toggle quickfix" })

    -- LSP
    vim.keymap.set("n", "K", function()
      vim.lsp.buf.hover({ border = "single", title = " Information " })
    end, { desc = "Open symbol information" })
    vim.keymap.set("n", "<leader>uh", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
    end, { desc = "Toggle inlay hints" })
    vim.keymap.set("n", "<leader>vl", vim.lsp.codelens.run, { desc = "Run the code lens on this line" })

    -- Diagnostic
    vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, { desc = "View diagnostic" })
    vim.keymap.set("n", "<leader>dk", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, { desc = "Previous diagnostic" })
    vim.keymap.set("n", "<leader>dj", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, { desc = "Next diagnostic" })
  end,

  live_rename = {
    {
      "<leader>rn",
      function()
        require("live-rename").rename()
      end,
      desc = "Rename symbol",
    },
  },

  conform = {
    {
      "<leader>ff",
      function()
        require("conform").format({ async = true })
      end,
      mode = { "n", "x" },
      desc = "Format buffer using conform",
    },
  },

  oil = {
    { "-", vim.cmd.Oil, desc = "Open parent directory" },
  },

  yazi = {
    {
      -- Open in the current working directory
      "<leader>e",
      "<cmd>Yazi<cr>",
      desc = "Open the file manager in nvim's working directory",
    },
  },

  -- Each key closes the diffview that is open, if any, instead of opening another.
  git_diffview = {
    {
      "<leader>gh",
      function()
        if next(require("diffview.lib").views) == nil then
          vim.cmd.DiffviewFileHistory('"' .. vim.api.nvim_buf_get_name(0) .. '"')
        else
          vim.cmd.DiffviewClose()
        end
      end,
      desc = "Git file history (current buffer)",
    },
    {
      "<leader>gd",
      function()
        if next(require("diffview.lib").views) == nil then
          vim.cmd.DiffviewOpen()
        else
          vim.cmd.DiffviewClose()
        end
      end,
      desc = "Git diff open",
    },
  },

  gitsigns = {
    {
      "<leader>gb",
      function()
        local blame_buffer = nil
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_get_option_value("filetype", { buf = bufnr }) == "gitsigns-blame" then
            blame_buffer = bufnr
            break
          end
        end

        if blame_buffer ~= nil then
          vim.api.nvim_buf_delete(blame_buffer, {})
        else
          require("gitsigns").blame()
        end
      end,
      desc = "Show git blame",
    },
    {
      "<leader>gs",
      function()
        require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end,
      mode = { "x" },
      desc = "Stage hunk",
    },
    {
      "<leader>gs",
      function()
        require("gitsigns").stage_hunk()
      end,
      mode = { "n" },
      desc = "Stage hunk",
    },
    {
      "<leader>gx",
      function()
        require("gitsigns").reset_hunk()
      end,
      mode = { "n" },
      desc = "Reset hunk",
    },
    {
      "<leader>gx",
      function()
        require("gitsigns").reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end,
      mode = { "x" },
      desc = "Reset hunk",
    },
    {
      "<leader>gS",
      function()
        require("gitsigns").stage_buffer()
      end,
      desc = "Stage buffer",
    },
    {
      "<leader>gX",
      function()
        require("gitsigns").reset_buffer()
      end,
      desc = "Reset buffer",
    },
  },

  treesitter_context = {
    {
      -- Not "[c" (the plugin's example): that is the built-in previous-change
      -- motion in diff mode, which diffview relies on.
      "[x",
      function()
        require("treesitter-context").go_to_context(vim.v.count1)
      end,
      desc = "Go to context (enclosing scope)",
    },
  },

  -- Loaded with toggleterm.nvim (plugins/terminal.lua).
  lazygit = {
    {
      "<leader>gg",
      function()
        require("config.terminals").lazygit()
      end,
      desc = "lazygit (toggle)",
    },
    {
      "<leader>gl",
      function()
        require("config.terminals").lazygit_file()
      end,
      desc = "lazygit: commits touching this file",
    },
  },

  toggleterm = {
    -- No action: loads toggleterm, whose open_mapping then handles the key.
    { [[<C-\>]], mode = { "n", "t" }, desc = "Toggle terminal" },
    { "<leader>tf", "<cmd>ToggleTerm direction=float<cr>", desc = "Terminal (float)" },
    { "<leader>th", "<cmd>ToggleTerm direction=horizontal<cr>", desc = "Terminal (below)" },
    { "<leader>tv", "<cmd>ToggleTerm direction=vertical<cr>", desc = "Terminal (right)" },
    { "<leader>ts", "<cmd>TermSelect<cr>", desc = "Pick a terminal" },
  },

  picker = {
    {
      "<leader>sf",
      function()
        Snacks.picker.files()
      end,
      desc = "Search files",
    },
    {
      "<leader>sr",
      function()
        Snacks.picker.recent({ filter = { cwd = true } })
      end,
      desc = "Search recent files (current working directory only)",
    },
    {
      "<leader>si",
      function()
        Snacks.picker.git_files()
      end,
      desc = "Search git files",
    },
    {
      "<leader>sg",
      function()
        Snacks.picker.grep()
      end,
      desc = "Search by grep",
    },
    {
      "<leader>sw",
      function()
        Snacks.picker.grep_word()
      end,
      desc = "Search current word",
    },
    {
      "<leader>sw",
      function()
        Snacks.picker.grep_word()
      end,
      mode = "x",
      desc = "Search current selection",
    },
    {
      "<leader>sb",
      function()
        Snacks.picker.buffers()
      end,
      desc = "Search buffers",
    },
    {
      "<leader>so",
      function()
        Snacks.picker.lsp_workspace_symbols()
      end,
      desc = "Search workspace symbols",
    },
    {
      "<leader>s.",
      function()
        Snacks.picker.resume()
      end,
      desc = "Resume the last search",
    },
    {
      "<leader>sd",
      function()
        Snacks.picker.diagnostics()
      end,
      desc = "Search diagnostics",
    },
    {
      "<leader>sh",
      function()
        Snacks.picker.help()
      end,
      desc = "Search help",
    },
    {
      "<leader>sk",
      function()
        Snacks.picker.keymaps()
      end,
      desc = "Search keymaps",
    },
    {
      "<leader>s:",
      function()
        Snacks.picker.command_history()
      end,
      desc = "Search command history",
    },
    {
      "<leader>gB",
      function()
        Snacks.picker.git_branches()
      end,
      desc = "Git branches (switch)",
    },
    {
      "gd",
      function()
        Snacks.picker.lsp_definitions()
      end,
      desc = "Go to definition",
    },
    {
      "gD",
      function()
        Snacks.picker.lsp_declarations()
      end,
      desc = "Go to declaration",
    },
    {
      "gi",
      function()
        Snacks.picker.lsp_implementations()
      end,
      desc = "Go to implementation",
    },
    {
      "go",
      function()
        Snacks.picker.lsp_type_definitions()
      end,
      desc = "Go to definition of the type",
    },
    {
      "gr",
      function()
        Snacks.picker.lsp_references()
      end,
      desc = "Go to references",
    },
    {
      "<leader>va",
      function()
        vim.lsp.buf.code_action()
      end,
      mode = { "n", "x" },
      desc = "View LSP code actions",
    },
  },

  trouble = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle<cr>",
      desc = "Diagnostics (Trouble)",
    },
    {
      "<leader>xX",
      "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
      desc = "Buffer Diagnostics (Trouble)",
    },
    {
      "<leader>cs",
      "<cmd>Trouble symbols toggle focus=false<cr>",
      desc = "Symbols (Trouble)",
    },
    {
      "<leader>cl",
      "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
      desc = "LSP Definitions / references / ... (Trouble)",
    },
    {
      "<leader>xL",
      "<cmd>Trouble loclist toggle<cr>",
      desc = "Location List (Trouble)",
    },
    {
      "<leader>xQ",
      "<cmd>Trouble qflist toggle<cr>",
      desc = "Quickfix List (Trouble)",
    },
  },
}
