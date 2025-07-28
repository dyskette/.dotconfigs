return {
  "stevearc/conform.nvim",
  cmd = { "ConformInfo" },
  keys = {
    {
      "<leader>ff",
      "<cmd>lua require('conform').format({ async = true, lsp_format = 'fallback' })<cr>",
      desc = "Format buffer",
    },
  },
  init = function()
    vim.o.formatexpr = [[v:lua.require("conform").formatexpr()]]
  end,
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      sh = { "beautysh" },
      python = { "isort", "black" },
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
    },
    formatters = {},
  },
}
