-- Markdown Preview Language Server (mpls) configuration
-- Uses vim.lsp.config() API (Neovim 0.11+)

-- Build mpls command with current theme
-- Note: older mpls versions use --dark-mode flag instead of --theme
local function get_mpls_cmd()
  local cmd = {
    "mpls",
    "--enable-emoji",
    "--enable-footnotes",
  }

  if vim.o.background == "dark" then
    table.insert(cmd, "--dark-mode")
  end

  return cmd
end

local function setup_mpls()
  vim.lsp.config.mpls = {
    cmd = get_mpls_cmd(),
    filetypes = { "markdown", "markdown.mdx" },
    root_markers = { ".marksman.toml", ".git" },
    on_attach = function(client, bufnr)
      vim.api.nvim_buf_create_user_command(bufnr, "MplsOpenPreview", function()
        local params = {
          command = "open-preview",
        }
        client:request("workspace/executeCommand", params, function(err, _)
          if err then
            vim.notify("Error executing command: " .. err.message, vim.log.levels.ERROR)
          else
            vim.notify("Preview opened", vim.log.levels.INFO)
          end
        end)
      end, {
        desc = "Preview markdown with mpls",
      })

      -- Setup keymaps for this buffer
      require("config.keymaps").mpls()
    end,
  }

  vim.lsp.enable("mpls")
end

-- Restart mpls with new theme when colorscheme changes
local function setup_mpls_theme_sync()
  local group = vim.api.nvim_create_augroup("MplsThemeSync", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "Restart mpls LSP with matching theme on colorscheme change",
    callback = function()
      local clients = vim.lsp.get_clients({ name = "mpls" })
      if #clients == 0 then
        return
      end

      -- Update the config with new theme
      vim.lsp.config.mpls.cmd = get_mpls_cmd()

      -- Restart mpls clients
      for _, client in ipairs(clients) do
        local attached_buffers = vim.lsp.get_buffers_by_client_id(client.id)
        client:stop()

        -- Re-attach to buffers after a short delay
        vim.defer_fn(function()
          for _, bufnr in ipairs(attached_buffers) do
            if vim.api.nvim_buf_is_valid(bufnr) then
              vim.lsp.buf_attach_client(bufnr, vim.lsp.start(vim.lsp.config.mpls))
            end
          end
        end, 500)
      end
    end,
  })
end

-- Debounced mpls focus handler for automatic preview updates
local function create_debounced_mpls_sender(delay)
  delay = delay or 300
  local timer = nil

  return function()
    if timer then
      timer:close()
      timer = nil
    end

    ---@diagnostic disable-next-line: undefined-field
    timer = vim.uv.new_timer()
    if not timer then
      vim.notify("Failed to create timer for MPLS focus", vim.log.levels.ERROR)
      return
    end

    timer:start(
      delay,
      0,
      vim.schedule_wrap(function()
        local bufnr = vim.api.nvim_get_current_buf()

        local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
        if filetype ~= "markdown" then
          return
        end

        local clients = vim.lsp.get_clients({ name = "mpls" })

        if #clients == 0 then
          return
        end

        local client = clients[1]
        local params = { uri = vim.uri_from_bufnr(bufnr) }

        ---@diagnostic disable-next-line: param-type-mismatch
        client:notify("mpls/editorDidChangeFocus", params)

        if timer then
          timer:close()
          timer = nil
        end
      end)
    )
  end
end

-- Setup mpls focus tracking for automatic preview updates on buffer change
local function setup_mpls_focus_tracking()
  local send_mpls_focus = create_debounced_mpls_sender(300)

  local group = vim.api.nvim_create_augroup("MplsFocus", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*.md",
    callback = send_mpls_focus,
    group = group,
    desc = "Notify MPLS of buffer focus changes",
  })
end

-- Run mpls setup immediately (uses native vim.lsp API, not lspconfig)
setup_mpls()
setup_mpls_focus_tracking()
setup_mpls_theme_sync()

return {
  -- Paste image as a file in cwd/assets/ and get the path
  {
    "HakonHarnes/img-clip.nvim",
    keys = require("config.keymaps").imgclip,
    ft = { "markdown" },
  },
}
