return {
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonUpdate", "MasonInstall", "MasonUninstall", "MasonUninstallAll", "MasonLog" },
    opts = {
      ui = {
        border = "rounded",
      },
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
      },
    },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    cmd = {
      "MasonToolsInstall",
      "MasonToolsInstallSync",
      "MasonToolsUpdate",
      "MasonToolsUpdateSync",
      "MasonToolsClean",
    },
    opts = {
      ensure_installed = {
        -- Language Servers
        "lua-language-server", -- Lua
        "bash-language-server", -- Bash
        "powershell-editor-services", -- PowerShell
        "pyright", -- Python
        "typescript-language-server", -- TypeScript
        "vue-language-server", -- Vue (Volar)
        "eslint-lsp", -- JavaScript Linter (via LSP)
        "html-lsp", -- HTML (vscode-html-language-server)
        "css-lsp", -- CSS (vscode-css-language-server)
        "json-lsp", -- JSON (vscode-json-language-server)
        "yaml-language-server", -- YAML
        "lemminx", -- XML
        "roslyn", -- C#
        "rust-analyzer", -- Rust

        -- Debuggers
        "netcoredbg", -- C# Debugger

        -- Formatters
        "stylua", -- Lua formatter
        "beautysh", -- Shell/Bash formatter
        "prettier", -- JS/HTML/CSS formatter
        "isort", -- Python import sorter
        "black", -- Python formatter
        -- "csharpier",                  -- C# formatter (prefer 'dotnet format' instead)

        -- Linters (commented out; handled elsewhere)
        -- "eslint",                    -- JS linter — using LSP version instead
        -- "pylint",                    -- Python linter — use from virtualenv
      },
    },
    dependencies = {
      "williamboman/mason.nvim",
    },
  },
}
