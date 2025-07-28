return {
  -- Also check ":help normal-index" and ":help visual-index" for default key mappings
  vanilla = function()
    vim.g.mapleader = " "

    -- Clipboard
    vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
    vim.keymap.set({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })

    -- Selection
    vim.keymap.set("n", "<leader>a", ":keepjumps normal! ggVG<cr>", { desc = "Select all text in buffer" })

    -- Moving text
    vim.keymap.set("x", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up in visual mode" })
    vim.keymap.set("x", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down in visual mode" })

    -- keep cursor in the middle of the buffer vertically and unfold (zv) if there is a fold
    vim.keymap.set("n", "n", "nzzzv", { desc = "Go to next coincidence" })
    vim.keymap.set("n", "N", "Nzzzv", { desc = "Go to previous coincidence" })

    -- Indent while remaining in visual mode
    vim.keymap.set("x", "<", "<gv", { desc = "Indent backwards" })
    vim.keymap.set("x", ">", ">gv", { desc = "Indent forward" })

    -- Terminal
    vim.keymap.set("t", "<C-|><C-n>", "<C-\\><C-n>", { desc = "Exit terminal", noremap = true })

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

    -- Diagnostics

    vim.keymap.set("n", "<leader>va", vim.lsp.buf.code_action, { desc = "View actions for diagnostics" })
    vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, { desc = "View diagnostic" })
    vim.keymap.set("n", "<leader>dk", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, { desc = "Previous diagnostic" })
    vim.keymap.set("n", "<leader>dj", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, { desc = "Next diagnostic" })
  end,

  telescope = {
    { "<leader>sf", "<cmd>Telescope find_files<cr>", desc = "Search files" },
    {
      "<leader>sr",
      "<cmd>lua require('telescope.builtin').oldfiles({ only_cwd = true })<cr>",
      desc = "Search recent files",
    },
    { "<leader>si", "<cmd>Telescope git_files<cr>", desc = "Search git files" },
    { "<leader>sg", "<cmd>Telescope live_grep<cr>", desc = "Search by grep" },
    { "<leader>sw", "<cmd>Telescope grep_string<cr>", desc = "Search help", mode = { "n", "x" } },
    { "<leader>sb", "<cmd>Telescope buffers<cr>", desc = "Search buffers" },
    { "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Search help" },
    { "<leader>so", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Search help" },

    { "gd", "<cmd>Telescope lsp_definitions<cr>", desc = "Search definitions" },
    { "gi", "<cmd>Telescope lsp_implementations<cr>", desc = "Search implementations" },
    { "go", "<cmd>Telescope lsp_type_definitions<cr>", desc = "Search type definitions" },
    { "gr", "<cmd>Telescope lsp_references<cr>", desc = "Search references" },
  },

  live_rename = {
    { "<leader>rn", "<cmd>lua require('live-rename').rename()<cr>", desc = "Rename symbol" },
  },

  lsp = function(client, buffer)
    local fzf = require("fzf-lua")
    local live_rename = require("live-rename")

    local opts = function(description)
      return {
        buffer = buffer,
        desc = description,
        silent = true,
      }
    end

    vim.keymap.set("n", "K", function()
      print("Executing hover...")
      vim.lsp.buf.hover({ border = "rounded", title = " Information " })
    end, opts("Open symbol information"))
    vim.keymap.set("n", "<leader>rn", live_rename.rename, opts("Rename symbol"))
    vim.keymap.set({ "n", "x" }, "<leader>fl", function()
      vim.lsp.buf.format({ async = true })
    end, opts("Format document using LSP"))

    vim.keymap.set("n", "gd", fzf.lsp_definitions, opts("Go to definition"))
    vim.keymap.set("n", "gD", fzf.lsp_declarations, opts("Go to declaration"))
    vim.keymap.set("n", "gi", fzf.lsp_implementations, opts("Go to implementation"))
    vim.keymap.set("n", "go", fzf.lsp_typedefs, opts("Go to definition of the type"))
    vim.keymap.set("n", "gr", fzf.lsp_references, opts("Go to references"))
    vim.keymap.set("n", "<leader>so", fzf.lsp_workspace_symbols, { desc = "Search symbols" })
    vim.keymap.set({ "n", "x" }, "<leader>va", fzf.lsp_code_actions, opts("View code action"))

    vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts("View diagnostic"))
    vim.keymap.set("n", "<leader>dk", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, opts("Previous diagnostic"))
    vim.keymap.set("n", "<leader>dj", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, opts("Next diagnostic"))
  end,

  conform = {
    {
      "<leader>ff",
      "<cmd>lua require('conform').format({ async = true, lsp_format = 'fallback' })<cr>",
      desc = "Format buffer",
    },
  },

  imgclip = function()
    local imgclip = require("img-clip")
    vim.keymap.set({ "n", "x" }, "<leader>ii", imgclip.pasteImage, { desc = "Paste image from clipbard" })
  end,

  dap = {
    -- Debugging keymaps using <cmd>
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
      "<leader>di",
      function()
        require("dapui").eval(nil, { enter = true })
      end,
      desc = "Debug inspect value",
    },
    {
      "<leader>dw",
      function()
        require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
      end,
      desc = "Debug write output message",
    },
    {
      "<leader>dr",
      function()
        require("dap").repl.open()
      end,
      desc = "Debug, use REPL to evaluate sentences",
    },
    {
      "<leader>dl",
      function()
        require("dap").run_last()
      end,
      desc = "Debug run the last session again",
    },
    {
      "<leader>dh",
      function()
        require("dap.ui.widgets").hover()
      end,
      mode = { "n", "v" },
      desc = "Debug evaluate expression and display in floating window",
    },
    {
      "<leader>dp",
      function()
        require("dap.ui.widgets").preview()
      end,
      mode = { "n", "v" },
      desc = "Debug evaluate expression and display in preview window",
    },
    {
      "<leader>df",
      function()
        require("dap.ui.widgets").centered_float(require("dap.ui.widgets").frames)
      end,
      desc = "Debug show the stack frames in a floating window",
    },
    {
      "<leader>ds",
      function()
        require("dap.ui.widgets").centered_float(require("dap.ui.widgets").scopes)
      end,
      desc = "Debug show the variables of current scope in a floating window",
    },
  },

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
      desc = "Git: File history (current buffer)",
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
      desc = "Git: Toggle diff view",
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
  },

  neogit = {
    { "<leader>gg", "<cmd>Neogit<cr>", desc = "Open git status" },
  },
}
