local utils = require("config.utils")

local conform_opts = {
  formatters_by_ft = {
    lua = { "stylua" },
    sh = { "beautysh" },
    python = { "ruff_organize_imports", "ruff_format" },
    javascript = { "prettier" },
    typescript = { "prettier" },
    javascriptreact = { "prettier" },
    typescriptreact = { "prettier" },
    svelte = { "prettier" },
    vue = { "prettier" },
    css = { "prettier" },
    html = { "prettier" },
    json = { "prettier" },
    yaml = { "prettier" },
    markdown = { "prettier" },
    sql = { "sql_formatter" },
  },
  formatters = {
    sql_formatter = {
      prepend_args = { "-l", "postgresql" },
    },
  },
}

local nvim_lint_config = function()
  local lint = require("lint")

  -- Python is absent on purpose: ruff runs as a language server (see
  -- lspconfig.lua) and publishes its diagnostics live, rather than only on
  -- read and write the way nvim-lint fires. pylint used to live here, and had
  -- to be installed into each project's virtual environment to be found.
  lint.linters_by_ft = {
    -- javascript = { "eslint_d" },
    -- typescript = { "eslint_d" },
    -- javascriptreact = { "eslint_d" },
    -- typescriptreact = { "eslint_d" },
    -- svelte = { "eslint_d" },
  }

  local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

  vim.api.nvim_create_autocmd({ utils.events.BufReadPre, utils.events.BufWritePost }, {
    group = lint_augroup,
    callback = function()
      lint.try_lint()
    end,
  })
end

return {
  {
    "mfussenegger/nvim-lint",
    cond = not vim.g.vscode,
    event = { utils.events.BufReadPre, utils.events.BufNewFile },
    config = nvim_lint_config,
  },
  {
    "stevearc/conform.nvim",
    cond = not vim.g.vscode,
    opts = conform_opts,
    keys = require("config.keymaps").conform,
  },
}
