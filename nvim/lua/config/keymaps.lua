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

    -- keep cursor in the middle of the buffer vertically and unfold (zv) if there is a fold
    vim.keymap.set("n", "n", "nzzzv", { desc = "Go to next coincidence" })
    vim.keymap.set("n", "N", "Nzzzv", { desc = "Go to previous coincidence" })

    -- Indent while remaining in visual mode
    vim.keymap.set("x", "<", "<gv", { desc = "Indent backwards" })
    vim.keymap.set("x", ">", ">gv", { desc = "Indent forward" })

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
    vim.keymap.set({ "n", "x" }, "<leader>fl", function()
      vim.lsp.buf.format({ async = true })
    end, { desc = "Format document using LSP" })

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
    {
      -- Open in the current working directory
      "<leader>e",
      "<cmd>Yazi<cr>",
      desc = "Open the file manager in nvim's working directory",
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

  neogit = {
    {
      "<leader>gg",
      function()
        require("neogit").open()
      end,
      desc = "Git status open",
    },
  },

  fzf = {
    {
      "<leader>sf",
      function()
        require("fzf-lua").files()
      end,
      desc = "Search files",
    },
    {
      "<leader>sr",
      function()
        require("fzf-lua").oldfiles({ cwd_only = true, include_current_session = true })
      end,
      desc = "Search recent files (current working directory only)",
    },
    {
      "<leader>si",
      function()
        require("fzf-lua").git_files()
      end,
      desc = "Search git files",
    },
    {
      "<leader>sg",
      function()
        require("fzf-lua").live_grep()
      end,
      desc = "Search by grep",
    },
    {
      "<leader>sw",
      function()
        require("fzf-lua").grep_cword()
      end,
      desc = "Search current word",
    },
    {
      "<leader>sw",
      function()
        require("fzf-lua").grep_visual()
      end,
      mode = "x",
      desc = "Search current selection",
    },
    {
      "<leader>sb",
      function()
        require("fzf-lua").buffers()
      end,
      desc = "Search buffers",
    },
    {
      "<leader>so",
      function()
        require("fzf-lua").lsp_workspace_symbols()
      end,
      desc = "Search workspace symbols",
    },
    {
      "gd",
      function()
        require("fzf-lua").lsp_definitions()
      end,
      desc = "Go to definition",
    },
    {
      "gD",
      function()
        require("fzf-lua").lsp_declarations()
      end,
      desc = "Go to declaration",
    },
    {
      "gi",
      function()
        require("fzf-lua").lsp_implementations()
      end,
      desc = "Go to implementation",
    },
    {
      "go",
      function()
        require("fzf-lua").lsp_typedefs()
      end,
      desc = "Go to definition of the type",
    },
    {
      "gr",
      function()
        require("fzf-lua").lsp_references()
      end,
      desc = "Go to references",
    },
    {
      "<leader>va",
      function()
        require("fzf-lua").lsp_code_actions()
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
