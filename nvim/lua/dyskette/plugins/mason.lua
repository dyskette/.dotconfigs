local utils = require("dyskette.utils")

local mason_config = function()
	require("mason").setup({
		ui = {
			border = "rounded",
		},
		registries = {
			"github:mason-org/mason-registry",
			"github:Crashdummyy/mason-registry",
		}
	})
end

local mason_tool_installer_config = function()
	local mason_tool_installer = require("mason-tool-installer")

	local language_servers = {
		-- scripting
		"lua-language-server",
		"bash-language-server",
		"powershell-editor-services",
		"pyright", -- python

		-- javascript and typescript
		"typescript-language-server", -- typescript
		"vue-language-server", -- volar
		"eslint-lsp", -- javascript linter

		-- web common
		"html-lsp", -- html (vscode-html-language-server)
		"css-lsp", -- css (vscode-css-language-server)

		-- common file formats
		"json-lsp", -- json (vscode-json-language-server)
		"yaml-language-server", -- yaml
		"lemminx", -- xml

		-- other languages
		-- "omnisharp", -- c#
		-- "csharp-language-server", -- c#
		"roslyn", -- c#
		"rust-analyzer", -- rust
	}

	local debuggers = {
		"netcoredbg", -- c#
	}

	local linters = {
		-- "eslint", -- js linter -- I'll use the LSP version instead
		-- "pylint", -- python linter -- Install pylint in the virtual environment instead
	}

	local formatters = {
		"stylua", -- lua
		"beautysh", -- sh/bash
		"prettier", -- js/html/css
		"isort", -- python imports
		"black", -- python
		-- "csharpier", -- c# -- TODO: Figure out how to use "dotnet format" instead
	}

	mason_tool_installer.setup({
		ensure_installed = vim.iter({
			language_servers,
			debuggers,
			linters,
			formatters,
		})
			:flatten()
			:totable(),
	})
end

return {
	{
		"williamboman/mason.nvim",
		event = utils.events.VeryLazy,
		config = mason_config
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
		config = mason_tool_installer_config,
		dependencies = {
			{ "williamboman/mason.nvim" },
		},
	},
}
