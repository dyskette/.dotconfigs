return {
  -- Also check ":help normal-index" and ":help visual-index" for default key mappings
  vanilla = function()
    vim.g.mapleader = " "

    vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
    vim.keymap.set({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })

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

    -- keep cursor in the middle of the buffer vertically and unfold (zv) if there is a fold
    vim.keymap.set("n", "n", "nzzzv", { desc = "Go to next coincidence" })
    vim.keymap.set("n", "N", "Nzzzv", { desc = "Go to previous coincidence" })

    -- Indent while remaining in visual mode
    vim.keymap.set("x", "<", "<gv", { desc = "Indent backwards" })
    vim.keymap.set("x", ">", ">gv", { desc = "Indent forward" })

    -- Terminal
    vim.keymap.set("t", "<C-|>", "<C-\\><C-n>", { desc = "Exit terminal", noremap = true })

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
      vim.lsp.buf.hover({ border = "rounded", title = " Information " })
    end, { desc = "Open symbol information" })
    vim.keymap.set({ "n", "x" }, "<leader>fl", function()
      vim.lsp.buf.format({ async = true })
    end, { desc = "Format document using LSP" })
    vim.keymap.set({ "n", "x" }, "<leader>va", function()
      vim.lsp.buf.code_action()
    end, { desc = "View LSP code actions" })

    -- Diagnostic
    vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, { desc = "View diagnostic" })
    vim.keymap.set("n", "<leader>dk", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, { desc = "Previous diagnostic" })
    vim.keymap.set("n", "<leader>dj", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, { desc = "Next diagnostic" })
  end,

  telescope = {
    {
      "<leader>sf",
      function()
        require("telescope.builtin").find_files()
      end,
      desc = "Search files",
    },
    {
      "<leader>sr",
      function()
        require("telescope.builtin").oldfiles({ only_cwd = true })
      end,
      desc = "Search recent files (current working directory only)",
    },
    {
      "<leader>si",
      function()
        require("telescope.builtin").git_files()
      end,
      desc = "Search git files",
    },
    {
      "<leader>sg",
      function()
        require("telescope.builtin").live_grep()
      end,
      desc = "Search by grep",
    },
    {
      "<leader>sw",
      function()
        require("telescope.builtin").grep_string()
      end,
      desc = "Search current word",
    },
    {
      "<leader>sw",
      function()
        -- Extracts the currently selected text in visual mode for telescope search.
        -- Uses vim marks: '.' (cursor position) and 'v' (visual selection start)
        -- to determine selection boundaries, then extracts the text with getregion().
        local function get_visual_selection()
          local cursor_mark = "."
          local visual_start_mark = "v"
          local cursor_position = vim.fn.getpos(cursor_mark)
          local visual_start_position = vim.fn.getpos(visual_start_mark)
          local region_text = vim.fn.getregion(cursor_position, visual_start_position)

          return region_text[1]
        end

        require("telescope.builtin").grep_string({ search = get_visual_selection() })
      end,
      mode = "x",
      desc = "Search current selection",
    },
    {
      "<leader>sb",
      function()
        require("telescope.builtin").buffers()
      end,
      desc = "Search buffers",
    },
    {
      "<leader>so",
      function()
        require("telescope.builtin").lsp_workspace_symbols()
      end,
      desc = "Search workspace symbols",
    },
    {
      "gd",
      function()
        require("telescope.builtin").lsp_definitions()
      end,
      desc = "Go to definition",
    },
    {
      "gD",
      function()
        require("telescope.builtin").lsp_declarations()
      end,
      desc = "Go to declaration",
    },
    {
      "gi",
      function()
        require("telescope.builtin").lsp_implementations()
      end,
      desc = "Go to implementation",
    },
    {
      "go",
      function()
        require("telescope.builtin").lsp_typedefs()
      end,
      desc = "Go to definition of the type",
    },
    {
      "gr",
      function()
        require("telescope.builtin").lsp_references()
      end,
      desc = "Go to references",
    },
  },

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
        require("conform").format({ async = true, lsp_format = "fallback" })
      end,
      mode = { "n", "x" },
      desc = "Format buffer using conform",
    },
  },

  oil = {
    { "-", vim.cmd.Oil, desc = "Open parent directory" },
  },

  yazi = {
    { "<leader>e", vim.cmd.Yazi, mode = { "n", "x" }, desc = "Open parent directory" },
  },

  imgclip = {
    {
      "<leader>ii",
      function()
        require("img-clip").pasteImage()
      end,
      mode = { "n", "x" },
      desc = "Paste image from clipbard",
    },
  },

  dap = {
    {
      "<leader>di",
      function()
        require("dapui").eval(nil, { enter = true })
      end,
      desc = "Debug inspect value",
    },
    {
      "<F5>",
      function()
        require("dap").continue()
      end,
      desc = "Debug start or continue",
    },
    {
      "<S-F5>",
      function()
        require("dap").terminate()
      end,
      desc = "Terminate the debug session",
    },
    {
      "<F9>",
      function()
        require("dap").toggle_breakpoint()
      end,
      desc = "Debug toggle breakpoint",
    },
    {
      "<F10>",
      function()
        require("dap").step_over()
      end,
      desc = "Debug step over",
    },
    {
      "<F11>",
      function()
        require("dap").step_into()
      end,
      desc = "Debug step into",
    },
    {
      "<F12>",
      function()
        require("dap").step_out()
      end,
      desc = "Debug step out",
    },
    {
      "<Leader>dw",
      function()
        require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
      end,
      desc = "Debug write output message",
    },
    {
      "<Leader>dr",
      function()
        require("dap").repl.open()
      end,
      desc = "Debug, use REPL to evaluate sentences",
    },
    {
      "<Leader>dl",
      function()
        require("dap").run_last()
      end,
      desc = "Debug run the last session again",
    },
    {
      "<Leader>dh",
      function()
        require("dap.ui.widgets").hover()
      end,
      mode = { "n", "v" },
      desc = "Debug evaluate expression and display in floating window",
    },
    {
      "<Leader>dp",
      function()
        require("dap.ui.widgets").preview()
      end,
      mode = { "n", "v" },
      desc = "Debug evaluate expression and display in preview window",
    },
    {
      "<Leader>df",
      function()
        require("dap.ui.widgets").centered_float(require("dap.ui.widgets").frames)
      end,
      desc = "Debug show the stack frames in a floating window",
    },
    {
      "<Leader>ds",
      function()
        require("dap.ui.widgets").centered_float(require("dap.ui.widgets").scopes)
      end,
      desc = "Debug show the variables of current scope in a floating window",
    },
  },

  git_diffview = function()
    vim.keymap.set("n", "<leader>gh", function()
      if next(require("diffview.lib").views) == nil then
        vim.cmd.DiffviewFileHistory('"' .. vim.api.nvim_buf_get_name(0) .. '"')
      else
        vim.cmd.DiffviewClose()
      end
    end, { desc = "Git file history (current buffer)" })
    vim.keymap.set("n", "<leader>gd", function()
      if next(require("diffview.lib").views) == nil then
        vim.cmd.DiffviewOpen()
      else
        vim.cmd.DiffviewClose()
      end
    end, { desc = "Git diff open" })
  end,

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
  },

  neogit = {
    {
      "<leader>gg",
      function()
        require("neogit").open()
      end,
      desc = "Git status open",
    },
  },

  smart_splits = {
    {
      "<A-h>",
      function()
        require("smart-splits").resize_left()
      end,
      desc = "Resize split left",
    },
    {
      "<A-j>",
      function()
        require("smart-splits").resize_down()
      end,
      desc = "Resize split down",
    },
    {
      "<A-k>",
      function()
        require("smart-splits").resize_up()
      end,
      desc = "Resize split up",
    },
    {
      "<A-l>",
      function()
        require("smart-splits").resize_right()
      end,
      desc = "Resize split right",
    },
    {
      "<C-h>",
      function()
        require("smart-splits").move_cursor_left()
      end,
      desc = "Navigate left (tmux/vim)",
    },
    {
      "<C-j>",
      function()
        require("smart-splits").move_cursor_down()
      end,
      desc = "Navigate down (tmux/vim)",
    },
    {
      "<C-k>",
      function()
        require("smart-splits").move_cursor_up()
      end,
      desc = "Navigate up (tmux/vim)",
    },
    {
      "<C-l>",
      function()
        require("smart-splits").move_cursor_right()
      end,
      desc = "Navigate right (tmux/vim)",
    },
    {
      "<C-\\>",
      function()
        require("smart-splits").move_cursor_previous()
      end,
      desc = "Navigate to previous (tmux/vim)",
    },
    {
      "<leader><leader>h",
      function()
        require("smart-splits").swap_buf_left()
      end,
      desc = "Swap buffer left",
    },
    {
      "<leader><leader>j",
      function()
        require("smart-splits").swap_buf_down()
      end,
      desc = "Swap buffer down",
    },
    {
      "<leader><leader>k",
      function()
        require("smart-splits").swap_buf_up()
      end,
      desc = "Swap buffer up",
    },
    {
      "<leader><leader>l",
      function()
        require("smart-splits").swap_buf_right()
      end,
      desc = "Swap buffer right",
    },
  },
}
