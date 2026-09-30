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

-- No nvim-lint: every linter it ran is covered by a language server now (ruff
-- for python, eslint-lsp for javascript), which publish diagnostics live
-- rather than on read and write. Add it back with a linters_by_ft entry if a
-- language ever needs a linter that has no server.
return {
  {
    "stevearc/conform.nvim",
    cond = not vim.g.vscode,
    opts = conform_opts,
    keys = require("config.keymaps").conform,
  },
}
