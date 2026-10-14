local mason_cmd = require("config.mason_cmd")

-- Formatting prefers the language servers that are already running over
-- starting a formatter process per format: ruff for python, and the json and
-- yaml servers (yaml-language-server bundles prettier, so its output is
-- prettier's). The rest run as programs.

--- Organize imports through the ruff server attached to the buffer: its
--- `source.organizeImports.ruff` code action, which is what `ruff check
--- --select I --fix` does, without starting ruff.
---
--- conform hands a formatter the buffer's lines and expects the new lines
--- back, so the action's edits are applied to a scratch copy rather than the
--- buffer; conform then applies the difference itself, and runs the server's
--- formatting after it (lsp_format = "last").
local ruff_organize_imports_lsp = {
  meta = {
    url = "https://docs.astral.sh/ruff/editors/features/",
    description = "Organize imports through the attached ruff language server.",
  },
  condition = function(_, ctx)
    return #vim.lsp.get_clients({ bufnr = ctx.buf, name = "ruff" }) > 0
  end,
  format = function(_, ctx, lines, callback)
    local client = vim.lsp.get_clients({ bufnr = ctx.buf, name = "ruff" })[1]
    local uri = vim.uri_from_bufnr(ctx.buf)
    local params = {
      textDocument = { uri = uri },
      range = { start = { line = 0, character = 0 }, ["end"] = { line = #lines, character = 0 } },
      context = { only = { "source.organizeImports.ruff" }, diagnostics = {} },
    }

    local apply = function(action)
      local edit = action and action.edit
      local edits = edit and edit.changes and edit.changes[uri] or {}
      for _, change in ipairs(edit and edit.documentChanges or {}) do
        if change.textDocument and change.textDocument.uri == uri then
          vim.list_extend(edits, change.edits)
        end
      end
      if #edits == 0 then
        return callback(nil, lines)
      end
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
      vim.lsp.util.apply_text_edits(edits, scratch, client.offset_encoding)
      local result = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
      vim.api.nvim_buf_delete(scratch, { force = true })
      callback(nil, result)
    end

    client:request("textDocument/codeAction", params, function(err, actions)
      if err then
        return callback(err.message)
      end
      local action = actions and actions[1]
      if action and not action.edit and client:supports_method("codeAction/resolve") then
        client:request("codeAction/resolve", action, function(resolve_err, resolved)
          if resolve_err then
            return callback(resolve_err.message)
          end
          apply(resolved)
        end, ctx.buf)
      else
        apply(action)
      end
    end, ctx.buf)
  end,
}

--- conform's formatter overrides that start mason tools without their
--- Windows shim (see config/mason_cmd.lua): the program, and for node tools
--- node with the script, ahead of the formatter's own arguments. A tool that
--- is not installed keeps conform's default command and its usual error.
--- @param tools table<string, string> conform formatter name -> mason command name
local function direct_commands(tools)
  local formatters = {}
  for formatter, command in pairs(tools) do
    local direct = mason_cmd.resolve(command)
    if direct then
      formatters[formatter] = { command = table.remove(direct, 1), prepend_args = direct }
    end
  end
  return formatters
end

local conform_opts = function()
  local formatters = direct_commands({
    stylua = "stylua",
    beautysh = "beautysh",
    prettier = "prettier",
    sql_formatter = "sql-formatter",
  })
  formatters.ruff_organize_imports_lsp = ruff_organize_imports_lsp
  -- After the script, when sql-formatter runs through node.
  formatters.sql_formatter = formatters.sql_formatter or {}
  formatters.sql_formatter.prepend_args =
    vim.list_extend(formatters.sql_formatter.prepend_args or {}, { "-l", "postgresql" })

  return {
    -- A default rather than an argument of the format() call, as a call
    -- argument would override the per-filetype lsp_format below.
    default_format_opts = { lsp_format = "fallback" },
    formatters_by_ft = {
      lua = { "stylua" },
      sh = { "beautysh" },
      python = { "ruff_organize_imports_lsp", lsp_format = "last" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      svelte = { "prettier" },
      vue = { "prettier" },
      css = { "prettier" },
      html = { "prettier" },
      json = { lsp_format = "prefer" },
      yaml = { lsp_format = "prefer" },
      markdown = { "prettier" },
      sql = { "sql_formatter" },
    },
    formatters = formatters,
  }
end

-- No nvim-lint: every linter it ran is covered by a language server now (ruff
-- for python, eslint-lsp for javascript), which publish diagnostics live
-- rather than on read and write. Add it back with a linters_by_ft entry if a
-- language ever needs a linter that has no server.
return {
  {
    "stevearc/conform.nvim",
    opts = conform_opts,
    keys = require("config.keymaps").conform,
  },
}
