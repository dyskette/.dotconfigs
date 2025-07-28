return {
  "mason-org/mason-lspconfig.nvim",
  opts = {},
  cmd = { "LspInstall", "LspUninstall" },
  event = "Filetype",
  dependencies = {
    {
      "mason-org/mason.nvim",
      opts = {},
      cmd = { "Mason", "MasonUpdate", "MasonInstall", "MasonUninstall", "MasonUninstallAll", "MasonLog" },
    },
    {
      "neovim/nvim-lspconfig",
      cmd = { "LspInfo", "LspStart", "LspStop", "LspRestart" },
    },
  },
}
