local utils = require("config.utils")

local mason_opts = {
  registries = {
    "github:mason-org/mason-registry",
    "github:Crashdummyy/mason-registry",
  },
}

local mason_tool_installer_opts = function()
  local language_servers = {
    -- scripting
    "lua-language-server",
    "bash-language-server",
    "powershell-editor-services",
    "basedpyright", -- python (resolves the project .venv itself)
    "ruff", -- python linter + formatter (replaces pylint, isort, black)

    -- javascript and typescript
    "vtsls", -- typescript/vue
    "vue-language-server", -- vue
    "eslint-lsp", -- javascript linter

    -- web common
    "html-lsp", -- html (vscode-html-language-server)
    "css-lsp", -- css (vscode-css-language-server)

    -- common file formats
    "json-lsp", -- json (vscode-json-language-server)
    "yaml-language-server", -- yaml
    "lemminx", -- xml
    "taplo", -- toml

    -- other languages
    -- "omnisharp", -- c#
    -- "csharp-language-server", -- c#
    "roslyn", -- c# (includes integrated Razor support)
    "rust-analyzer", -- rust
  }

  local debuggers = {
    "netcoredbg", -- c#
  }

  local linters = {
    -- "eslint", -- js linter -- I'll use the LSP version instead
    -- "pylint", -- python linter -- replaced by ruff, which needs no venv to be found
  }

  local formatters = {
    "stylua", -- lua
    "beautysh", -- sh/bash
    "prettier", -- js/html/css
    "sql-formatter", -- sql
    -- "csharpier", -- c# -- TODO: Figure out how to use "dotnet format" instead
  }

  return {
    ensure_installed = vim
      .iter({
        language_servers,
        debuggers,
        linters,
        formatters,
      })
      :flatten()
      :totable(),
  }
end

return {
  {
    "williamboman/mason.nvim",
    cond = not vim.g.vscode,
    event = utils.events.VeryLazy,
    opts = mason_opts,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    cond = not vim.g.vscode,
    cmd = {
      "MasonToolsInstall",
      "MasonToolsInstallSync",
      "MasonToolsUpdate",
      "MasonToolsUpdateSync",
      "MasonToolsClean",
    },
    opts = mason_tool_installer_opts,
    dependencies = {
      { "williamboman/mason.nvim" },
    },
  },
}
