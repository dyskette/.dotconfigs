local utils = require("dyskette.utils")

local nvim_lint_config = function()
  local lint = require("lint")

  lint.linters_by_ft = {
    python = { "pylint" },
  }

  local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = lint_augroup,
    callback = function()
      lint.try_lint()
    end,
  })
end

return {
  {
    "mfussenegger/nvim-lint",
    event = {
      utils.events.BufReadPre,
      utils.events.BufNewFile,
      utils.events.BufWritePre,
    },
    config = nvim_lint_config,
  },
  {
    "stevearc/conform.nvim",
    cmd = { "ConformInfo" },
    keys = require("dyskette.keymaps").conform,
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
  },
}
